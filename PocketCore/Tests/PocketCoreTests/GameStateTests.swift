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

    func testPortfolioWithoutGameDecodes() throws {
        let json = #"{"schema":1,"holdings":[],"dividends":[],"favorites":[],"quotes":{}}"#
        let p = try JSONDecoder().decode(Portfolio.self, from: Data(json.utf8))
        XCTAssertNil(p.game)
        XCTAssertEqual(p.game ?? GameState(), GameState())
    }
}
