import XCTest
@testable import ETFToGo

/// What the lobby remembers having shown, and how its replay is laid out in time (spec 5.3, 5.4).
final class LobbyReplayPlayerTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lobby-replay-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        LobbyShownStore().reset()
    }

    func testShownStoreRoundTrip() throws {
        let suite = "lobby-shown-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LobbyShownStore(defaults: defaults)
        XCTAssertNil(store.load(), "A fresh install has shown nothing: no replay")
        let shown = LobbySnapshot(xp: 460, coins: 320, month: "2026-11", quests: ["visitDividends", "logDividend"])
        store.save(shown)
        XCTAssertEqual(store.load(), shown)
        XCTAssertEqual(LobbyShownStore(defaults: defaults).load(), shown, "Kept on the phone")
        store.reset()
        XCTAssertNil(store.load())
    }

    /// A restore shows the restored numbers as they are: nothing is replayed from what the lobby showed before.
    @MainActor func testRestoreResetsShownSnapshot() throws {
        let old = PortfolioStore(url: directory.appendingPathComponent("old.json"))
        try old.save(Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "", strategy: .saving))
        let backup = try Data(contentsOf: old.export())

        LobbyShownStore().save(LobbySnapshot(xp: 120, coins: 120, month: "2026-11", quests: []))
        XCTAssertNotNil(LobbyShownStore().load())
        let phone = PortfolioStore(url: directory.appendingPathComponent("new.json"))
        try phone.importBackup(backup)
        XCTAssertNil(LobbyShownStore().load(), "The next lobby shows the restored numbers without a replay")
    }

    /// Quest ticks, then the coins, then the bar (and its flash when it fills): all within two seconds.
    func testPlanOrderAndLength() throws {
        let busiest = LobbyReplay(newQuests: ["a", "b", "c", "d"], coinsFrom: 300, coinsTo: 420, xpFrom: 440, xpTo: 560, levelFrom: 4, levelTo: 4)
        var crossing = busiest
        crossing.xpTo = 760; crossing.levelTo = 5
        for replay in [busiest, crossing] {
            let plan = LobbyReplayPlan.of(replay, lead: 0.5)
            XCTAssertEqual(plan.ticks.map(\.quest), ["a", "b", "c", "d"], "In the quest card's order")
            let lastTick = try XCTUnwrap(plan.ticks.last?.at)
            let coins = try XCTUnwrap(plan.coinsAt), bar = try XCTUnwrap(plan.barAt)
            XCTAssertGreaterThanOrEqual(plan.ticks[0].at, 0.5, "After the lead")
            XCTAssertLessThan(lastTick, coins, "Ticks before the coins")
            XCTAssertLessThan(coins, bar, "Coins before the bar")
            XCTAssertLessThanOrEqual(plan.total - plan.lead, 2, "The whole replay within 2 s")
            XCTAssertEqual(plan.fillsToLevelUp, replay.crossesLevel)
        }
        let coinsOnly = LobbyReplayPlan.of(LobbyReplay(newQuests: [], coinsFrom: 0, coinsTo: 5, xpFrom: 10, xpTo: 10, levelFrom: 1, levelTo: 1))
        XCTAssertNil(coinsOnly.barAt, "The bar stays where it is when the experience did not grow")
        XCTAssertTrue(coinsOnly.ticks.isEmpty)
    }

    func testBarFraction() {
        XCTAssertEqual(LobbyReplayPlayer.fraction(xp: 0), 0)
        XCTAssertEqual(LobbyReplayPlayer.fraction(xp: 50), 0.5, accuracy: 0.0001, "Level 1 runs from 0 to 100")
        XCTAssertEqual(LobbyReplayPlayer.fraction(xp: 450), 0, "Level 4 starts at 450")
    }
}
