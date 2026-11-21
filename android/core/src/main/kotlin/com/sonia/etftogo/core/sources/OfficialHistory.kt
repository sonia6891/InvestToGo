package com.sonia.etftogo.core.sources

import com.sonia.etftogo.core.game.YearMonth
import com.sonia.etftogo.core.support.AppDataError
import com.sonia.etftogo.core.support.TAIPEI
import com.sonia.etftogo.core.support.swiftDouble
import com.sonia.etftogo.core.support.swiftInt
import com.sonia.etftogo.core.support.swiftRounded
import com.sonia.etftogo.core.support.swiftStripAll
import com.sonia.etftogo.core.support.swiftTrim
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.net.URI
import java.time.Instant

@Serializable
data class DailyBar(val date: String, val close: Double)

@Serializable
data class DividendEvent(val symbol: String, val exDate: String, val cash: Double)

@Serializable
data class SplitEvent(
    val symbol: String,
    val resumeDate: String,
    /** Shares after ÷ before (4 for 0050, 1/7 for 00632R). */
    val ratio: Double,
)

/** Parsers and URL builders for the TWSE / TPEx official history endpoints. */
object OfficialHistory {
    // Dates and numbers

    /** "114/06/18" or "114年01月17日" -> "2025-06-18"; null when it isn't a ROC date. */
    fun rocDate(s: String): String? {
        val parts = s.swiftTrim().split('/', '年', '月', '日').filter { it.isNotEmpty() }
        if (parts.size != 3) return null
        val y = swiftInt(parts[0]) ?: return null
        val m = swiftInt(parts[1]) ?: return null
        val d = swiftInt(parts[2]) ?: return null
        if (m !in 1..12 || d !in 1..31 || y <= 0) return null
        return "%04d-%02d-%02d".format(y + 1911, m, d)
    }

    private fun number(s: String): Double? = swiftDouble(s.replace(",", "").swiftTrim())

    private fun obj(data: ByteArray): JsonObject = parseObject(data) ?: throw AppDataError("官方資料格式不符（不是 JSON 物件）")

    /** Cells as text; a number keeps the text it was written with and a null reads "<null>", as Swift's "\(value)" gives. */
    private fun cell(value: JsonElement): String = when (value) {
        is JsonNull -> "<null>"
        is JsonPrimitive -> value.content
        else -> value.toString()
    }

    /** Field name -> column index; all whitespace is removed from names ("日 期" -> "日期"). */
    private fun fieldIndexes(any: JsonElement?): Map<String, Int> {
        val names = (any as? JsonArray)?.map { it.string ?: return emptyMap() } ?: return emptyMap()
        val map = linkedMapOf<String, Int>()
        names.forEachIndexed { i, f -> map.putIfAbsent(f.swiftStripAll(), i) }
        return map
    }

    /** TWSE bodies: `stat` must be OK; the 「沒有符合條件」 message means a genuinely empty result (null). */
    private fun twseTable(data: ByteArray, what: String): JsonObject? {
        val o = obj(data)
        val stat = o["stat"].string ?: ""
        if (stat.contains("沒有符合條件")) return null
        if (stat.lowercase() != "ok") throw AppDataError("${what}回應異常：${stat.ifEmpty { "缺少 stat" }}")
        return o
    }

    private fun tpexTable(data: ByteArray, what: String): JsonObject {
        val o = obj(data)
        return (o["tables"] as? JsonArray)?.let { tables -> tables.map { it as? JsonObject ?: return@let null } }?.firstOrNull()
            ?: throw AppDataError("${what}資料格式不符（缺少 tables）")
    }

    /** Shared row parsing: `data` must be an array; non-empty data needs every required field and at least one parsable row. */
    private fun <T> parseTable(table: JsonObject, what: String, required: List<String>, row: (Map<String, Int>, List<String>) -> T?): List<T> {
        val raw = (table["data"] as? JsonArray)?.let { data -> data.map { it as? JsonArray ?: return@let null } }
            ?: throw AppDataError("${what}資料格式不符（缺少 data）")
        if (raw.isEmpty()) return emptyList()
        val idx = fieldIndexes(table["fields"])
        required.firstOrNull { it !in idx }?.let { throw AppDataError("${what}資料欄位不符（缺少「$it」）") }
        val out = raw.map { r -> r.map(::cell) }.mapNotNull { row(idx, it) }
        if (out.isEmpty()) throw AppDataError("${what}資料無法解析（${raw.size} 列皆無效）")
        return out
    }

    private fun barRow(dateKey: String, closeKey: String): (Map<String, Int>, List<String>) -> DailyBar? = { idx, r ->
        val di = idx[dateKey]
        val ci = idx[closeKey]
        if (di == null || ci == null || r.size <= maxOf(di, ci)) null else {
            val date = rocDate(r[di])
            val close = number(r[ci])
            if (date != null && close != null && close > 0) DailyBar(date, close) else null
        }
    }

    // Prices

    fun twseMonth(data: ByteArray): List<DailyBar> {
        val o = twseTable(data, "證交所日成交") ?: return emptyList()
        return parseTable(o, "證交所日成交", listOf("日期", "收盤價"), barRow("日期", "收盤價"))
    }

