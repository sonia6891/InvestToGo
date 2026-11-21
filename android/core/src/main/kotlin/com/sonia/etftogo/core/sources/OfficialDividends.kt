@file:OptIn(ExperimentalSerializationApi::class)

package com.sonia.etftogo.core.sources

import com.sonia.etftogo.core.support.AppDataError
import com.sonia.etftogo.core.support.CoreJson
import com.sonia.etftogo.core.support.CoreResources
import com.sonia.etftogo.core.support.DataChecks
import com.sonia.etftogo.core.support.SwiftDate
import com.sonia.etftogo.core.support.charCount
import com.sonia.etftogo.core.support.swiftDouble
import com.sonia.etftogo.core.support.swiftInt
import com.sonia.etftogo.core.support.swiftTrim
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.Required
import kotlinx.serialization.Serializable
import java.net.URI
import java.time.Instant
import java.time.ZoneId

/** One official ETF distribution: ex-dividend date, payment date ("" when not announced) and amount per unit (null until set). */
@Serializable
data class OfficialDistribution(val ex: String, val pay: String, val amount: Double? = null)

/**
 * Official distributions from the ex-rights and ex-dividend notices in the exchanges' open data, TWSE 上市股票除權除息
 * 預告表 and TPEx 上櫃股票除權除息預告表: upcoming ex-dividend days and cash amounts, without the payment day. Each
 * refresh adds to what is known, so the record builds up from the day in sources["since"]; figures over the past year
 * (frequency, trailing amount) wait until the record covers it. Bundled as official-dividends.json.
 */
