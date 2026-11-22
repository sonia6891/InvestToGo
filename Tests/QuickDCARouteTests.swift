import XCTest
@testable import ETFToGo

/// When a request for 記一筆 (the lobby's button, or a tapped debit-day reminder) opens the sheet (final review I2, I3).
final class QuickDCARouteTests: XCTestCase {
    private func free(onScreen: Bool = true, covered: Bool = false, modalPending: Bool = false, note: Bool = false,
                      locked: Bool = false, replaying: Bool = false, closing: Bool = false) -> Bool {
        QuickDCARoute.lobbyFree(onScreen: onScreen, covered: covered, modalPending: modalPending, note: note,
                                locked: locked, replaying: replaying, closing: closing)
    }

    func testLobbyFreeOnlyWithNothingElseUp() {
        XCTAssertTrue(free())
        XCTAssertFalse(free(onScreen: false), "Under a feature screen")
        XCTAssertFalse(free(covered: true), "Under LEVEL×UP")
        XCTAssertFalse(free(modalPending: true), "LEVEL×UP is about to come up")
        XCTAssertFalse(free(note: true), "A 口袋會員全開 note is up or about to come up")
        XCTAssertFalse(free(locked: true), "Under the app lock screen or its privacy cover")
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

    /// Never 記一筆 over a 口袋會員全開 note: the request waits (it is kept) and opens once the note has gone.
    func testWaitsForAMemberOpenNoteThenOpens() {
        XCTAssertEqual(QuickDCARoute.decide(locked: false, showing: false, free: free(note: true)), .wait, "The note is up")
        XCTAssertEqual(QuickDCARoute.decide(locked: false, showing: false, free: free(note: false)), .open, "The note has gone")
    }

    /// A reminder tapped on a warm return past the lock's grace: the request waits under the lock, and opens once it is
    /// passed (merge follow-up M1).
    func testWaitsForTheAppLockThenOpens() {
        XCTAssertEqual(QuickDCARoute.decide(locked: false, showing: false, free: free(locked: true)), .wait, "Locked")
        XCTAssertEqual(QuickDCARoute.decide(locked: false, showing: false, free: free(locked: false)), .open, "Unlocked")
    }

    /// The note's button went to 會員: a request that waited for the note is dropped; any other close keeps it.
    func testANoteThatGoesToMemberDropsTheWaitingRequest() {
        XCTAssertFalse(QuickDCARoute.keepsRequest(afterNoteToMember: true), "The person chose to go elsewhere")
        XCTAssertTrue(QuickDCARoute.keepsRequest(afterNoteToMember: false), "Closed: 記一筆 opens now")
    }

    /// A sheet asked for whose content never came on screen is let go; one that came up, or none asked for, is not.
    func testSheetWatchdog() {
        XCTAssertTrue(SheetWatchdog.dropped(asked: true, appeared: false), "UIKit dropped the presentation")
        XCTAssertFalse(SheetWatchdog.dropped(asked: true, appeared: true), "On screen")
        XCTAssertFalse(SheetWatchdog.dropped(asked: false, appeared: false), "Nothing asked for")
        XCTAssertGreaterThanOrEqual(SheetWatchdog.grace, .seconds(1), "Longer than a sheet takes to come up")
    }

    /// 記一筆 up, or asked for and on its way: the notes and the rating sheet give way to it.
    func testBusyWhileUpOrAskedFor() {
        XCTAssertFalse(QuickDCARoute.busy(showing: false, requested: false))
        XCTAssertTrue(QuickDCARoute.busy(showing: true, requested: false), "The sheet is up")
        XCTAssertTrue(QuickDCARoute.busy(showing: false, requested: true), "A tap or a tapped reminder is on its way")
        XCTAssertTrue(QuickDCARoute.busy(showing: true, requested: true))
    }

    /// 記一筆 is asked for by the person: opening it (`AppRouter.openQuickDCA`, the lobby's one way in) never takes this
    /// launch's one big prompt, so a note or the rating sheet can still come up after it in the same launch.
    @MainActor func testOpeningTheSheetLeavesTheLaunchPromptFree() {
        let taken = LaunchPrompt.taken
        defer { LaunchPrompt.taken = taken }
        LaunchPrompt.taken = false
        let router = AppRouter()
        router.quickDCARequested = true
        router.openQuickDCA()
        XCTAssertFalse(router.quickDCARequested, "The request is answered")
        XCTAssertTrue(router.quickDCAShowing)
        XCTAssertFalse(LaunchPrompt.taken, "記一筆 did not take the launch's prompt")
        XCTAssertTrue(LaunchPrompt.take(), "A note or the rating sheet still can")
        router.quickDCAClosed()
    }

    @MainActor func testRouterPublishesTheSheet() {
        let router = AppRouter()
        XCTAssertFalse(router.quickDCAShowing)
        router.quickDCAOpened()
        XCTAssertTrue(router.quickDCAShowing)
        router.quickDCAClosed()
        XCTAssertFalse(router.quickDCAShowing)
    }

    @MainActor func testRouterPublishesTheMemberOpenNote() {
        let router = AppRouter()
        XCTAssertFalse(router.memberNoteShowing)
        router.memberNoteOpened()
        XCTAssertTrue(router.memberNoteShowing)
        router.memberNoteClosed()
        XCTAssertFalse(router.memberNoteShowing)
        router.memberNoteClosed()
        XCTAssertFalse(router.memberNoteShowing, "Closing twice is harmless")
    }
}