    fun tpexMonth(data: ByteArray): List<DailyBar> {
        val table = tpexTable(data, "櫃買日成交")
        return parseTable(table, "櫃買日成交", listOf("日期", "收盤"), barRow("日期", "收盤"))
    }

    // Dividends

    fun twseDividends(data: ByteArray): List<DividendEvent> {
        val o = twseTable(data, "證交所除權息") ?: return emptyList()
        val req = listOf("資料日期", "股票代號", "權值+息值", "權/息")
        // 權 rows parse fine but are not cash dividends; they give an empty list so they don't count as unparsable.
        val all: List<List<DividendEvent>> = parseTable(o, "證交所除權息", req) { idx, r ->
            val di = idx.getValue("資料日期")
            val si = idx.getValue("股票代號")
            val ci = idx.getValue("權值+息值")
            val ki = idx.getValue("權/息")
            if (r.size <= maxOf(di, si, ci, ki)) return@parseTable null
            val date = rocDate(r[di]) ?: return@parseTable null
            val cash = number(r[ci]) ?: return@parseTable null
            if (r[ki].swiftTrim() != "息") emptyList() else listOf(DividendEvent(r[si].swiftTrim(), date, cash))
        }
        return all.flatten()
    }

    fun tpexDividends(data: ByteArray): List<DividendEvent> {
        val table = tpexTable(data, "櫃買除權息")
        val count = (table["fields"] as? JsonArray)?.size ?: 0
        return parseTable(table, "櫃買除權息", listOf("除權息日期", "代號", "現金股利")) { idx, r ->
            val di = idx.getValue("除權息日期")
            val si = idx.getValue("代號")
            val ci = idx.getValue("現金股利")
            if (r.size != count) return@parseTable null
            val date = rocDate(r[di]) ?: return@parseTable null
            val cash = number(r[ci]) ?: return@parseTable null
            DividendEvent(r[si].swiftTrim(), date, cash)
        }
    }

    // Splits

    fun splits(data: ByteArray): List<SplitEvent> {
        val o = twseTable(data, "ETF 分割") ?: return emptyList()
        val req = listOf("恢復買賣日期", "ETF代號", "停止買賣前收盤價格", "恢復買賣參考價")
        return parseTable(o, "ETF 分割", req) { idx, r ->
            val di = idx.getValue("恢復買賣日期")
            val si = idx.getValue("ETF代號")
            val bi = idx.getValue("停止買賣前收盤價格")
            val ai = idx.getValue("恢復買賣參考價")
            if (r.size <= maxOf(di, si, bi, ai)) return@parseTable null
            val date = rocDate(r[di]) ?: return@parseTable null
            val before = number(r[bi]) ?: return@parseTable null
            val after = number(r[ai]) ?: return@parseTable null
            if (!(before > 0 && after > 0)) return@parseTable null
            val x = before / after
            val ratio = if (x >= 1) swiftRounded(x) else 1 / swiftRounded(1 / x)
            SplitEvent(r[si].swiftTrim(), date, ratio)
        }
    }

    /** Dates where the close jumps by more than ×2.5 or below ×0.4 with no dividend and no known split that day. */
    fun suspectedSplits(bars: List<DailyBar>, dividends: List<DividendEvent>, known: List<SplitEvent>): List<String> {
        val explained = dividends.map { it.exDate }.toSet() + known.map { it.resumeDate }
        val out = mutableListOf<String>()
        for (i in 1 until bars.size) {
            val prev = bars[i - 1].close
            if (!(prev > 0)) continue
            val r = bars[i].close / prev
            if ((r > 2.5 || r < 0.4) && bars[i].date !in explained) out += bars[i].date
        }
        return out
    }

    // URLs: only the code and the dates go out.

    private fun ymd(date: Instant, separator: String): String {
        val c = date.atZone(TAIPEI)
        return listOf("%04d".format(c.year), "%02d".format(c.monthValue), "%02d".format(c.dayOfMonth)).joinToString(separator)
    }

    fun twseMonthURL(symbol: String, month: YearMonth): URI =
        URI("https://www.twse.com.tw/rwd/zh/afterTrading/STOCK_DAY?date=${"%04d%02d".format(month.year, month.month)}01&stockNo=$symbol&response=json")

    fun tpexMonthURL(symbol: String, month: YearMonth): URI =
        URI("https://www.tpex.org.tw/www/zh-tw/afterTrading/tradingStock?code=$symbol&date=${"%04d/%02d".format(month.year, month.month)}/01&response=json")

    fun twseDividendsURL(from: Instant, to: Instant): URI =
        URI("https://www.twse.com.tw/rwd/zh/exRight/TWT49U?startDate=${ymd(from, "")}&endDate=${ymd(to, "")}&response=json")

    fun tpexDividendsURL(from: Instant, to: Instant): URI =
        URI("https://www.tpex.org.tw/www/zh-tw/bulletin/exDailyQ?startDate=${ymd(from, "/")}&endDate=${ymd(to, "/")}&response=json")

    fun splitsURL(from: Instant, to: Instant): URI =
        URI("https://www.twse.com.tw/rwd/zh/split/TWTCAU?startDate=${ymd(from, "")}&endDate=${ymd(to, "")}&response=json")
}
