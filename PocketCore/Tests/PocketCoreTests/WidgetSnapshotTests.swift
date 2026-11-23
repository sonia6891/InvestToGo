import XCTest
@testable import PocketCore

final class WidgetSnapshotTests: XCTestCase {
    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        GameRules.taipei.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    private var now: Date { at(2026, 11, 21) }

    private func months(_ from: (Int, Int), count: Int) -> [YearMonth] {
        var out: [YearMonth] = []; var m = YearMonth(year: from.0, month: from.1)
        for _ in 0..<count { out.append(m); m = m.next() }
        return out
    }
    private func game(_ ms: [YearMonth], habit: Habit? = .dca, done: [String: Set<String>] = [:]) -> GameState {
        var g = GameState(); g.habit = habit; g.questsDone = done
        for m in ms { g.insertMonth(m) }
        return g
    }
    private func portfolio(_ g: GameState, buyOn: Date? = nil) -> Portfolio {
        var p = Portfolio()
        let h = Holding(symbol: "0050", name: "測試", shares: 123456, unitCost: 80, broker: "", strategy: .saving)
        p.holdings = [h]
        if let buyOn { p.trades = [Trade(date: buyOn, action: .buy, holding: h)] }
        p.game = g
        return p
    }
    /// 12 months 2025-12…2026-11 with a buy on 2026-11-05 and dcaLogged done.
    private func running() -> WidgetSnapshot {
        let g = game(months((2025, 12), count: 12), done: ["2026-11": ["dcaLogged"]])
        return .of(portfolio(g, buyOn: at(2026, 11, 5)), skinID: "voxel", now: now)
    }

