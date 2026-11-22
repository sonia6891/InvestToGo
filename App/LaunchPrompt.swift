import Foundation

/// One big prompt per launch: whatever comes up by itself over the app (a 口袋會員全開 note, Apple's rating prompt)
/// takes this first, and only one of them gets it in a process's life (a launch is the process's life, however long
/// it stays in the background). Nothing is kept: the next cold launch starts free again.
///
/// The rating prompt (wired when that branch merges) must ask only when
/// `!LaunchPrompt.taken && !MembershipStore.shared.memberOpenNoteWaiting`, so a 7 days' note that will really come up
/// on this launch goes first (one that cannot, such as the summary while the App Store has no price, holds nothing
/// back), and then take it with `LaunchPrompt.take()` once its prompt is on screen, as the notes do.
@MainActor enum LaunchPrompt {
    /// This launch's one prompt has been shown.
    static var taken = false

    /// Takes this launch's prompt: true for the first caller, false for every one after it.
    static func take() -> Bool {
        guard !taken else { return false }
        taken = true
        return true
    }
}
