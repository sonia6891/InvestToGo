package com.sonia.etftogo.core.game

import com.sonia.etftogo.core.models.Holding
import com.sonia.etftogo.core.models.Portfolio
import com.sonia.etftogo.core.models.Strategy
import com.sonia.etftogo.core.models.TradeAction
import com.sonia.etftogo.core.support.CoreJson
import java.time.LocalDateTime
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The real actions that move the game (final review C1, I2; rulings R31, R34). */
class GameTriggerTests {
    private fun date(y: Int, m: Int, d: Int, hour: Int = 12) = taipei(y, m, d, hour)
    private val now = taipei(2026, 11, 12)
    private val dca = listOf(XPEvent.MONTHLY_DCA)
    private val card = listOf(XPEvent.FIRST_DEX_CARD)
    private val dividend = listOf(XPEvent.DIVIDEND_LOGGED)
    private val none = emptyList<XPEvent>()
    private fun holding(symbol: String = "0050", name: String = "元大台灣50", strategy: Strategy = Strategy.SAVING, cost: Double = 50.0) =
        Holding(symbol = symbol, name = name, shares = 1000.0, unitCost = cost, broker = "", strategy = strategy)

    // Migration

    @Test fun migrationBackfillsMonthsFromBuysAndPurchaseDatesWithoutExperience() {
        val h = holding().copy(purchaseDate = date(2026, 8, 6))
        val p = Portfolio(holdings = listOf(h)).log(TradeAction.BUY, h, date(2026, 9, 6)).log(TradeAction.BUY, h, date(2026, 10, 6))
            .log(TradeAction.SELL, h, date(2026, 6, 6)).log(TradeAction.ADJUST, h, date(2026, 5, 6))
        val g = GameState().migrate(p)
        assertEquals(setOf(YearMonth(2026, 8), YearMonth(2026, 9), YearMonth(2026, 10)), g.dcaMonths, "Buys and purchase dates only; sells and edits are not DCA months")
        assertEquals(3, g.longestStreak)
        assertEquals(3, g.streak(now), "November's debit not yet made is not a break")
        assertEquals(0, g.xp, "Months only")
        assertEquals(0, g.coins)
        assertEquals(0, g.counter(CounterKey.MONTHLY_DCA))
        assertNull(g.levelUpDue)
        assertFalse(g.isNewbie, "An upgrading user with records is no longer a newbie")
        assertEquals(GameMigration.current, g.migration)
    }

    @Test fun migrationRunsOnce() {
        val p = Portfolio().log(TradeAction.BUY, holding(), date(2026, 3, 6))
        val g = GameState().migrate(Portfolio()).migrate(p)
        assertTrue(g.dcaMonths.isEmpty(), "Already migrated: later records are not backfilled again")
    }

    @Test fun backfillMergesRunsAcrossAGap() {
        var g = GameState().insertMonth(YearMonth(2026, 1)).first.insertMonth(YearMonth(2026, 3)).first
        assertEquals(1, g.longestStreak)
        g = g.insertMonth(YearMonth(2026, 2)).first
        assertEquals(3, g.longestStreak, "The month between two runs joins them")
    }

    @Test fun migrationDecodesFromOlderSave() {
        val old = CoreJson.json.decodeFromString(GameState.serializer(), """{"xp":40}""")
        assertEquals(0, old.migration)
        assertEquals(emptySet(), old.rewardKeys)
    }

    // Buys

    @Test fun buyThisMonthEarnsDCAAndFinishesTheQuest() {
        val (g, events) = GameState(habit = Habit.DCA).logBuy(now, now)
        assertEquals(listOf(XPEvent.MONTHLY_DCA, XPEvent.QUEST_DONE), events)
        assertEquals(140, g.xp)
        assertTrue(g.isDone(Quests.dcaLogged, YearMonth.of(now)))
        assertEquals(none, g.logBuy(now, now).second, "A second buy the same month earns nothing")
    }

    @Test fun buyLastMonthEarnsDCAButNotThisMonthsQuest() {
        val (g, events) = GameState().logBuy(date(2026, 10, 6), now)
        assertEquals(dca, events)
        assertFalse(g.isDone(Quests.dcaLogged, YearMonth.of(now)))
    }

    @Test fun oldBuysRecordMonthsWithoutExperience() {
        var g = GameState()
        for (m in 1..8) {
            val (next, events) = g.logBuy(date(2026, m, 6), now)
            assertEquals(none, events)
            g = next
        }
        assertEquals(8, g.dcaMonths.size)
        assertEquals(8, g.longestStreak)
        assertEquals(0, g.xp, "Typing in history does not farm levels")
    }

