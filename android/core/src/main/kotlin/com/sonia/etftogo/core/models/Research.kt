package com.sonia.etftogo.core.models

import com.sonia.etftogo.core.support.AppDataError
import com.sonia.etftogo.core.support.CoreJson
import com.sonia.etftogo.core.support.DataChecks
import com.sonia.etftogo.core.support.charCount
import kotlinx.serialization.Serializable
import java.net.URI
import java.time.Year
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.sqrt

@Serializable
data class FundComponent(val symbol: String, val name: String? = null, val weight: Double) {
    val id: String get() = symbol
}

@Serializable
data class ComponentSnapshot(
    val symbol: String,
    val date: String,
    val components: List<FundComponent>,
    val source: String? = null,
) {
    val totalWeight: Double get() = components.fold(0.0) { total, c -> total + c.weight }

    fun validate() {
        val ok = DataChecks.code(symbol) && DataChecks.date(date) != null && date <= DataChecks.day() && components.isNotEmpty() &&
            components.size <= 1000 && components.map { it.symbol }.toSet().size == components.size && totalWeight > 0 && totalWeight <= 101 &&
            components.all { it.symbol.isNotEmpty() && it.symbol.charCount <= 40 && (it.name?.charCount ?: 0) <= 120 && it.weight.isFinite() && it.weight in 0.0..100.0 }
        if (!ok) throw AppDataError("成分資料日期、代碼或權重不正確。")
    }

    companion object {
        fun imported(bytes: ByteArray, symbol: String): ComponentSnapshot {
            if (bytes.size > 1_000_000) throw AppDataError("成分檔不可超過 1 MB。")
            var value = CoreJson.decode(serializer(), bytes)
            if (value.symbol != symbol) throw AppDataError("成分檔與這檔 ETF 的代碼不同。")
            value = value.copy(source = "使用者匯入；原來源：" + (value.source ?: "未提供"))
            value.validate()
            return value
        }
    }
}

data class ExposureRow(val symbol: String, val name: String, val value: Double, val funds: Set<String>) {
    val id: String get() = symbol
}

data class OverlapRow(val symbol: String, val name: String, val left: Double, val right: Double) {
    val id: String get() = symbol
}

object ResearchMath {
    const val direct = "直接持有"

    /**
     * Holdings listed in `stocks` count as directly held and merge into the same row as that stock held through ETFs.
     * `quote` defaults to the portfolio's own saved quotes.
     */
    fun exposures(portfolio: Portfolio, stocks: Set<String> = emptySet(), quote: ((String) -> Quote?)? = null): List<ExposureRow> {
        val price: (String) -> Quote? = quote ?: { portfolio.quotes[it] }
        val result = LinkedHashMap<String, ExposureRow>()
        for (h in portfolio.holdings) {
            val q = price(h.symbol) ?: continue
            if (!q.isTWD) continue
            val snapshot = portfolio.components?.get(h.symbol)
            if (snapshot != null) {
                for (c in snapshot.components) {
                    val row = result[c.symbol] ?: ExposureRow(c.symbol, c.name ?: c.symbol, 0.0, emptySet())
                    result[c.symbol] = row.copy(value = row.value + h.shares * q.price * c.weight / 100, funds = row.funds + h.symbol)
                }
            } else if (h.symbol in stocks) {
                val row = result[h.symbol] ?: ExposureRow(h.symbol, h.name, 0.0, emptySet())
                result[h.symbol] = row.copy(value = row.value + h.shares * q.price, funds = row.funds + direct)
            }
        }
        return result.values.sortedWith { a, b -> if (a.value == b.value) a.symbol.compareTo(b.symbol) else b.value.compareTo(a.value) }
    }

