import XCTest
@testable import ETFToGo

final class DCARemindersTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "DCARemindersTests"
    private var now: Date { GameRules.taipei.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 12))! }

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func turnOn(day: Int = 6, minutes: Int = 540, eve: Bool = true) {
        defaults.set(true, forKey: Onboarding.remindKey)
        defaults.set(day, forKey: Onboarding.dayKey)
        defaults.set(minutes, forKey: Onboarding.remindMinutesKey)
        defaults.set(eve, forKey: Onboarding.remindEveKey)
    }
    private func buy(_ on: Date) -> Trade {
        Trade(date: on, action: .buy, holding: Holding(symbol: "0050", name: "測試", shares: 100, unitCost: 10, broker: "", strategy: .saving))
    }

    func testInputsOffWhenReminderOff() {
        defaults.set(false, forKey: Onboarding.remindKey)
        defaults.set(6, forKey: Onboarding.dayKey)
        XCTAssertNil(DCAReminders.inputs(Portfolio(), defaults: defaults, now: now))
        defaults.set(true, forKey: Onboarding.remindKey)
        defaults.set(0, forKey: Onboarding.dayKey)
        XCTAssertNil(DCAReminders.inputs(Portfolio(), defaults: defaults, now: now))
    }

    func testInputsFromSettingsAndPreset() {
        turnOn()
        var data = Portfolio()
        data.quickDCA = QuickDCAPreset(symbol: "0050", amount: 5000, broker: "")
        XCTAssertEqual(DCAReminders.inputs(data, defaults: defaults, now: now),
                       DCAReminderInputs(day: 6, minutes: 540, dayBefore: true, showAmount: true, amount: 5000, symbol: "0050",
                                         month: YearMonth(now).key, loggedThisMonth: false))
    }

    func testInputsFallBackToOnboardingValues() {
        turnOn()
        defaults.set("006208", forKey: Onboarding.symbolKey)
        defaults.set(3000, forKey: Onboarding.monthlyKey)
        let result = DCAReminders.inputs(Portfolio(), defaults: defaults, now: now)
        XCTAssertEqual(result?.amount, 3000)
        XCTAssertEqual(result?.symbol, "006208")
    }

    func testShowAmountOff() {
        turnOn()
        defaults.set(false, forKey: DCAReminders.showAmountKey)
        XCTAssertEqual(DCAReminders.inputs(Portfolio(), defaults: defaults, now: now)?.showAmount, false)
    }

    func testLoggedThisMonthFollowsTheRecords() {
        turnOn()
        var data = Portfolio()
        var game = GameState()
        game.dcaMonths = [YearMonth(now)]
        data.game = game
        data.trades = [buy(now)]
        XCTAssertEqual(DCAReminders.inputs(data, defaults: defaults, now: now)?.loggedThisMonth, true)
        data.trades = []
        XCTAssertEqual(DCAReminders.inputs(data, defaults: defaults, now: now)?.loggedThisMonth, false)
    }

    func testOwnIDsIncludeLegacy() {
        XCTAssertEqual(DCAReminders.ownIDs(in: ["dca-reminder", "dca-reminder-eve", "dca-reminder-2026-12", "dca-reminder-eve-2026-12", "dividend-ABC", "price-alert-1"]),
                       ["dca-reminder", "dca-reminder-eve", "dca-reminder-2026-12", "dca-reminder-eve-2026-12"])
    }

    func testDividendReminderCapLeavesRoomForDCA() {
        XCTAssertEqual(DividendReminders.limit, 40)
        XCTAssertLessThanOrEqual(DividendReminders.limit + 24, 64)
    }

    func testResetClearsShowAmount() {
        XCTAssertTrue(Onboarding.keys.contains(DCAReminders.showAmountKey))
    }
}
