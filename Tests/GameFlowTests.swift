import XCTest
@testable import ETFToGo

/// The first-launch flow and the LEVEL×UP decision, without the simulator UI.
final class GameFlowTests: XCTestCase {
    private let now = GameRules.taipei.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))!

    // MARK: Level-up shown once (spec 5.12)

    func testLevelUpIsDueOnceWhenExperienceCrossesAWholeLevel() {
        var game = GameState()
        game.xp = 290
        XCTAssertNil(game.levelUpDue, "Level 1 is where everyone starts: nothing to celebrate")
        game.award(.dividendLogged)
        XCTAssertEqual(game.xp, 310)
        XCTAssertEqual(game.levelUpDue, 2)
        XCTAssertEqual(game.lastAward, .dividendLogged)
        game.celebrate(2)
        XCTAssertNil(game.levelUpDue, "Celebrated once")
        game.award(.dividendLogged)
        XCTAssertNil(game.levelUpDue, "More experience inside level 2 celebrates nothing")
    }

    func testSeveralLevelsAtOnceCelebrateTheHighestOnce() {
        var game = GameState()
        game.xp = 650
        XCTAssertEqual(game.levelUpDue, 3)
        game.celebrate(3)
        XCTAssertNil(game.levelUpDue)
        game.celebrate(2)
        XCTAssertEqual(game.celebratedLevel, 3, "The celebrated level never goes back down")
    }

    func testCelebratedLevelIsSaved() throws {
        var game = GameState()
        game.xp = 310
        game.celebrate(2)
        let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(back.celebratedLevel, 2)
        XCTAssertNil(back.levelUpDue, "A relaunch does not celebrate again")
    }

    func testOlderSaveCelebratesNothingAlreadyHeld() throws {
        let old = try JSONDecoder().decode(GameState.self, from: Data(#"{"xp":1800,"coins":1800}"#.utf8))
        XCTAssertEqual(GameRules.level(xp: old.xp), 7)
        XCTAssertNil(old.levelUpDue, "Levels reached before this build are not new")
        XCTAssertNil(old.lastAward)
    }

    func testDemoProgressIsNotALevelUp() {
        var game = GameState()
        DemoArguments.apply(to: &game, args: ["--ui-testing", "--demo-level", "7"], now: now)
        XCTAssertNil(game.levelUpDue, "Screenshots at LV.7 open on the lobby, not on a celebration")
        DemoArguments.apply(to: &game, args: ["--ui-testing", "--demo-xp", "290"], now: now)
        XCTAssertNil(game.levelUpDue)
        game.award(.dividendLogged)
        XCTAssertEqual(game.levelUpDue, 2, "The test's +20 crosses into level 2")
    }

    func testOpenLevelUpShowsTheDemoLevel() {
        var game = GameState()
        DemoArguments.apply(to: &game, args: ["--ui-testing", "--demo-streak", "12", "--demo-level", "7", "--open", "levelup"], now: now)
        XCTAssertEqual(game.levelUpDue, 7)
        XCTAssertEqual(LevelUp.reason(game, now: now), "連續定投 12 個月")
    }

    func testReasonNamesTheLastEvent() {
        var game = GameState()
        game.award(.dividendLogged)
        XCTAssertEqual(LevelUp.reason(game, now: now), "記一筆配息")
        game.award(.questDone)
        XCTAssertEqual(LevelUp.reason(game, now: now), "完成本月任務")
        _ = game.recordDCA(on: now)
        XCTAssertEqual(LevelUp.reason(game, now: now), "連續定投 1 個月")
    }

    // MARK: First launch (spec 5.1, 5.2)

    func testFirstLaunchStartsOnTheSplash() {
        XCTAssertEqual(Onboarding.start([], onboarded: false), .splash)
        XCTAssertEqual(Onboarding.start(["--ui-testing", "--reset"], onboarded: false), .splash)
        XCTAssertNil(Onboarding.start([], onboarded: true), "Once finished, launches go to the lobby")
    }

    func testSkipOnboardingOnlyWhenUITesting() {
        XCTAssertNil(Onboarding.start(["--ui-testing", "--skip-onboarding"], onboarded: false))
        XCTAssertEqual(Onboarding.start(["--skip-onboarding"], onboarded: false), .splash, "Ignored outside UI tests")
    }

    func testOpenSplashOrOnboardingPage() {
        XCTAssertEqual(Onboarding.start(["--ui-testing", "--skip-onboarding", "--open", "splash"], onboarded: true), .splash)
        XCTAssertEqual(Onboarding.start(["--ui-testing", "--open", "onboarding"], onboarded: true), .page(1))
        XCTAssertEqual(Onboarding.start(["--ui-testing", "--open", "onboarding", "--page", "3"], onboarded: true), .page(3))
        XCTAssertEqual(Onboarding.start(["--ui-testing", "--open", "onboarding", "--page", "9"], onboarded: true), .page(4))
        XCTAssertNil(Onboarding.start(["--open", "splash"], onboarded: true), "Only with --ui-testing")
    }
}
