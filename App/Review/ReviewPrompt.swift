import StoreKit
import UIKit

// App Store 評分視窗 (owner, 2026-11-22: the rating sheet, the meow-work way): Apple's own rating sheet, asked for
// once ever, as meow-work's assets/meow-v4-review.js does, adapted to an app without a trial:
//   * on day 1, the first day of use (owner, 2026-11-22: moved from day 3 to day 1), once onboarding is finished and
//     the person is in the app (never during the first-launch flow); an ask that did not happen (the screen never came
//     free, or the app left the front) is tried again on later opens, up to calendar day 7 counted from the first open
//     (day 1), never after;
//   * never over the opening, the lock screen or privacy cover, onboarding, a sheet or full-screen cover (LEVEL×UP,
//     記一筆), an alert, a purchase in progress or an open keyboard: it waits until the screen has been free of them for
//     1.5 s, and gives up after 90 s (the next open tries again, while still in the window);
//   * no pre-prompt, no reward, no text of our own (App Review Guideline 5.6.1); Apple decides whether the sheet shows;
//   * no active window scene (the app went to the background): nothing was shown, so it is not counted as asked.
// The state is this phone's only (UserDefaults, never in the app's backup file). Never under --ui-testing, in the
// unit-test host or in previews.

/// The days of use, as kept on this phone.
struct ReviewDays: Equatable {
    /// The first day used, `yyyy-MM-dd` (local, Gregorian).
    var first: String?
    /// How many distinct local days the app has been used.
    var days = 0
    /// The last day counted.
    var last: String?
    /// The sheet has been asked for (once ever).
    var asked = false
}

enum ReviewRules {
    /// The distinct day of use that asks: the first (owner, 2026-11-22).
    static let askDay = 1
    /// The last calendar day (counted from the first open, which is day 1) on which a missed ask is tried again.
    static let lastDay = 7

    /// Today counted as a day of use (once per day).
    static func counted(_ state: ReviewDays, today: String) -> ReviewDays {
        var next = state
        if next.first == nil { next.first = today }
        if next.last != today {
            next.last = today
            next.days += 1
        }
        return next
    }

    /// Calendar day number since the first open (the first open's day is 1); nil when a day cannot be read.
    static func calendarDay(first: String, today: String) -> Int? {
        guard let start = parse(first), let now = parse(today) else { return nil }
        return Int((now.timeIntervalSince(start) / 86_400).rounded()) + 1
    }

    /// Not asked yet, a day of use counted (`askDay`), and still within calendar day 7.
    static func eligible(_ state: ReviewDays, today: String) -> Bool {
        guard !state.asked, state.days >= askDay, let first = state.first,
              let day = calendarDay(first: first, today: today) else { return false }
        return day <= lastDay
    }

    private static func parse(_ day: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)
    }
}

/// Counts the days of use and asks for the rating sheet at the right moment.
@MainActor final class ReviewPrompt {
    static let firstKey = "review.firstDay", daysKey = "review.days", lastKey = "review.lastDay", askedKey = "review.asked"

    static let shared = ReviewPrompt(
        defaults: .standard,
        // Debug builds may ask (StoreKit always shows the sheet there, which is how it is checked by hand); never in UI
        // tests, the unit-test host or previews.
        allowed: UsageGate.allowed(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment,
                                   debug: false),
        now: { Date() }, timeZone: { TimeZone.current })

    /// One check of the screen; `settle` free checks in a row ask; `limit` checks at most (0.5 s × 3 = 1.5 s, × 180 = 90 s).
    var tick: Duration = .milliseconds(500)
    var settle = 3
    var limit = 180