@Serializable
data class OfficialDividends(
    @Required val sources: Map<String, String> = emptyMap(),
    @Required val events: Map<String, List<OfficialDistribution>> = emptyMap(),
    @Required val freq: Map<String, String> = emptyMap(),
    /** When the last refresh succeeded on the device (spec 9); null for the bundled record and older saves. */
    val fetchedAt: SwiftDate? = null,
) {
    fun isNewer(than: OfficialDividends): Boolean {
        val twse = sources["twse"] ?: ""
        val otherTwse = than.sources["twse"] ?: ""
        return twse > otherTwse || (twse == otherTwse && (sources["tpex"] ?: "") > (than.sources["tpex"] ?: ""))
    }

    fun list(symbol: String): List<OfficialDistribution> = events[symbol] ?: emptyList()
    fun frequency(symbol: String): String? = freq[symbol]

    /** The day the record starts; null for a record kept from before, which held data read from the TWSE website. */
    val since: String? get() = sources["since"]

    /** Whether the record covers the past year (as of [now]), so counts and sums over it are whole. */
    fun coversYear(now: Instant = Instant.now()): Boolean = (since ?: "9999") <= DataChecks.day(yearBefore(now))

    /** Sum of announced amounts per unit with an ex-dividend date in the past year; null until the record covers it. */
    fun trailingAmount(symbol: String, now: Instant = Instant.now()): Double? {
        if (!coversYear(now)) return null
        val from = DataChecks.day(yearBefore(now))
        val today = DataChecks.day(now)
        val items = list(symbol).filter { it.ex > from && it.ex <= today && (it.amount ?: 0.0) > 0 }
        return if (items.isEmpty()) null else items.fold(0.0) { total, item -> total + (item.amount ?: 0.0) }
    }

    /**
     * Adds announcements to the known ones: a known ex-dividend day keeps its payment day, and its amount until the
     * notice sets one. With `frequency`, once the record covers the past year, every ETF's label is worked out again
     * from the whole record (an ETF with no new announcement still gets one, and a changed rhythm is relabelled).
     */
    fun merging(fresh: Map<String, List<OfficialDistribution>>, frequency: Boolean, now: Instant = Instant.now()): OfficialDividends {
        val nextEvents = LinkedHashMap(events)
        for ((symbol, items) in fresh) {
            val byDay = LinkedHashMap<String, OfficialDistribution>()
            for (item in list(symbol)) byDay.putIfAbsent(item.ex, item)
            for (item in items) byDay[item.ex] = OfficialDistribution(item.ex, byDay[item.ex]?.pay ?: "", item.amount ?: byDay[item.ex]?.amount)
            nextEvents[symbol] = byDay.values.sortedByDescending { it.ex }
        }
        var nextFreq: Map<String, String> = freq
        if (frequency && coversYear(now)) {
            val labels = LinkedHashMap(freq)
            for ((symbol, items) in nextEvents) {
                val label = frequency(items, now)
                if (label == null) labels.remove(symbol) else labels[symbol] = label
            }
            nextFreq = labels
        }
        return copy(events = nextEvents, freq = nextFreq)
    }

    companion object {
        /** Calendar.current: a year back in the device's zone, as iPhone counts it. */
        private fun yearBefore(now: Instant): Instant = now.atZone(ZoneId.systemDefault()).minusYears(1).toInstant()

        fun bundled(): OfficialDividends =
            try { CoreJson.decode(serializer(), CoreResources.read("official-dividends.json")) } catch (_: Exception) { OfficialDividends() }

        /** Distribution frequency from the number of ex-dividend dates in the past year. */
        fun frequency(list: List<OfficialDistribution>, now: Instant = Instant.now()): String? {
            val from = DataChecks.day(yearBefore(now))
            val today = DataChecks.day(now)
            return when (list.count { it.ex > from && it.ex <= today }) {
                in 9..Int.MAX_VALUE -> "月配"
                in 5..8 -> "雙月配"
                in 3..4 -> "季配"
                2 -> "半年配"
                1 -> "年配"
                else -> null
            }
        }

        /** "115年10月22日" or "1151016" → "2026-10-22". */
        fun rocDay(text: String): String? {
            val value = text.swiftTrim()
            val parts: List<Int> = if (value.contains("年")) {
                value.replace("年", "-").replace("月", "-").replace("日", "").split("-").filter { it.isNotEmpty() }.mapNotNull(::swiftInt)
            } else if (value.charCount == 7 && value.all { it in '0'..'9' }) {
                listOfNotNull(swiftInt(value.take(3)), swiftInt(value.substring(3, 5)), swiftInt(value.takeLast(2)))
            } else {
                return null
            }
            if (parts.size != 3 || parts[1] !in 1..12 || parts[2] !in 1..31) return null
            return "%04d-%02d-%02d".format(parts[0] + 1911, parts[1], parts[2])
        }

        val twseURL = URI("https://openapi.twse.com.tw/v1/exchangeReport/TWT48U_ALL")
        val tpexURL = URI("https://www.tpex.org.tw/openapi/v1/tpex_exright_prepost")

        /**
         * The notice's ETFs among `markets` with a cash dividend (息, 權息): ex-dividend day and amount per unit, null until
         * set. TWSE names the fields Code, Date and Exdividend; TPEx SecuritiesCompanyCode, ExRrightsExDividendDate and
         * ExRrightsExDividend. Both write dates in ROC years ("1151022").
         */
        fun decode(bytes: ByteArray, market: String, markets: Map<String, String>): Map<String, List<OfficialDistribution>> {
            val tpex = market == "TPEx"
            val (codeKey, dayKey, kindKey) = if (tpex) Triple("SecuritiesCompanyCode", "ExRrightsExDividendDate", "ExRrightsExDividend") else Triple("Code", "Date", "Exdividend")
            val rows = DataChecks.jsonRows(bytes)
            if (rows == null || !(rows.firstOrNull()?.let { codeKey in it && dayKey in it } ?: true)) {
                throw AppDataError(if (tpex) "上櫃配息資料格式不符。" else "上市配息資料格式不符。")
            }
            val events = linkedMapOf<String, MutableList<OfficialDistribution>>()
            for (row in rows) {
                val symbol = row[codeKey].string?.swiftTrim() ?: continue
                if (!(if (tpex) markets[symbol] == "TPEx" else markets[symbol] != null)) continue
                if (!(row[kindKey].string ?: "").contains("息")) continue
                val ex = rocDay(row[dayKey].string ?: "") ?: continue
                val amount = swiftDouble((row["CashDividend"].string ?: "").replace(",", ""))?.takeIf { it > 0 }
                events.getOrPut(symbol) { mutableListOf() } += OfficialDistribution(ex, "", amount)
            }
            return events
        }
    }
}
