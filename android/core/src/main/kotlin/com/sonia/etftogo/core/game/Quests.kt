package com.sonia.etftogo.core.game

import java.time.Instant

enum class QuestTrigger(val rawValue: String) {
    DCA_LOGGED("dcaLogged"), DIVIDENDS_VIEWED("dividendsViewed"), NEW_ETF_RESEARCHED("newETFResearched"), REMINDER_SET("reminderSet"),
    RECONCILED("reconciled"), FIRST_PLAN_SET("firstPlanSet"), FIRST_DEX_CARD("firstDexCard");

    companion object {
        fun of(raw: String): QuestTrigger? = entries.firstOrNull { it.rawValue == raw }
    }
}

data class Quest(val id: String, val title: String, val trigger: QuestTrigger)

object Quests {
    val dcaLogged = Quest("dcaLogged", "本月定投一次", QuestTrigger.DCA_LOGGED)
    val dividendsViewed = Quest("dividendsViewed", "看一次配息", QuestTrigger.DIVIDENDS_VIEWED)
    val newETFResearched = Quest("newETFResearched", "研究 1 檔新 ETF", QuestTrigger.NEW_ETF_RESEARCHED)
    val reminderSet = Quest("reminderSet", "設定除息提醒", QuestTrigger.REMINDER_SET)
    val reconciled = Quest("reconciled", "完成一次對帳", QuestTrigger.RECONCILED)
    val firstPlanSet = Quest("firstPlanSet", "設定第一筆定投", QuestTrigger.FIRST_PLAN_SET)
    val firstDexCard = Quest("firstDexCard", "收集第 1 張圖鑑卡", QuestTrigger.FIRST_DEX_CARD)

    /** The fixed question bank: five monthly quests, then the two newbie ones. */
    val pool: List<Quest> = listOf(dcaLogged, dividendsViewed, newETFResearched, reminderSet, reconciled, firstPlanSet, firstDexCard)

    /** Earned once ever, never again in a later month. */
    val newbieOnly: Set<QuestTrigger> = setOf(QuestTrigger.FIRST_PLAN_SET, QuestTrigger.FIRST_DEX_CARD)
    private val monthly = pool.take(5)

    /** Each habit always keeps its own quest; the other two rotate through the rest by month. */
    private fun core(h: Habit): Quest = when (h) {
        Habit.DCA -> dcaLogged
        Habit.DIVIDENDS -> dividendsViewed
        Habit.SAVING_GOAL -> newETFResearched
    }

    /**
     * Always 3 quests. Same month + habit + newbie flag -> same result (seeded by year/month, no RNG).
     * Newbies get 設定第一筆定投 and 收集第 1 張圖鑑卡 plus the habit's own quest.
     */
    fun forMonth(m: YearMonth, habit: Habit, isNewbie: Boolean): List<Quest> {
        val c = core(habit)
        if (isNewbie) return listOf(firstPlanSet, firstDexCard, c)
        val rest = monthly.filter { it != c }
        val seed = m.year * 12 + m.month
        return listOf(c, rest[Math.floorMod(seed, rest.size)], rest[Math.floorMod(seed + 1, rest.size)])
    }
}

/**
 * Finishes this month's quest for `trigger`, only from the list the lobby shows this player (`Quests.forMonth` with
 * `isNewbie`). `[QUEST_DONE]` once per quest per month; the newbie-only quests can be finished once ever. Otherwise `[]`.
 */
fun GameState.complete(trigger: QuestTrigger, now: Instant): Pair<GameState, List<XPEvent>> {
    val m = YearMonth.of(now)
    val quest = Quests.forMonth(m, habit ?: Habit.DCA, isNewbie).firstOrNull { it.trigger == trigger } ?: return this to emptyList()
    if (quest.trigger in Quests.newbieOnly && questsDone.values.any { quest.id in it }) return this to emptyList()
    val month = questsDone[m.key] ?: emptySet()
    if (quest.id in month) return this to emptyList()
    return copy(questsDone = questsDone + (m.key to month + quest.id)).award(XPEvent.QUEST_DONE, now) to listOf(XPEvent.QUEST_DONE)
}

/**
 * Whether the lobby's quest card ticks `quest` in `month`. Monthly quests count only in the month they were
 * finished; the newbie-only ones stay done once finished in any month.
 */
fun GameState.isDone(quest: Quest, month: YearMonth): Boolean {
    if (quest.trigger in Quests.newbieOnly) return questsDone.values.any { quest.id in it }
    return questsDone[month.key]?.contains(quest.id) ?: false
}
