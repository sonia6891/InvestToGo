import XCTest
@testable import PocketCore

final class GameStateTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        GameRules.taipei.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testLevelEvery300XP() {
        XCTAssertEqual(GameRules.level(xp: 0), 1)
        XCTAssertEqual(GameRules.level(xp: 299), 1)
        XCTAssertEqual(GameRules.level(xp: 300), 2)
        XCTAssertEqual(GameRules.level(xp: 3000), 11)
        let p = GameRules.progress(xp: 420)
        XCTAssertEqual(p.into, 120)
        XCTAssertEqual(p.needed, 300)
    }

    func testStreakAcrossYearBoundaryAndGaps() {
        var g = GameState()
        _ = g.recordDCA(on: date(2025, 11, 5))
        _ = g.recordDCA(on: date(2025, 12, 5))
        _ = g.recordDCA(on: date(2026, 1, 5))
        XCTAssertEqual(g.streak(now: date(2026, 1, 15)), 3)
        _ = g.recordDCA(on: date(2026, 3, 5))
        XCTAssertEqual(g.streak(now: date(2026, 3, 10)), 1)
        XCTAssertEqual(g.longestStreak, 3)
    }

    func testStreakStillAliveBeforeThisMonthsDebit() {
        var g = GameState()
        for m in 8...10 { _ = g.recordDCA(on: date(2026, m, 5)) }
        XCTAssertEqual(g.streak(now: date(2026, 11, 2)), 3)
        XCTAssertEqual(g.streak(now: date(2026, 12, 1)), 0)
    }

    func testSameMonthCountsOnce() {
        var g = GameState()
        XCTAssertEqual(g.recordDCA(on: date(2026, 5, 3)), [.monthlyDCA])
        XCTAssertEqual(g.xp, 100)
        XCTAssertEqual(g.recordDCA(on: date(2026, 5, 20)), [])
        XCTAssertEqual(g.xp, 100)
        XCTAssertEqual(g.coins, 100)
    }

    func testTwelveMonthDemoStreak() {
        var g = GameState()
        for i in 0..<12 { _ = g.recordDCA(on: date(2025 + (i + 0) / 12, 1 + i % 12, 8)) }
        XCTAssertEqual(g.streak(now: date(2025, 12, 20)), 12)
        XCTAssertEqual(g.longestStreak, 12)
    }

    func testAwardAddsXPAndCoins() {
        var g = GameState()
        g.award(.questDone)
        g.award(.dividendLogged)
        XCTAssertEqual(g.xp, 60)
        XCTAssertEqual(g.coins, 60)
    }

    func testGameStateRoundTripsThroughJSON() throws {
        var g = GameState()
        _ = g.recordDCA(on: date(2026, 2, 3))
        g.collected["0050"] = date(2026, 2, 3)
        g.questsDone["2026-02"] = ["a", "b"]
        let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(g))
        XCTAssertEqual(back, g)
        let empty = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(GameState()))
        XCTAssertEqual(empty, GameState())
    }

    // MARK: Importing a backup (final review A6)

    /// A phone with no progress yet takes the backup's whole; the months 月報 and 年報 read come with it.
    func testFreshGameAdoptsTheBackups() {
        var backup = GameState()
        _ = backup.recordDCA(on: date(2026, 10, 5), now: date(2026, 10, 5))
        backup.award(.dividendLogged, at: date(2026, 11, 3))
        backup.collected["0050"] = date(2026, 10, 6)
        backup.rewardKeys = ["dividend|00878|2026-11"]
        XCTAssertFalse(backup.isFresh)
        XCTAssertGreaterThan(backup.xp, 0)

        XCTAssertTrue(GameState().isFresh)
        // A phone just set up: onboarding and the launch migration have run, nothing has been earned.
        var local = GameState()
        local.habit = .dca
        local.migration = 3
        local.migratedAt = date(2026, 11, 14)
        XCTAssertTrue(local.isFresh)

        for start in [nil, GameState(), local] as [GameState?] {
            let result = GameState.afterImport(local: start, incoming: backup)
            XCTAssertEqual(result.game, backup, "Adopted whole: level, streak, cards, reward keys")
            XCTAssertFalse(result.skipped)
            XCTAssertEqual(result.game?.xpByMonth.values.reduce(0, +), backup.xp, "The experience by month still adds up to the experience")
        }
    }

    /// A phone that has its own progress keeps it untouched: nothing is merged, and the caller is told.
    func testGameWithProgressIsKept() {
        var backup = GameState()
        backup.award(.questDone, at: date(2026, 10, 3))
        backup.collected["0056"] = date(2026, 10, 6)
        for change in 0..<4 {
            var local = GameState()
            switch change {
            case 0: local.award(.dividendLogged, at: date(2026, 11, 3))
            case 1: local.dcaMonths = [YearMonth(year: 2026, month: 11)]
            case 2: local.collected["0050"] = date(2026, 11, 2)
            default: local.rewardKeys = ["reconciled|2026-11"]
            }
            XCTAssertFalse(local.isFresh, "case \(change)")
            let result = GameState.afterImport(local: local, incoming: backup)
            XCTAssertEqual(result.game, local, "case \(change): not a point, month or card is added")
            XCTAssertTrue(result.skipped, "case \(change)")
        }
        // Nothing to say when the backup has no progress, none at all, or the very same one.
        var local = GameState()
        local.award(.dividendLogged, at: date(2026, 11, 3))
        XCTAssertFalse(GameState.afterImport(local: local, incoming: nil).skipped)
        XCTAssertEqual(GameState.afterImport(local: local, incoming: nil).game, local)
        XCTAssertFalse(GameState.afterImport(local: local, incoming: GameState()).skipped)
        XCTAssertFalse(GameState.afterImport(local: local, incoming: local).skipped)
        XCTAssertNil(GameState.afterImport(local: nil, incoming: nil).game)
    }

    /// A backup whose months add up to more than its experience (or go below zero) loses the months, not the total.
    func testAdoptedExperienceByMonthNeverExceedsTheTotal() {
        var odd = GameState()
        odd.xp = 100
        odd.xpByMonth = ["2026-10": 80, "2026-11": 90]
        XCTAssertEqual(GameState.afterImport(local: nil, incoming: odd).game?.xpByMonth, [:])
        XCTAssertEqual(GameState.afterImport(local: nil, incoming: odd).game?.xp, 100)
        odd.xpByMonth = ["2026-10": -5]
        XCTAssertEqual(odd.checkedForAdoption().xpByMonth, [:])
        odd.xpByMonth = ["2026-10": Int.max, "2026-11": Int.max]
        XCTAssertEqual(odd.checkedForAdoption().xpByMonth, [:], "No overflow on a file made to break the sum")
        odd.xpByMonth = ["2026-10": 60, "2026-11": 40]
        XCTAssertEqual(odd.checkedForAdoption().xpByMonth, ["2026-10": 60, "2026-11": 40])
        odd.xp = -30; odd.coins = -1; odd.xpByMonth = [:]
        XCTAssertEqual(odd.checkedForAdoption().xp, 0)
        XCTAssertEqual(odd.checkedForAdoption().coins, 0)
    }

    func testPortfolioWithoutGameDecodes() throws {
        let json = #"{"schema":1,"holdings":[],"dividends":[],"favorites":[],"quotes":{}}"#
        let p = try JSONDecoder().decode(Portfolio.self, from: Data(json.utf8))
        XCTAssertNil(p.game)
        XCTAssertEqual(p.game ?? GameState(), GameState())
    }
}
