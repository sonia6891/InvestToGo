import XCTest
@testable import ETFToGo

/// Final-review fixes outside the game loop: ▲▼ on the older screens (I3), the debit-day reminder settings and the
/// onboarding amount (I5).
final class FinalFixTests: XCTestCase {
    /// Every move the older screens show starts with ▲, ▼ or －, and carries a percentage: never a bare "+1.2%".
    func testLegacyMovesCarryAnArrowAndAPercentage() {
        let pattern = try! NSRegularExpression(pattern: #"^[▲▼－] "#)
        let bare = try! NSRegularExpression(pattern: #"^[+\-−]"#)
        let samples: [(Double, Double?)] = [(5.2, nil), (-3.75, nil), (0, nil), (12.5, 1200), (-6, -60000), (0.001, 1)]
        for (percent, amount) in samples {
            let text = TrendText.text(percent: percent, amount: amount)
            let range = NSRange(text.startIndex..., in: text)
            XCTAssertNotNil(pattern.firstMatch(in: text, range: range), "\(text) starts with a direction")
            XCTAssertNil(bare.firstMatch(in: text, range: range), "\(text) is not a bare signed number")
            XCTAssertTrue(text.hasSuffix("%") || text.hasSuffix("%)"), "\(text) shows a percentage")
        }
        XCTAssertEqual(TrendText.text(percent: 12.5, amount: 1200), "▲ 1,200 (+12.50%)")
        XCTAssertEqual(TrendText.text(percent: -6, amount: -60000), "▼ 60,000 (-6.00%)")
        XCTAssertEqual(TrendText.text(percent: 0), "－ 0.00%", "An exact 0 has no direction (R22)")
        XCTAssertEqual(TrendText.arrowed(-500), "▼ 500")
        XCTAssertEqual(TrendText.arrowed(0), "－ 0")
    }

    func testResultPercentNeedsACost() {
        XCTAssertEqual(TrendText.percent(50, of: 1000), 5)
        XCTAssertNil(TrendText.percent(50, of: 0))
        XCTAssertNil(TrendText.percent(.nan, of: 10))
    }

    func testDebitDayReminderSummary() {
        XCTAssertEqual(DCAReminders.summary(on: true, day: 6, minutes: 9 * 60, dayBefore: false), "每月 6 日 09:00 通知")
        XCTAssertEqual(DCAReminders.summary(on: true, day: 8, minutes: 21 * 60 + 30, dayBefore: true), "每月 8 日 21:30 通知，前一天也提醒")
        XCTAssertEqual(DCAReminders.summary(on: false, day: 6, minutes: 540, dayBefore: false), "每月扣款日通知你確認定期定額")
        XCTAssertEqual(DCAReminders.minutes(DCAReminders.time(21 * 60 + 30)), 21 * 60 + 30)
    }

    func testOnboardingAmountIsThePlanDefault() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "plan-\(UUID().uuidString)"))
        XCTAssertNil(Onboarding.monthlyDefault(defaults))
        defaults.set(3000, forKey: Onboarding.monthlyKey)
        XCTAssertEqual(Onboarding.monthlyDefault(defaults), 3000)
    }

    /// 「查看 n 檔結果」 counts inside the series chip chosen on 找 ETF, as the list will.
    func testFilterSheetCountIncludesTheSeriesChip() {
        let funds = [Fund(id: "0050", name: "元大台灣50", strategy: .saving), Fund(id: "006208", name: "富邦台50", strategy: .saving),
                     Fund(id: "0056", name: "元大高股息", strategy: .income)]
        let none: (String) -> String? = { _ in nil }
        XCTAssertEqual(FilterSheet.count(funds, filter: FundFilter(), series: nil, frequency: none), 3)
        let series = DexSeries.of(funds[2])
        let inSeries = funds.filter { DexSeries.of($0) == series }.count
        XCTAssertEqual(FilterSheet.count(funds, filter: FundFilter(), series: series, frequency: none), inSeries)
        XCTAssertLessThan(inSeries, 3, "The chip narrows the count")
    }

    func testResetNeedsUITesting() {
        // `--reset` alone (a stale scheme argument) never wipes anything: Onboarding.reset is gated the same way as the
        // records and the skin (final review M7).
        let defaults = UserDefaults(suiteName: "reset-\(UUID().uuidString)")!
        defaults.set(true, forKey: Onboarding.doneKey)
        Onboarding.reset(["--reset"], defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: Onboarding.doneKey))
        Onboarding.reset(["--ui-testing", "--reset"], defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: Onboarding.doneKey))
    }
}
