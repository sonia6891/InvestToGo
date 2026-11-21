package com.sonia.etftogo.core.sources

import com.sonia.etftogo.core.models.ComponentSnapshot
import com.sonia.etftogo.core.models.FundComponent
import com.sonia.etftogo.core.support.AppDataError
import com.sonia.etftogo.core.support.swiftDouble
import com.sonia.etftogo.core.support.swiftInt
import com.sonia.etftogo.core.support.swiftTrimAll
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.util.regex.Pattern

/** Fund companies whose own public holdings pages the app can read. */
@Serializable
enum class Issuer(val rawValue: String, val displayName: String) {
    @SerialName("yuanta") YUANTA("yuanta", "元大投信"),
    @SerialName("cathay") CATHAY("cathay", "國泰投信"),
    @SerialName("fubon") FUBON("fubon", "富邦投信"),
    @SerialName("capital") CAPITAL("capital", "群益投信"),
    @SerialName("fhtrust") FHTRUST("fhtrust", "復華投信"),
    @SerialName("ctbc") CTBC("ctbc", "中國信託投信"),
}

/** Which fund company runs an ETF, read from the start of its name. */
object IssuerDirectory {
    private val prefixes = listOf(
        "元大" to Issuer.YUANTA, "國泰" to Issuer.CATHAY, "富邦" to Issuer.FUBON, "群益" to Issuer.CAPITAL,
        "復華" to Issuer.FHTRUST, "中信" to Issuer.CTBC, "中國信託" to Issuer.CTBC,
    )

    /** Active ETFs are listed as 「主動群益台灣強棒」: the 主動 in front is not part of the company's name. */
    fun issuer(fundName: String): Issuer? {
        var trimmed = fundName.swiftTrimAll()
        if (trimmed.startsWith("主動")) trimmed = trimmed.drop(2).swiftTrimAll()
        return prefixes.firstOrNull { trimmed.startsWith(it.first) }?.second
    }

    /** Said instead of holdings for a bond ETF. */
    const val bondFund = "債券型 ETF 沒有股票成分可顯示"

    /**
     * A bond ETF (00679B, 00687B, 00937B…) holds bonds: its company's page has no stock rows, and reading it would
     * look like a page that was redesigned. It is told before anything is asked for: by the catalogue's fund type
     * when that names bonds (a 平衡 fund holds stocks too, so it is not one), else by a code ending in B, which the
     * exchanges give to bond ETFs only.
     */
    fun isBondFund(symbol: String, fundType: String?): Boolean {
        if (fundType != null && fundType.contains("債") && !fundType.contains("平衡") && !fundType.contains("多重資產")) return true
        return symbol.uppercase().endsWith("B")
    }
}

/** Parsers for each fund company's holdings response. A reshaped or error body throws; none returns an empty snapshot. */
object IssuerHoldings {
    // Values

    private fun fail(issuer: Issuer, why: String) = AppDataError("${issuer.displayName}持股資料$why")

    private fun obj(data: ByteArray, issuer: Issuer): JsonObject = parseObject(data) ?: throw fail(issuer, "格式不符（不是 JSON 物件）")

    private fun text(any: JsonElement?): String? = any.string?.swiftTrimAll()

    private fun filled(any: JsonElement?): String? = text(any)?.takeIf { it.isNotEmpty() }

    /** A JSON number, or a string such as "1,234.5" or "4.123%". */
    private fun number(any: JsonElement?): Double? {
        val s = any.string
        val value = if (s != null) {
            swiftDouble(s.replace(",", "").replace("%", "").replace("％", "").swiftTrimAll())
        } else {
            any.double
        }
        return value?.takeIf { it.isFinite() }
    }

    /** "20261111", "2026/11/11" or "2026-11-11" -> "2026-11-11". */
    fun day(any: JsonElement?): String? = day(text(any))

