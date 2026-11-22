import XCTest
@testable import PocketCore

final class DCAReminderPlanTests: XCTestCase {
    private let cal = GameRules.taipei
    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    private func inputs(day: Int = 6, dayBefore: Bool = true, showAmount: Bool = true, amount: Int? = 5000,
                        symbol: String? = "0050", month: String = "2026-11", logged: Bool = false) -> DCAReminderInputs {
        DCAReminderInputs(day: day, minutes: 540, dayBefore: dayBefore, showAmount: showAmount, amount: amount,
                          symbol: symbol, month: month, loggedThisMonth: logged)
    }

    func testAfterThisMonthsDebitStartsNextMonth() {
        let r = DCAReminderPlan.requests(inputs(), now: at(2026, 11, 21, 10))
        XCTAssertEqual(r.count, 24)
        XCTAssertEqual(r.first?.id, "dca-reminder-eve-2026-12")
        XCTAssertEqual(r.first?.fire, at(2026, 12, 5))
        XCTAssertEqual(r[1].id, "dca-reminder-2026-12")
        XCTAssertEqual(r[1].fire, at(2026, 12, 6))
        XCTAssertEqual(r.last?.id, "dca-reminder-2027-11")
    }
    func testBeforeThisMonthsDebitIncludesThisMonth() {
        let r = DCAReminderPlan.requests(inputs(), now: at(2026, 11, 3, 8))
        XCTAssertEqual(r.count, 24)
        XCTAssertEqual(r.first?.id, "dca-reminder-eve-2026-11")
        XCTAssertEqual(r.first?.fire, at(2026, 11, 5))
        XCTAssertEqual(r.last?.id, "dca-reminder-2027-10")
    }
    func testLoggedThisMonthSkipsIt() {
        let r = DCAReminderPlan.requests(inputs(logged: true), now: at(2026, 11, 3, 8))
        XCTAssertEqual(r.count, 24)
        XCTAssertEqual(r.first?.id, "dca-reminder-eve-2026-12")
        XCTAssertEqual(r.last?.id, "dca-reminder-2027-11")
    }
    func testUnloggedMonthIsScheduledAgain() {
        let now = at(2026, 11, 3, 8)
        XCTAssertFalse(DCAReminderPlan.requests(inputs(logged: true), now: now).contains { $0.id == "dca-reminder-2026-11" })
        XCTAssertTrue(DCAReminderPlan.requests(inputs(logged: false), now: now).contains { $0.id == "dca-reminder-2026-11" })
    }
    func testEvePassedDayAhead() {
        let r = DCAReminderPlan.requests(inputs(), now: at(2026, 11, 5, 10))
        XCTAssertEqual(r.count, 23)
        XCTAssertEqual(r.first?.id, "dca-reminder-2026-11")
        XCTAssertFalse(r.contains { $0.id == "dca-reminder-eve-2026-11" })
        XCTAssertEqual(r.last?.id, "dca-reminder-2027-10")
    }
    func testNoDayBefore() {
        let r = DCAReminderPlan.requests(inputs(dayBefore: false), now: at(2026, 11, 21))
        XCTAssertEqual(r.count, 12)
        XCTAssertFalse(r.contains { $0.id.contains("-eve-") })
    }
    func testDayThreeEveIsTheSecond() {
        let r = DCAReminderPlan.requests(inputs(day: 3), now: at(2026, 11, 21))
        XCTAssertEqual(r.first?.id, "dca-reminder-eve-2026-12")
        XCTAssertEqual(r.first?.fire, at(2026, 12, 2))
    }
    func testTexts() {
        let now = at(2026, 11, 21)
        func pair(_ i: DCAReminderInputs) -> [String] {
            let r = DCAReminderPlan.requests(i, now: now)
            XCTAssertTrue(r.allSatisfy { $0.userInfo == ["route": "quickDCA"] })
            return [r[0].title, r[0].body, r[1].title, r[1].body]
        }
        XCTAssertEqual(pair(inputs()), ["定期定額提醒", "明天扣款日，帳戶記得留 5,000 元", "今天扣款日", "每月 5,000 元・0050，記一筆讓連續定投接下去"])
        XCTAssertEqual(pair(inputs(showAmount: false)), ["定期定額提醒", "明天扣款日，記得確認定期定額", "今天扣款日", "記得確認定期定額"])
        XCTAssertEqual(pair(inputs(amount: nil)), ["定期定額提醒", "明天是每月 6 日的扣款日。", "定期定額提醒", "今天是每月 6 日的扣款日，記得確認定期定額。"])
        XCTAssertEqual(pair(inputs(symbol: nil)), pair(inputs(amount: nil)))
    }
    func testIdsAreUnique() {
        let ids = DCAReminderPlan.requests(inputs(), now: at(2026, 11, 3)).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
