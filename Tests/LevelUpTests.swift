import XCTest
@testable import ETFToGo

/// The LEVEL×UP moment remembers where the numeral rolls from.
final class LevelUpTests: XCTestCase {
    private let now = GameRules.taipei.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))!

    func testMomentRemembersPreviousLevel() {
        var game = GameState()
        game.celebratedLevel = 3
        let moment = LevelUp.moment(game, level: 5, now: now)
        XCTAssertEqual(moment.from, 3)
        XCTAssertEqual(moment.level, 5)
    }

    func testFromIsNeverAboveOneBelowTheNewLevelOrBelowOne() {
        XCTAssertEqual(LevelUp.from(celebrated: 5, level: 5), 4, "A stale celebrated level rolls from level - 1")
        XCTAssertEqual(LevelUp.from(celebrated: 0, level: 3), 1)
        XCTAssertEqual(LevelUp.from(celebrated: 1, level: 1), 1)
    }
}