    func testOfCarriesOnlyTheAllowedKeys() throws {
        let g = game(months((2025, 12), count: 12))
        let s = WidgetSnapshot.of(portfolio(g, buyOn: at(2026, 11, 5)), skinID: "voxel", now: now)
        let data = try JSONEncoder().encode(s)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(Set(json.keys), ["version", "writtenAt", "month", "streak", "longestStreak", "isNewbie", "habit", "dcaMonths", "quests", "skinID"])
        XCTAssertEqual(Set((json["quests"] as! [[String: Any]])[0].keys), ["id", "title", "done"])
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("123456")); XCTAssertFalse(text.contains("9876543"))
    }

    func testOfReadsStreakAndQuests() {
        let s = running()
        XCTAssertEqual(s.month, "2026-11"); XCTAssertEqual(s.streak, 12); XCTAssertEqual(s.longestStreak, 12); XCTAssertFalse(s.isNewbie)
        XCTAssertEqual(s.quests.first, WidgetQuest(id: "dcaLogged", title: "本月定投一次", done: true))
        XCTAssertEqual(s.quests.count, 3); XCTAssertEqual(s.dcaMonths.first, "2025-12"); XCTAssertEqual(s.dcaMonths.last, "2026-11")
    }

    func testKeepsOnlyTheNewest24Months() {
        let s = WidgetSnapshot.of(portfolio(game(months((2024, 6), count: 30))), skinID: "voxel", now: now)
        XCTAssertEqual(s.dcaMonths.count, 24); XCTAssertEqual(s.dcaMonths.first, "2024-12"); XCTAssertEqual(s.dcaMonths.last, "2026-11")
    }

    func testDCATickFollowsTheRecords() {
        let g = game(months((2026, 11), count: 1), done: ["2026-11": ["dcaLogged"]])
        let s = WidgetSnapshot.of(portfolio(g), skinID: "voxel", now: now)
        XCTAssertFalse(s.quests[0].done)
    }

    func testNewMonthResetsQuests() {
        let d = running().display(at: at(2026, 12, 1, 9))
        XCTAssertEqual(d.month, "2026-12"); XCTAssertEqual(d.streak, 12)
        XCTAssertEqual(d.quests.map(\.id), Quests.forMonth(YearMonth(year: 2026, month: 12), habit: .dca, isNewbie: false).map(\.id))
        XCTAssertTrue(d.quests.allSatisfy { !$0.done })
    }

    func testNewMonthAfterAMissedMonth() {
        let g = game(months((2026, 6), count: 5))
        let s = WidgetSnapshot.of(portfolio(g), skinID: "voxel", now: at(2026, 10, 20))
        let d = s.display(at: at(2026, 12, 2))
        XCTAssertEqual(d.streak, 0)
        XCTAssertEqual(WidgetHero.of(d), WidgetHero(top: "今天開始", value: 1, bottom: "第 1 個月", record: "最長紀錄 5 個月"))
    }

    func testNewbieQuestsStayDoneAcrossMonths() {
        let g = game([], done: ["2026-11": ["firstDexCard"]])
        let s = WidgetSnapshot.of(portfolio(g), skinID: "voxel", now: now)
        XCTAssertTrue(s.quests.first { $0.id == "firstDexCard" }!.done)
        let d = s.display(at: at(2026, 12, 3))
        XCTAssertTrue(d.quests.first { $0.id == "firstDexCard" }!.done)
        XCTAssertFalse(d.quests.first { $0.id == "firstPlanSet" }!.done)
        XCTAssertFalse(d.quests.first { $0.id == "dcaLogged" }!.done)
    }

    func testLongStreakBeyondTheWindow() {
        let s = WidgetSnapshot.of(portfolio(game(months((2024, 6), count: 30))), skinID: "voxel", now: now)
        XCTAssertEqual(s.streak, 30)
        XCTAssertEqual(s.display(at: at(2026, 12, 3)).streak, 30)
    }

    func testSameMonthIsUnchanged() {
        let s = running()
        XCTAssertEqual(s.display(at: now.addingTimeInterval(3 * 86_400)), s)
    }

    func testUnchangedIgnoresWrittenAt() {
        let p = portfolio(game(months((2025, 12), count: 12)))
        let a = WidgetSnapshot.of(p, skinID: "voxel", now: now), b = WidgetSnapshot.of(p, skinID: "voxel", now: now.addingTimeInterval(60))
        XCTAssertNotEqual(a, b); XCTAssertEqual(a.unchanged, b.unchanged)
    }

    func testUnreadableFileShowsNewbie() throws {
        XCTAssertNil(WidgetSnapshot.decode(Data("{".utf8)))
        var s = running(); s.version = 2
        XCTAssertNil(WidgetSnapshot.decode(try JSONEncoder().encode(s)))
        XCTAssertEqual(WidgetSnapshot.decode(try JSONEncoder().encode(running())), running())
        XCTAssertEqual(WidgetHero.of(.newbie(now: now)), WidgetHero(top: "今天開始", value: 1, bottom: "第 1 個月", record: nil))
    }

    /// The lobby's words (LobbyHero, 「第 1 個月，今天開始」): the 1 always has its unit under it.
    func testHeroCopy() {
        XCTAssertEqual(WidgetHero.of(running()), WidgetHero(top: "連續定投", value: 12, bottom: "個月", record: nil))
        var broken = running(); broken.streak = 0; broken.longestStreak = 0; broken.isNewbie = false
        XCTAssertEqual(WidgetHero.of(broken), WidgetHero(top: "今天開始", value: 1, bottom: "第 1 個月", record: "最長紀錄 1 個月"))
        broken.longestStreak = 5
        XCTAssertEqual(WidgetHero.of(broken).record, "最長紀錄 5 個月")
        XCTAssertEqual(WidgetHero.of(.newbie(now: now)), WidgetHero(top: "今天開始", value: 1, bottom: "第 1 個月", record: nil))
    }

    func testQuestLine() {
        var s = running()
        s.quests = [WidgetQuest(id: "a", title: "a", done: true), WidgetQuest(id: "b", title: "b", done: true), WidgetQuest(id: "c", title: "c", done: false)]
        XCTAssertEqual(s.questLine, "本月任務 2/3")
    }

    func testNextMonthStart() {
        XCTAssertEqual(WidgetSnapshot.nextMonthStart(after: now), ISO8601DateFormatter().date(from: "2026-11-30T16:00:00Z"))
        XCTAssertEqual(WidgetSnapshot.nextMonthStart(after: at(2026, 12, 31, 23, 59)), ISO8601DateFormatter().date(from: "2026-12-31T16:00:00Z"))
    }
}
