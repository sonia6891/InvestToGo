package com.sonia.etftogo.core.game

import com.sonia.etftogo.core.models.Fund
import com.sonia.etftogo.core.models.Strategy
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DexTests {
    private fun fund(id: String, name: String = "測試", s: Strategy = Strategy.SAVING, type: String? = null) = Fund(id = id, name = name, strategy = s, fundType = type)
    private val card = listOf(XPEvent.FIRST_DEX_CARD)

    @Test fun seriesPrecedence() {
        assertEquals(DexSeries.BOND, DexSeries.of(fund("a", "元大美債20年", Strategy.SAVING)))
        assertEquals(DexSeries.BOND, DexSeries.of(fund("b", "某ETF", Strategy.INCOME, type = "債券型")))
        assertEquals(DexSeries.HIGH_DIVIDEND, DexSeries.of(fund("c", "元大高股息", Strategy.SAVING)))
        assertEquals(DexSeries.HIGH_DIVIDEND, DexSeries.of(fund("d", "某ETF", Strategy.INCOME)))
        assertEquals(DexSeries.MARKET_CAP, DexSeries.of(fund("e", "元大台灣50", Strategy.SAVING)))
        assertEquals(DexSeries.THEME, DexSeries.of(fund("f", "台灣50正2", Strategy.RISK)))
        assertEquals(DexSeries.THEME, DexSeries.of(fund("g", "某ETF", Strategy.UNCLASSIFIED)))
    }

    @Test fun rankIntoTenBands() {
        val funds = (1..10).map { fund("f$it") }
        var facts = DexFacts(aum = funds.mapIndexed { i, f -> f.id to (i + 1).toDouble() }.toMap())
        funds.forEachIndexed { i, f -> assertEquals(i + 1, Dex.stats(f, funds, facts).size) }
        assertEquals(10, Dex.stats(funds[0], listOf(funds[0]), facts).size)
        facts = facts.copy(aum = funds.associate { it.id to 5.0 })
        assertEquals(List(10) { 10 }, funds.map { Dex.stats(it, funds, facts).size })
    }

    @Test fun tiedCheapestFeeBothGetTen() {
        val a = fund("a"); val b = fund("b"); val c = fund("c")
        val facts = DexFacts(feeRate = mapOf("a" to 0.1, "b" to 0.1, "c" to 0.5))
        assertEquals(10, Dex.stats(a, listOf(a, b, c), facts).fee)
        assertEquals(10, Dex.stats(b, listOf(a, b, c), facts).fee)
        assertTrue(Dex.stats(c, listOf(a, b, c), facts).fee < 10)
    }

    @Test fun higherVolatilityMoreBars() {
        val a = fund("a"); val b = fund("b")
        val facts = DexFacts(volatility = mapOf("a" to 30.0, "b" to 10.0))
        assertTrue(Dex.stats(a, listOf(a, b), facts).volatility > Dex.stats(b, listOf(a, b), facts).volatility)
    }

    @Test fun missingSizeAndHistoryAreZero() {
        val a = fund("a")
        val s = Dex.stats(a, listOf(a), DexFacts())
        assertEquals(0, s.size); assertEquals(0, s.history); assertEquals(0, s.fee)
    }

    @Test fun nonFiniteIsZeroAndExcluded() {
        val a = fund("a"); val b = fund("b"); val c = fund("c")
        val facts = DexFacts(aum = mapOf("a" to Double.NaN, "b" to 1.0, "c" to 2.0))
        assertEquals(0, Dex.stats(a, listOf(a, b, c), facts).size)
        assertEquals(5, Dex.stats(b, listOf(a, b, c), facts).size)
        assertEquals(10, Dex.stats(c, listOf(a, b, c), facts).size)
    }

    @Test fun duplicateIdsInAmongDoNotSkew() {
        val a = fund("a"); val b = fund("b")
        val facts = DexFacts(aum = mapOf("a" to 1.0, "b" to 2.0))
        assertEquals(Dex.stats(a, listOf(a, b), facts), Dex.stats(a, listOf(a, a, a, b), facts))
        assertEquals(5, Dex.stats(a, listOf(a, b), facts).size)
    }

    @Test fun eachNewCardEarnsXP() {
        var g = GameState()
        val now = Instant.now()
        g.collect("0050", now).let { (next, e) -> assertEquals(card, e); g = next }
        g.collect("0056", now).let { (next, e) -> assertEquals(card, e); g = next }
        assertEquals(60, g.xp)
    }

    @Test fun lowerFeeMoreBars() {
        val a = fund("a"); val b = fund("b")
        val facts = DexFacts(feeRate = mapOf("a" to 0.1, "b" to 0.5))
        assertTrue(Dex.stats(a, listOf(a, b), facts).fee > Dex.stats(b, listOf(a, b), facts).fee)
    }

    @Test fun olderListingMoreBars() {
        val a = fund("a"); val b = fund("b")
        val facts = DexFacts(listed = mapOf("a" to Instant.ofEpochSecond(1_000), "b" to Instant.ofEpochSecond(2_000)))
        assertTrue(Dex.stats(a, listOf(a, b), facts).history > Dex.stats(b, listOf(a, b), facts).history)
    }

    @Test fun yieldRanksWithinSeriesOnly() {
        val bond = fund("b1", "美債", Strategy.SAVING); val eq1 = fund("e1"); val eq2 = fund("e2")
        val facts = DexFacts(yield = mapOf("b1" to 9.0, "e1" to 1.0, "e2" to 2.0))
        val all = listOf(bond, eq1, eq2)
        assertEquals(10, Dex.stats(bond, all, facts).yield)
        assertEquals(5, Dex.stats(eq1, all, facts).yield)
        assertEquals(10, Dex.stats(eq2, all, facts).yield)
    }

    @Test fun missingFactIsZero() {
        val a = fund("a")
        val s = Dex.stats(a, listOf(a), DexFacts(feeRate = mapOf("a" to 0.3)))
        assertEquals(0, s.yield)
        assertEquals(0, s.volatility)
        assertEquals(10, s.fee)
    }

    @Test fun collectOnce() {
        val now = Instant.ofEpochSecond(1_700_000_000)
        var g = GameState()
        g.collect("0050", now).let { (next, e) -> assertEquals(card, e); g = next }
        assertEquals(30, g.xp)
        g.collect("0050", now.plusSeconds(60)).let { (next, e) -> assertEquals(emptyList(), e); g = next }
        assertEquals(30, g.xp)
        assertEquals(now, g.collected["0050"])
    }

    @Test fun seriesProgress() {
        val funds = listOf(fund("0050", "元大台灣50"), fund("006208", "富邦台50"), fund("0056", "元大高股息", Strategy.INCOME))
        val g = GameState().collect("0050", Instant.now()).first
        assertEquals(1 to 2, g.seriesProgress(DexSeries.MARKET_CAP, funds))
        assertEquals(0, g.seriesProgress(DexSeries.HIGH_DIVIDEND, funds).first)
    }
}
