import XCTest
@testable import PocketCore

final class GoalPlannerTests: XCTestCase {
    func testTenYearsThreeMillionAtSixPercent() {
        XCTAssertEqual(GoalPlanner.monthlyContribution(target: 3_000_000, years: 10, current: 0, annualReturn: 6), 18464.56, accuracy: 0.01)
    }
    func testExistingMoneyReducesContribution() {
        XCTAssertEqual(GoalPlanner.monthlyContribution(target: 3_000_000, years: 10, current: 500_000, annualReturn: 6), 12953.35, accuracy: 0.01)
    }
    func testZeroReturnIsStraightDivision() {
        XCTAssertEqual(GoalPlanner.monthlyContribution(target: 3_000_000, years: 10, current: 0, annualReturn: 0), 25000.0, accuracy: 0.0001)
    }
    func testAlreadyThereIsZero() {
        XCTAssertEqual(GoalPlanner.monthlyContribution(target: 3_000_000, years: 10, current: 4_000_000, annualReturn: 6), 0)
    }
    func testBadInputIsZero() {
        XCTAssertEqual(GoalPlanner.monthlyContribution(target: 3_000_000, years: 0, current: 0, annualReturn: 6), 0)
        XCTAssertEqual(GoalPlanner.monthlyContribution(target: .nan, years: 10, current: 0, annualReturn: 6), 0)
    }
    func testScenariosUseComboRates() {
        let s = GoalPlanner.scenarios(target: 3_000_000, years: 10, current: 0, annualReturn: 6)
        XCTAssertEqual(s.map(\.scenario), [.optimistic, .base, .conservative])
        XCTAssertEqual(s.map(\.annualReturn), [9, 6, -1])
        XCTAssertTrue(s[0].monthly < s[1].monthly && s[1].monthly < s[2].monthly)
    }
}
