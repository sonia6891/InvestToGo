package com.sonia.etftogo.core.analytics

import com.sonia.etftogo.core.game.YearMonth
import com.sonia.etftogo.core.sources.DailyBar
import com.sonia.etftogo.core.sources.DividendEvent
import com.sonia.etftogo.core.sources.SplitEvent
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BacktestTests {
    private fun bars(vararg pairs: Pair<String, Double>) = pairs.map { DailyBar(it.first, it.second) }
    private fun input(s: YearMonth, e: YearMonth, reinvest: Boolean = true) = BacktestInput(listOf(BacktestLeg("X", 1.0)), 1000.0, s, e, reinvest)
    private val jan = YearMonth(2024, 1)
    private val feb = YearMonth(2024, 2)
    private val base = bars("2024-01-02" to 10.0, "2024-01-31" to 10.0, "2024-02-01" to 20.0, "2024-02-29" to 20.0)
    private fun history(bars: List<DailyBar>, dividends: List<DividendEvent> = emptyList(), splits: List<SplitEvent> = emptyList(), suspect: Boolean = false) =
        SymbolHistory(bars, dividends, splits, suspect)

    @Test fun twoMonthsNoDividends() {
        val r = Backtest.run(input(jan, feb), mapOf("X" to history(base)))
        assertEquals(2000.0, r.invested, 1e-6)
        assertEquals(3000.0, r.endValue, 1e-6)
        assertEquals(0.0, r.maxDrawdown, 1e-9)
        assertEquals(2, r.curve.size)
    }

    @Test fun dividendReinvestVersusCash() {
        val b = bars("2024-01-02" to 10.0, "2024-01-15" to 10.0, "2024-01-31" to 10.0, "2024-02-01" to 20.0, "2024-02-29" to 20.0)
        val h = history(b, listOf(DividendEvent("X", "2024-01-15", 1.0)))
        val re = Backtest.run(input(jan, feb, reinvest = true), mapOf("X" to h))
        val ca = Backtest.run(input(jan, feb, reinvest = false), mapOf("X" to h))
        assertEquals(3200.0, re.endValue, 1e-6)
        assertEquals(3100.0, ca.endValue, 1e-6)
        assertEquals(100.0, re.dividends, 1e-6)
        assertEquals(100.0, ca.dividends, 1e-6)
    }

    @Test fun splitDoesNotLookLikeACrash() {
        val h = history(bars("2025-06-02" to 100.0, "2025-06-18" to 25.0, "2025-07-01" to 25.0), splits = listOf(SplitEvent("X", "2025-06-18", 4.0)))
        val r = Backtest.run(input(YearMonth(2025, 6), YearMonth(2025, 7)), mapOf("X" to h))
        assertEquals(2000.0, r.endValue, 1e-6)
        assertEquals(0.0, r.maxDrawdown, 1e-9)
    }

    @Test fun lateListingStartsAtFirstBar() {
        val r = Backtest.run(input(jan, YearMonth(2024, 3)), mapOf("X" to history(bars("2024-03-04" to 10.0, "2024-03-29" to 10.0))))
        assertEquals(1000.0, r.invested, 1e-6)
        assertTrue(r.notes.any { "上市" in it })
        assertEquals("X 於 2024-03 上市，之前的月份不投入", r.notes.first())
    }

    @Test fun suspectNote() {
        val r = Backtest.run(input(jan, feb), mapOf("X" to history(base, suspect = true)))
        assertTrue("X 資料可能未還原，結果僅供參考" in r.notes)
    }

    @Test fun xirrTenPercent() {
        val d1 = Instant.parse("2023-01-01T00:00:00Z")
        val d2 = Instant.parse("2024-01-01T00:00:00Z")
        val r = Finance.xirr(listOf(CashFlow(d1, -1000.0), CashFlow(d2, 1100.0)))
        assertNotNull(r)
        assertEquals(0.10, r, 1e-4)
        assertNull(Finance.xirr(listOf(CashFlow(d1, -1000.0), CashFlow(d2, -5.0))))
    }

    @Test fun singleDayRunHasNoXirr() {
        val r = Backtest.run(input(jan, jan), mapOf("X" to history(bars("2024-01-02" to 10.0))))
        assertEquals(1000.0, r.invested, 1e-6)
        assertNull(r.xirr)
    }

    @Test fun runXirrPositiveOnRisingPrices() {
        // A year-long span keeps the annualised rate inside the -99%...1000% bracket.
        val h = history(bars("2024-01-02" to 10.0, "2024-02-01" to 10.0, "2024-12-31" to 11.0))
        val r = Backtest.run(input(jan, YearMonth(2024, 12)), mapOf("X" to h))
        assertNotNull(r.xirr)
        assertTrue((r.xirr ?: -1.0) > 0)
    }

    @Test fun endBeyondDataAddsNoCurvePoints() {
        val r = Backtest.run(input(jan, YearMonth(2024, 6)), mapOf("X" to history(base)))
        assertEquals(2, r.curve.size)
        assertEquals(feb, r.curve.last().month)
        assertEquals(2000.0, r.invested, 1e-6)
    }

    @Test fun legWithoutHistoryIsNoted() {
        val inp = BacktestInput(listOf(BacktestLeg("X", 0.5), BacktestLeg("Y", 0.5)), 1000.0, jan, feb, true)
        val r = Backtest.run(inp, mapOf("X" to history(base)))
        assertTrue("Y 沒有取得歷史資料，這次沒有計入" in r.notes)
        assertEquals(1000.0, r.invested, 1e-6)
    }

    @Test fun dividendBeforeSplitUsesPreSplitShares() {
        // 100 shares bought in Jan; next bar is Mar 1, after a Feb 10 dividend of 1.0 and a Feb 20 2x split.
        val h = history(bars("2024-01-02" to 10.0, "2024-03-01" to 10.0), listOf(DividendEvent("X", "2024-02-10", 1.0)), listOf(SplitEvent("X", "2024-02-20", 2.0)))
        val r = Backtest.run(input(jan, YearMonth(2024, 3), reinvest = false), mapOf("X" to h))
        assertEquals(100.0, r.dividends, 1e-6)
    }

    @Test fun maxDrawdown() {
        assertEquals(0.25, Backtest.maxDrawdown(listOf(100.0, 120.0, 90.0, 130.0)), 1e-9)
    }
}
