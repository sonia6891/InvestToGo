import Foundation

/// Where the app was asked to go from outside it, and what the lobby has up. A tapped debit-day reminder (or the
/// lobby's own 「記一筆」) asks for 記一筆; the lobby opens the sheet once it is free and the records can be read, then
/// clears the request.
@MainActor final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var quickDCARequested = false
    /// 記一筆 is on screen, from the moment it opens until it has gone. Other prompts (LEVEL×UP, and later the app
    /// lock and the member-open notes) wait for it, as it waits for them.
    @Published private(set) var quickDCAShowing = false

    func quickDCAOpened() { quickDCAShowing = true }
    func quickDCAClosed() { if quickDCAShowing { quickDCAShowing = false } }
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
    /// toast), no replay is playing, and the sheet is not still closing.
    static func lobbyFree(onScreen: Bool, covered: Bool, modalPending: Bool, replaying: Bool, closing: Bool) -> Bool {
        onScreen && !covered && !modalPending && !replaying && !closing
    }

    /// Never over locked records: the request waits and the sheet opens once they are read (the phone was just
    /// unlocked by the tap, so that is in the same activation).
    static func decide(locked: Bool, showing: Bool, free: Bool) -> QuickDCARoute {
        if showing { return .drop }
        if locked { return .wait }
        return free ? .open : .wait
    }
}