    @Test fun futureBuyCountsForNothing() {
        val (g, events) = GameState().logBuy(date(2026, 12, 6), now)
        assertEquals(none, events)
        assertTrue(g.dcaMonths.isEmpty())
    }

    @Test fun nearMidnightTaipeiBuyLandsInTheTaipeiMonth() {
        // 2026-11-30 16:30 UTC is 2026-12-01 00:30 in Taipei.
        val lateNight = LocalDateTime.of(2026, 11, 30, 16, 30).toInstant(ZoneOffset.UTC)
        assertEquals(YearMonth(2026, 12), YearMonth.of(lateNight))
        val (g, events) = GameState(habit = Habit.DCA).logBuy(lateNight, lateNight)
        assertEquals(listOf(XPEvent.MONTHLY_DCA, XPEvent.QUEST_DONE), events)
        assertEquals(setOf(YearMonth(2026, 12)), g.dcaMonths)
        assertEquals(setOf("dcaLogged"), g.questsDone["2026-12"])
        assertEquals(1, g.streak(lateNight))
        // One minute before Taipei midnight is still November.
        assertEquals(YearMonth(2026, 11), YearMonth.of(LocalDateTime.of(2026, 11, 30, 15, 59).toInstant(ZoneOffset.UTC)))
    }

    // Fund visits (dex)

    @Test fun firstVisitCollectsTheCardAndFinishesTheNewbieQuest() {
        val (g, visit) = GameState().visitFund("0050", now)
        assertEquals(FundVisit(new = true, cardXP = 30), visit)
        assertTrue(g.isDone(Quests.firstDexCard, YearMonth.of(now)))
        assertEquals(70, g.xp, "+30 card and +40 quest")
        val (again, second) = g.visitFund("0050", now)
        assertEquals(FundVisit(), second, "Already collected")
        assertEquals(70, again.xp)
    }

    @Test fun visitFinishesNewETFResearchedForTheSavingGoalHabit() {
        val g = GameState(habit = Habit.SAVING_GOAL, dcaMonths = setOf(YearMonth.of(now).previous())).visitFund("00878", now).first
        assertTrue(g.isDone(Quests.newETFResearched, YearMonth.of(now)))
    }

    @Test fun dexExperienceOnlyForThreeNewCardsAMonth() {
        var g = GameState(dcaMonths = setOf(YearMonth.of(now)), habit = Habit.DIVIDENDS) // not a newbie: no quest experience in the way
        for (code in listOf("a", "b", "c")) {
            val (next, events) = g.collect(code, now)
            assertEquals(card, events); g = next
        }
        val (fourth, events) = g.collect("d", now)
        assertEquals(none, events, "The fourth new card this month earns nothing")
        g = fourth
        assertNotNull(g.collected["d"], "but is still collected")
        assertEquals(90, g.xp)
        val (fifth, next) = g.collect("e", date(2026, 12, 1, hour = 0))
        assertEquals(card, next, "A new Taipei month starts again")
        assertEquals(120, fifth.xp)
    }

    // Dividends, reconciliation, fees

    @Test fun dividendExperienceOncePerCodeAndPaymentMonth() {
        var g = GameState()
        g.logDividend("00878", date(2026, 11, 6), true, now).let { (next, e) -> assertEquals(dividend, e); g = next }
        g.logDividend("00878", date(2026, 11, 10), true, now).let { (next, e) -> assertEquals(none, e, "Deleted and logged again: nothing"); g = next }
        g.logDividend("0056", date(2026, 10, 18), true, now).let { (next, e) -> assertEquals(dividend, e, "Last month still counts"); g = next }
        assertEquals(40, g.xp)
        assertEquals(2, g.counter(CounterKey.DIVIDEND_LOGGED))
    }

    /** Re-review N1: changing the code or the month no longer farms experience. */
    @Test fun dividendExperienceNeedsAHeldCodeARecentPaymentAndACap() {
        var g = GameState()
        fun log(symbol: String, paid: java.time.Instant, held: Boolean = true, at: java.time.Instant = now): List<XPEvent> {
            val (next, events) = g.logDividend(symbol, paid, held, at)
            g = next
            return events
        }
        assertEquals(none, log("9999", date(2026, 11, 6), held = false), "A code not held")
        assertEquals(none, log("00878", date(2026, 11, 20)), "Not paid yet")
        assertEquals(none, log("00878", date(2027, 2, 18)), "A future month")
        assertEquals(none, log("00878", date(2026, 9, 18)), "Two months back is history")
        assertEquals(none, log("00878", date(2024, 11, 6)))
        assertEquals(0, g.xp)
        assertTrue(g.rewardKeys.isEmpty(), "Nothing paid, nothing spent: a later real log can still earn")
        // Three a month, like the dex cards.
        for (code in listOf("0050", "0056", "00878")) assertEquals(dividend, log(code, date(2026, 11, 6)))
        assertEquals(none, log("00919", date(2026, 11, 6)), "The fourth this month earns nothing")
        assertEquals(60, g.xp)
        assertEquals(dividend, log("00919", date(2026, 12, 2), at = date(2026, 12, 3)), "A new Taipei month starts again")
    }

