package com.sonia.etftogo.core.game

import java.time.Instant

/** `GameRules.progress`: experience into the current level, and the experience the level spans. */
typealias LevelProgress = GameRules.Progress

/**
 * Consecutive recorded months ending this month, or last month when this month's debit hasn't happened yet
 * (a missing current month is not a break). Neither recorded -> 0.
 */
fun GameState.streak(now: Instant): Int {
    val thisMonth = YearMonth.of(now)
    var m = if (thisMonth in dcaMonths) thisMonth else thisMonth.previous()
    var n = 0
    while (m in dcaMonths) {
        n += 1
        m = m.previous()
    }
    return n
}

/**
 * One monthly DCA per calendar month; a repeat in the same month earns nothing. The experience is earned
 * `now`, the day the debit was typed in (the debit's own day when not given).
 */
fun GameState.recordDCA(on: Instant, now: Instant? = null): Pair<GameState, List<XPEvent>> {
    val (game, inserted) = insertMonth(YearMonth.of(on))
    if (!inserted) return game to emptyList()
    return game.award(XPEvent.MONTHLY_DCA, now ?: on) to listOf(XPEvent.MONTHLY_DCA)
}

/** Adds a DCA month without any reward and keeps `longestStreak` up to date; false when it was already there. */
fun GameState.insertMonth(month: YearMonth): Pair<GameState, Boolean> {
    if (month in dcaMonths) return this to false
    val months = dcaMonths + month
    // The run that contains this month (a backfilled month can join two runs).
    var run = 1
    var m = month.previous()
    while (m in months) { run += 1; m = m.previous() }
    m = month.next()
    while (m in months) { run += 1; m = m.next() }
    return copy(dcaMonths = months, longestStreak = maxOf(longestStreak, run)) to true
}

/**
 * One coin per XP point; coins only accumulate for now. The one place experience is added: the points also
 * go into `xpByMonth` under the Taipei month of `at`, the moment they were earned.
 */
fun GameState.award(event: XPEvent, at: Instant = Instant.now()): GameState {
    val gain = GameRules.xp[event] ?: 0
    var byMonth = xpByMonth
    if (gain > 0) {
        val key = YearMonth.of(at).key
        byMonth = byMonth + (key to (byMonth[key] ?: 0) + gain)
    }
    return copy(xp = xp + gain, coins = coins + gain, xpByMonth = byMonth, lastAward = event).count(event.counterKey)
}

/**
 * The level to celebrate with LEVEL×UP, or null: the current level once experience has crossed a whole level
 * above the last one celebrated. Several levels crossed at once are celebrated together, as the highest.
 */
val GameState.levelUpDue: Int? get() {
    val level = GameRules.level(xp)
    return if (level > celebratedLevel) level else null
}

/** Coins earned since the last LEVEL×UP was accepted. */
val GameState.coinsSinceCelebration: Int get() = maxOf(0, coins - celebratedCoins)

/**
 * Records that LEVEL×UP for `level` was accepted (the level never goes back down), with the coins and
 * achievements it showed.
 */
fun GameState.celebrate(level: Int): GameState =
    copy(celebratedLevel = maxOf(celebratedLevel, level), celebratedCoins = coins, celebratedAchievements = unlocked.keys.toSet())
