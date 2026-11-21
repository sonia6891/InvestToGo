package com.sonia.etftogo.core.analytics

import com.sonia.etftogo.core.game.YearMonth
import com.sonia.etftogo.core.sources.DailyBar
import com.sonia.etftogo.core.sources.DividendEvent
import com.sonia.etftogo.core.sources.SplitEvent
import com.sonia.etftogo.core.support.epochSeconds
import com.sonia.etftogo.core.support.swiftInt
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.math.pow

data class SymbolHistory(
    val bars: List<DailyBar>,
    val dividends: List<DividendEvent>,
    val splits: List<SplitEvent>,
    /** The close series looks unadjusted (a jump the splits do not explain); results get a caveat note. */
    val suspect: Boolean,
    /** The bars are 富果's adjusted closes (dividends already in the price), not the exchanges' own. */
    val fromFugle: Boolean = false,
)

data class BacktestLeg(val symbol: String, val weight: Double)

data class BacktestInput(
    /** Weights sum to 1. */
    val legs: List<BacktestLeg>,
    val monthly: Double,
    val start: YearMonth,
    val end: YearMonth,
    val reinvest: Boolean,
)

data class CurvePoint(val month: YearMonth, val invested: Double, val value: Double)

data class BacktestResult(
    val invested: Double,
    val endValue: Double,
    val dividends: Double,
    val xirr: Double?,
    /** 0…1, peak-to-trough on the monthly value series. */
    val maxDrawdown: Double,
    val curve: List<CurvePoint>,
    val notes: List<String>,
)

data class CashFlow(val date: Instant, val amount: Double)

object Finance {
    /** Annualised internal rate of return, 365-day convention; bisection on -0.99…10; null without a sign change. */
    fun xirr(flows: List<CashFlow>): Double? {
        val t0 = flows.minOfOrNull { it.date } ?: return null
        val t1 = flows.maxOf { it.date }
        if (t1.epochSeconds() - t0.epochSeconds() < 86_400 || flows.none { it.amount > 0 } || flows.none { it.amount < 0 }) return null
        fun f(r: Double): Double = flows.fold(0.0) { sum, flow ->
            val years = (flow.date.epochSeconds() - t0.epochSeconds()) / 86_400 / 365
            sum + flow.amount / (1 + r).pow(years)
        }
        var lo = -0.99
        var hi = 10.0
        var fLo = f(lo)
        val fHi = f(hi)
        if (!fLo.isFinite() || !fHi.isFinite() || fLo * fHi > 0) return null
        if (fLo == 0.0) return lo
        if (fHi == 0.0) return hi
        repeat(200) {
            val mid = (lo + hi) / 2
            val fMid = f(mid)
            if (fMid == 0.0) return mid
            if ((fMid < 0) == (fLo < 0)) { lo = mid; fLo = fMid } else hi = mid
            if (hi - lo < 1e-10) return (lo + hi) / 2
        }
        return (lo + hi) / 2
    }
}

object Backtest {
    /** Largest peak-to-trough fall as a fraction of the peak. */
    fun maxDrawdown(values: List<Double>): Double {
        var peak = Double.NEGATIVE_INFINITY
        var worst = 0.0
        for (v in values) {
            peak = maxOf(peak, v)
            if (peak > 0) worst = maxOf(worst, (peak - v) / peak)
        }
        return worst
    }

    /** Swift `date.split(separator: "-")`: empty pieces are dropped. */
    private fun parts(date: String): List<Int?> = date.split("-").filter { it.isNotEmpty() }.map(::swiftInt)

    private fun month(date: String): YearMonth? {
        val p = parts(date)
        if (p.size != 3) return null
        val y = p[0] ?: return null
        val m = p[1] ?: return null
        return YearMonth(y, m)
    }

    /** Midnight UTC of the day; out-of-range months and days roll over as Foundation's Calendar does. */
    private fun parse(date: String): Instant? {
        val p = parts(date)
        if (p.size != 3) return null
        val y = p[0] ?: return null
        val m = p[1] ?: return null
        val d = p[2] ?: return null
        return LocalDate.of(y, 1, 1).plusMonths((m - 1).toLong()).plusDays((d - 1).toLong()).atStartOfDay(ZoneOffset.UTC).toInstant()
    }

    /** One leg's state at a month end. */
    private data class MonthEnd(val holding: Double, val cash: Double)