    @Test fun dividendsPaidBeforeTheGameStartedEarnNothing() {
        var g = GameState().migrate(Portfolio(), now)
        assertEquals(now, g.migratedAt)
        assertEquals(none, g.logDividend("00878", date(2026, 11, 6), true, now).second, "Typed in after upgrading: history")
        g.logDividend("00878", date(2026, 11, 12, hour = 1), true, now).let { (next, e) -> assertEquals(dividend, e, "Paid the day the game started"); g = next }
        g = g.migrate(Portfolio(), date(2026, 12, 1))
        assertEquals(now, g.migratedAt, "Set once")
        val back = CoreJson.json.decodeFromString(GameState.serializer(), CoreJson.json.encodeToString(GameState.serializer(), g))
        assertEquals(now, back.migratedAt)
    }

    /** Re-review N6: a holding saved without a purchase date logged its buy on the day it was typed in. */
    @Test fun backfillSkipsTheEntryDayOfAnUndatedHolding() {
        val undated = holding("0056", "元大高股息", Strategy.INCOME, 30.0)
        val p = Portfolio(holdings = listOf(undated)).log(TradeAction.BUY, undated, date(2026, 7, 2)).log(TradeAction.BUY, undated, date(2026, 9, 6))
        assertEquals(setOf(YearMonth(2026, 9)), GameState().backfillDCA(p).dcaMonths, "The entry day is not a debit; a later buy is")
    }

    @Test fun reconcileOncePerMonthAndFinishesTheQuest() {
        // Find a month whose rotation includes 完成一次對帳.
        val month = firstMonthWith(Quests.reconciled, now)
        var g = GameState(dcaMonths = setOf(YearMonth.of(month)), habit = Habit.DCA)
        g.reconcile(month).let { (next, e) -> assertEquals(listOf(XPEvent.RECONCILED, XPEvent.QUEST_DONE), e); g = next }
        assertEquals(none, g.reconcile(month).second, "A second import the same day earns nothing")
        val ym = YearMonth.of(month)
        assertEquals(none, g.reconcile(date(ym.year, ym.month, 25)).second, "Nor another day the same Taipei month (re-review N2)")
        assertEquals(1, g.counter(CounterKey.RECONCILED))
        g.reconcile(month.plusTaipeiMonth()).let { (next, e) -> assertEquals(XPEvent.RECONCILED, e.first()); g = next }
        assertEquals(2, g.counter(CounterKey.RECONCILED))
    }

    @Test fun feeComparisonCountsOncePerDay() {
        var g = GameState()
        g.compareFees(now).let { (next, counted) -> assertTrue(counted); g = next }
        g.compareFees(now).let { (next, counted) -> assertFalse(counted); g = next }
        g.compareFees(date(2026, 11, 14)).let { (next, counted) -> assertTrue(counted); g = next }
        assertEquals(2, g.counter(CounterKey.FEE_COMPARED))
        assertEquals(0, g.xp, "A counter, not experience")
    }

    @Test fun planAndReminderQuestsForANewbie() {
        var g = GameState()
        g.complete(QuestTrigger.FIRST_PLAN_SET, now).let { (next, e) -> assertEquals(listOf(XPEvent.QUEST_DONE), e); g = next }
        assertEquals(none, g.complete(QuestTrigger.FIRST_PLAN_SET, now).second)
        // 設定除息提醒 is a monthly quest: find a month whose rotation has it.
        g = g.copy(dcaMonths = setOf(YearMonth.of(now)))
        val month = firstMonthWith(Quests.reminderSet, now)
        assertEquals(listOf(XPEvent.QUEST_DONE), g.complete(QuestTrigger.REMINDER_SET, month).second)
    }

    // Coming soon

    @Test fun achievementsWithoutAFeatureAreComingSoonAndNeverUnlock() {
        assertEquals(setOf("checkupDone", "exDividendSkin", "yearReport"), Achievements.all.filter { it.comingSoon }.map { it.id }.toSet())
        val g = GameState().count(CounterKey.CHECKUP).count(CounterKey.EX_DIVIDEND_SEASON).count(CounterKey.YEAR_REPORT)
        val fresh = g.refreshAchievements(Portfolio(), now).second
        for (id in listOf("checkupDone", "exDividendSkin", "yearReport")) assertFalse(id in fresh, id)
    }
}
