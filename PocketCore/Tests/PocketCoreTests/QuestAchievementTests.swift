import XCTest
@testable import PocketCore

final class QuestAchievementTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        GameRules.taipei.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }
    private func holding(bought: Date?) -> Holding {
        var h = Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "富邦證券", strategy: .saving)
        h.purchaseDate = bought
        return h
    }
    private func paid(_ y: Int, _ m: Int) -> Dividend {
        Dividend(symbol: "00878", date: date(y, m, 20), amount: 100, status: .paid)
    }

    func testThreeQuestsEveryMonthDeterministic() {
        let start = YearMonth(year: 2026, month: 1)
        for h in Habit.allCases {
            var months = [start]
            for _ in 0..<11 { months.append(months.last!.next()) }
            let lists = months.map { Quests.forMonth($0, habit: h, isNewbie: false) }
            for (m, l) in zip(months, lists) {
                XCTAssertEqual(l.count, 3)
                XCTAssertEqual(Set(l.map(\.id)).count, 3)
                XCTAssertEqual(l, Quests.forMonth(m, habit: h, isNewbie: false))
            }
            XCTAssertGreaterThan(Set(lists.map { $0.map(\.id) }).count, 1)
        }
    }

    func testNewbieQuests() {
        for h in Habit.allCases {
            let q = Quests.forMonth(YearMonth(year: 2026, month: 11), habit: h, isNewbie: true)
            XCTAssertEqual(q.count, 3)
            XCTAssertTrue(q.contains { $0.trigger == .firstPlanSet })
            XCTAssertTrue(q.contains { $0.trigger == .firstDexCard })
        }
    }

    func testQuestCompletesOncePerMonth() {
        var g = GameState()
        let now = date(2026, 11, 12)
        XCTAssertEqual(g.complete(.dcaLogged, now: now), [.questDone])
        XCTAssertEqual(g.complete(.dcaLogged, now: now), [])
        XCTAssertEqual(g.xp, 40)
        XCTAssertEqual(g.questsDone["2026-11"], ["dcaLogged"])
        XCTAssertEqual(g.complete(.dcaLogged, now: date(2026, 12, 1)), [.questDone])
    }

    func testQuestNotInThisMonthIsIgnored() {
        var g = GameState()
        g.habit = .dividends
        let now = date(2026, 11, 12)
        let triggers = Quests.forMonth(YearMonth(now), habit: .dividends, isNewbie: false).map(\.trigger)
        XCTAssertTrue(triggers.contains(.dividendsViewed))
        let absent = [QuestTrigger.dcaLogged, .newETFResearched, .reminderSet, .reconciled].first { !triggers.contains($0) }!
        XCTAssertEqual(g.complete(absent, now: now), [])
        XCTAssertEqual(g.xp, 0)
    }

    private let allTriggers: [QuestTrigger] = [.dcaLogged, .dividendsViewed, .newETFResearched, .reminderSet, .reconciled, .firstPlanSet, .firstDexCard]

    func testNonNewbieCannotCompleteNewbieQuests() {
        var g = GameState()
        _ = g.recordDCA(on: date(2026, 10, 5))
        XCTAssertFalse(g.isNewbie)
        XCTAssertEqual(g.complete(.firstDexCard, now: date(2026, 11, 12)), [])
        XCTAssertEqual(g.complete(.firstPlanSet, now: date(2026, 11, 12)), [])
        XCTAssertNil(g.questsDone["2026-11"])
    }

    func testQuestsDoneNeverExceedsThree() {
        for newbie in [true, false] {
            var g = GameState()
            if !newbie { _ = g.recordDCA(on: date(2026, 10, 5)) }
            for t in allTriggers { _ = g.complete(t, now: date(2026, 11, 12)) }
            XCTAssertEqual(g.questsDone["2026-11"]?.count, 3)
        }
    }

    func testNewbieCannotCompleteQuestOutsideTheirList() {
        var g = GameState()
        g.habit = .dca
        let shown = Quests.forMonth(YearMonth(year: 2026, month: 11), habit: .dca, isNewbie: true).map(\.trigger)
        let hidden = [QuestTrigger.dividendsViewed, .newETFResearched, .reminderSet, .reconciled].first { !shown.contains($0) }!
        XCTAssertEqual(g.complete(hidden, now: date(2026, 11, 12)), [])
    }

    func testNewbieQuestOnlyOnceEver() {
        var g = GameState()
        XCTAssertTrue(g.isNewbie)
        XCTAssertEqual(g.complete(.firstPlanSet, now: date(2026, 11, 12)), [.questDone])
        XCTAssertEqual(g.complete(.firstPlanSet, now: date(2026, 12, 3)), [])
    }

    /// The lobby's quest card: a newbie quest finished in an earlier month still shows as done; a monthly quest
    /// only counts in the month it was finished.
    func testIsDoneKeepsNewbieQuestsAcrossMonths() {
        var g = GameState()
        _ = g.complete(.firstPlanSet, now: date(2026, 10, 12))
        g.questsDone["2026-10", default: []].insert(Quests.dcaLogged.id)
        let november = YearMonth(year: 2026, month: 11)
        XCTAssertTrue(g.isDone(Quests.firstPlanSet, in: november))
        XCTAssertFalse(g.isDone(Quests.firstDexCard, in: november))
        XCTAssertFalse(g.isDone(Quests.dcaLogged, in: november))
        XCTAssertTrue(g.isDone(Quests.dcaLogged, in: YearMonth(year: 2026, month: 10)))
    }

    func testAwardCountsEvents() {
        var g = GameState()
        g.award(.reconciled); g.award(.reconciled)
        g.count(.feeCompared)
        XCTAssertEqual(g.counts["reconciled"], 2)
        XCTAssertEqual(g.counts["feeCompared"], 1)
    }

    func testNoMoneyTargetAchievements() {
        for a in Achievements.all {
            XCTAssertFalse(a.title.contains("萬"), a.title)
            XCTAssertFalse(a.title.contains("元"), a.title)
        }
        XCTAssertEqual(Achievements.all.count, 11)
        XCTAssertEqual(Set(Achievements.all.map(\.id)).count, 11)
        XCTAssertEqual(Achievements.all.first { $0.id == "dividendMilestone" }?.title, "累計領息里程碑")
    }

    func testDCAPunchCardUnlocksAt12() {
        let card = Achievements.all.first { $0.id == "dcaPunchCard" }!
        XCTAssertEqual(card.goal, 12)
        var g = GameState()
        var m = YearMonth(year: 2026, month: 1)
        for i in 0..<12 { g.dcaMonths.insert(m); m = m.next(); if i == 10 { XCTAssertFalse(g.refreshAchievements(Portfolio(), now: date(2026, 12, 1)).contains("dcaPunchCard")) } }
        let now = date(2026, 12, 31)
        XCTAssertTrue(g.refreshAchievements(Portfolio(), now: now).contains("dcaPunchCard"))
        XCTAssertEqual(g.unlocked["dcaPunchCard"], now)
        XCTAssertFalse(g.refreshAchievements(Portfolio(), now: now).contains("dcaPunchCard"))
    }

    func testDividendStreakAndMilestoneCountRecordsNotAmounts() {
        var p = Portfolio()
        p.dividends = [paid(2025, 11), paid(2025, 12), paid(2026, 1), paid(2026, 2), paid(2026, 3), paid(2026, 4)]
        var g = GameState()
        let ids = g.refreshAchievements(p, now: date(2026, 5, 1))
        XCTAssertTrue(ids.contains("dividendStreak"))
        XCTAssertFalse(ids.contains("dividendMilestone"))
        // A gap breaks the run; announced dividends do not count.
        p.dividends = [paid(2026, 1), paid(2026, 2), paid(2026, 4), paid(2026, 5), paid(2026, 6), paid(2026, 7)]
        p.dividends.append(Dividend(symbol: "00878", date: date(2026, 8, 20), amount: 100, status: .announced))
        XCTAssertEqual(Achievements.longestDividendRun(p), 4)
        p.dividends = (1...12).map { paid(2026, $0) }
        var g2 = GameState()
        XCTAssertTrue(g2.refreshAchievements(p, now: date(2027, 1, 1)).contains("dividendMilestone"))
    }

    func testAnniversaryAndSteadyYear() {
        let now = date(2026, 11, 12)
        var p = Portfolio()
        p.holdings = [holding(bought: date(2025, 11, 20))]
        var g = GameState()
        XCTAssertFalse(g.refreshAchievements(p, now: now).contains("holdingAnniversary"))
        p.holdings = [holding(bought: date(2025, 11, 12))]
        let ids = g.refreshAchievements(p, now: now)
        XCTAssertTrue(ids.contains("holdingAnniversary"))
        XCTAssertTrue(ids.contains("steadyYear"))

        var sold = GameState()
        p.log(.sell, holding(bought: nil), date: date(2026, 6, 1))
        let ids2 = sold.refreshAchievements(p, now: now)
        XCTAssertTrue(ids2.contains("holdingAnniversary"))
        XCTAssertFalse(ids2.contains("steadyYear"))
        // An old sell no longer blocks it.
        var q = Portfolio()
        q.holdings = [holding(bought: date(2024, 1, 1))]
        q.log(.sell, holding(bought: nil), date: date(2025, 3, 1))
        var g3 = GameState()
        XCTAssertTrue(g3.refreshAchievements(q, now: now).contains("steadyYear"))
    }

    func testCounterAchievements() {
        var g = GameState()
        for _ in 0..<5 { g.award(.reconciled) }
        for _ in 0..<3 { g.count(.feeCompared) }
        g.count(.checkup); g.count(.exDividendSeason); g.count(.yearReport)
        for i in 0..<10 { g.collected["etf\(i)"] = date(2026, 1, 1) }
        let ids = g.refreshAchievements(Portfolio(), now: date(2026, 11, 12))
        for id in ["reconcileMaster", "feeSaver", "checkupDone", "exDividendSkin", "yearReport", "dexCollector"] {
            XCTAssertTrue(ids.contains(id), id)
        }
    }

    func testGameStateDecodesJSONWithoutNewKeys() throws {
        let json = """
        {"xp":120,"coins":120,"dcaMonths":[],"longestStreak":2,"collected":{},"unlocked":{},"questsDone":{"2026-11":["dcaLogged"]}}
        """
        let g = try JSONDecoder().decode(GameState.self, from: Data(json.utf8))
        XCTAssertEqual(g.xp, 120)
        XCTAssertEqual(g.longestStreak, 2)
        XCTAssertNil(g.habit)
        XCTAssertEqual(g.counts, [:])
        let empty = try JSONDecoder().decode(GameState.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, GameState())
    }

    func testGameStateRoundTripsNewFields() throws {
        var g = GameState()
        g.habit = .savingGoal
        g.count(.checkup)
        let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(g))
        XCTAssertEqual(back, g)
    }
}