    fun run(input: BacktestInput, history: Map<String, SymbolHistory>): BacktestResult {
        val notes = mutableListOf<String>()
        val flows = mutableListOf<CashFlow>()
        var totalDividends = 0.0
        var lastBarDate: String? = null
        val holdings = mutableMapOf<YearMonth, Double>()
        val cash = mutableMapOf<YearMonth, Double>()
        val contributed = mutableMapOf<YearMonth, Double>()
        val active = mutableSetOf<YearMonth>()

        val months = mutableListOf<YearMonth>()
        var cursor = input.start
        while (cursor <= input.end) { months += cursor; cursor = cursor.next() }

        for (leg in input.legs) {
            val h = history[leg.symbol]
            if (h == null) {
                notes += "${leg.symbol} 沒有取得歷史資料，這次沒有計入"
                continue
            }
            val bars = h.bars.sortedBy { it.date }
            val splits = h.splits.sortedBy { it.resumeDate }
            val dividends = h.dividends.sortedBy { it.exDate }
            var si = 0
            var di = 0
            var shares = 0.0
            var legCash = 0.0
            val boughtMonths = mutableSetOf<YearMonth>()
            var firstMonth: YearMonth? = null
            val endState = mutableMapOf<YearMonth, MonthEnd>()

            for (bar in bars) {
                val bm = month(bar.date) ?: continue
                if (bm < input.start || bm > input.end) continue
                if (firstMonth == null) firstMonth = bm
                // (1) splits and (2) dividends due by this bar, in date order (split first on a tie); a dividend is
                // paid on the shares held at its date and reinvested at this close (next bar if its ex-date has none)
                while (true) {
                    val sd = if (si < splits.size && splits[si].resumeDate <= bar.date) splits[si].resumeDate else null
                    val dd = if (di < dividends.size && dividends[di].exDate <= bar.date) dividends[di].exDate else null
                    if (sd != null && (dd == null || sd <= dd)) {
                        shares *= splits[si].ratio; si += 1
                    } else if (dd != null) {
                        val amount = shares * dividends[di].cash
                        totalDividends += amount
                        if (input.reinvest && bar.close > 0) shares += amount / bar.close else legCash += amount
                        di += 1
                    } else break
                }
                // (3) monthly buy on the leg's first bar of the month
                if (bm !in boughtMonths && bar.close > 0) {
                    boughtMonths += bm
                    val amount = input.monthly * leg.weight
                    shares += amount / bar.close
                    contributed[bm] = (contributed[bm] ?: 0.0) + amount
                    parse(bar.date)?.let { flows += CashFlow(it, -amount) }
                }
                if (lastBarDate == null || bar.date > lastBarDate) lastBarDate = bar.date
                endState[bm] = MonthEnd(shares * bar.close, legCash)
            }
            // A month with no bar after listing keeps the leg's last known state; before listing it adds nothing.
            var carried: MonthEnd? = null
            for (mm in months) {
                endState[mm]?.let { carried = it }
                val s = carried ?: continue
                holdings[mm] = (holdings[mm] ?: 0.0) + s.holding
                cash[mm] = (cash[mm] ?: 0.0) + s.cash
                active += mm
            }
            val fm = firstMonth
            if (fm == null) notes += "${leg.symbol} 沒有取得歷史資料，這次沒有計入"
            if (fm != null && fm > input.start) notes += "${leg.symbol} 於 ${fm.key} 上市，之前的月份不投入"
            if (h.suspect) notes += "${leg.symbol} 資料可能未還原，結果僅供參考"
        }

        val curve = mutableListOf<CurvePoint>()
        var running = 0.0
        // No points past the month of the latest bar: months beyond the data are not fabricated.
        val lastMonth = lastBarDate?.let(::month) ?: input.end
        for (mm in months) {
            running += contributed[mm] ?: 0.0
            if (mm !in active || mm > lastMonth) continue
            curve += CurvePoint(mm, running, (holdings[mm] ?: 0.0) + (cash[mm] ?: 0.0))
        }
        val endValue = curve.lastOrNull()?.value ?: 0.0
        var xirr: Double? = null
        val last = lastBarDate
        if (running > 0 && last != null) {
            parse(last)?.let { xirr = Finance.xirr(flows + CashFlow(it, endValue)) }
        }
        return BacktestResult(running, endValue, totalDividends, xirr, maxDrawdown(curve.map { it.value }), curve, notes)
    }
}
