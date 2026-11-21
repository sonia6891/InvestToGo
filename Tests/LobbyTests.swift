import XCTest
import SwiftUI
@testable import ETFToGo

/// The lobby's state, launch arguments and gestures, without the simulator UI.
final class LobbyTests: XCTestCase {
    private let now = GameRules.taipei.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))!

    func testDemoStreakEndsThisMonth() {
        var game = GameState()
        DemoArguments.apply(to: &game, args: ["--ui-testing", "--demo-streak", "12"], now: now)
        XCTAssertEqual(game.dcaMonths.count, 12)
        XCTAssertTrue(game.dcaMonths.contains(YearMonth(now)))
        XCTAssertEqual(game.streak(now: now), 12)
        XCTAssertEqual(game.longestStreak, 12)
    }

    func testDemoLevelAndXP() {
        var game = GameState()
        DemoArguments.apply(to: &game, args: ["--ui-testing", "--demo-level", "7"], now: now)
        XCTAssertEqual(game.xp, GameRules.xpToReach(level: 7))
        XCTAssertEqual(GameRules.level(xp: game.xp), 7)
        DemoArguments.apply(to: &game, args: ["--ui-testing", "--demo-level", "7", "--demo-xp", "290"], now: now)
        XCTAssertEqual(game.xp, 290, "--demo-xp wins")
    }

    func testDemoArgumentsNeedUITesting() {
        var game = GameState()
        DemoArguments.apply(to: &game, args: ["--demo-streak", "12", "--demo-xp", "500"], now: now)
        XCTAssertEqual(game, GameState())
    }

    func testHeroForNewbieRunningAndBrokenStreaks() {
        XCTAssertEqual(LobbyHero.of(GameState(), now: now), LobbyHero(value: 1, caption: "第 1 個月", tag: "今天開始", record: nil, label: "第 1 個月，今天開始"))

        var running = GameState()
        DemoArguments.apply(to: &running, args: ["--ui-testing", "--demo-streak", "12"], now: now)
        let hero = LobbyHero.of(running, now: now)
        XCTAssertEqual(hero.value, 12)
        XCTAssertEqual(hero.caption, "12 個月")
        XCTAssertEqual(hero.label, "連續定投 12 個月")
        XCTAssertNil(hero.record)

        // R15: a broken run restarts at a lone 1 with the best run, never a bare 0.
        var broken = GameState()
        broken.dcaMonths = [YearMonth(year: 2026, month: 3), YearMonth(year: 2026, month: 4)]
        broken.longestStreak = 2
        let restart = LobbyHero.of(broken, now: now)
        XCTAssertEqual(restart.value, 1)
        XCTAssertEqual(restart.tag, "今天開始")
        XCTAssertEqual(restart.record, "最長紀錄 2 個月")
    }

    func testOpenArgumentPicksAFeature() {
        XCTAssertEqual(Feature.launch(["--ui-testing", "--open", "dividends"]), .dividends)
        XCTAssertNil(Feature.launch(["--ui-testing", "--open", "lobby"]))
        XCTAssertNil(Feature.launch(["--ui-testing", "--open", "skinKit"]))
        XCTAssertNil(Feature.launch(["--ui-testing"]))
        XCTAssertEqual(Feature.allCases.map(\.title), ["找 ETF", "配息", "口袋", "工具", "成就"])
    }

    func testPullDownReturnsOnlyFromTheTopThird() {
        XCTAssertTrue(FeatureScreen.isPullToLobby(start: CGPoint(x: 100, y: 120), translation: CGSize(width: 10, height: 140), height: 800))
        XCTAssertFalse(FeatureScreen.isPullToLobby(start: CGPoint(x: 100, y: 400), translation: CGSize(width: 0, height: 200), height: 800), "Starts below the top third")
        XCTAssertFalse(FeatureScreen.isPullToLobby(start: CGPoint(x: 100, y: 120), translation: CGSize(width: 0, height: 100), height: 800), "Too short")
        XCTAssertFalse(FeatureScreen.isPullToLobby(start: CGPoint(x: 100, y: 120), translation: CGSize(width: 200, height: 130), height: 800), "Mostly sideways")
    }

    func testQuickPickDiscsStayOnScreenAboveTheBar() {
        for size in [CGSize(width: 375, height: 600), CGSize(width: 430, height: 800)] {
            for i in 0..<5 {
                let p = QuickPick.position(i, of: 5, in: size)
                XCTAssertGreaterThanOrEqual(p.x - 40, 0, "\(size) disc \(i) left edge")
                XCTAssertLessThanOrEqual(p.x + 40, size.width, "\(size) disc \(i) right edge")
                XCTAssertLessThan(p.y + 50, size.height - GameBottomBar.height / 2, "\(size) disc \(i) clears the bar")
            }
        }
    }

    func testLobbySignatures() {
        XCTAssertEqual(LobbySignature.of(.find), .swing)
        XCTAssertEqual(LobbySignature.of(.dividends), .flip)
        XCTAssertEqual(LobbySignature.of(.pocket), .hop)
        XCTAssertEqual(LobbySignature.of(.tools), .blink)
        XCTAssertEqual(LobbySignature.phase(.find), 0)
        XCTAssertEqual(LobbySignature.phase(.dividends), 0.25)
        XCTAssertEqual(LobbySignature.phase(.pocket), 0.5)
        XCTAssertEqual(LobbySignature.phase(.tools), 0.75)
    }

    func testSignatureMovesEveryFourToSevenSecondsOutOfStep() {
        let four: [Feature] = [.find, .dividends, .pocket, .tools]
        for feature in four {
            let phase = LobbySignature.phase(feature), interval = LobbySignature.interval(phase: phase)
            XCTAssertTrue((4...7).contains(interval), "\(feature) moves every \(interval) s")
            // Sampled every 0.05 s over one interval: exactly one move, lasting moveDuration.
            let samples = stride(from: 1000.0, to: 1000 + interval, by: 0.05).map { LobbySignature.progress(time: $0, phase: phase) }
            let moving = samples.filter { $0 != nil }.count
            XCTAssertEqual(Double(moving) * 0.05, LobbySignature.moveDuration, accuracy: 0.11, "\(feature)")
            XCTAssertTrue(samples.compactMap { $0 }.allSatisfy { (0..<1).contains($0) })
        }
        // Deterministic: the same moment gives the same pose.
        XCTAssertEqual(LobbySignature.progress(time: 12_345.6, phase: 0.25), LobbySignature.progress(time: 12_345.6, phase: 0.25))
        // Out of step: each keeps its own rhythm, so they drift apart rather than moving together.
        XCTAssertEqual(Set(four.map { LobbySignature.interval(phase: LobbySignature.phase($0)) }).count, 4)
        // At rest, and the swing stays within ±8°.
        XCTAssertEqual(LobbySignature.swing.pose(nil), LobbySignature.Pose())
        let swing = stride(from: 0.0, to: 1, by: 0.01).map { abs(LobbySignature.swing.pose($0).rotation) }
        XCTAssertLessThanOrEqual(swing.max() ?? 0, 8)
        XCTAssertGreaterThan(swing.max() ?? 0, 7)
    }
}
