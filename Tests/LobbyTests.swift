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
        XCTAssertEqual(game.xp, 6 * GameRules.xpPerLevel)
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
}
