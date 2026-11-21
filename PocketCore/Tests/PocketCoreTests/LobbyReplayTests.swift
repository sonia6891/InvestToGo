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
        let s = LobbySnapshot.of(game, now: now)
        XCTAssertEqual(s.quests, Set(quests.prefix(2).map(\.id)))
        XCTAssertEqual(s.xp, 340); XCTAssertEqual(s.coins, 330)
        XCTAssertEqual(s.month, "2026-11")
    }
}
