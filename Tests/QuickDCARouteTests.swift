import XCTest
@testable import ETFToGo

/// When a request for 記一筆 (the lobby's button, or a tapped debit-day reminder) opens the sheet (final review I2, I3).
final class QuickDCARouteTests: XCTestCase {
    private func free(onScreen: Bool = true, covered: Bool = false, modalPending: Bool = false, replaying: Bool = false, closing: Bool = false) -> Bool {
        QuickDCARoute.lobbyFree(onScreen: onScreen, covered: covered, modalPending: modalPending, replaying: replaying, closing: closing)
    }

    func testLobbyFreeOnlyWithNothingElseUp() {
        XCTAssertTrue(free())
        XCTAssertFalse(free(onScreen: false), "Under a feature screen")
        XCTAssertFalse(free(covered: true), "Under LEVEL×UP")
        XCTAssertFalse(free(modalPending: true), "LEVEL×UP is about to come up")
        XCTAssertFalse(free(replaying: true), "The replay is playing")
        XCTAssertFalse(free(closing: true), "The sheet is still closing")
    }

    /// A reminder tapped on a locked phone: the request waits while the records are locked (it is not thrown away),
    /// and the sheet opens once they are read.
    func testLockedWaitsThenOpensOnceRead() {
        XCTAssertEqual(QuickDCARoute.decide(locked: true, showing: false, free: true), .wait, "Never over locked records")
        XCTAssertEqual(QuickDCARoute.decide(locked: true, showing: false, free: false), .wait)
        XCTAssertEqual(QuickDCARoute.decide(locked: false, showing: false, free: true), .open, "Read: the sheet opens")
    }

    func testWaitsForTheLobbyAndDropsWhenAlreadyUp() {
        XCTAssertEqual(QuickDCARoute.decide(locked: false, showing: false, free: free(replaying: true)), .wait)
        XCTAssertEqual(QuickDCARoute.decide(locked: false, showing: false, free: free(modalPending: true)), .wait)
        XCTAssertEqual(QuickDCARoute.decide(locked: false, showing: true, free: false), .drop, "The sheet is already up")
    }

    @MainActor func testRouterPublishesTheSheet() {
        let router = AppRouter()
        XCTAssertFalse(router.quickDCAShowing)
        router.quickDCAOpened()
        XCTAssertTrue(router.quickDCAShowing)
        router.quickDCAClosed()
        XCTAssertFalse(router.quickDCAShowing)
    }
}