    fun day(raw: String?): String? {
        val s = raw?.swiftTrimAll() ?: return null
        var parts = s.split('/', '-')
        if (parts.size == 1 && s.length == 8) parts = listOf(s.take(4), s.substring(4, 6), s.takeLast(2))
        val digits = parts.all { part -> part.isNotEmpty() && part.all { it in '0'..'9' } }
        if (parts.size != 3 || !digits || parts[0].length != 4) return null
        val y = swiftInt(parts[0]) ?: return null
        val m = swiftInt(parts[1]) ?: return null
        val d = swiftInt(parts[2]) ?: return null
        if (m !in 1..12 || d !in 1..31) return null
        return "%04d-%02d-%02d".format(y, m, d)
    }

    /** The response names its own ETF; a different one must not be filed under `symbol`. */
    private fun checkFund(issuer: Issuer, any: JsonElement?, symbol: String) {
        val code = filled(any) ?: return
        if (code.uppercase() != symbol.uppercase()) throw fail(issuer, "與查詢的 ETF 不符（回應為 $code）")
    }

    /**
     * Builds the snapshot from the stock rows. Rows without a code are skipped (cash-like lines); a row with a code
     * but no readable weight throws, so a snapshot never silently loses weight. The same code twice is summed.
     */
    private fun snapshot(issuer: Issuer, symbol: String, date: String?, rows: List<JsonObject>, code: String, name: String, weight: String): ComponentSnapshot {
        if (date == null) throw fail(issuer, "格式不符（缺少資料日期）")
        if (rows.isEmpty()) throw fail(issuer, "沒有股票成分")
        val found = linkedMapOf<String, FundComponent>()
        for (row in rows) {
            val id = filled(row[code]) ?: continue
            val w = number(row[weight]) ?: throw fail(issuer, "無法解析（$id 的權重無效）")
            val label = filled(row[name])
            val old = found[id]
            found[id] = if (old != null) old.copy(weight = old.weight + w, name = old.name ?: label) else FundComponent(id, label, w)
        }
        if (found.isEmpty()) throw fail(issuer, "無法解析（${rows.size} 列皆無效）")
        val value = ComponentSnapshot(symbol, date, found.values.toList(), issuer.displayName)
        value.validate()
        return value
    }

    // Holdings

    /** 元大 PCF：`FundWeights.StockWeights[] {code,name,weights}`，日期 `PCF.trandate`。 */
    fun yuanta(data: ByteArray, symbol: String): ComponentSnapshot {
        val issuer = Issuer.YUANTA
        val o = obj(data, issuer)
        val pcf = o["PCF"].obj ?: throw fail(issuer, "格式不符（缺少 PCF）")
        checkFund(issuer, pcf["markcd"], symbol)
        val rows = o["FundWeights"].obj?.get("StockWeights").objects ?: throw fail(issuer, "格式不符（缺少 StockWeights）")
        return snapshot(issuer, symbol, day(pcf["trandate"]), rows, "code", "name", "weights")
    }

    /** 國泰 GetETFDetailStockList：`result[] {stockCode,stockName,weights}`；回應沒有日期，由查詢日期帶入。 */
    fun cathay(data: ByteArray, symbol: String, date: String): ComponentSnapshot {
        val issuer = Issuer.CATHAY
        val o = obj(data, issuer)
        val ok = o["success"].bool
        if (ok != null && !ok) throw fail(issuer, "回應異常：" + (filled(o["returnMessage"]) ?: "success 為 false"))
        val rows = o["result"].objects ?: throw fail(issuer, "格式不符（缺少 result）")
        return snapshot(issuer, symbol, day(date), rows, "stockCode", "stockName", "weights")
    }

