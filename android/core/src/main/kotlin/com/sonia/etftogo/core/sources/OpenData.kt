package com.sonia.etftogo.core.sources

import com.sonia.etftogo.core.models.OPEN_DATA_SOURCE
import com.sonia.etftogo.core.models.Quote
import com.sonia.etftogo.core.models.StoreError
import com.sonia.etftogo.core.support.DataChecks
import com.sonia.etftogo.core.support.SwiftDate
import com.sonia.etftogo.core.support.TaiwanMarket
import com.sonia.etftogo.core.support.swiftDouble
import com.sonia.etftogo.core.support.swiftRounded
import com.sonia.etftogo.core.support.swiftTrim
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import java.net.URI
import java.time.DayOfWeek
import java.time.Instant

/**
 * Each trading day's prices from the exchanges' open data, released after the close under the 政府資料開放授權條款
 * (free to use, with the attribution on the About page): TWSE 上市個股日成交資訊 and 每日收盤行情 (TAIEX), TPEx 上櫃股票
 * 收盤行情 and 櫃買指數. Intraday prices come only from the user's own Fugle key.
 */
object OpenData {
    const val source = OPEN_DATA_SOURCE

    /** One trading day's figures, cached on the device. */
    @Serializable
    data class Day(val quotes: Map<String, Quote>, val indices: Map<String, Quote>, val fetchedAt: SwiftDate) {
        /** The latest trading day in the data (TWSE and TPEx may be a day apart while one has not published yet). */
        val day: String get() = (quotes.values + indices.values).maxOfOrNull { it.date } ?: ""

        /**
         * The older of the two exchanges' latest days, by their indices: TWSE's open data can lag TPEx's by a day or
         * more. An index that did not decode does not count, or the closes would look behind forever.
         */
        val settledDay: String get() = listOf("taiex", "tpex").mapNotNull { indices[it]?.date }.minOrNull() ?: day
    }

    val twseQuotes = URI("https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL")
    val twseIndices = URI("https://openapi.twse.com.tw/v1/exchangeReport/MI_INDEX")
    val tpexQuotes = URI("https://www.tpex.org.tw/openapi/v1/tpex_mainboard_quotes")
    val tpexIndex = URI("https://www.tpex.org.tw/openapi/v1/tpex_index")

    private fun rows(bytes: ByteArray): List<JsonObject> = DataChecks.jsonRows(bytes) ?: throw StoreError.InvalidQuote

    private fun number(value: JsonElement?): Double? {
        val text = value.string?.replace(",", "")?.replace("+", "")?.swiftTrim() ?: return null
        return swiftDouble(text)?.takeIf { it.isFinite() }
    }

    /** The close is fixed at 13:30 Taipei on its trading day, so a newer live quote always wins over it. */
    private fun quote(code: String, day: String, close: Double, change: Double?, open: Double?, high: Double?, low: Double?, shares: Double?): Quote? {
        val midnight = DataChecks.date(day)
        if (!(close > 0) || midnight == null) return null
        val previous = change?.let { close - it }
        val percent = previous?.let { if (it > 0) swiftRounded((close - it) / it * 10000) / 100 else null }
        var value = Quote(
            symbol = code, price = close, changePercent = percent, date = day, fetchedAt = midnight.plusSeconds(13 * 3600 + 1800),
            currency = if (code.endsWith("K") || code.endsWith("C")) "UNKNOWN" else "TWD", change = change, open = open, high = high,
            low = low, volume = shares?.let { swiftRounded(it / 1000) }, source = source,
        )
        if (!value.isValid) value = value.copy(open = null, high = null, low = null, volume = null)
        return if (value.isValid) value else null
    }

    /** 上市個股日成交資訊: Code, Date (ROC), OpeningPrice … ClosingPrice, Change, TradeVolume (shares). */
    fun decodeTWSE(bytes: ByteArray): Map<String, Quote> {
        val result = linkedMapOf<String, Quote>()
        for (row in rows(bytes)) {
            val code = row["Code"].string ?: continue
            if (!DataChecks.code(code)) continue
            val day = DataChecks.rocDay(row["Date"].string ?: "") ?: continue
            val close = number(row["ClosingPrice"]) ?: continue
            quote(code, day, close, number(row["Change"]), number(row["OpeningPrice"]), number(row["HighestPrice"]), number(row["LowestPrice"]),
                number(row["TradeVolume"]))?.let { result[code] = it }
        }
        return result
    }

    /** 上櫃股票收盤行情: SecuritiesCompanyCode, Date (ROC), Open … Close, Change (signed), TradingShares. */
    fun decodeTPEx(bytes: ByteArray): Map<String, Quote> {
        val result = linkedMapOf<String, Quote>()
        for (row in rows(bytes)) {
            val code = row["SecuritiesCompanyCode"].string?.swiftTrim() ?: continue
            if (!DataChecks.code(code)) continue
            val day = DataChecks.rocDay(row["Date"].string ?: "") ?: continue
            val close = number(row["Close"]) ?: continue
            quote(code, day, close, number(row["Change"]), number(row["Open"]), number(row["High"]), number(row["Low"]), number(row["TradingShares"]))
                ?.let { result[code] = it }
        }
        return result
    }

    /** 每日收盤行情－大盤統計資訊: the 發行量加權股價指數 row; 漲跌 holds the sign and 漲跌點數 the size. */
    fun decodeTAIEX(bytes: ByteArray): Quote? {
        val row = rows(bytes).firstOrNull { it["指數"].string == "發行量加權股價指數" } ?: return null
        val day = DataChecks.rocDay(row["日期"].string ?: "") ?: return null
        val close = number(row["收盤指數"]) ?: return null
        val size = number(row["漲跌點數"])
        val sign = if ((row["漲跌"].string ?: "").contains("-")) -1.0 else 1.0
        return quote("IX0001", day, close, size?.let { it * sign }, null, null, null, null)
    }

    /** 櫃買指數歷史資料: the latest row; Date is yyyyMMdd and Change is signed. */
    fun decodeTPExIndex(bytes: ByteArray): Quote? {
        val dated = rows(bytes).mapNotNull { row ->
            val raw = row["Date"].string ?: return@mapNotNull null
            if (raw.length != 8) return@mapNotNull null
            "${raw.take(4)}-${raw.substring(4, 6)}-${raw.takeLast(2)}" to row
        }
        val latest = dated.maxByOrNull { it.first } ?: return null
        val close = number(latest.second["Close"]) ?: return null
        val row = latest.second
        return quote("IX0043", latest.first, close, number(row["Change"]), number(row["Open"]), number(row["High"]), number(row["Low"]), null)
    }

    /** The trading day whose close should be out by now: today after 14:30 on a weekday, else the weekday before. */
    fun expectedDay(now: Instant = Instant.now()): String {
        var date = now.atZone(TaiwanMarket.zone)
        if (date.hour * 60 + date.minute < 14 * 60 + 30) date = date.minusDays(1)
        while (date.dayOfWeek == DayOfWeek.SATURDAY || date.dayOfWeek == DayOfWeek.SUNDAY) date = date.minusDays(1)
        return DataChecks.day(date.toInstant())
    }
}
