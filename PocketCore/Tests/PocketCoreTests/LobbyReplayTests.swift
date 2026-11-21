import XCTest
@testable import PocketCore

final class LobbyReplayTests: XCTestCase {
    private func snap(xp: Int, coins: Int? = nil, month: String = "2026-11", quests: Set<String> = []) -> LobbySnapshot {
        LobbySnapshot(xp: xp, coins: coins ?? xp, month: month, quests: quests)
    }

    func testNoSnapshotNoReplay() {
        XCTAssertNil(LobbyReplay.between(shown: nil, now: snap(xp: 100)))
    }

    func testEqualSnapshotsHaveNoReplay() {
        XCTAssertNil(LobbyReplay.between(shown: snap(xp: 100, quests: ["a"]), now: snap(xp: 100, quests: ["a"])))
    }

    func testGainReplays() throws {
        let r = try XCTUnwrap(LobbyReplay.between(shown: snap(xp: 260), now: snap(xp: 280)))
        XCTAssertEqual(r.xpFrom, 260); XCTAssertEqual(r.xpTo, 280)
        XCTAssertEqual(r.coinsFrom, 260); XCTAssertEqual(r.coinsTo, 280)
        XCTAssertEqual(r.levelFrom, 3); XCTAssertEqual(r.levelTo, 3)
        XCTAssertFalse(r.crossesLevel)
        XCTAssertEqual(r.newQuests, [])
    }

    func testLowerNumbersNoReplay() {
        XCTAssertNil(LobbyReplay.between(shown: snap(xp: 300), now: snap(xp: 200)))
        XCTAssertNil(LobbyReplay.between(shown: snap(xp: 300, coins: 300), now: snap(xp: 400, coins: 200)))
    }

    func testNewQuestTicks() throws {
        let r = try XCTUnwrap(LobbyReplay.between(shown: snap(xp: 100, quests: ["a"]), now: snap(xp: 100, quests: ["a", "b"])))
        XCTAssertEqual(r.newQuests, ["b"])
    }

    func testQuestTicksFollowTheGivenOrder() throws {
        let r = try XCTUnwrap(LobbyReplay.between(shown: snap(xp: 100), now: snap(xp: 140, quests: ["a", "b", "c"]), questOrder: ["c", "a", "b"]))
        XCTAssertEqual(r.newQuests, ["c", "a", "b"])
    }

    func testReplayAcrossMonthHasNoTicks() throws {
        let r = try XCTUnwrap(LobbyReplay.between(shown: snap(xp: 100, month: "2026-10", quests: ["a", "b", "c"]), now: snap(xp: 200, month: "2026-11")))
        XCTAssertEqual(r.newQuests, [])
        // Quests done in the new month are not ticked either: the month changed under the card.
        let r2 = try XCTUnwrap(LobbyReplay.between(shown: snap(xp: 100, month: "2026-10"), now: snap(xp: 140, month: "2026-11", quests: ["a"])))
        XCTAssertEqual(r2.newQuests, [])
    }

    func testReplayCrossingTwoLevels() throws {
        let r = try XCTUnwrap(LobbyReplay.between(shown: snap(xp: 90), now: snap(xp: 300)))
        XCTAssertEqual(r.levelFrom, 1); XCTAssertEqual(r.levelTo, 3)
        XCTAssertTrue(r.crossesLevel)
    }

    func testSnapshotOfGame() {
        let now = GameRules.taipei.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))!
        var game = GameState()
        game.habit = .dca
        game.dcaMonths = [YearMonth(now).previous()]
        let month = YearMonth(now)
        let quests = Quests.forMonth(month, habit: .dca, isNewbie: false)
        game.questsDone[month.key] = Set(quests.prefix(2).map(\.id))
        game.xp = 340; game.coins = 330
        var records = Portfolio()
        records.game = game
        records.trades = [Trade(date: now, action: .buy, holding: Holding(symbol: "0050", name: "測試", shares: 100, unitCost: 10, broker: "", strategy: .saving))]
        let s = LobbySnapshot.of(game, records: records, now: now)
        XCTAssertEqual(s.quests, Set(quests.prefix(2).map(\.id)))
        XCTAssertEqual(s.xp, 340); XCTAssertEqual(s.coins, 330)
        XCTAssertEqual(s.month, "2026-11")
    }

    func testSnapshotUnticksADeletedDCA() {
        let now = GameRules.taipei.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))!
        let month = YearMonth(now)
        var game = GameState()
        game.habit = .dca
        game.dcaMonths = [month]
        game.questsDone[month.key] = [Quests.dcaLogged.id]
        var records = Portfolio()
        records.game = game
        XCTAssertFalse(LobbySnapshot.of(game, records: records, now: now).quests.contains(Quests.dcaLogged.id), "No buy this month: the tick is gone")
        records.trades = [Trade(date: now, action: .buy, holding: Holding(symbol: "0050", name: "測試", shares: 100, unitCost: 10, broker: "", strategy: .saving))]
        XCTAssertTrue(LobbySnapshot.of(game, records: records, now: now).quests.contains(Quests.dcaLogged.id))
    }

    // MARK: arrival (what the lobby plays on arriving)

    func testArrivalCrossingGivesCrossesLevel() throws {
        XCTAssertLessThan(GameRules.level(xp: 100), GameRules.level(xp: 5000))
        let r = try XCTUnwrap(LobbyReplay.arrival(shown: snap(xp: 100), now: snap(xp: 5000), questOrder: [], levelUpDue: nil, celebratedLevel: 1))
        XCTAssertTrue(r.crossesLevel)
        XCTAssertEqual(r.levelFrom, GameRules.level(xp: 100)); XCTAssertEqual(r.levelTo, GameRules.level(xp: 5000))
    }

    func testArrivalWithNothingShownPlaysNothingEvenWhenALevelIsDue() {
        XCTAssertNil(LobbyReplay.arrival(shown: nil, now: snap(xp: 5000), questOrder: [], levelUpDue: 9, celebratedLevel: 1))
    }

    func testArrivalWithALevelStillDueFillsAgainToFull() throws {
        let xp = 5000, level = GameRules.level(xp: xp)
        XCTAssertGreaterThan(level, 1)
        let r = try XCTUnwrap(LobbyReplay.arrival(shown: snap(xp: xp), now: snap(xp: xp), questOrder: [], levelUpDue: level, celebratedLevel: level - 1))
        XCTAssertEqual(r.levelFrom, level - 1); XCTAssertEqual(r.levelTo, level)
        XCTAssertTrue(r.crossesLevel)
        XCTAssertEqual(r.xpFrom, xp); XCTAssertEqual(r.xpTo, xp)
        XCTAssertEqual(r.newQuests, [])
    }

    func testArrivalKeepsTheEarlierLevelWhenADueLevelIsAlsoCrossed() throws {
        let r = try XCTUnwrap(LobbyReplay.arrival(shown: snap(xp: 5000), now: snap(xp: 5100), questOrder: [], levelUpDue: 9, celebratedLevel: 2))
        XCTAssertEqual(r.levelFrom, min(GameRules.level(xp: 5000), 2))
    }

    func testArrivalWithNoLevelDueIsJustTheDifference() {
        XCTAssertNil(LobbyReplay.arrival(shown: snap(xp: 300), now: snap(xp: 300), questOrder: [], levelUpDue: nil, celebratedLevel: 1))
    }
}
