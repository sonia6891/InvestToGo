import XCTest
@testable import PocketCore

final class PortfolioModelTests: XCTestCase {
    func testNoMarketValueWithoutCompleteQuotes() {
        var data = Portfolio.demo
        XCTAssertEqual(data.marketValue, 348500)
        data.quotes.removeValue(forKey: "0050")
        XCTAssertNil(data.marketValue, "Missing prices must not silently use cost as market value")
    }
    func testProjectionZeroReturnAndMonthlyTiming() {
        XCTAssertEqual(Projection.value(initial: 100000, monthly: 5000, years: 10, annualPercent: 0), 700000, accuracy: 0.01)
        XCTAssertLessThan(Projection.value(initial: 100000, monthly: 0, years: 10, annualPercent: -5), 100000)
    }
    func testBackupRejectsInvalidData() throws {
        var data = Portfolio.demo
        data.holdings[0].shares = -1
        XCTAssertThrowsError(try Portfolio.decodeBackup(JSONEncoder().encode(data)))
        data = .demo; data.schema = 99
        XCTAssertThrowsError(try Portfolio.decodeBackup(JSONEncoder().encode(data)))
        data = .demo; data.holdings.append(data.holdings[0])
        XCTAssertThrowsError(try Portfolio.decodeBackup(JSONEncoder().encode(data)))
    }
    func testSchemaOneStillDecodesWithoutNewFields() throws {
        let bytes = Data(#"{"schema":1,"holdings":[],"dividends":[],"favorites":[],"quotes":{}}"#.utf8)
        let value = try Portfolio.decodeBackup(bytes); XCTAssertNil(value.components); XCTAssertTrue(value.holdings.isEmpty)
    }
    func testPlanReinvestmentDoesNotCountDividendsTwice() throws {
        var plan = LegacyPlan(principal: 100000, monthly: 0, years: 1, totalReturn: 0.06, distributionRate: 0.04, frequency: 4, reinvest: 1, deductionRate: 0)
        let full = try XCTUnwrap(PlanMath.project(plan).last)
        XCTAssertEqual(full.total, 106000, accuracy: 0.001)
        XCTAssertEqual(full.cash, 0)
        plan.totalReturn = 0; plan.reinvest = 0
        let cash = try XCTUnwrap(PlanMath.project(plan).last)
        XCTAssertEqual(cash.total, 100000, accuracy: 0.001)
        XCTAssertEqual(cash.cash, 100000 * (1 - pow(0.99, 4)), accuracy: 0.001)
        plan.deductionRate = 0.1
        XCTAssertLessThan(try XCTUnwrap(PlanMath.project(plan).last).total, 100000)
    }
}
