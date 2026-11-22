import UIKit
import XCTest
@testable import ETFToGo

/// App Store 評分視窗: asked once ever, on day 1 (the first day of use); a missed ask is tried again up to
/// calendar day 7 from the first open, never after; only on a free screen; not counted when no scene was in front.
@MainActor final class ReviewPromptTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var date = Date(timeIntervalSince1970: 1_795_316_645) // 2026-11-22 11:04 in Taipei
    private let taipei = TimeZone(identifier: "Asia/Taipei")!

    override func setUp() async throws {
        suite = "ETFToGo.tests.review.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func prompt(allowed: Bool = true) -> ReviewPrompt {
        let zone = taipei
        let prompt = ReviewPrompt(defaults: defaults, allowed: allowed, now: { [unowned self] in self.date }, timeZone: { zone })
        prompt.tick = .milliseconds(1)
        prompt.settle = 3
        prompt.limit = 20
        // This launch's one prompt is free unless a test says otherwise (the real LaunchPrompt is process-wide).
        prompt.launchFree = { true }
        prompt.takeLaunch = { true }
        return prompt
    }

    private func day(_ n: Int) { date = Date(timeIntervalSince1970: 1_795_316_645 + Double(n - 1) * 86_400) }

    /// Opens the app on calendar day `n`; returns whether the sheet was asked for.
    private func open(onDay n: Int, busy: @escaping () -> Bool = { false }, scene: Bool = true, asks: inout Int) async -> Bool {
        day(n)
        var count = 0
        let asked = await prompt().opened(busy: busy, request: { count += 1; return scene })
        asks += count
        return asked
    }

    // MARK: The day rule

    func testDayRule() {
        var s = ReviewDays()
        XCTAssertFalse(ReviewRules.eligible(s, today: "2026-11-22"), "Nothing counted yet")
        s = ReviewRules.counted(s, today: "2026-11-22")
        XCTAssertEqual(s, ReviewDays(first: "2026-11-22", days: 1, last: "2026-11-22", asked: false))
        XCTAssertEqual(ReviewRules.counted(s, today: "2026-11-22"), s, "The same day counts once")
        XCTAssertTrue(ReviewRules.eligible(s, today: "2026-11-22"), "Day 1 asks")
        XCTAssertTrue(ReviewRules.eligible(s, today: "2026-11-28"), "Calendar day 7 still asks")
        XCTAssertFalse(ReviewRules.eligible(s, today: "2026-11-29"), "Calendar day 8 never")
        s.asked = true
        XCTAssertFalse(ReviewRules.eligible(s, today: "2026-11-22"), "Only once")
        XCTAssertEqual(ReviewRules.calendarDay(first: "2026-11-22", today: "2026-11-22"), 1)
        XCTAssertEqual(ReviewRules.calendarDay(first: "2026-11-28", today: "2026-12-04"), 7, "Across a month")
    }

    // MARK: Asking

    func testDayOneAsksOnceAndNeverAgain() async {
        var asks = 0
        let d1 = await open(onDay: 1, asks: &asks)
        XCTAssertTrue(d1, "Day 1 asks")
        let again = await open(onDay: 1, asks: &asks)
        let d2 = await open(onDay: 2, asks: &asks)
        let d5 = await open(onDay: 5, asks: &asks)
        XCTAssertFalse(again)
        XCTAssertFalse(d2)
        XCTAssertFalse(d5)
        XCTAssertEqual(asks, 1, "Once ever")
        XCTAssertTrue(prompt().state.asked)
    }

    func testAMissedDayOneIsTriedOnLaterOpensUpToDaySeven() async {
        var asks = 0
        let busy = await open(onDay: 1, busy: { true }, asks: &asks)
        XCTAssertFalse(busy, "The screen never came free: gave up")
        XCTAssertEqual(asks, 0)
        let away = await open(onDay: 4, scene: false, asks: &asks)
        XCTAssertFalse(away, "No scene in front")
        XCTAssertFalse(prompt().state.asked, "Not counted as asked")
        let d7 = await open(onDay: 7, asks: &asks)
        XCTAssertTrue(d7, "Tried again on a later open, still day 7")
        XCTAssertEqual(asks, 2)
        let d7again = await open(onDay: 7, asks: &asks)
        XCTAssertFalse(d7again, "Only once")
    }

    func testNeverAfterDaySeven() async {
        var asks = 0
        _ = await open(onDay: 1, busy: { true }, asks: &asks)
        _ = await open(onDay: 3, busy: { true }, asks: &asks)
        let d8 = await open(onDay: 8, asks: &asks)
        let d9 = await open(onDay: 9, asks: &asks)
        XCTAssertFalse(d8, "Day 8 never")
        XCTAssertFalse(d9)
        XCTAssertEqual(asks, 0)
    }

    func testWaitsForTheScreenToBeFreeForSettleChecks() async {
        // Busy for the first five checks, then free: asked on the third free check, the eighth in all.
        var checks = 0, askedAt = 0
        let asked = await prompt().opened(busy: { checks += 1; return checks <= 5 }, request: { askedAt = checks; return true })
        XCTAssertTrue(asked)
        XCTAssertEqual(askedAt, 8)
        // A busy moment in between starts the 1.5 s over.
        defaults.set(false, forKey: ReviewPrompt.askedKey)
        checks = 0
        let pattern = [false, false, true, false, false, false]
        _ = await prompt().opened(busy: { checks += 1; return checks <= pattern.count ? pattern[checks - 1] : false },
                                  request: { askedAt = checks; return true })
        XCTAssertEqual(askedAt, 6)
    }

    func testNeverUnderUITests() async {
        XCTAssertFalse(UsageGate.allowed(arguments: ["--ui-testing"], environment: [:]))
        var asks = 0
        for n in 1...3 {
            day(n)
            _ = await prompt(allowed: false).opened(busy: { false }, request: { asks += 1; return true })
        }
        XCTAssertEqual(asks, 0)
        XCTAssertNil(defaults.string(forKey: ReviewPrompt.firstKey), "Nothing counted")
    }

    // MARK: Holds and re-triggers

    func testAHeldPromptDoesNotAskAndItsReleaseAfterTheGiveUpStillAsksThisLaunch() async {
        let held = prompt()
        held.hold("levelUp")
        var asks = 0
        let asked = await held.opened(busy: { false }, request: { asks += 1; return true })
        XCTAssertFalse(asked, "LEVEL×UP on its way: no sheet, and the wait gave up")
        XCTAssertEqual(asks, 0)
        XCTAssertFalse(held.state.asked, "Not counted")
        // LEVEL×UP closes after the give-up: the release starts the wait again, so this launch still asks.
        held.release("levelUp")
        XCTAssertTrue(held.holds.isEmpty)
        for _ in 0..<400 where !held.state.asked { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(asks, 1, "Asked once after the release")
        XCTAssertTrue(held.state.asked)
        // Nothing left to re-arm: another hold and release asks nothing more.
        held.hold("replay")
        held.release("replay")
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(asks, 1)
    }

    func testAGiveUpWithNothingHeldIsNotReArmed() async {
        let busy = prompt()
        var asks = 0
        let asked = await busy.opened(busy: { true }, request: { asks += 1; return true })
        XCTAssertFalse(asked)
        busy.hold("replay")
        busy.release("replay")
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(asks, 0, "The next open tries again, not a release")
    }

    /// A keyboardDidHide that never came (the app left the front with the keyboard up) does not block the rest of the
    /// process: becoming active clears it.
    func testBecomingActiveClearsAKeyboardThatNeverSaidItHid() async {
        let typed = prompt()
        NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(10))
        var asks = 0
        let blocked = await typed.opened(busy: { false }, request: { asks += 1; return true })
        XCTAssertFalse(blocked, "The keyboard is up: no sheet")
        XCTAssertEqual(asks, 0)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(10))
        let asked = await typed.opened(busy: { false }, request: { asks += 1; return true })
        XCTAssertTrue(asked, "Back in front: the stale keyboard no longer blocks")
        XCTAssertEqual(asks, 1)
    }

    func testAReleaseLetsItAskAfterTheSettle() async {
        let held = prompt()
        held.hold("levelUp")
        held.hold("replay", while: true)
        held.hold("replay", while: false)
        XCTAssertEqual(held.holds, ["levelUp"])
        // Released on the fifth check: free on the fifth, sixth and seventh, asked on the seventh.
        var checks = 0, askedAt = 0
        let asked = await held.opened(busy: {
            checks += 1
            if checks == 5 { held.release("levelUp") }
            return false
        }, request: { askedAt = checks; return true })
        XCTAssertTrue(asked)
        XCTAssertEqual(askedAt, 7)
    }

    /// The app left the front and came straight back: the new wait asks, the one it replaces stops.
    func testAQuickReTriggerIsNotTurnedAway() async {
        let shared = prompt()
        shared.limit = 10_000
        let first = Task { await shared.opened(busy: { true }, request: { true }) }
        try? await Task.sleep(for: .milliseconds(30))
        let second = await shared.opened(busy: { false }, request: { true })
        XCTAssertTrue(second, "The re-trigger asks")
        let firstAsked = await first.value
        XCTAssertFalse(firstAsked, "The older wait stopped")
    }

    // MARK: One big prompt per launch (LaunchPrompt)

    func testTheLaunchGate() {
        XCTAssertTrue(ReviewPrompt.launchFree(taken: false, noteWaiting: false))
        XCTAssertFalse(ReviewPrompt.launchFree(taken: false, noteWaiting: true), "A 7 days' note coming up on this launch goes first")
        XCTAssertFalse(ReviewPrompt.launchFree(taken: true, noteWaiting: false), "Another prompt took this launch")
        XCTAssertFalse(ReviewPrompt.launchFree(taken: true, noteWaiting: true))
        // The app's own gate reads the real LaunchPrompt: once another prompt took this launch, it is closed.
        let saved = LaunchPrompt.taken
        defer { LaunchPrompt.taken = saved }
        LaunchPrompt.taken = true
        XCTAssertFalse(ReviewPrompt(defaults: defaults, allowed: true, now: { Date() }, timeZone: { .current }).launchFree(),
                       "The default gate reads LaunchPrompt.taken")
    }

    func testNoAskWhileAMemberOpenNoteIsWaitingAndNothingRecorded() async {
        let gated = prompt()
        var took = 0, asks = 0
        gated.launchFree = { ReviewPrompt.launchFree(taken: false, noteWaiting: true) }
        gated.takeLaunch = { took += 1; return true }
        let asked = await gated.opened(busy: { false }, request: { asks += 1; return true })
        XCTAssertFalse(asked)
        XCTAssertEqual(asks, 0)
        XCTAssertEqual(took, 0, "This launch's prompt is left for the note")
        XCTAssertFalse(gated.state.asked, "Nothing recorded")
        // A later launch, the note seen: the rating asks, taking the launch's prompt just before.
        gated.launchFree = { ReviewPrompt.launchFree(taken: false, noteWaiting: false) }
        day(2)
        let later = await gated.opened(busy: { false }, request: { asks += 1; return took == 1 })
        XCTAssertTrue(later)
        XCTAssertEqual(asks, 1)
        XCTAssertTrue(gated.state.asked)
    }


    func testNoAskOnceLaunchPromptIsTakenAndNothingRecorded() async {
        let saved = LaunchPrompt.taken
        defer { LaunchPrompt.taken = saved }
        LaunchPrompt.taken = false
        XCTAssertTrue(LaunchPrompt.take(), "A 7 days' note took this launch's prompt")
        let gated = prompt()
        gated.launchFree = { ReviewPrompt.launchFree(taken: LaunchPrompt.taken, noteWaiting: false) }
        gated.takeLaunch = { LaunchPrompt.take() }
        var asks = 0
        let asked = await gated.opened(busy: { false }, request: { asks += 1; return true })
        XCTAssertFalse(asked)
        XCTAssertEqual(asks, 0)
        XCTAssertFalse(gated.state.asked, "Nothing recorded: a later launch asks")
        // The next cold launch starts free.
        LaunchPrompt.taken = false
        let next = await gated.opened(busy: { false }, request: { asks += 1; return true })
        XCTAssertTrue(next)
        XCTAssertTrue(LaunchPrompt.taken, "The rating took this launch's prompt")
    }

    /// Through the app's own export (資料備份與還原): the rating state stays on the phone.
    func testTheStateStaysOutOfTheAppBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("review-backup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PortfolioStore(url: directory.appendingPathComponent("records.json"))
        try store.save(Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "", strategy: .saving))
        let keys = [ReviewPrompt.firstKey, ReviewPrompt.daysKey, ReviewPrompt.lastKey, ReviewPrompt.askedKey]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) } }
        let phone = ReviewPrompt(defaults: .standard, allowed: true, now: { Date() }, timeZone: { .current })
        phone.state = ReviewDays(first: "2026-11-22", days: 4, last: "2026-11-25", asked: true)
        let backup = String(decoding: try Data(contentsOf: store.export()), as: UTF8.self)
        XCTAssertTrue(backup.contains("0050"), "The export has the records")
        XCTAssertFalse(backup.contains("review."), "but not the rating state")
        XCTAssertFalse(backup.contains("2026-11-25"))
    }
}
