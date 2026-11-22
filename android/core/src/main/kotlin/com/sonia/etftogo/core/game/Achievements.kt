package com.sonia.etftogo.core.game

import com.sonia.etftogo.core.models.DividendStatus
import com.sonia.etftogo.core.models.Portfolio
import com.sonia.etftogo.core.models.TradeAction
import com.sonia.etftogo.core.support.Upcoming
import java.time.Instant

// Goals are counts, never money (spec 6.5: no "存到 50 萬"). Source for all: spec 6.5 / 2026-11-11 doc section 8.
/** Consecutive months with a paid dividend. */
const val dividendStreakGoal = 6
/** A holding kept this many days counts as an anniversary. */
const val anniversaryDays = 365L
const val holdingAnniversaryGoal = 1
/** Months with a recorded DCA. */
const val dcaPunchCardGoal = 12
/** Held a year with no sells in that year. */
const val steadyYearGoal = 1
/** Reconciliations completed. */
const val reconcileMasterGoal = 5
/** Fee comparisons made. */
const val feeSaverGoal = 3
/** Checkups finished. */
const val checkupDoneGoal = 1
/** Dex cards collected. */
const val dexCollectorGoal = 10
/** Ex-dividend season 外觀主題 unlocked. */
const val exDividendSkinGoal = 1
/** Year reports opened. */
const val yearReportGoal = 1
/** Number of paid dividend records (a count, not an amount). */
const val dividendMilestoneGoal = 12

/**
 * One wall entry. `comingSoon`: the feature that would count toward it is not in the app yet, so the wall shows
 * 「即將推出」 and it never unlocks (ruling R31). `progress` is the current value toward `goal`, evaluated at `now`.
 */
class Achievement(
    val id: String,
    val title: String,
    val goal: Int,
    val comingSoon: Boolean = false,
    val progress: (GameState, Portfolio, Instant) -> Int,
)

object Achievements {
    /** Longest run of consecutive months that have at least one paid dividend. */
    fun longestDividendRun(p: Portfolio): Int {
        val months = p.dividends.filter { it.status == DividendStatus.PAID }.map { YearMonth.of(it.date) }.toSet()
        var best = 0
        for (m in months) {
            if (m.previous() in months) continue
            var n = 0
            var x = m
            while (x in months) { n += 1; x = x.next() }
            best = maxOf(best, n)
        }
        return best
    }

    private fun cutoff(now: Instant): Instant = now.atZone(GameRules.taipei).minusDays(anniversaryDays).toInstant()

    fun hasAnniversary(p: Portfolio, now: Instant): Boolean {
        val c = cutoff(now)
        return p.holdings.any { h -> h.purchaseDate?.let { it <= c } ?: false }
    }

    fun steady(p: Portfolio, now: Instant): Boolean {
        val c = cutoff(now)
        return hasAnniversary(p, now) && (p.trades ?: emptyList()).none { it.action == TradeAction.SELL && it.date > c }
    }

    val all: List<Achievement> = listOf(
        Achievement("dividendStreak", "連續領息", dividendStreakGoal) { _, p, _ -> longestDividendRun(p) },
        Achievement("holdingAnniversary", "持有週年紀念", holdingAnniversaryGoal) { _, p, now -> if (hasAnniversary(p, now)) 1 else 0 },
        Achievement("dcaPunchCard", "定期定額打卡", dcaPunchCardGoal) { g, _, _ -> g.dcaMonths.size },
        Achievement("steadyYear", "一年不亂動", steadyYearGoal) { _, p, now -> if (steady(p, now)) 1 else 0 },
        Achievement("reconcileMaster", "對帳達人", reconcileMasterGoal) { g, _, _ -> g.counter(CounterKey.RECONCILED) },
        Achievement("feeSaver", "省費達人", feeSaverGoal) { g, _, _ -> g.counter(CounterKey.FEE_COMPARED) },
        Achievement("checkupDone", "體檢完成", checkupDoneGoal, comingSoon = true) { g, _, _ -> g.counter(CounterKey.CHECKUP) },
        Achievement("dexCollector", "ETF 圖鑑", dexCollectorGoal) { g, _, _ -> g.collected.size },
        Achievement("exDividendSkin", "除息季限定外觀主題", exDividendSkinGoal, comingSoon = true) { g, _, _ -> g.counter(CounterKey.EX_DIVIDEND_SEASON) },
        Achievement("yearReport", "口袋年報", yearReportGoal, comingSoon = true) { g, _, _ -> g.counter(CounterKey.YEAR_REPORT) },
        Achievement("dividendMilestone", "累計領息里程碑", dividendMilestoneGoal) { _, p, _ -> p.dividends.count { it.status == DividendStatus.PAID } },
    )

    /**
     * The achievements on the wall and in its count. One whose feature is not in the app yet (`comingSoon`) can
     * never be reached, so it is left off while `Upcoming.visible` is false.
     */
    fun shown(upcoming: Boolean = Upcoming.visible): List<Achievement> = if (upcoming) all else all.filter { !it.comingSoon }
}

/** Achievements unlocked since the last LEVEL×UP was accepted, in catalog order. */
val GameState.achievementsSinceCelebration: List<String>
    get() = Achievements.all.map { it.id }.filter { it in unlocked && it !in celebratedAchievements }

/** Unlocks every achievement whose goal is met and returns the newly unlocked ids (catalog order). */
fun GameState.refreshAchievements(p: Portfolio, now: Instant): Pair<GameState, List<String>> {
    var game = this
    val fresh = mutableListOf<String>()
    for (a in Achievements.all) {
        // Each check sees the unlocks made earlier in this pass, as Swift's mutating loop does.
        if (a.comingSoon || a.id in game.unlocked || a.progress(game, p, now) < a.goal) continue
        game = game.copy(unlocked = game.unlocked + (a.id to now))
        fresh += a.id
    }
    return game to fresh
}
