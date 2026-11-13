import XCTest
@testable import ETFToGo

/// Answers like the exchanges do, from memory, and counts what was asked.
private actor FakeHistoryFetcher: HistoryFetching {
    private(set) var urls: [URL] = []
    private var broken = false
    private let barDay: String

    /// `barDay` is the ROC date of the one bar every 證交所 month answers with, e.g. "114/06/02".
    init(barDay: String) { self.barDay = barDay }

    func breakMonths(_ value: Bool) { broken = value }
    func count(_ part: String) -> Int { urls.filter { $0.absoluteString.contains(part) }.count }

    func get(_ url: URL) async throws -> Data {
        urls.append(url)
        let text = url.absoluteString
        if text.contains("STOCK_DAY") {
            if broken { return Data("<html>maintenance</html>".utf8) }
            let body = "{\"stat\":\"OK\",\"fields\":[\"日期\",\"收盤價\"],\"data\":[[\"" + barDay + "\",\"50.00\"]]}"
            return Data(body.utf8)
        }
        if text.contains("tradingStock") {
            return Data("{\"tables\":[{\"fields\":[\"日 期\",\"收盤\"],\"data\":[]}]}".utf8)
        }
        return Data("{\"stat\":\"很抱歉，沒有符合條件的資料!\",\"total\":0}".utf8)
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); value = value.addingTimeInterval(seconds); lock.unlock() }
}

final class BacktestClientTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    /// Noon in Taipei.
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        GameRules.taipei.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func client(_ fetcher: FakeHistoryFetcher, _ clock: TestClock) -> OfficialHistoryClient {
        OfficialHistoryClient(fetcher: fetcher, root: root, minInterval: 0, clock: { clock.now }, fugleKeySaved: { false })
    }

    func testCachedPastMonthIsNotRefetched() async throws {
        let fetcher = FakeHistoryFetcher(barDay: "114/06/02")
        let clock = TestClock(date(2026, 11, 14))
        let month = YearMonth(year: 2025, month: 6)
        let first = try await client(fetcher, clock).history(symbol: "0050", market: "TWSE", from: month, to: month) { _ in }
        XCTAssertEqual(first.bars, [DailyBar(date: "2025-06-02", close: 50)])
        // A new client reads the same folder: the cache is on disk, not in memory.
        clock.advance(40 * 86_400)
        let second = try await client(fetcher, clock).history(symbol: "0050", market: "TWSE", from: month, to: month) { _ in }
        XCTAssertEqual(second.bars, first.bars)
        let months = await fetcher.count("STOCK_DAY")
        XCTAssertEqual(months, 1, "A month that had ended when it was fetched is never asked for again")
        let dividends = await fetcher.count("TWT49U")
        XCTAssertEqual(dividends, 2, "The dividends of 2025 (two half-year requests) were complete the first time")
    }

    func testCurrentMonthRefetchedAfterADay() async throws {
        let fetcher = FakeHistoryFetcher(barDay: "115/11/02")
        let clock = TestClock(date(2026, 11, 14))
        let month = YearMonth(year: 2026, month: 11)
        let subject = client(fetcher, clock)
        _ = try await subject.history(symbol: "0050", market: "TWSE", from: month, to: month) { _ in }
        clock.advance(3600)
        _ = try await subject.history(symbol: "0050", market: "TWSE", from: month, to: month) { _ in }
        var months = await fetcher.count("STOCK_DAY")
        XCTAssertEqual(months, 1, "An hour later the current month is still fresh")
        clock.advance(24 * 3600)
        let third = try await subject.history(symbol: "0050", market: "TWSE", from: month, to: month) { _ in }
        months = await fetcher.count("STOCK_DAY")
        XCTAssertEqual(months, 2, "25 hours after the fetch the current month is asked for again")
        XCTAssertEqual(third.bars.count, 1)
    }

    /// A month fetched while it was running is partial: once it has ended it is fetched one more time, then kept.
    func testMonthFetchedBeforeItEndedIsCompletedLater() async throws {
        let fetcher = FakeHistoryFetcher(barDay: "115/11/02")
        let clock = TestClock(date(2026, 11, 14))
        let month = YearMonth(year: 2026, month: 11)
        let subject = client(fetcher, clock)
        _ = try await subject.history(symbol: "0050", market: "TWSE", from: month, to: month) { _ in }
        clock.advance(30 * 86_400)
        _ = try await subject.history(symbol: "0050", market: "TWSE", from: month, to: month) { _ in }
        clock.advance(30 * 86_400)
        _ = try await subject.history(symbol: "0050", market: "TWSE", from: month, to: month) { _ in }
        let months = await fetcher.count("STOCK_DAY")
        XCTAssertEqual(months, 2)
    }

    func testThrownMonthIsNotCached() async throws {
        let fetcher = FakeHistoryFetcher(barDay: "114/06/02")
        let clock = TestClock(date(2026, 11, 14))
        let month = YearMonth(year: 2025, month: 6)
        let subject = client(fetcher, clock)
        await fetcher.breakMonths(true)
        do {
            _ = try await subject.history(symbol: "0050", market: "TWSE", from: month, to: month) { _ in }
            XCTFail("A body that is not the exchange JSON throws")
        } catch {}
        await fetcher.breakMonths(false)
        let history = try await subject.history(symbol: "0050", market: "TWSE", from: month, to: month) { _ in }
        XCTAssertEqual(history.bars.count, 1, "The failed answer was not kept as an empty month")
        let months = await fetcher.count("STOCK_DAY")
        XCTAssertEqual(months, 2)
    }

    /// Without a market from the catalogue, 上市 is asked first and 上櫃 only when 上市 has nothing.
    func testUnknownMarketTriesTWSEThenStaysThere() async throws {
        let fetcher = FakeHistoryFetcher(barDay: "114/06/02")
        let clock = TestClock(date(2026, 11, 14))
        let subject = client(fetcher, clock)
        let history = try await subject.history(symbol: "0050", market: nil, from: YearMonth(year: 2025, month: 5), to: YearMonth(year: 2025, month: 6)) { _ in }
        // The fake answers every month with the same June bar, so May keeps none of it.
        XCTAssertEqual(history.bars, [DailyBar(date: "2025-06-02", close: 50)])
        let twse = await fetcher.count("STOCK_DAY")
        let tpex = await fetcher.count("tradingStock")
        XCTAssertEqual(twse, 2)
        XCTAssertEqual(tpex, 0, "June settled the market as 上市, so May did not ask 櫃買中心")
    }
}
