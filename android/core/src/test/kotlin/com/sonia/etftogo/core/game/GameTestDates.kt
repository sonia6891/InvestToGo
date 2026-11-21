package com.sonia.etftogo.core.game

import java.time.Instant
import java.time.LocalDateTime

/** Swift tests' `GameRules.taipei.date(from: DateComponents(year:month:day:hour:))`. */
fun taipei(y: Int, m: Int, d: Int, hour: Int = 12, minute: Int = 0): Instant =
    LocalDateTime.of(y, m, d, hour, minute).atZone(GameRules.taipei).toInstant()

/** Swift `GameRules.taipei.date(byAdding: .month, value: 1, to:)`. */
fun Instant.plusTaipeiMonth(): Instant = atZone(GameRules.taipei).plusMonths(1).toInstant()

/** The first month from `start` (stepping a month at a time) whose non-newbie rotation for `habit` contains `quest`. */
fun firstMonthWith(quest: Quest, start: Instant, habit: Habit = Habit.DCA): Instant {
    var month = start
    while (quest !in Quests.forMonth(YearMonth.of(month), habit, isNewbie = false)) month = month.plusTaipeiMonth()
    return month
}