    fun overlap(left: ComponentSnapshot, right: ComponentSnapshot): List<OverlapRow> {
        val other = right.components.associateBy { it.symbol }
        return left.components.mapNotNull { x ->
            val y = other[x.symbol] ?: return@mapNotNull null
            OverlapRow(x.symbol, x.name ?: y.name ?: x.symbol, x.weight, y.weight)
        }.sortedByDescending { minOf(it.left, it.right) }
    }
}

@Serializable
data class PricePoint(val date: String, val close: Double) {
    val id: String get() = date
}

@Serializable
data class PriceHistory(
    val symbol: String,
    val adjusted: Boolean,
    val points: List<PricePoint>,
    val fetchedDay: String,
    val source: String,
) {
    fun validate() {
        val today = DataChecks.day()
        val ok = DataChecks.code(symbol) && adjusted && points.size >= 2 && points.size <= 10000 && DataChecks.date(fetchedDay) != null &&
            points.map { it.date }.toSet().size == points.size &&
            points.all { DataChecks.date(it.date) != null && it.date <= today && it.close.isFinite() && it.close > 0 } &&
            points.zipWithNext().all { (a, b) -> a.date < b.date }
        if (!ok) throw AppDataError("歷史資料缺失、日期重複或沒有確認還原價格，未計算績效。")
    }
}

class PerformanceStats(history: PriceHistory) {
    val change: Double
    val annualized: Double?
    val drawdown: Double
    val volatility: Double?

    init {
        history.validate()
        val p = history.points
        val first = p.first()
        val last = p.last()
        val days = (DataChecks.date(last.date)!!.epochSecond - DataChecks.date(first.date)!!.epochSecond) / 86400.0
        change = last.close / first.close - 1
        annualized = if (days >= 365) (last.close / first.close).pow(365.25 / days) - 1 else null
        var peak = first.close
        var maxDrop = 0.0
        val returns = mutableListOf<Double>()
        p.forEachIndexed { index, point ->
            peak = maxOf(peak, point.close)
            maxDrop = maxOf(maxDrop, 1 - point.close / peak)
            if (index > 0) returns += ln(point.close / p[index - 1].close)
        }
        drawdown = maxDrop
        volatility = if (returns.size >= 20) {
            val average = returns.fold(0.0) { a, b -> a + b } / returns.size
            sqrt(returns.fold(0.0) { a, r -> a + (r - average).pow(2) } / (returns.size - 1) * 252)
        } else null
    }
}

@Serializable
data class FeeRecord(
    val symbol: String,
    val effectiveDate: String,
    val management: String,
    val custody: String,
    val annualExpensePercent: Double? = null,
    val expenseYear: Int? = null,
    val sourceURL: String,
    val note: String,
) {
    fun validate() {
        if (!(DataChecks.code(symbol) && DataChecks.date(effectiveDate) != null && effectiveDate <= DataChecks.day() &&
                management.isNotEmpty() && management.charCount <= 2000 && custody.isNotEmpty() && custody.charCount <= 2000 && note.charCount <= 2000)) {
            throw AppDataError("請填寫費率級距及有效日期。")
        }
        // A reference address is optional (older records have one); when present it must be a plain https link.
        if (sourceURL.isNotEmpty() && !isPlainLink(sourceURL, setOf("https"))) throw AppDataError("參考網址須為 https 開頭。")
        val rate = annualExpensePercent
        if (rate != null) {
            val year = expenseYear
            if (!(rate.isFinite() && rate in 0.0..100.0 && year != null && year in 1990..Year.now().value)) {
                throw AppDataError("總費用率須附統計年度，且數值應為 0～100%。")
            }
        } else if (expenseYear != null) throw AppDataError("費用年度與總費用率須一起填寫。")
    }
}

/** Swift's `URL(string:)` check: one of `schemes`, a host, and no user or password. */
internal fun isPlainLink(text: String, schemes: Set<String>): Boolean {
    val uri = try { URI(text) } catch (_: Exception) { return false }
    return uri.scheme in schemes && !uri.host.isNullOrEmpty() && uri.rawUserInfo == null
}

