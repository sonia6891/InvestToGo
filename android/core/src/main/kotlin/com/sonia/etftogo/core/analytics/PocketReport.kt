package com.sonia.etftogo.core.analytics

import com.sonia.etftogo.core.game.GameRules
import com.sonia.etftogo.core.game.GameState
import com.sonia.etftogo.core.game.YearMonth
import com.sonia.etftogo.core.game.reconciledKey
import com.sonia.etftogo.core.models.DividendStatus
import com.sonia.etftogo.core.models.Portfolio
import java.time.Instant

/** The stretch of time one 口袋月報／年報 covers (spec 5.5), in Taipei months like the rest of the game layer. */
sealed interface ReportPeriod {
    /** One calendar month. */
    data class Month(val month: YearMonth) : ReportPeriod
    /** One calendar year, January to December. */
    data class Year(val year: Int) : ReportPeriod
    /** 今年到目前: the year from January up to `now`. */
    data class YearToDate(val year: Int) : ReportPeriod

    /** Whether a Taipei month is part of the period. 今年到目前 stops at the month `now` is in. */
    fun contains(month: YearMonth, now: Instant): Boolean = when (this) {
        is Month -> month == this.month
        is Year -> month.year == year
        is YearToDate -> month.year == year && month <= YearMonth.of(now)
    }

    /** Whether a moment is part of the period. 今年到目前 leaves out anything dated after `now`. */
    fun contains(date: Instant, now: Instant): Boolean {
        if (this is YearToDate && date > now) return false
        return contains(YearMonth.of(date), now)
    }

    /** 「2026 年 10 月」, 「2026 年」 or 「2026 年 1 月 1 日至 11 月 14 日」. */
    fun title(now: Instant): String = when (this) {
        is Month -> "${month.year} 年 ${month.month} 月"
        is Year -> "$year 年"
        is YearToDate -> {
            val today = now.atZone(GameRules.taipei)
            // A year that is over (or has not begun) has no "so far": it is named as the year.
            if (today.year != year) "$year 年" else "$year 年 1 月 1 日至 ${today.monthValue} 月 ${today.dayOfMonth} 日"
        }
    }
}

/**
 * What one report card says. Only what the person did and received: never what the holdings are worth, what they
 * cost or what they gained, so the card can be shared (spec 5.5). `xpEarned` is null when no month of the period was
 * recorded (before `GameState.xpByMonth` existed), and the card then leaves the line out.
 */
data class ReportCard(
    val title: String,
    val dividends: Double,
    val dcaMonths: Int,
    val reconciles: Int,
    val newDexCards: Int,
    val level: Int,
    val xpEarned: Int?,
    val notes: List<String>,
)

object PocketReport {
    /**
     * The card for `period`, from the records and the game progress as they are at `now`. With `showDividends` off
     * (顯示領息金額 switched off) the note that counts the payments is left out too.
     */
    fun make(period: ReportPeriod, portfolio: Portfolio, now: Instant, showDividends: Boolean = true): ReportCard {
        val game = portfolio.game ?: GameState()
        val paid = portfolio.dividends.filter { it.status == DividendStatus.PAID && period.contains(it.date, now) }
        val dividends = paid.fold(0.0) { total, d -> total + d.amount }
        val dcaMonths = game.dcaMonths.count { period.contains(it, now) }
        val reconciles = reconciledMonths(game).count { period.contains(it, now) }
        val newDexCards = game.collected.values.count { period.contains(it, now) }
        val logged = xpMonths(game).filter { period.contains(it.first, now) }
        val xpEarned: Int? = if (logged.isEmpty()) null else logged.fold(0) { total, entry -> total + entry.second }

        val notes = mutableListOf<String>()
        if (showDividends && paid.isNotEmpty()) notes += "領息 ${paid.size} 筆，來自 ${paid.map { it.symbol }.toSet().size} 檔。"
        if (paid.isEmpty() && dcaMonths == 0 && reconciles == 0 && newDexCards == 0 && (xpEarned ?: 0) == 0) {
            notes += "這段時間還沒有紀錄。記一筆配息或定期定額，下一張就有內容。"
        }
        return ReportCard(period.title(now), dividends, dcaMonths, reconciles, newDexCards, GameRules.level(game.xp), xpEarned, notes)
    }

    /** The months whose 對帳 was rewarded: the 「reconciled|yyyy-MM」 reward keys. */
    private fun reconciledMonths(game: GameState): List<YearMonth> =
        game.rewardKeys.mapNotNull { key -> if (key.startsWith(reconciledKey)) YearMonth.fromKey(key.removePrefix(reconciledKey)) else null }

    /** `GameState.xpByMonth` with its keys read back as months; a key that is not a month is left out. */
    private fun xpMonths(game: GameState): List<Pair<YearMonth, Int>> =
        game.xpByMonth.mapNotNull { (key, xp) -> YearMonth.fromKey(key)?.let { it to xp } }

    /** The first month anything a report counts happened in, never after `now`'s month; null when nothing has. */
    fun earliestMonth(portfolio: Portfolio, now: Instant): YearMonth? {
        val game = portfolio.game ?: GameState()
        val months = portfolio.dividends.filter { it.status == DividendStatus.PAID }.map { YearMonth.of(it.date) } +
            game.dcaMonths + reconciledMonths(game) + game.collected.values.map { YearMonth.of(it) } + xpMonths(game).map { it.first }
        val current = YearMonth.of(now)
        return months.filter { it <= current }.minOrNull()
    }

    /**
     * Whether the lobby says 「上個月的口袋月報出爐了」 now: to a member, once for each month that has ended, and only
     * when the records reach back to that month. `seen` is the month (「2026-10」) last announced, empty when none was.
     */
    fun noticeDue(now: Instant, seen: String, isMember: Boolean, portfolio: Portfolio): Boolean {
        val month = noticeMonth(now)
        if (!isMember || seen == month.key) return false
        val earliest = earliestMonth(portfolio, now) ?: return false
        return earliest <= month
    }

    /** The month the lobby's notice is about: the one before `now`'s. */
    fun noticeMonth(now: Instant): YearMonth = YearMonth.of(now).previous()
}
