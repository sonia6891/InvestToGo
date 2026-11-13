import XCTest
@testable import PocketCore

final class BacktestTests: XCTestCase {
    private func bars(_ pairs: [(String, Double)]) -> [DailyBar] { pairs.map { DailyBar(date: $0.0, close: $0.1) } }
    private func input(_ s: YearMonth, _ e: YearMonth, reinvest: Bool = true) -> BacktestInput {
        BacktestInput(legs: [("X", 1)], monthly: 1000, start: s, end: e, reinvest: reinvest)
    }
    private let jan = YearMonth(year: 2024, month: 1), feb = YearMonth(year: 2024, month: 2)
    private var base: [DailyBar] {
        bars([("2024-01-02", 10), ("2024-01-31", 10), ("2024-02-01", 20), ("2024-02-29", 20)])
    }

    func testTwoMonthsNoDividends() {
        let h = SymbolHistory(bars: base, dividends: [], splits: [], suspect: false)
        let r = Backtest.run(input(jan, feb), history: ["X": h])
        XCTAssertEqual(r.invested, 2000, accuracy: 1e-6)
        XCTAssertEqual(r.endValue, 3000, accuracy: 1e-6)
        XCTAssertEqual(r.maxDrawdown, 0, accuracy: 1e-9)
        XCTAssertEqual(r.curve.count, 2)
    }

    func testDividendReinvestVersusCash() {
        let b = bars([("2024-01-02", 10), ("2024-01-15", 10), ("2024-01-31", 10), ("2024-02-01", 20), ("2024-02-29", 20)])
        let h = SymbolHistory(bars: b, dividends: [DividendEvent(symbol: "X", exDate: "2024-01-15", cash: 1)],
                              splits: [], suspect: false)
        let re = Backtest.run(input(jan, feb, reinvest: true), history: ["X": h])
        let ca = Backtest.run(input(jan, feb, reinvest: false), history: ["X": h])
        XCTAssertEqual(re.endValue, 3200, accuracy: 1e-6)
        XCTAssertEqual(ca.endValue, 3100, accuracy: 1e-6)
        XCTAssertEqual(re.dividends, 100, accuracy: 1e-6)
        XCTAssertEqual(ca.dividends, 100, accuracy: 1e-6)
    }

    func testSplitDoesNotLookLikeACrash() {
        let h = SymbolHistory(bars: bars([("2025-06-02", 100), ("2025-06-18", 25), ("2025-07-01", 25)]),
                              dividends: [], splits: [SplitEvent(symbol: "X", resumeDate: "2025-06-18", ratio: 4)],
                              suspect: false)
        let r = Backtest.run(input(YearMonth(year: 2025, month: 6), YearMonth(year: 2025, month: 7)), history: ["X": h])
        XCTAssertEqual(r.endValue, 2000, accuracy: 1e-6)
        XCTAssertEqual(r.maxDrawdown, 0, accuracy: 1e-9)
    }

    func testLateListingStartsAtFirstBar() {
        let h = SymbolHistory(bars: bars([("2024-03-04", 10), ("2024-03-29", 10)]), dividends: [], splits: [], suspect: false)
        let r = Backtest.run(input(jan, YearMonth(year: 2024, month: 3)), history: ["X": h])
        XCTAssertEqual(r.invested, 1000, accuracy: 1e-6)
        XCTAssertTrue(r.notes.contains { $0.contains("上市") })
        XCTAssertEqual(r.notes.first, "X 於 2024-03 上市，之前的月份不投入")
    }

    func testSuspectNote() {
        let h = SymbolHistory(bars: base, dividends: [], splits: [], suspect: true)
        let r = Backtest.run(input(jan, feb), history: ["X": h])
        XCTAssertTrue(r.notes.contains("X 資料可能未還原，結果僅供參考"))
    }

    func testXirrTenPercent() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d1 = cal.date(from: DateComponents(year: 2023, month: 1, day: 1))!
        let d2 = cal.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let r = Finance.xirr([(d1, -1000), (d2, 1100)])
        XCTAssertNotNil(r)
        XCTAssertEqual(r ?? 0, 0.10, accuracy: 1e-4)
        XCTAssertNil(Finance.xirr([(d1, -1000), (d2, -5)]))
    }

    func testMaxDrawdown() {
        XCTAssertEqual(Backtest.maxDrawdown([100, 120, 90, 130]), 0.25, accuracy: 1e-9)
    }
}
