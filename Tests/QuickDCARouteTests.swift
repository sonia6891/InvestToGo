import XCTest
@testable import ETFToGo

/// When a request for 記一筆 (the lobby's button, or a tapped debit-day reminder) opens the sheet (final review I2, I3).
final class QuickDCARouteTests: XCTestCase {
    private func free(onScreen: Bool = true, covered: Bool = false, modalPending: Bool = false, note: Bool = false,
                      replaying: Bool = false, closing: Bool = false) -> Bool {
        QuickDCARoute.lobbyFree(onScreen: onScreen, covered: covered, modalPending: modalPending, note: note,
                                replaying: replaying, closing: closing)
    }

    func testLobbyFreeOnlyWithNothingElseUp() {
        XCTAssertTrue(free())
        XCTAssertFalse(free(onScreen: false), "Under a feature screen")
        XCTAssertFalse(free(covered: true), "Under LEVEL×UP")
        XCTAssertFalse(free(modalPending: true), "LEVEL×UP is about to come up")
        XCTAssertFalse(free(note: true), "A 口袋會員全開 note is up or about to come up")
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

    /// 記一筆 up, or asked for and on its way: the notes and the rating sheet give way to it.
    func testBusyWhileUpOrAskedFor() {
        XCTAssertFalse(QuickDCARoute.busy(showing: false, requested: false))
        XCTAssertTrue(QuickDCARoute.busy(showing: true, requested: false), "The sheet is up")
        XCTAssertTrue(QuickDCARoute.busy(showing: false, requested: true), "A tap or a tapped reminder is on its way")
        XCTAssertTrue(QuickDCARoute.busy(showing: true, requested: true))
    }

    /// 記一筆 is asked for by the person: it never takes this launch's one big prompt, so a note or the rating sheet
    /// can still come up after it in the same launch.
    @MainActor func testOpeningTheSheetLeavesTheLaunchPromptFree() {
        let taken = LaunchPrompt.taken
        defer { LaunchPrompt.taken = taken }
        LaunchPrompt.taken = false
        let router = AppRouter()
        router.quickDCARequested = true
        XCTAssertEqual(QuickDCARoute.decide(locked: false, showing: router.quickDCAShowing, free: free()), .open)
        router.quickDCARequested = false
        router.quickDCAOpened()
        router.quickDCAClosed()
        XCTAssertFalse(LaunchPrompt.taken)
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
