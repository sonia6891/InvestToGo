import XCTest
@testable import ETFToGo

/// 口袋 and 配息's figures (spec 5.7, 5.8), the 記一筆配息 reward and the sample data, without the simulator UI.
final class PocketScreenTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return c
    }()
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))! }
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))! }

    func testPocketSummaryCountsGainsAndLossesHonestly() {
        let gain = Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 100, broker: "", strategy: .saving)
        let loss = Holding(symbol: "00679B", name: "元大美債20年", shares: 1000, unitCost: 30, broker: "", strategy: .unclassified)
        let unpriced = Holding(symbol: "00999", name: "沒有報價", shares: 10, unitCost: 10, broker: "", strategy: .unclassified)
        let values: [String: Double] = ["0050": 120_000, "00679B": 27_000]
        let summary = PocketSummary.of([loss, unpriced, gain]) { values[$0.symbol] }

        XCTAssertEqual(summary.total, 147_000, "Only priced holdings are added up")
        XCTAssertEqual(summary.missing, 1)
        XCTAssertEqual(summary.gain, 17_000, accuracy: 0.001, "20,000 gained and 3,000 lost on 130,000 of cost")
        XCTAssertEqual(try XCTUnwrap(summary.gainPercent), 17_000.0 / 130_000 * 100, accuracy: 1e-9)
        XCTAssertEqual(summary.rows.map(\.holding.symbol), ["0050", "00679B", "00999"], "Largest value first, unpriced last")
        XCTAssertEqual(try XCTUnwrap(summary.rows[0].share), 120_000.0 / 147_000 * 100, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(summary.rows[1].gainPercent), -10, accuracy: 1e-9, "A loss stays a loss")
        XCTAssertNil(summary.rows[2].share)
        XCTAssertNil(summary.rows[2].gainPercent)
        XCTAssertEqual(summary.rows.compactMap(\.share).reduce(0, +), 100, accuracy: 1e-9, "The bar's shares fill it")

        let empty = PocketSummary.of([unpriced]) { values[$0.symbol] }
        XCTAssertNil(empty.total, "No price at all: no total rather than NT$ 0")
        XCTAssertNil(empty.gainPercent)
    }

    func testTotalGainTagShowsArrowAmountAndPercent() {
        XCTAssertEqual(SkinChange.text(percent: 12.4, amount: 31_620, format: money), "▲ 31,620 (+12.40%)")
        XCTAssertEqual(SkinChange.text(percent: -3.6, amount: -900, format: money), "▼ 900 (-3.60%)")
        XCTAssertEqual(SkinChange.spoken(percent: -3.6, amount: -900, format: money), "下跌 900 元，3.60%")
        XCTAssertEqual(SkinChange.tone(12.4), \SkinColors.up)
        XCTAssertEqual(SkinChange.tone(-3.6), \SkinColors.down)
        XCTAssertEqual(SkinChange.tone(0.001), \SkinColors.sub)
    }

    func testDividendYearCountsReceivedOnly() {
        let records = [
            Dividend(symbol: "00878", date: day(2026, 1, 15), amount: 1500, status: .paid),
            Dividend(symbol: "0050", date: day(2026, 1, 20), amount: 1000, status: .paid),
            Dividend(symbol: "00878", date: day(2026, 10, 15), amount: 1500, status: .paid),
            Dividend(symbol: "00919", date: day(2026, 12, 16), amount: 810, status: .announced),
            Dividend(symbol: "00878", date: day(2025, 4, 15), amount: 1200, status: .paid),
            Dividend(symbol: "00878", date: day(2025, 12, 15), amount: 9999, status: .paid),
        ]
        let year = DividendYear.of(records, now: now, calendar: calendar)
        XCTAssertEqual(year.total, 4000, "Announced records are not received")
        XCTAssertEqual(year.count, 3)
        XCTAssertEqual(year.months, [1, 10])
        XCTAssertEqual(year.previous, 1200, "Last year only up to this day a year ago")
        XCTAssertEqual(year.tag(hidden: false), "領了 3 次 · 比去年多 2,800")
        XCTAssertEqual(year.tag(hidden: true), "領了 3 次 · 比去年多 ＊＊＊＊")
        XCTAssertEqual(DividendYear(total: 500, count: 1, months: [3], previous: 800).tag(hidden: false), "領了 1 次 · 比去年少 300")
        XCTAssertEqual(DividendYear(total: 500, count: 1, months: [3], previous: 0).tag(hidden: false), "領了 1 次")
        XCTAssertEqual(DividendYear.of([], now: now, calendar: calendar), DividendYear())
    }

    func testUpcomingDividendsMergeBrokersAndSkipPastOnes() {
        let cash = Holding(symbol: "00878", name: "國泰永續高股息", shares: 2000, unitCost: 20, broker: "A", strategy: .income)
        let margin = Holding(symbol: "00878", name: "國泰永續高股息", shares: 1000, unitCost: 20, broker: "B", strategy: .income)
        let other = Holding(symbol: "0056", name: "元大高股息", shares: 1000, unitCost: 30, broker: "A", strategy: .income)
        let coming = OfficialDistribution(ex: "2026-11-18", pay: "", amount: 0.5)
        let entries: [(symbol: String, event: OfficialDistribution, shares: Double, holding: Holding)] = [
            ("00878", coming, 2000, cash), ("00878", coming, 1000, margin),
            ("0056", OfficialDistribution(ex: "2026-11-05", pay: "", amount: 1.0), 1000, other),
            ("0056", OfficialDistribution(ex: "2026-12-19", pay: "", amount: nil), 1000, other),
        ]
        let items = UpcomingDividend.from(entries, today: "2026-11-12")
        XCTAssertEqual(items.map(\.id), ["00878-2026-11-18", "0056-2026-12-19"], "Soonest first; a past ex-date is gone")
        XCTAssertEqual(items[0].shares, 3000, "Both brokers' shares")
        XCTAssertNil(items[0].holding, "Recorded for the whole code")
        XCTAssertEqual(items[0].estimate, 1500)
        XCTAssertEqual(items[1].holding, other.id)
        XCTAssertNil(items[1].estimate, "No amount announced yet: no estimate")
    }

    @MainActor func testLoggingADividendEarnsTwentyWhateverTheAmount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PortfolioStore(url: directory.appendingPathComponent("p.json"))
        var small = Dividend(symbol: "0050", date: Date(), amount: 1, status: .paid)
        try store.saveDividend(small, rewardNew: true)
        XCTAssertEqual(store.data.game?.xp, 20)
        XCTAssertEqual(store.data.game?.coins, 20)
        XCTAssertEqual(store.data.game?.counter(.dividendLogged), 1)
        try store.saveDividend(Dividend(symbol: "00878", date: Date(), amount: 1_000_000, status: .paid), rewardNew: true)
        XCTAssertEqual(store.data.game?.xp, 40, "A large dividend earns the same +20")
        small.amount = 5
        try store.saveDividend(small, rewardNew: true)
        XCTAssertEqual(store.data.game?.xp, 40, "Editing a record earns nothing")
        try store.saveDividend(Dividend(symbol: "0056", date: Date(), amount: 10, status: .paid))
        XCTAssertEqual(store.data.game?.xp, 40, "Records saved without 記一筆配息 earn nothing")
        XCTAssertEqual(PortfolioStore(url: directory.appendingPathComponent("p.json")).data.game?.xp, 40, "Saved with the record")
    }

    @MainActor func testDemoPocketNeedsUITestingAndFillsOnlyAnEmptyPocket() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PortfolioStore(url: directory.appendingPathComponent("p.json"))
        DemoArguments.seedPocket(store, args: ["--demo-pocket"], now: now, calendar: calendar)
        XCTAssertTrue(store.data.holdings.isEmpty, "Ignored without --ui-testing")
        DemoArguments.seedPocket(store, args: ["--ui-testing", "--demo-pocket"], now: now, calendar: calendar)
        XCTAssertEqual(store.data.holdings.map(\.symbol), ["0050", "00878", "006208", "00679B"])
        let year = DividendYear.of(store.data.dividends, now: now, calendar: calendar)
        XCTAssertEqual(year.total, 8640)
        XCTAssertEqual(year.count, 7)
        XCTAssertEqual(year.tag(hidden: false), "領了 7 次 · 比去年多 1,920")
        XCTAssertEqual(store.data.game?.xp ?? 0, 0, "Seeding is not logging")
        DemoArguments.seedPocket(store, args: ["--ui-testing", "--demo-pocket"], now: now, calendar: calendar)
        XCTAssertEqual(store.data.holdings.count, 4, "A filled pocket is left alone")
    }
}