    private let defaults: UserDefaults
    private let allowed: Bool
    private let now: () -> Date
    private let timeZone: () -> TimeZone
    /// Each `opened` takes the next number; an older wait that sees a newer one stops, so a quick re-trigger (the app
    /// left the front and came straight back) is never turned away by the wait it replaces.
    private var generation = 0
    private var keyboardUp = false
    /// Moments the app knows are coming that the sheet must not cover (LEVEL×UP on its way, the lobby's replay).
    private(set) var holds: Set<String> = []
    private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults, allowed: Bool, now: @escaping () -> Date, timeZone: @escaping () -> TimeZone) {
        self.defaults = defaults
        self.allowed = allowed
        self.now = now
        self.timeZone = timeZone
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.keyboardUp = true }
            },
            center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.keyboardUp = false }
            },
        ]
    }

    /// The sheet waits while `reason` is held ("levelUp", "replay"…).
    func hold(_ reason: String) { holds.insert(reason) }
    func release(_ reason: String) { holds.remove(reason) }
    func hold(_ reason: String, while on: Bool) { if on { hold(reason) } else { release(reason) } }

    var state: ReviewDays {
        get {
            ReviewDays(first: defaults.string(forKey: Self.firstKey), days: defaults.integer(forKey: Self.daysKey),
                       last: defaults.string(forKey: Self.lastKey), asked: defaults.bool(forKey: Self.askedKey))
        }
        set {
            defaults.set(newValue.first, forKey: Self.firstKey)
            defaults.set(newValue.days, forKey: Self.daysKey)
            defaults.set(newValue.last, forKey: Self.lastKey)
            defaults.set(newValue.asked, forKey: Self.askedKey)
        }
    }

    /// The app is in front past the opening, the lock and onboarding (`LaunchGate`): today is counted, and on an
    /// eligible day the sheet is asked for once the screen has been free for `settle` checks. Cancelled (the app left
    /// the front, the lock came up) or `limit` checks without a free moment: not asked, tried again on the next open.
    /// `busy` and `request` are the screen and StoreKit; `request` returns false when there was no active scene.
    /// Returns true when the sheet was asked for.
    @discardableResult
    func opened(busy: @MainActor () -> Bool = ReviewPrompt.screenBusy,
                request: @MainActor () -> Bool = ReviewPrompt.requestReview) async -> Bool {
        guard allowed else { return false }
        let today = UsageClock.day(now(), timeZone: timeZone())
        state = ReviewRules.counted(state, today: today)
        generation += 1
        let mine = generation
        guard ReviewRules.eligible(state, today: today) else { return false }
        var free = 0
        for _ in 0..<limit {
            do { try await Task.sleep(for: tick) } catch { return false }
            guard generation == mine else { return false }
            if busy() || keyboardUp || !holds.isEmpty { free = 0; continue }
            free += 1
            guard free >= settle else { continue }
            guard ReviewRules.eligible(state, today: today) else { return false }
            // One big prompt per launch, and a 口袋會員全開 note that will come up on this launch goes first: then nothing
            // is recorded and a later launch asks. Taken just before the request (the scene was in front a moment ago,
            // in the same busy check).
            guard launchFree(), takeLaunch(), request() else { return false }
            state.asked = true
            return true
        }
        return false
    }

    /// This launch's one prompt is free: nothing has taken it, and no 7 days' note is waiting to come up
    /// (`LaunchPrompt`, `MembershipStore.memberOpenNoteWaiting`; a note that cannot show, such as the summary with no
    /// price from the App Store, holds nothing back).
    var launchFree: @MainActor () -> Bool = {
        ReviewPrompt.launchFree(taken: LaunchPrompt.taken, noteWaiting: MembershipStore.shared.memberOpenNoteWaiting)
    }
    /// Takes this launch's prompt (`LaunchPrompt.take`).
    var takeLaunch: @MainActor () -> Bool = { LaunchPrompt.take() }

    nonisolated static func launchFree(taken: Bool, noteWaiting: Bool) -> Bool { !taken && !noteWaiting }

    /// Anything the sheet must never cover, one check each (another is one more line): the lock screen or cover, a
    /// purchase, no scene in front, a window above the app's (the lock window fading out), or a sheet, full-screen
    /// cover or alert presented in any window. The holds and the keyboard are checked in `opened`.
    static let busyChecks: [@MainActor () -> Bool] = [
        { AppLock.shared.locked || AppLock.shared.covered },
        { MembershipStore.shared.purchasing },
        { !ReviewPrompt.windowScenes().contains { $0.activationState == .foregroundActive } },
        { ReviewPrompt.windowScenes().flatMap(\.windows).contains { !$0.isHidden && $0.windowLevel > .normal } },
        { ReviewPrompt.windowScenes().flatMap(\.windows).contains { !$0.isHidden && $0.rootViewController?.presentedViewController != nil } },
    ]

    static func screenBusy() -> Bool { busyChecks.contains { $0() } }

    fileprivate static func windowScenes() -> [UIWindowScene] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    }

    /// Apple's rating sheet in the scene in front; false (not asked) when no scene is in front.
    static func requestReview() -> Bool {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return false }
        // iOS 16+ (the app needs 18, so SKStoreReviewController's fallback is never reached).
        AppStore.requestReview(in: scene)
        return true
    }
}
