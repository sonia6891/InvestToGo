package com.sonia.etftogo.core.game

import com.sonia.etftogo.core.models.Dividend
import com.sonia.etftogo.core.models.DividendStatus
import com.sonia.etftogo.core.models.Holding
import com.sonia.etftogo.core.models.Portfolio
import com.sonia.etftogo.core.models.Strategy
import com.sonia.etftogo.core.models.TradeAction
import com.sonia.etftogo.core.support.CoreJson
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class QuestAchievementTests {
    private fun date(y: Int, m: Int, d: Int) = taipei(y, m, d)
    private fun holding(bought: Instant?) =
        Holding(symbol = "0050", name = "元大台灣50", shares = 1000.0, unitCost = 50.0, broker = "富邦證券", strategy = Strategy.SAVING, purchaseDate = bought)
    private fun paid(y: Int, m: Int) = Dividend(symbol = "00878", date = date(y, m, 20), amount = 100.0, status = DividendStatus.PAID)
    private val quest = listOf(XPEvent.QUEST_DONE)
    private val none = emptyList<XPEvent>()
    private fun decode(text: String) = CoreJson.json.decodeFromString(GameState.serializer(), text)

    @Test fun threeQuestsEveryMonthDeterministic() {
        for (h in Habit.entries) {
            val months = generateSequence(YearMonth(2026, 1)) { it.next() }.take(12).toList()
            val lists = months.map { Quests.forMonth(it, h, isNewbie = false) }
            for ((m, l) in months.zip(lists)) {
                assertEquals(3, l.size)
                assertEquals(3, l.map { it.id }.toSet().size)
                assertEquals(Quests.forMonth(m, h, isNewbie = false), l)
            }
            assertTrue(lists.map { list -> list.map { it.id } }.toSet().size > 1)
        }
    }

    @Test fun newbieQuests() {
        for (h in Habit.entries) {
            val q = Quests.forMonth(YearMonth(2026, 11), h, isNewbie = true)
            assertEquals(3, q.size)
            assertTrue(q.any { it.trigger == QuestTrigger.FIRST_PLAN_SET })
            assertTrue(q.any { it.trigger == QuestTrigger.FIRST_DEX_CARD })
        }
    }

    @Test fun questCompletesOncePerMonth() {
        var g = GameState()
        val now = date(2026, 11, 12)
        g.complete(QuestTrigger.DCA_LOGGED, now).let { (next, e) -> assertEquals(quest, e); g = next }
        g.complete(QuestTrigger.DCA_LOGGED, now).let { (next, e) -> assertEquals(none, e); g = next }
        assertEquals(40, g.xp)
        assertEquals(setOf("dcaLogged"), g.questsDone["2026-11"])
        assertEquals(quest, g.complete(QuestTrigger.DCA_LOGGED, date(2026, 12, 1)).second)
    }

    @Test fun questNotInThisMonthIsIgnored() {
        val g = GameState(habit = Habit.DIVIDENDS)
        val now = date(2026, 11, 12)
        val triggers = Quests.forMonth(YearMonth.of(now), Habit.DIVIDENDS, isNewbie = false).map { it.trigger }
        assertTrue(QuestTrigger.DIVIDENDS_VIEWED in triggers)
        val absent = listOf(QuestTrigger.DCA_LOGGED, QuestTrigger.NEW_ETF_RESEARCHED, QuestTrigger.REMINDER_SET, QuestTrigger.RECONCILED).first { it !in triggers }
        val (after, events) = g.complete(absent, now)
        assertEquals(none, events)
        assertEquals(0, after.xp)
    }

    private val allTriggers = QuestTrigger.entries

    @Test fun nonNewbieCannotCompleteNewbieQuests() {
        val g = GameState().recordDCA(date(2026, 10, 5)).first
        assertFalse(g.isNewbie)
        assertEquals(none, g.complete(QuestTrigger.FIRST_DEX_CARD, date(2026, 11, 12)).second)
        val (after, events) = g.complete(QuestTrigger.FIRST_PLAN_SET, date(2026, 11, 12))
        assertEquals(none, events)
        assertNull(after.questsDone["2026-11"])
    }

    @Test fun questsDoneNeverExceedsThree() {
        for (newbie in listOf(true, false)) {
            var g = if (newbie) GameState() else GameState().recordDCA(date(2026, 10, 5)).first
            for (t in allTriggers) g = g.complete(t, date(2026, 11, 12)).first
            assertEquals(3, g.questsDone["2026-11"]?.size)
        }
    }

    @Test fun newbieCannotCompleteQuestOutsideTheirList() {
        val g = GameState(habit = Habit.DCA)
        val shown = Quests.forMonth(YearMonth(2026, 11), Habit.DCA, isNewbie = true).map { it.trigger }
        val hidden = listOf(QuestTrigger.DIVIDENDS_VIEWED, QuestTrigger.NEW_ETF_RESEARCHED, QuestTrigger.REMINDER_SET, QuestTrigger.RECONCILED).first { it !in shown }
        assertEquals(none, g.complete(hidden, date(2026, 11, 12)).second)
    }

    @Test fun newbieQuestOnlyOnceEver() {
        var g = GameState()
        assertTrue(g.isNewbie)
        g.complete(QuestTrigger.FIRST_PLAN_SET, date(2026, 11, 12)).let { (next, e) -> assertEquals(quest, e); g = next }
        assertEquals(none, g.complete(QuestTrigger.FIRST_PLAN_SET, date(2026, 12, 3)).second)
    }

    /** The lobby's quest card: a newbie quest finished earlier still shows as done; a monthly quest only in its month. */
    @Test fun isDoneKeepsNewbieQuestsAcrossMonths() {
        var g = GameState().complete(QuestTrigger.FIRST_PLAN_SET, date(2026, 10, 12)).first
        g = g.copy(questsDone = g.questsDone + ("2026-10" to (g.questsDone["2026-10"] ?: emptySet()) + Quests.dcaLogged.id))
        val november = YearMonth(2026, 11)
        assertTrue(g.isDone(Quests.firstPlanSet, november))
        assertFalse(g.isDone(Quests.firstDexCard, november))
        assertFalse(g.isDone(Quests.dcaLogged, november))
        assertTrue(g.isDone(Quests.dcaLogged, YearMonth(2026, 10)))
    }

    @Test fun awardCountsEvents() {
        val g = GameState().award(XPEvent.RECONCILED).award(XPEvent.RECONCILED).count(CounterKey.FEE_COMPARED)
        assertEquals(2, g.counts["reconciled"])
        assertEquals(1, g.counts["feeCompared"])
    }

    @Test fun noMoneyTargetAchievements() {
        for (a in Achievements.all) {
            assertFalse("萬" in a.title, a.title)
            assertFalse("元" in a.title, a.title)
        }
        assertEquals(11, Achievements.all.size)
        assertEquals(11, Achievements.all.map { it.id }.toSet().size)
        assertEquals("累計領息里程碑", Achievements.all.firstOrNull { it.id == "dividendMilestone" }?.title)
    }

    @Test fun dcaPunchCardUnlocksAt12() {
        val card = Achievements.all.first { it.id == "dcaPunchCard" }
        assertEquals(12, card.goal)
        var g = GameState()
        var m = YearMonth(2026, 1)
        for (i in 0 until 12) {
            g = g.copy(dcaMonths = g.dcaMonths + m); m = m.next()
            if (i == 10) {
                val (next, ids) = g.refreshAchievements(Portfolio(), date(2026, 12, 1))
                assertFalse("dcaPunchCard" in ids); g = next
            }
        }
        val now = date(2026, 12, 31)
        g.refreshAchievements(Portfolio(), now).let { (next, ids) -> assertTrue("dcaPunchCard" in ids); g = next }
        assertEquals(now, g.unlocked["dcaPunchCard"])
        assertFalse("dcaPunchCard" in g.refreshAchievements(Portfolio(), now).second)
    }

    @Test fun dividendStreakAndMilestoneCountRecordsNotAmounts() {
        var p = Portfolio(dividends = listOf(paid(2025, 11), paid(2025, 12), paid(2026, 1), paid(2026, 2), paid(2026, 3), paid(2026, 4)))
        val ids = GameState().refreshAchievements(p, date(2026, 5, 1)).second
        assertTrue("dividendStreak" in ids)
        assertFalse("dividendMilestone" in ids)
        // A gap breaks the run; announced dividends do not count.
        p = p.copy(dividends = listOf(paid(2026, 1), paid(2026, 2), paid(2026, 4), paid(2026, 5), paid(2026, 6), paid(2026, 7),
            Dividend(symbol = "00878", date = date(2026, 8, 20), amount = 100.0, status = DividendStatus.ANNOUNCED)))
        assertEquals(4, Achievements.longestDividendRun(p))
        p = p.copy(dividends = (1..12).map { paid(2026, it) })
        assertTrue("dividendMilestone" in GameState().refreshAchievements(p, date(2027, 1, 1)).second)
    }

    @Test fun anniversaryAndSteadyYear() {
        val now = date(2026, 11, 12)
        var p = Portfolio(holdings = listOf(holding(date(2025, 11, 20))))
        var g = GameState()
        g.refreshAchievements(p, now).let { (next, ids) -> assertFalse("holdingAnniversary" in ids); g = next }
        p = p.copy(holdings = listOf(holding(date(2025, 11, 12))))
        val ids = g.refreshAchievements(p, now).second
        assertTrue("holdingAnniversary" in ids)
        assertTrue("steadyYear" in ids)

        p = p.log(TradeAction.SELL, holding(null), date(2026, 6, 1))
        val ids2 = GameState().refreshAchievements(p, now).second
        assertTrue("holdingAnniversary" in ids2)
        assertFalse("steadyYear" in ids2)
        // An old sell no longer blocks it.
        val q = Portfolio(holdings = listOf(holding(date(2024, 1, 1)))).log(TradeAction.SELL, holding(null), date(2025, 3, 1))
        assertTrue("steadyYear" in GameState().refreshAchievements(q, now).second)
    }

    @Test fun counterAchievements() {
        var g = GameState()
        repeat(5) { g = g.award(XPEvent.RECONCILED) }
        repeat(3) { g = g.count(CounterKey.FEE_COMPARED) }
        g = g.count(CounterKey.CHECKUP).count(CounterKey.EX_DIVIDEND_SEASON).count(CounterKey.YEAR_REPORT)
        g = g.copy(collected = (0 until 10).associate { "etf$it" to date(2026, 1, 1) })
        val ids = g.refreshAchievements(Portfolio(), date(2026, 11, 12)).second
        for (id in listOf("reconcileMaster", "feeSaver", "dexCollector")) assertTrue(id in ids, id)
        // No feature counts these yet: they stay 「即將推出」 whatever the counter says (ruling R31).
        for (id in listOf("checkupDone", "exDividendSkin", "yearReport")) assertFalse(id in ids, id)
    }

    @Test fun gameStateDecodesJSONWithoutNewKeys() {
        val g = decode("""{"xp":120,"coins":120,"dcaMonths":[],"longestStreak":2,"collected":{},"unlocked":{},"questsDone":{"2026-11":["dcaLogged"]}}""")
        assertEquals(120, g.xp)
        assertEquals(2, g.longestStreak)
        assertNull(g.habit)
        assertEquals(emptyMap(), g.counts)
        assertEquals(GameState(), decode("{}"))
    }

    @Test fun gameStateRoundTripsNewFields() {
        val g = GameState(habit = Habit.SAVING_GOAL).count(CounterKey.CHECKUP)
        assertEquals(g, decode(CoreJson.json.encodeToString(GameState.serializer(), g)))
    }
}
