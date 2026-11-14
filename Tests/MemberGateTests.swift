import XCTest
@testable import ETFToGo

final class MemberGateTests: XCTestCase {
    func testDemoMemberNeedsUITesting() {
        XCTAssertFalse(MembershipStore.demoMember(from: ["--demo-member"]))
        XCTAssertTrue(MembershipStore.demoMember(from: ["--ui-testing", "--demo-member"]))
    }

    @MainActor func testHasFollowsMembership() {
        let store = MembershipStore()
        store.demoMember = false
        store.apply([])
        XCTAssertFalse(store.has(.backtest))
        store.apply([MembershipProducts.pocketMonthly])
        XCTAssertTrue(store.has(.backtest))
    }

    @MainActor func testDemoMemberWinsOverStoreKit() {
        let store = MembershipStore()
        store.apply([])
        store.demoMember = true
        XCTAssertTrue(store.has(.backtest))
    }
}