    /** 富邦 Assets.aspx：股票代碼/股票名稱/股數/金額/權重(%) 表頭之後、同一張表內的列；日期「資料日期：yyyy/MM/dd」。 */
    fun fubon(html: String, symbol: String): ComponentSnapshot {
        val issuer = Issuer.FUBON
        val date = matches("資料日期\\s*[：:]\\s*(\\d{4}/\\d{1,2}/\\d{1,2})", html).firstOrNull()?.let { day(it[0]) }
        val mark = compile("(?i)<t[dh]\\b[^>]*>\\s*股票代碼\\s*</t[dh]>", dotAll = false).matcher(html)
        if (!mark.find()) throw fail(issuer, "格式不符（缺少股票表頭）")
        val start = html.substring(0, mark.start()).lastIndexOf("<tr", ignoreCase = true)
            .takeIf { it >= 0 } ?: throw fail(issuer, "格式不符（缺少股票表頭）")
        val end = html.indexOf("</table", mark.end(), ignoreCase = true).takeIf { it >= 0 } ?: html.length
        val table = matches("(?i)<tr\\b[^>]*>(.*?)</tr>", html.substring(start, end)).map { tr ->
            matches("(?i)<t[dh]\\b[^>]*>(.*?)</t[dh]>", tr[0]).map { cellText(it[0]) }
        }
        val head = table.firstOrNull()
        val ci = head?.indexOf("股票代碼") ?: -1
        val wi = head?.indexOfFirst { it.startsWith("權重") } ?: -1
        if (head == null || ci < 0 || wi < 0) throw fail(issuer, "欄位不符（缺少「股票代碼」或「權重」）")
        val ni = head.indexOf("股票名稱").takeIf { it >= 0 }
        // A row with a different cell count, or with words where the code belongs (a 合計 line), is not a holding.
        val rows = table.drop(1).filter { it.size == head.size && isCode(it[ci]) }.map { cells ->
            JsonObject(mapOf("code" to JsonPrimitive(cells[ci]), "name" to JsonPrimitive(ni?.let { cells[it] } ?: ""), "weight" to JsonPrimitive(cells[wi])))
        }
        return snapshot(issuer, symbol, date, rows, "code", "name", "weight")
    }

    /** 群益 buyback：`data.stocks[] {stocNo,stocName,weight}`，日期 `data.pcf.date2`。 */
    fun capital(data: ByteArray, symbol: String): ComponentSnapshot {
        val issuer = Issuer.CAPITAL
        val o = obj(data, issuer)
        val code = number(o["code"])
        if (code != null && code != 200.0) throw fail(issuer, "回應異常：" + (filled(o["message"]) ?: "code %.0f".format(code)))
        val body = o["data"].obj ?: throw fail(issuer, "格式不符（缺少 data）")
        val rows = body["stocks"].objects ?: throw fail(issuer, "格式不符（缺少 stocks）")
        return snapshot(issuer, symbol, day(body["pcf"].obj?.get("date2")), rows, "stocNo", "stocName", "weight")
    }

    /** 復華 assets：`result[0].detail[]` 中 `ftype == "股票"` 的列，權重 `prate_addaccint`，日期 `result[0].dDate`。 */
    fun fhtrust(data: ByteArray, symbol: String): ComponentSnapshot {
        val issuer = Issuer.FHTRUST
        val o = obj(data, issuer)
        val fund = o["result"].objects?.firstOrNull() ?: throw fail(issuer, "格式不符（缺少 result）")
        checkFund(issuer, fund["etf002"], symbol)
        val detail = fund["detail"].objects ?: throw fail(issuer, "格式不符（缺少 detail）")
        val rows = detail.filter { text(it["ftype"]) == "股票" }
        return snapshot(issuer, symbol, day(fund["dDate"]), rows, "stockid", "stockname", "prate_addaccint")
    }

    /**
     * 中信 ETFHoldingWeight：`Data.FundAssetsDetail[Code == "STOCK"].Data[] {code_,name_,weights_}`，
     * 日期 `Data.FundAssets[0]["資料日期"]`。
     */
    fun ctbc(data: ByteArray, symbol: String): ComponentSnapshot {
        val issuer = Issuer.CTBC
        val o = obj(data, issuer)
        val code = number(o["ResultCode"])
        if (code != null && code != 0.0) throw fail(issuer, "回應異常：" + (filled(o["ResultMsg"]) ?: "ResultCode %.0f".format(code)))
        val body = o["Data"].obj ?: throw fail(issuer, "格式不符（缺少 Data）")
        checkFund(issuer, body["Fund"].objects?.firstOrNull()?.get("ETF_ID"), symbol)
        val groups = body["FundAssetsDetail"].objects ?: throw fail(issuer, "格式不符（缺少 FundAssetsDetail）")
        val stock = groups.firstOrNull { text(it["Code"]) == "STOCK" } ?: throw fail(issuer, "沒有股票成分")
        val rows = stock["Data"].objects ?: throw fail(issuer, "格式不符（缺少股票明細）")
        val date = day(body["FundAssets"].objects?.firstOrNull()?.get("資料日期"))
        return snapshot(issuer, symbol, date, rows, "code_", "name_", "weights_")
    }

