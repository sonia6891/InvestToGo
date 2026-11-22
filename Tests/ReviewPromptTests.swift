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

    func testTheStateStaysOnThePhone() throws {
        let backup = String(decoding: try JSONEncoder().encode(Portfolio()), as: UTF8.self)
        XCTAssertFalse(backup.contains("review."))
    }
}
