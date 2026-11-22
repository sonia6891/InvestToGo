package com.sonia.etftogo.core.game

import com.sonia.etftogo.core.models.Fund
import com.sonia.etftogo.core.models.Strategy
import com.sonia.etftogo.core.support.epochSeconds
import java.time.Instant
import kotlin.math.ceil

/** The four collection-book shelves. Raw values are the labels the dex screen shows. */
enum class DexSeries(val rawValue: String) {
    MARKET_CAP("市值型"), HIGH_DIVIDEND("高股息"), BOND("債券"), THEME("主題");

    companion object {
        /**
         * Precedence: bond, then high dividend, then market cap; everything else (including leveraged / inverse /
         * unclassified funds) is a theme.
         */
        fun of(fund: Fund): DexSeries {
            if ((fund.fundType ?: "").contains("債") || fund.name.contains("債")) return BOND
            if (fund.strategy == Strategy.INCOME || listOf("高股息", "高息", "優息").any { fund.name.contains(it) }) return HIGH_DIVIDEND
            if (fund.strategy == Strategy.SAVING) return MARKET_CAP
            return THEME
        }
    }
}

/** Five 1-10 bars, 0 when the fact is missing (the screen shows "—"). Facts only: no total, no recommendation. */
data class DexStats(val fee: Int, val size: Int, val yield: Int, val volatility: Int, val history: Int)

/** The raw facts per fund id. Any of them may be missing for a fund. */
data class DexFacts(
    val feeRate: Map<String, Double> = emptyMap(),
    val aum: Map<String, Double> = emptyMap(),
    val yield: Map<String, Double> = emptyMap(),
    val volatility: Map<String, Double> = emptyMap(),
    val listed: Map<String, Instant> = emptyMap(),
)

object Dex {
    /**
     * `band = ceil(rank / count * 10)` with `rank` = how many values are <= this fund's (a tie shares the HIGHEST
     * rank of its group). Non-finite values are treated as missing: 0 bars and left out of `count`.
     * Fee is reversed (lower fee -> more bars) and history ranks by age (older -> more bars).
     * Size and history rank across `among`; yield and volatility only within the fund's own series.
     */
    fun stats(fund: Fund, among: List<Fund>, facts: DexFacts): DexStats {
        val seen = mutableSetOf<String>()
        val all = (among + fund).filter { seen.add(it.id) }
        val series = DexSeries.of(fund)
        val sameSeries = all.filter { DexSeries.of(it) == series }
        return DexStats(
            fee = band(fund, all) { f -> facts.feeRate[f.id]?.let { -it } },
            size = band(fund, all) { f -> facts.aum[f.id] },
            yield = band(fund, sameSeries) { f -> facts.yield[f.id] },
            volatility = band(fund, sameSeries) { f -> facts.volatility[f.id] },
            history = band(fund, all) { f -> facts.listed[f.id]?.let { -it.epochSeconds() } },
        )
    }

    private fun band(fund: Fund, funds: List<Fund>, value: (Fund) -> Double?): Int {
        val mine = value(fund)?.takeIf { it.isFinite() } ?: return 0
        val values = funds.mapNotNull(value).filter { it.isFinite() }
        val rank = values.count { it <= mine }
        return minOf(10, maxOf(1, ceil(rank.toDouble() / values.size.toDouble() * 10).toInt()))
    }
}

/**
 * Collects the card the first time it is viewed and returns the experience it earned: `[FIRST_DEX_CARD]` for the
 * first `GameRules.dexXPPerMonth` new cards of the Taipei calendar month, `[]` after that (the card is still
 * collected) and for a card already held (ruling R34). Awards itself, so callers must not award again.
 */
fun GameState.collect(symbol: String, now: Instant): Pair<GameState, List<XPEvent>> {
    if (symbol in collected) return this to emptyList()
    val month = YearMonth.of(now)
    val earlier = collected.values.count { YearMonth.of(it) == month }
    val game = copy(collected = collected + (symbol to now))
    if (earlier >= GameRules.dexXPPerMonth) return game to emptyList()
    return game.award(XPEvent.FIRST_DEX_CARD, now) to listOf(XPEvent.FIRST_DEX_CARD)
}

/** Funds of series `s` in `funds` vs how many of them are collected. */
fun GameState.seriesProgress(s: DexSeries, funds: List<Fund>): Pair<Int, Int> {
    val inSeries = funds.filter { DexSeries.of(it) == s }
    return inSeries.count { it.id in collected } to inSeries.size
}
