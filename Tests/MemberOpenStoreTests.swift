import XCTest
@testable import ETFToGo

/// 口袋會員前 7 天全開 through `MembershipStore`'s one gate: every member feature opens and closes with the 7 days, by
/// an injected clock and an in-memory vault.
@MainActor final class MemberOpenStoreTests: XCTestCase {
    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    /// 2026-11-22 14:30 in Taipei.
    private let start = Date(timeIntervalSince1970: 1_795_329_000)
    private let day: TimeInterval = 86_400

    /// A non-member's store a minute into `day` of the 7 days.
    private func store(day n: Int, clock: Clock, vault: MemoryMemberOpenVault = MemoryMemberOpenVault()) -> MembershipStore {
        vault.record = vault.record ?? MemberOpenRecord(start: start)
        clock.now = start.addingTimeInterval(Double(n - 1) * day + 60)
        let store = MembershipStore(memberOpen: MemberOpenDays(vault: vault, now: { clock.now }))
        store.demoMember = false
        store.apply([])
        return store
    }

    func testTheSevenDaysOpenEveryMemberFeature() {
        let clock = Clock(start)
        for n in 1...7 {
            let store = store(day: n, clock: clock)
            for feature in MemberFeature.allCases { XCTAssertTrue(store.has(feature), "\(feature) is open on day \(n)") }
            XCTAssertTrue(store.wearsMemberSkins, "全部外觀主題 on day \(n)")
            XCTAssertEqual(store.open.day, n)
        }
    }

    func testDayEightLocksEveryMemberFeatureAgain() {
        let store = store(day: 8, clock: Clock(start))
        for feature in MemberFeature.allCases { XCTAssertFalse(store.has(feature), "\(feature) is locked on day 8") }
        XCTAssertFalse(store.wearsMemberSkins)
        XCTAssertTrue(store.open.ended)
    }

    /// Read between two refreshes, the gate is still closed past the end.
    func testTheGateClosesAtTheEndBeforeAnyRefresh() {
        let clock = Clock(start)
        let store = store(day: 7, clock: clock)
        XCTAssertTrue(store.has(.backtest))
        clock.now = start.addingTimeInterval(7 * day + 1)
        XCTAssertFalse(store.has(.backtest), "closed at the end")
        store.refreshOpen()
        XCTAssertFalse(store.open.active)
    }

    func testAMemberStaysAMemberWithNoNotes() {
        let clock = Clock(start), vault = MemoryMemberOpenVault()
        let store = store(day: 3, clock: clock, vault: vault)
        store.apply([MembershipProducts.pocketMonthly])
        XCTAssertTrue(store.has(.report))
        XCTAssertNil(store.memberOpen.due(member: true))
        // The subscription lapses months later: no summary and no 再考慮 about a plan that was bought.
        clock.now = start.addingTimeInterval(120 * day)
        store.apply([])
        XCTAssertFalse(store.has(.report))
        XCTAssertNil(store.memberOpen.due(member: false))
    }

    func testOnlyANonMembersUseIsCounted() {
        let clock = Clock(start)
        let store = store(day: 2, clock: clock)
        store.noteUse(.backtest)
        store.noteUse(.priceAlerts)
        XCTAssertEqual(store.memberOpen.usedFeatures(), [.backtest, .priceAlerts])

        let member = self.store(day: 2, clock: clock)
        member.apply([MembershipProducts.pocketMonthly])
        member.noteUse(.report)
        XCTAssertEqual(member.memberOpen.usedFeatures(), [], "a member's use is not the 7 days'")
    }

    func testTheSummaryOnlyForANonMemberAfterDaySeven() {
        let clock = Clock(start)
        let store = store(day: 8, clock: clock)
        XCTAssertEqual(store.memberOpen.due(member: store.isMember), .ended)
        store.apply([MembershipProducts.pocketMonthly])
        XCTAssertNil(store.memberOpen.due(member: store.isMember))
    }

    // MARK: Launches

    /// UI tests have the 7 days off unless `--member-open <day>` says which day it is; existing tests that check a
    /// locked member tool keep working unchanged.
    func testUITestsHaveTheDaysOffUnlessAsked() {
        XCTAssertEqual(MemberOpenDays.forLaunch(arguments: ["--ui-testing"], environment: [:]).info(), .off)
        let second = MemberOpenDays.forLaunch(arguments: ["--ui-testing", "--member-open", "2"], environment: [:]).info()
        XCTAssertTrue(second.active)
        XCTAssertEqual(second.day, 2)
        let eighth = MemberOpenDays.forLaunch(arguments: ["--ui-testing", "--member-open", "8"], environment: [:])
        XCTAssertTrue(eighth.info().ended)
        XCTAssertEqual(eighth.due(member: false), .ended)
        XCTAssertNil(MemberOpenDays.forLaunch(arguments: ["--ui-testing", "--member-open", "2"], environment: [:]).due(member: false),
                     "no note on a day that has none, so it never sits over a test")
    }

    func testTheUnitTestHostHasTheDaysOff() {
        let days = MemberOpenDays.forLaunch(arguments: [], environment: ["XCTestConfigurationFilePath": "/tmp/x"])
        XCTAssertEqual(days.info(), .off)
        let store = MembershipStore()
        store.demoMember = false
        store.apply([])
        XCTAssertFalse(store.has(.backtest), "the shared gate stays closed in the unit-test host")
    }

    func testTheMemberPageSaysTheSevenDays() {
        XCTAssertEqual(MemberView.tag(member: true, open: nil), "你是會員・全部外觀主題已解鎖")
        XCTAssertEqual(MemberView.tag(member: false, open: nil), "看懂・規劃・回顧")
        let open = MemberOpenInfo.of(start: start, now: start.addingTimeInterval(60))
        XCTAssertTrue(MemberView.tag(member: false, open: open).hasPrefix("全開中・"))
        XCTAssertTrue(MemberView.tag(member: false, open: open).hasSuffix(" 結束"))
    }
}