    // Fund-code lookups

    /** 國泰 GetETFList?Keyword=<code>：`result[] {stockCode, fundCode}`（00878 → "CN"）. */
    fun cathayFundCode(data: ByteArray, symbol: String): String? {
        val items = parseObject(data)?.get("result").objects ?: emptyList()
        val hit = items.firstOrNull { text(it["stockCode"])?.uppercase() == symbol.uppercase() }
        return filled(hit?.get("fundCode"))
    }

    /** 國泰 GetETFAssets：`result.preDate`（"2026/11/13"）, the day the holdings list is asked for, as "2026-11-13". */
    fun cathayAssetsDate(data: ByteArray): String? {
        val raw = text(parseObject(data)?.get("result").obj?.get("preDate")) ?: return null
        // A time after the day ("2026-11-13T00:00:00") is dropped.
        return day(raw.split('T', ' ').first())
    }

    /** 群益 items：`data[] {fundNo, stockNo}`. */
    fun capitalFundNo(data: ByteArray, symbol: String): String? {
        val items = parseObject(data)?.get("data").objects ?: emptyList()
        return filled(items.firstOrNull { text(it["stockNo"]) == symbol }?.get("fundNo"))
    }

    /**
     * 復華 etf_list 頁：one `<tr>` per fund, the ETF code in a cell of its own and the id in the row's
     * `/ETF/etf_detail/ETF<n>` link. `fhtrust` rejects a wrong fund afterwards.
     */
    fun fhtrustFundID(html: String, symbol: String): String? {
        for (row in matches("(?i)<tr\\b[^>]*>(.*?)</tr>", html)) {
            val cells = matches("(?i)<t[dh]\\b[^>]*>(.*?)</t[dh]>", row[0]).map { cellText(it[0]) }
            if (symbol !in cells) continue
            matches("etf_detail/(ETF\\d+)", row[0]).firstOrNull()?.let { return it[0] }
        }
        return null
    }

    /** 中信 ETFList：`Data.Data[] {ETF_ID, FID}`. */
    fun ctbcFID(data: ByteArray, symbol: String): String? {
        val items = parseObject(data)?.get("Data").obj?.get("Data").objects ?: emptyList()
        return filled(items.firstOrNull { text(it["ETF_ID"]) == symbol }?.get("FID"))
    }

    /** 中信 home/AuthToken：`Data.token`, sent with every later request. */
    fun ctbcToken(data: ByteArray): String? = filled(parseObject(data)?.get("Data").obj?.get("token"))

    // HTML

    private const val CODE_MARKS = " .-/"

    /**
     * A stock code as the pages print one: letters and digits ("2330", "00679B"), for foreign shares also with a
     * space, dot, hyphen or slash ("AAPL US", "BRK.B"). 「合計」 and other words are not codes.
     */
    private fun isCode(cell: String): Boolean {
        fun alnum(c: Char) = c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9'
        return cell.any(::alnum) && cell.all { alnum(it) || it in CODE_MARKS }
    }

    /** NSRegularExpression (ICU) semantics: `\d`, `\s` and `\b` are Unicode-aware. */
    private fun compile(pattern: String, dotAll: Boolean = true): Pattern =
        Pattern.compile(pattern, Pattern.UNICODE_CHARACTER_CLASS or if (dotAll) Pattern.DOTALL else 0)

    /** Capture groups of every match; `.` also matches newlines. */
    private fun matches(pattern: String, text: String): List<List<String>> {
        val m = compile(pattern).matcher(text)
        val out = mutableListOf<List<String>>()
        while (m.find()) out += (1..m.groupCount()).map { m.group(it) ?: "" }
        return out
    }

    private val tag = compile("<[^>]+>", dotAll = false)

    private fun cellText(html: String): String {
        var s = tag.matcher(html).replaceAll("")
        for ((entity, plain) in listOf("&nbsp;" to " ", "&lt;" to "<", "&gt;" to ">", "&amp;" to "&")) s = s.replace(entity, plain)
        return s.swiftTrimAll()
    }
}
