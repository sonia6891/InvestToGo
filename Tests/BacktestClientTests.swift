import XCTest
@testable import ETFToGo

/// Answers like the exchanges do, from memory, and counts what was asked.
private actor FakeHistoryFetcher: HistoryFetching {
    private(set) var urls: [URL] = []
    private var broken = false
    private let barDay: String?
    private let listedFrom: Int?
    private let known: Bool

    /// `barDay` is the ROC date of the one bar every 證交所 month answers with, e.g. "114/06/02"; without it each
    /// month answers with its own 2nd. Months before `listedFrom` (yyyyMM) are empty. `known` false: no exchange
    /// has the code.
    init(barDay: String? = nil, listedFrom: Int? = nil, known: Bool = true) {
        self.barDay = barDay; self.listedFrom = listedFrom; self.known = known
    }

    func breakMonths(_ value: Bool) { broken = value }
    func count(_ part: String) -> Int { urls.filter { $0.absoluteString.contains(part) }.count }

    func get(_ url: URL) async throws -> Data {
        urls.append(url)
        let text = url.absoluteString
        if text.contains("STOCK_DAY") {
            if broken { return Data("<html>maintenance</html>".utf8) }
            let empty = Data("{\"stat\":\"很抱歉，沒有符合條件的資料!\",\"total\":0}".utf8)
            guard known, let range = text.range(of: "date="), let month = Int(text[range.upperBound...].prefix(6)) else { return empty }
            if let listedFrom, month < listedFrom { return empty }
            let day = barDay ?? String(format: "%d/%02d/02", month / 100 - 1911, month % 100)
            let body = "{\"stat\":\"OK\",\"fields\":[\"日期\",\"收盤價\"],\"data\":[[\"" + day + "\",\"50.00\"]]}"
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

    /// With no listing month from the catalogue, the months before the listing end at three empty ones in a row.
    func testMonthsBeforeListingStopAfterThreeEmpty() async throws {
        let fetcher = FakeHistoryFetcher(listedFrom: 202506)
        let clock = TestClock(date(2026, 11, 14))
        let history = try await client(fetcher, clock).history(symbol: "0050", market: "TWSE", from: YearMonth(year: 2024, month: 1), to: YearMonth(year: 2025, month: 12)) { _ in }
        XCTAssertEqual(history.bars.count, 7, "June to December 2025")
        XCTAssertEqual(history.bars.first?.date, "2025-06-02")
        let months = await fetcher.count("STOCK_DAY")
        XCTAssertEqual(months, 10, "Seven months with bars, then May, April and March; not the 14 before those")
    }

    /// The catalogue's listing month is where reading starts: nothing earlier is asked for.
    func testListingMonthFromTheCatalogueStartsThere() async throws {
        let fetcher = FakeHistoryFetcher(listedFrom: 202506)
        let clock = TestClock(date(2026, 11, 14))
        let history = try await client(fetcher, clock).history(symbol: "0050", market: "TWSE", listed: YearMonth(year: 2025, month: 6),
                                                               from: YearMonth(year: 2024, month: 1), to: YearMonth(year: 2025, month: 12)) { _ in }
        XCTAssertEqual(history.bars.count, 7)
        let months = await fetcher.count("STOCK_DAY")
        XCTAssertEqual(months, 7)
    }

    /// A code neither exchange has: three months on both, then an error, and no folder for it.
    func testUnknownCodeThrowsAfterThreeMonths() async throws {
        let fetcher = FakeHistoryFetcher(known: false)
        let clock = TestClock(date(2026, 11, 14))
        do {
            _ = try await client(fetcher, clock).history(symbol: "9999", market: nil, from: YearMonth(year: 2016, month: 11), to: YearMonth(year: 2026, month: 11)) { _ in }
            XCTFail("An unknown code throws")
        } catch {
            XCTAssertEqual((error as? AppDataError)?.text, "找不到這檔的歷史資料")
        }
        let twse = await fetcher.count("STOCK_DAY")
        let tpex = await fetcher.count("tradingStock")
        XCTAssertEqual(twse, 3)
        XCTAssertEqual(tpex, 3)
        let all = await fetcher.urls.count
        XCTAssertEqual(all, 6, "No dividend or split requests either")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("9999").path), "Nothing is cached for it")
    }

    /// The wait is worked out from what is not on the phone yet: 2 s a request, 8 s for each half-year of 證交所 dividends.
    func testEstimateCountsOnlyWhatIsNotCached() async throws {
        let fetcher = FakeHistoryFetcher()
        let clock = TestClock(date(2026, 11, 14))
        let subject = client(fetcher, clock)
        let month = YearMonth(year: 2025, month: 6)
        let before = await subject.estimatedSeconds(symbol: "0050", market: "TWSE", from: month, to: month)
        XCTAssertEqual(before, 2 + 16 + 2, "One month, two half-years of dividends, the split list")
        _ = try await subject.history(symbol: "0050", market: "TWSE", from: month, to: month) { _ in }
        let after = await subject.estimatedSeconds(symbol: "0050", market: "TWSE", from: month, to: month)
        XCTAssertEqual(after, 0)
        let requests = await fetcher.urls.count
        XCTAssertEqual(requests, 4, "Estimating asked the network for nothing")
    }

    @MainActor func testEstimateWords() {
        XCTAssertEqual(BacktestModel.estimateText(seconds: 40, fugle: false), "下載不到 1 分鐘，離開這頁會停止。")
        XCTAssertEqual(BacktestModel.estimateText(seconds: 250, fugle: false), "第一次下載大約需要 5 分鐘（之後會快很多），離開這頁會停止。")
        XCTAssertEqual(BacktestModel.estimateText(seconds: 0, fugle: false), "歷史資料已經在手機裡，不用再下載。")
        XCTAssertNil(BacktestModel.estimateText(seconds: nil, fugle: false))
    }

    // MARK: Final review fixes

    /// B11. N years is N × 12 monthly buys, not N × 12 + 1: five years at 10,000 a month is 600,000 put in.
    @MainActor func testWindowIsExactlyTwelveMonthsAYear() {
        let now = date(2026, 11, 14)
        for years in [1, 3, 5, 10] {
            let window = BacktestModel.window(years: years, now: now)
            var months = 0
            var cursor = window.start
            while cursor <= window.end { months += 1; cursor = cursor.next() }
            XCTAssertEqual(months, years * 12, "\(years) 年")
            XCTAssertEqual(window.end, YearMonth(year: 2026, month: 11))
        }
        XCTAssertEqual(BacktestModel.window(years: 5, now: now).start, YearMonth(year: 2021, month: 12))
        XCTAssertEqual(BacktestModel.window(years: 1, now: date(2026, 12, 3)).start, YearMonth(year: 2026, month: 1), "December wraps into the next year")

        // What the result card would say: one buy in each month of the window.
        let window = BacktestModel.window(years: 5, now: now)
        var bars: [DailyBar] = []
        var cursor = window.start
        while cursor <= window.end { bars.append(DailyBar(date: cursor.key + "-02", close: 50)); cursor = cursor.next() }
        let input = BacktestInput(legs: [(symbol: "0050", weight: 1)], monthly: 10_000, start: window.start, end: window.end, reinvest: true)
        let result = Backtest.run(input, history: ["0050": SymbolHistory(bars: bars, dividends: [], splits: [], suspect: false)])
        XCTAssertEqual(result.invested, 600_000)
    }

    /// A1. A saved 富果 key that does not work (invalid, 429, a plan without history) is not a dead end: the
    /// exchanges are read instead, and the result says so.
    func testFugleFailureFallsBackToTheExchanges() async throws {
        let fetcher = FakeHistoryFetcher(barDay: "114/06/02")
        let clock = TestClock(date(2026, 11, 14))
        let month = YearMonth(year: 2025, month: 6)
        let asked = Counter()
        let fell = Counter()
        let subject = OfficialHistoryClient(fetcher: fetcher, root: root, minInterval: 0, clock: { clock.now }, fugleKeySaved: { true },
                                            fugleBars: { _, _ in asked.add(); throw StoreError.http(401) })
        XCTAssertTrue(subject.usesFugle)
        let history = try await subject.history(symbol: "0050", market: "TWSE", from: month, to: month, fellBack: { fell.add() }) { _ in }
        XCTAssertEqual(asked.value, 1, "富果 was asked first")
        XCTAssertEqual(fell.value, 1, "The caller hears that the exchanges are being read instead")
        XCTAssertFalse(history.fromFugle, "The result is marked as the exchanges' data")
        XCTAssertEqual(history.bars, [DailyBar(date: "2025-06-02", close: 50)])
        let months = await fetcher.count("STOCK_DAY")
        XCTAssertEqual(months, 1, "The official path was used")
    }

    /// With a key that works the result is 富果's and the exchanges are not asked.
    func testFugleAnswerIsMarkedAsFugle() async throws {
        let fetcher = FakeHistoryFetcher(barDay: "114/06/02")
        let clock = TestClock(date(2026, 11, 14))
        let month = YearMonth(year: 2025, month: 6)
        let subject = OfficialHistoryClient(fetcher: fetcher, root: root, minInterval: 0, clock: { clock.now }, fugleKeySaved: { true },
                                            fugleBars: { _, _ in [DailyBar(date: "2025-05-30", close: 48), DailyBar(date: "2025-06-03", close: 51)] })
        let history = try await subject.history(symbol: "0050", market: "TWSE", from: month, to: month) { _ in }
        XCTAssertTrue(history.fromFugle)
        XCTAssertEqual(history.bars, [DailyBar(date: "2025-06-03", close: 51)], "Only the bars inside the window")
        let requests = await fetcher.urls.count
        XCTAssertEqual(requests, 0)
        // `fugle: false` reads the exchanges even with a key: how a run keeps one source once 富果 failed for a leg.
        let official = try await subject.history(symbol: "0050", market: "TWSE", from: month, to: month, fugle: false) { _ in }
        XCTAssertFalse(official.fromFugle)
        XCTAssertEqual(official.bars, [DailyBar(date: "2025-06-02", close: 50)])
    }

    /// A cancelled 富果 request is a cancellation, not a reason to start the long official download.
    func testCancelledFugleRequestDoesNotFallBack() async throws {
        let fetcher = FakeHistoryFetcher(barDay: "114/06/02")
        let clock = TestClock(date(2026, 11, 14))
        let month = YearMonth(year: 2025, month: 6)
        let subject = OfficialHistoryClient(fetcher: fetcher, root: root, minInterval: 0, clock: { clock.now }, fugleKeySaved: { true },
                                            fugleBars: { _, _ in throw CancellationError() })
        do {
            _ = try await subject.history(symbol: "0050", market: "TWSE", from: month, to: month) { _ in }
            XCTFail("A cancellation is passed on")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let requests = await fetcher.urls.count
        XCTAssertEqual(requests, 0)
    }

    /// A1 and A2 through the model: 富果 fails for the second ETF, so both are read from the exchanges and the result
    /// card's source is the exchanges'; the screen is kept awake for the run and released when it ends.
    @MainActor func testRunKeepsOneSourceAndReleasesTheScreen() async throws {
        // The model's window ends in the real current month, so this client's clock is the real one too.
        let fetcher = FakeHistoryFetcher()
        let subject = OfficialHistoryClient(fetcher: fetcher, root: root, minInterval: 0, fugleKeySaved: { true },
                                            fugleBars: { symbol, _ in
                                                if symbol == "0056" { throw StoreError.http(429) }
                                                return [DailyBar(date: "2026-10-02", close: 80), DailyBar(date: "2026-11-03", close: 81)]
                                            })
        let awake = Flags()
        let model = BacktestModel(keepAwake: { awake.values.append($0) })
        model.run(legs: [(symbol: "0050", weight: 0.5), (symbol: "0056", weight: 0.5)], markets: ["0050": "TWSE", "0056": "TWSE"],
                  listed: [:], monthly: 10_000, years: 1, reinvest: true, client: subject)
        XCTAssertTrue(model.running)
        XCTAssertEqual(awake.values, [true], "The screen stays on while the download runs")
        XCTAssertTrue(model.fromFugle, "With a key saved the run starts on 富果")
        for _ in 0..<400 where model.running { try await Task.sleep(nanoseconds: 25_000_000) }
        XCTAssertFalse(model.running)
        XCTAssertEqual(awake.values, [true, false], "Auto-lock is back when the run ends")
        XCTAssertFalse(model.fromFugle, "One leg came from the exchanges, so the whole result does")
        let result = try XCTUnwrap(model.result)
        XCTAssertEqual(result.invested, 120_000, accuracy: 0.01, "Both legs bought in all twelve months, at the exchanges' closes")
        XCTAssertEqual(result.endValue, 120_000, accuracy: 0.01, "Every close is 50, 富果's 80 was not mixed in")

        // Cancelling and leaving the page release it as well, and never twice.
        model.run(legs: [(symbol: "0050", weight: 1)], markets: [:], listed: [:], monthly: 10_000, years: 1, reinvest: true, client: subject)
        model.cancel()
        model.cancel()
        XCTAssertEqual(awake.values, [true, false, true, false])
    }

    /// A2. A failed run does not leave the screen on either.
    @MainActor func testFailedRunReleasesTheScreen() async throws {
        let fetcher = FakeHistoryFetcher(known: false)
        let subject = OfficialHistoryClient(fetcher: fetcher, root: root, minInterval: 0, fugleKeySaved: { false })
        let awake = Flags()
        let model = BacktestModel(keepAwake: { awake.values.append($0) })
        model.run(legs: [(symbol: "9999", weight: 1)], markets: [:], listed: [:], monthly: 10_000, years: 1, reinvest: true, client: subject)
        for _ in 0..<400 where model.running { try await Task.sleep(nanoseconds: 25_000_000) }
        XCTAssertNotNil(model.notFound)
        XCTAssertEqual(awake.values, [true, false])
    }

    /// A3. 回測 takes ETFs only: a stock's 配股 and 減資 are not in the data.
    func testFormTakesOnlyETFs() {
        let isETF: (String) -> Bool = { $0.hasPrefix("00") }
        XCTAssertEqual(try BacktestForm.adding(" 0056 ", to: ["0050"], isETF: isETF).get(), "0056")
        XCTAssertEqual(try BacktestForm.adding("00679b", to: [], isETF: isETF).get(), "00679B")
        func problem(_ text: String, _ picked: [String]) -> String? {
            if case .failure(let error) = BacktestForm.adding(text, to: picked, isETF: isETF) { return error.text }
            return nil
        }
        XCTAssertEqual(problem("2330", ["0050"]), "回測只支援 ETF。")
        XCTAssertEqual(problem("台積電", []), "代號格式不符，請輸入像 0056 或 00679B 的代號。")
        XCTAssertEqual(problem("0050", ["0050"]), "0050 已經在清單裡。")
        XCTAssertEqual(problem("0056", ["0050", "006208", "00878"]), "最多 3 檔。")
        XCTAssertEqual(BacktestForm.candidates(own: ["2330", "0050", "0056", "2454", "0056", "00878"], picked: ["0050"], isETF: isETF), ["0056", "00878"],
                       "Held and favourite stocks are not offered")
    }
}

/// What the model asked of the idle timer, in order.
private final class Flags {
    var values: [Bool] = []
}

/// Counts calls from any thread.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
