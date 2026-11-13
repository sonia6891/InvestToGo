import XCTest
@testable import PocketCore

/// The real actions that move the game (final review C1, I2; rulings R31, R34).
final class GameTriggerTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        GameRules.taipei.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }
    private let now = GameRules.taipei.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 12))!

    // MARK: Migration

    func testMigrationBackfillsMonthsFromBuysAndPurchaseDatesWithoutExperience() {
        var p = Portfolio()
        var h = Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "", strategy: .saving)
        h.purchaseDate = date(2026, 8, 6)
        p.holdings = [h]
        p.log(.buy, h, date: date(2026, 9, 6))
        p.log(.buy, h, date: date(2026, 10, 6))
        p.log(.sell, h, date: date(2026, 6, 6))
        p.log(.adjust, h, date: date(2026, 5, 6))
        var g = GameState()
        g.migrate(p)
        XCTAssertEqual(g.dcaMonths, [YearMonth(year: 2026, month: 8), YearMonth(year: 2026, month: 9), YearMonth(year: 2026, month: 10)],
                       "Buys and purchase dates only; sells and edits are not DCA months")
        XCTAssertEqual(g.longestStreak, 3)
        XCTAssertEqual(g.streak(now: now), 3, "November's debit not yet made is not a break")
        XCTAssertEqual(g.xp, 0, "Months only")
        XCTAssertEqual(g.coins, 0)
        XCTAssertEqual(g.counter(.monthlyDCA), 0)
        XCTAssertNil(g.levelUpDue)
        XCTAssertFalse(g.isNewbie, "An upgrading user with records is no longer a newbie")
        XCTAssertEqual(g.migration, GameMigration.current)
    }

    func testMigrationRunsOnce() {
        var p = Portfolio()
        let h = Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "", strategy: .saving)
        p.log(.buy, h, date: date(2026, 3, 6))
        var g = GameState()
        g.migrate(Portfolio())
        g.migrate(p)
        XCTAssertTrue(g.dcaMonths.isEmpty, "Already migrated: later records are not backfilled again")
    }

    func testBackfillMergesRunsAcrossAGap() {
        var g = GameState()
        _ = g.insertMonth(YearMonth(year: 2026, month: 1))
        _ = g.insertMonth(YearMonth(year: 2026, month: 3))
        XCTAssertEqual(g.longestStreak, 1)
        _ = g.insertMonth(YearMonth(year: 2026, month: 2))
        XCTAssertEqual(g.longestStreak, 3, "The month between two runs joins them")
    }

    func testMigrationDecodesFromOlderSave() throws {
        let old = try JSONDecoder().decode(GameState.self, from: Data(#"{"xp":40}"#.utf8))
        XCTAssertEqual(old.migration, 0)
        XCTAssertEqual(old.rewardKeys, [])
    }

    // MARK: Buys

    func testBuyThisMonthEarnsDCAAndFinishesTheQuest() {
        var g = GameState()
        g.habit = .dca
        XCTAssertEqual(g.logBuy(on: now, now: now), [.monthlyDCA, .questDone])
        XCTAssertEqual(g.xp, 140)
        XCTAssertTrue(g.isDone(Quests.dcaLogged, in: YearMonth(now)))
        XCTAssertEqual(g.logBuy(on: now, now: now), [], "A second buy the same month earns nothing")
    }

    func testBuyLastMonthEarnsDCAButNotThisMonthsQuest() {
        var g = GameState()
        XCTAssertEqual(g.logBuy(on: date(2026, 10, 6), now: now), [.monthlyDCA])
        XCTAssertFalse(g.isDone(Quests.dcaLogged, in: YearMonth(now)))
    }

    func testOldBuysRecordMonthsWithoutExperience() {
        var g = GameState()
        for m in 1...8 { XCTAssertEqual(g.logBuy(on: date(2026, m, 6), now: now), []) }
        XCTAssertEqual(g.dcaMonths.count, 8)
        XCTAssertEqual(g.longestStreak, 8)
        XCTAssertEqual(g.xp, 0, "Typing in history does not farm levels")
    }

    func testFutureBuyCountsForNothing() {
        var g = GameState()
        XCTAssertEqual(g.logBuy(on: date(2026, 12, 6), now: now), [])
        XCTAssertTrue(g.dcaMonths.isEmpty)
    }

    func testNearMidnightTaipeiBuyLandsInTheTaipeiMonth() {
        // 2026-11-30 16:30 UTC is 2026-12-01 00:30 in Taipei.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let lateNight = utc.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 16, minute: 30))!
        XCTAssertEqual(YearMonth(lateNight), YearMonth(year: 2026, month: 12))
        var g = GameState()
        g.habit = .dca
        XCTAssertEqual(g.logBuy(on: lateNight, now: lateNight), [.monthlyDCA, .questDone])
        XCTAssertEqual(g.dcaMonths, [YearMonth(year: 2026, month: 12)])
        XCTAssertEqual(g.questsDone["2026-12"], ["dcaLogged"])
        XCTAssertEqual(g.streak(now: lateNight), 1)
        // One minute before Taipei midnight is still November.
        let beforeMidnight = utc.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 15, minute: 59))!
        XCTAssertEqual(YearMonth(beforeMidnight), YearMonth(year: 2026, month: 11))
    }

    // MARK: Fund visits (dex)

    func testFirstVisitCollectsTheCardAndFinishesTheNewbieQuest() {
        var g = GameState()
        XCTAssertEqual(g.visitFund("0050", now: now), FundVisit(new: true, cardXP: 30))
        XCTAssertTrue(g.isDone(Quests.firstDexCard, in: YearMonth(now)))
        XCTAssertEqual(g.xp, 70, "+30 card and +40 quest")
        XCTAssertEqual(g.visitFund("0050", now: now), FundVisit(), "Already collected")
        XCTAssertEqual(g.xp, 70)
    }

    func testVisitFinishesNewETFResearchedForTheSavingGoalHabit() {
        var g = GameState()
        g.habit = .savingGoal
        g.dcaMonths = [YearMonth(now).previous()]
        _ = g.visitFund("00878", now: now)
        XCTAssertTrue(g.isDone(Quests.newETFResearched, in: YearMonth(now)))
    }

    func testDexExperienceOnlyForThreeNewCardsAMonth() {
        var g = GameState()
        g.dcaMonths = [YearMonth(now)]  // not a newbie: no quest experience in the way
        g.habit = .dividends
        XCTAssertEqual(g.collect("a", now: now), [.firstDexCard])
        XCTAssertEqual(g.collect("b", now: now), [.firstDexCard])
        XCTAssertEqual(g.collect("c", now: now), [.firstDexCard])
        XCTAssertEqual(g.collect("d", now: now), [], "The fourth new card this month earns nothing")
        XCTAssertNotNil(g.collected["d"], "but is still collected")
        XCTAssertEqual(g.xp, 90)
        XCTAssertEqual(g.collect("e", now: date(2026, 12, 1, hour: 0)), [.firstDexCard], "A new Taipei month starts again")
        XCTAssertEqual(g.xp, 120)
    }

    // MARK: Dividends, reconciliation, fees

    func testDividendExperienceOncePerCodeAndPaymentMonth() {
        var g = GameState()
        XCTAssertEqual(g.logDividend(symbol: "00878", paid: date(2026, 11, 18)), [.dividendLogged])
        XCTAssertEqual(g.logDividend(symbol: "00878", paid: date(2026, 11, 20)), [], "Deleted and logged again: nothing")
        XCTAssertEqual(g.logDividend(symbol: "0056", paid: date(2026, 11, 18)), [.dividendLogged])
        XCTAssertEqual(g.logDividend(symbol: "00878", paid: date(2027, 2, 18)), [.dividendLogged])
        XCTAssertEqual(g.xp, 60)
        XCTAssertEqual(g.counter(.dividendLogged), 3)
    }

    func testReconcileOncePerDayAndFinishesTheQuest() {
        var g = GameState()
        g.dcaMonths = [YearMonth(now)]
        g.habit = .dca
        // Find a month whose rotation includes 完成一次對帳.
        var month = now
        while !Quests.forMonth(YearMonth(month), habit: .dca, isNewbie: false).contains(Quests.reconciled) {
            month = GameRules.taipei.date(byAdding: .month, value: 1, to: month)!
        }
        g.dcaMonths = [YearMonth(month)]
        XCTAssertEqual(g.reconcile(now: month), [.reconciled, .questDone])
        XCTAssertEqual(g.reconcile(now: month), [], "A second import the same day earns nothing")
        XCTAssertEqual(g.counter(.reconciled), 1)
        let tomorrow = GameRules.taipei.date(byAdding: .day, value: 1, to: month)!
        XCTAssertEqual(g.reconcile(now: tomorrow), [.reconciled])
        XCTAssertEqual(g.counter(.reconciled), 2)
    }

    func testFeeComparisonCountsOncePerDay() {
        var g = GameState()
        XCTAssertTrue(g.compareFees(now: now))
        XCTAssertFalse(g.compareFees(now: now))
        XCTAssertTrue(g.compareFees(now: date(2026, 11, 14)))
        XCTAssertEqual(g.counter(.feeCompared), 2)
        XCTAssertEqual(g.xp, 0, "A counter, not experience")
    }

    func testPlanAndReminderQuestsForANewbie() {
        var g = GameState()
        XCTAssertEqual(g.complete(.firstPlanSet, now: now), [.questDone])
        XCTAssertEqual(g.complete(.firstPlanSet, now: now), [])
        // 設定除息提醒 is a monthly quest: find a month whose rotation has it.
        g.dcaMonths = [YearMonth(now)]
        var month = now
        while !Quests.forMonth(YearMonth(month), habit: .dca, isNewbie: false).contains(Quests.reminderSet) {
            month = GameRules.taipei.date(byAdding: .month, value: 1, to: month)!
        }
        XCTAssertEqual(g.complete(.reminderSet, now: month), [.questDone])
    }

    // MARK: Coming soon

    func testAchievementsWithoutAFeatureAreComingSoonAndNeverUnlock() {
        XCTAssertEqual(Set(Achievements.all.filter(\.comingSoon).map(\.id)), ["checkupDone", "exDividendSkin", "yearReport"])
        var g = GameState()
        g.count(.checkup); g.count(.exDividendSeason); g.count(.yearReport)
        let fresh = g.refreshAchievements(Portfolio(), now: now)
        for id in ["checkupDone", "exDividendSkin", "yearReport"] { XCTAssertFalse(fresh.contains(id), id) }
    }
}
