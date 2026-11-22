import Foundation

/// Where the app was asked to go from outside it, and what the lobby has up. A tapped debit-day reminder (or the
/// lobby's own 「記一筆」) asks for 記一筆; the lobby opens the sheet once it is free and the records can be read, then
/// clears the request.
@MainActor final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var quickDCARequested = false
    /// 記一筆 is on screen, from the moment it opens until it has gone. Other prompts (LEVEL×UP, the member-open notes,
    /// the rating sheet) wait for it; it waits in turn for LEVEL×UP, a note and the app lock (`QuickDCARoute.lobbyFree`).
    @Published private(set) var quickDCAShowing = false
    /// A 口袋會員全開 note is over the lobby, from the moment it is chosen (about to present) until its sheet has gone:
    /// 記一筆 waits for it, and a waiting request opens once it has gone.
    @Published private(set) var memberNoteShowing = false

    func quickDCAOpened() { quickDCAShowing = true }
    /// The router's part of opening 記一筆: the request is answered and the sheet is up. Nothing else: 記一筆 is asked
    /// for by the person, so it never takes `LaunchPrompt`.
    func openQuickDCA() {
        quickDCARequested = false
        quickDCAOpened()
    }
    func quickDCAClosed() { if quickDCAShowing { quickDCAShowing = false } }
    func memberNoteOpened() { memberNoteShowing = true }
    func memberNoteClosed() { if memberNoteShowing { memberNoteShowing = false } }
}

/// What a request for 記一筆 does now (final review I2, I3).
enum QuickDCARoute: Equatable {
    /// Kept for later: the records are locked, or the lobby is not free yet.
    case wait
    /// The sheet opens and the request is cleared.
    case open
    /// Cleared without opening: the sheet is already up.
    case drop

    /// The lobby can take 記一筆: it is in front, nothing covers it or is about to (LEVEL×UP, or its wait for a
    /// toast; a 口袋會員全開 note, `note`; the app lock screen or its privacy cover, `locked`), no replay is playing, and
    /// the sheet is not still closing.
    static func lobbyFree(onScreen: Bool, covered: Bool, modalPending: Bool, note: Bool, locked: Bool, replaying: Bool,
                          closing: Bool) -> Bool {
        onScreen && !covered && !modalPending && !note && !locked && !replaying && !closing
    }

    /// Never over locked records: the request waits and the sheet opens once they are read (the phone was just
    /// unlocked by the tap, so that is in the same activation).
    static func decide(locked: Bool, showing: Bool, free: Bool) -> QuickDCARoute {
        if showing { return .drop }
        if locked { return .wait }
        return free ? .open : .wait
    }

    /// 記一筆 is up or asked for (a tap, or a tapped reminder, on its way to the sheet). The prompts that come up by
    /// themselves give way to it: a 口袋會員全開 note waits (later in this launch if `LaunchPrompt` is still free,
    /// otherwise the next), and the rating sheet is held ("quickDCA") and asks again once it is released. 記一筆 is
    /// asked for by the person, so it never takes `LaunchPrompt` itself.
    static func busy(showing: Bool, requested: Bool) -> Bool { showing || requested }

    /// A 口袋會員全開 note has gone. Its button went to 會員 (`toMember`): a 記一筆 request that waited for it is
    /// dropped, since the person chose to go elsewhere (ruling, merge follow-up M5); otherwise it is kept and opens now.
    static func keepsRequest(afterNoteToMember toMember: Bool) -> Bool { !toMember }
}

/// A sheet that was asked for but never came up (UIKit dropped the presentation): after `grace` without its content's
/// `onAppear`, the request is let go, so a flag such as `memberNoteShowing` or `quickDCAShowing` never stays up for the
/// rest of the launch with nothing on screen.
enum SheetWatchdog {
    static let grace: Duration = .seconds(3)
    static func dropped(asked: Bool, appeared: Bool) -> Bool { asked && !appeared }
}
