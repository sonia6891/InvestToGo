package com.sonia.etftogo.core.sources

import com.sonia.etftogo.core.models.Fund
import com.sonia.etftogo.core.models.Strategy
import com.sonia.etftogo.core.support.AppDataError
import com.sonia.etftogo.core.support.CoreJson
import com.sonia.etftogo.core.support.CoreResources
import com.sonia.etftogo.core.support.DataChecks
import com.sonia.etftogo.core.support.SwiftDate
import com.sonia.etftogo.core.support.charCount
import com.sonia.etftogo.core.support.nfc
import com.sonia.etftogo.core.support.swiftTrim
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

@Serializable
data class CatalogSnapshot(
    val funds: List<Fund>,
    val listedDate: String,
    val fetchedDay: String,
    val sources: List<String>,
    /**
     * When this list was fetched on the device (spec 9: LoadFailed shows the last good data's day and time); null for
     * the bundled list and lists saved before it was recorded.
     */
    val fetchedAt: SwiftDate? = null,
) {
    fun validate() {
        val today = DataChecks.day()
        val ok = funds.isNotEmpty() && funds.size <= 2000 && funds.map { it.id }.toSet().size == funds.size &&
            DataChecks.date(listedDate) != null && DataChecks.date(fetchedDay) != null && listedDate <= today && fetchedDay <= today &&
            funds.all { DataChecks.code(it.id) && it.name.isNotEmpty() && it.name.charCount <= 120 && (it.market ?: "") in setOf("TWSE", "TPEx") }
        if (!ok) throw AppDataError("ETF 名單未通過驗證，保留上次成功資料。")
    }

    companion object {
        fun bundled(): CatalogSnapshot? = try {
            CoreJson.decode(serializer(), CoreResources.read("catalog.json")).also { it.validate() }
        } catch (_: Exception) {
            null
        }
    }
}

object CatalogAPI {
    const val listedURL = "https://openapi.twse.com.tw/v1/opendata/t187ap47_L"
    const val twseURL = "https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL"
    const val otcURL = "https://www.tpex.org.tw/openapi/v1/tpex_mainboard_quotes"

    fun strategy(name: String): Strategy = when {
        name.contains("正2") || name.contains("反1") || name.contains("槓桿") || name.contains("反向") -> Strategy.RISK
        name.contains("高股息") || name.contains("優息") || name.contains("高息") -> Strategy.INCOME
        name in setOf("元大台灣50", "富邦台50", "元大富櫃50") -> Strategy.SAVING
        else -> Strategy.UNCLASSIFIED
    }

    /**
     * The ETFs are the codes starting with 00 in each exchange's daily trading list (TWSE 上市個股日成交資訊, TPEx 上櫃股票
     * 收盤行情), so funds that left the market or are not listed yet drop out. TWSE 基金基本資料彙總表 adds the full name,
     * fund type and listing day of listed ETFs; the open data has none of these for OTC ETFs, so they carry over from
     * the previous list.
     */
    fun decode(listed: ByteArray, twse: ByteArray, otc: ByteArray, previous: CatalogSnapshot? = null, today: String = DataChecks.day()): CatalogSnapshot {
        val details = mutableMapOf<String, JsonObject>()
        val dates = mutableListOf<String>()
        for (row in rows(listed)) {
            val code = text(row["基金代號"])
            val day = DataChecks.rocDay(text(row["出表日期"]) ?: "")
            if (code == null || day == null || day > today || code in details) throw AppDataError("上市基本資料欄位或日期改變，未覆寫。")
            details[code] = row
            dates += day
        }
        val known = linkedMapOf<String, Fund>()
        for (fund in previous?.funds ?: emptyList()) known.putIfAbsent(fund.id, fund)
        val funds = mutableListOf<Fund>()
        for ((market, bytes, codeKey, nameKey) in listOf(Market("TWSE", twse, "Code", "Name"), Market("TPEx", otc, "SecuritiesCompanyCode", "CompanyName"))) {
            val records = rows(bytes)
            val before = funds.size
            if (codeKey !in records[0] || nameKey !in records[0]) throw AppDataError("每日成交資料欄位改變，未覆寫。")
            for (row in records) {
                val code = text(row[codeKey]) ?: continue
                if (!code.startsWith("00") || !DataChecks.code(code)) continue
                val name = text(row[nameKey])?.let(::unescape) ?: continue
                val detail = if (market == "TWSE") details[code] else null
                val old = known[code]
                funds += Fund(
                    id = code, name = name, strategy = strategy(name), market = market,
                    fullName = text(detail?.get("基金中文名稱"))?.let(::unescape) ?: old?.fullName,
                    fundType = text(detail?.get("基金類型")) ?: old?.fundType,
                    listingDate = DataChecks.rocDay(text(detail?.get("上市日期")) ?: "") ?: old?.listingDate,
                )
            }
            if (funds.size <= before) throw AppDataError("上市或上櫃資料不完整，保留原名單。")
        }
        val value = CatalogSnapshot(funds.sortedBy { it.id }, dates.maxOrNull() ?: today, today, listOf(listedURL, twseURL, otcURL))
        value.validate()
        return value
    }

    private data class Market(val name: String, val bytes: ByteArray, val codeKey: String, val nameKey: String)

    private fun rows(bytes: ByteArray): List<JsonObject> {
        val rows = DataChecks.jsonRows(bytes)
        if (rows.isNullOrEmpty()) throw AppDataError("上市或上櫃資料不完整，保留原名單。")
        return rows
    }

    private fun text(value: JsonElement?): String? = value.string?.swiftTrim()?.takeIf { it.isNotEmpty() }

    private val numericEntity = Regex("&#[0-9]{1,7};")

    /**
     * The TWSE fund list writes some characters as HTML entities ("S&amp;P", "&#63754;"). The result is in NFC, so
     * a CJK compatibility ideograph such as U+F90A (what "&#63754;" spells) becomes the unified 金 U+91D1, which the
     * bundled fonts have.
     */
    fun unescape(text: String): String {
        if (!text.contains("&")) return text.nfc
        var result = text
        while (true) {
            val match = numericEntity.find(result) ?: break
            val scalar = match.value.drop(2).dropLast(1).toLong()
            if (scalar > 0x10FFFF || scalar in 0xD800..0xDFFF) break
            result = result.replaceRange(match.range, String(Character.toChars(scalar.toInt())))
        }
        for ((entity, character) in listOf("&lt;" to "<", "&gt;" to ">", "&quot;" to "\"", "&#39;" to "'", "&amp;" to "&")) {
            result = result.replace(entity, character)
        }
        return result.nfc
    }
}
