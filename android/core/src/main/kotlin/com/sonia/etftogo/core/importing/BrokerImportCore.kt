package com.sonia.etftogo.core.importing

import com.sonia.etftogo.core.models.Fund
import com.sonia.etftogo.core.models.Holding
import com.sonia.etftogo.core.support.AppDataError
import com.sonia.etftogo.core.support.DataChecks
import com.sonia.etftogo.core.support.StableID
import com.sonia.etftogo.core.support.cFixed
import com.sonia.etftogo.core.support.charCount
import com.sonia.etftogo.core.support.priceText
import com.sonia.etftogo.core.support.swiftDouble
import com.sonia.etftogo.core.support.swiftTrimAll
import com.sonia.etftogo.core.support.uuidString
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

// Port of PocketCore Import/BrokerImportCore.swift: a broker's holdings CSV read into holdings for one account.

data class CSVTable(val headers: List<String>, val rows: List<List<String>>) {
    /** The column titled with one of `names`, trying the names in order (so 總成本 wins over a plain 成本). */
    fun guess(names: List<String>): Int {
        for (name in names) {
            val i = headers.indexOfFirst { it.lowercase() == name }
            if (i >= 0) return i
        }
        return -1
    }

    companion object {
        /**
         * Taiwan brokers' and Excel's "Big5" files are Windows code page 950, which has the ETEN characters (碁 銹 裏 …)
         * that Java's plain "Big5" table lacks; iPhone reads the same files with its own Big5 converter. Android names the
         * code page differently on some builds, so the first name this runtime knows is used.
         */
        private val big5: Charset? = listOf("x-windows-950", "windows-950", "MS950", "Big5")
            .firstNotNullOfOrNull { name -> runCatching { Charset.forName(name) }.getOrNull() }

        /** The text of `bytes` in `charset`, or null when any byte does not decode (Swift's `String(data:encoding:)`). */
        private fun decode(bytes: ByteArray, charset: Charset?): String? {
            charset ?: return null
            return try {
                charset.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes)).toString()
            } catch (_: CharacterCodingException) {
                null
            }
        }

        fun parse(bytes: ByteArray): CSVTable {
            if (bytes.size > 5_000_000) throw AppDataError("CSV 不可超過 5 MB。")
            val utf16BOM = bytes.size >= 2 && ((bytes[0] == 0xFF.toByte() && bytes[1] == 0xFE.toByte()) || (bytes[0] == 0xFE.toByte() && bytes[1] == 0xFF.toByte()))
            val decoded = if (utf16BOM) decode(bytes, Charsets.UTF_16) else decode(bytes, Charsets.UTF_8) ?: decode(bytes, big5)
            val text = decoded ?: throw AppDataError("請將對帳單另存為 UTF-8 CSV。")
            val rows = mutableListOf<List<String>>()
            var row = mutableListOf<String>()
            val cell = StringBuilder()
            var quoted = false
            var endedQuote = false
            val chars = text.trim { it == '﻿' }.replace("\r\n", "\n").replace("\r", "\n")
            var i = 0
            while (i < chars.length) {
                val c = chars[i]
                if (quoted) {
                    if (c == '"') {
                        if (i + 1 < chars.length && chars[i + 1] == '"') { cell.append('"'); i += 1 } else { quoted = false; endedQuote = true }
                    } else cell.append(c)
                } else if (c == '"') {
                    if (cell.isNotEmpty() || endedQuote) throw AppDataError("CSV 引號格式錯誤。")
                    quoted = true
                } else if (c == ',' || c == '\n') {
                    row.add(cell.toString().swiftTrimAll()); cell.clear(); endedQuote = false
                    if (c == '\n') {
                        if (row.any { it.isNotEmpty() }) rows.add(row)
                        row = mutableListOf()
                    }
                } else {
                    if (endedQuote && c != ' ') throw AppDataError("CSV 引號後出現不明字元。")
                    if (!endedQuote) cell.append(c)
                }
                i += 1
            }
            if (quoted) throw AppDataError("CSV 引號未結束，未匯入。")
            row.add(cell.toString().swiftTrimAll())
            if (row.any { it.isNotEmpty() }) rows.add(row)
            if (rows.size < 2 || rows.size > 10001) throw AppDataError("需要標題列與持有資料，最多 10,000 筆。")
            val headers = rows.removeAt(0).toMutableList()
            headers[0] = headers[0].replace("﻿", "")
            // Spreadsheets often end lines with empty cells, and total or note rows are shorter than the title row.
            while (headers.size > 1 && headers.last().isEmpty()) headers.removeAt(headers.size - 1)
            if (headers.size > 100) throw AppDataError("CSV 欄位超過 100 欄。")
            val padded = rows.map { original ->
                val r = original.toMutableList()
                while (r.size > headers.size && r.last().isEmpty()) r.removeAt(r.size - 1)
                r + List(maxOf(headers.size - r.size, 0)) { "" }
            }
            // A row still wider than the titles (such as an unquoted 1,000) is kept as is and skipped with a reason when previewed.
            return CSVTable(headers, padded)
        }
    }
}

data class BrokerMapping(
    val symbol: Int,
    val name: Int,
    val shares: Int,
    val cost: Int,
    val lots: Boolean = false,
    val totalCost: Boolean = true,
) {
    companion object {
        /** Picks columns by their titles, including 國泰證券's (股票代號、商品名稱、現股庫存、付出成本). */
        fun guessing(table: CSVTable) = BrokerMapping(
            symbol = table.guess(listOf("代碼", "代號", "股票代號", "股票代碼", "證券代號", "商品代碼", "商品代號", "symbol", "code")),
            name = table.guess(listOf("名稱", "股票名稱", "證券名稱", "商品名稱", "name")),
            shares = table.guess(listOf("股數", "庫存股數", "現股庫存", "庫存數量", "數量", "shares", "quantity")),
            cost = table.guess(listOf("總成本", "付出成本", "持有成本", "投資成本", "成本", "cost")),
        )
    }
}

data class BrokerPreview(
    val holdings: List<Holding>,
    val sourceAccount: String,
    val broker: String,
    /** CSV rows not imported, each with its reason; shown before importing. */
    val skipped: List<String> = emptyList(),
    /** Codes on skipped rows. Replacing the account keeps their earlier holdings rather than removing them. */
    val skippedCodes: Set<String> = emptySet(),
) {
    val totalCost: Double get() = holdings.fold(0.0) { sum, h -> sum + h.cost }

    /** Holdings whose average cost is far from the latest price: most likely a price per share taken as a total, or the other way round. */
    fun warnings(price: (String) -> Double?): List<String> = holdings.mapNotNull { holding ->
        costWarning(holding.unitCost, price(holding.symbol))?.let { warning ->
            "${holding.symbol} ${holding.name}" + (if (holding.broker.endsWith("（融資）")) "（融資）" else "") + "：" + warning
        }
    }

    /** One position to import; `place` names it in error messages. */
    private data class Entry(val place: String, val code: String, val name: String, var quantity: Double?, var cost: Double?, val margin: Boolean = false, val problem: String? = null)

    companion object {
        /** ETFs take the fund list's name and strategy; stocks are named from the stock list and left unclassified, as in the 新增持有 form. */
        fun make(table: CSVTable, mapping: BrokerMapping, broker: String, account: String, funds: List<Fund>): BrokerPreview {
            val columns = listOf(mapping.symbol, mapping.shares, mapping.cost)
            if (!columns.all { it in table.headers.indices } || columns.toSet().size != 3) throw AppDataError("請指定不同的代號、數量與成本欄。")
            val entries = table.rows.mapIndexed { offset, row ->
                Entry(place = "第 ${offset + 2} 列", code = row[mapping.symbol].uppercase(), name = if (mapping.name in table.headers.indices) row[mapping.name] else "",
                    quantity = number(row[mapping.shares]), cost = number(row[mapping.cost]),
                    problem = if (row.size > table.headers.size) "欄位比標題列多，可能有未加引號的逗號" else null)
            }
            return build(entries, mapping.lots, mapping.totalCost, broker, account, funds, skipInvalid = true)
        }

        /**
         * The lots the user checked after reading screenshots. Each lot's total is its cost, or its price per share times its
         * shares; lots of one code and kind (現股 or 融資) become one holding with the shares and totals added up.
         */
        fun make(drafts: List<ScreenshotImport.Draft>, broker: String, account: String, funds: List<Fund>): BrokerPreview {
            if (drafts.isEmpty()) throw AppDataError("沒有要匯入的持有。")
            val entries = mutableListOf<Entry>()
            for ((offset, draft) in drafts.withIndex()) {
                val code = draft.symbol.swiftTrimAll().uppercase()
                val place = "第 ${offset + 1} 筆"
                if (code.isEmpty()) throw AppDataError("${place}還沒有代號，請填入或刪除這一筆。")
                if (draft.kind == ScreenshotImport.Kind.SHORT) throw AppDataError("$place $code 是融券（放空部位），不匯入；請刪除這一筆。")
                val quantity = draft.shareCount ?: throw AppDataError("$place $code 還沒有股數，請對照截圖填入。")
                val total = draft.totalCost ?: throw AppDataError("$place $code 還沒有${if (draft.perShare) "每股成本" else "總成本"}，請對照截圖填入。")
                if (!(quantity.isFinite() && quantity > 0 && total.isFinite() && total >= 0)) throw AppDataError("$place $code 的股數或成本不正確。")
                val margin = draft.kind == ScreenshotImport.Kind.MARGIN
                val same = entries.firstOrNull { it.code == code && it.margin == margin }
                if (same != null) {
                    same.quantity = (same.quantity ?: 0.0) + quantity
                    same.cost = (same.cost ?: 0.0) + total
                } else {
                    entries.add(Entry(place, code, "", quantity, total, margin))
                }
            }
            return build(entries, lots = false, totalCost = true, broker = broker, account = account, funds = funds)
        }

        fun costWarning(average: Double, price: Double?): String? {
            if (price == null || !(price > 0) || ScreenshotImport.plausible(average, price)) return null
            val ratio = average / price
            val size = if (ratio < 1) "只有現價 ${priceText(price)} 元的 " + cFixed(ratio * 100, 1) + "%" else "是現價 ${priceText(price)} 元的 " + cFixed(ratio, 1) + " 倍"
            return "平均成本 ${priceText(average)} 元，$size，請確認成本是每股價格還是總金額。"
        }

        fun number(text: String): Double? = swiftDouble(text.replace(",", "").replace(" ", ""))

        /** A share count written 1,000, 1,000股 or 2張 (1 張 = 1,000 股). */
        fun shareCount(text: String): Double? {
            var value = text.swiftTrimAll()
            val lots = value.endsWith("張")
            if (lots || value.endsWith("股")) value = value.dropLast(1)
            return number(value)?.let { if (lots) it * 1000 else it }
        }

        /**
         * With `skipInvalid` (CSV), a row with a bad code, quantity or cost, or a code in neither list, is skipped and listed
         * instead of stopping the whole file; the screenshot list asks the user to fix each lot instead.
         */
        private fun build(entries: List<Entry>, lots: Boolean, totalCost: Boolean, broker: String, account: String, funds: List<Fund>, skipInvalid: Boolean = false): BrokerPreview {
            val name = broker.swiftTrimAll()
            val alias = account.swiftTrimAll()
            if (name.isEmpty() || name.charCount > 80 || alias.isEmpty() || alias.charCount > 80) throw AppDataError("請填券商名稱與帳戶暱稱（各 80 字以內）。")
            val source = StableID.make("broker-account", name + "\u0000" + alias).uuidString
            val holdings = mutableListOf<Holding>()
            val seen = mutableSetOf<String>()
            val skipped = mutableListOf<String>()
            val skippedCodes = linkedSetOf<String>()
            for (entry in entries) {
                val code = entry.code
                fun skip(reason: String) {
                    if (!skipInvalid) throw AppDataError("${entry.place} $code：$reason，整份未匯入。")
                    skipped.add("${entry.place}${if (code.isEmpty()) "" else " $code"}：$reason")
                    if (DataChecks.code(code)) skippedCodes.add(code)
                }
                if (entry.problem != null) { skip(entry.problem); continue }
                if (!DataChecks.code(code)) { skip("不是股票或 ETF 代號"); continue }
                val qty = entry.quantity
                val cost = entry.cost
                if (qty == null || cost == null || !qty.isFinite() || !(qty > 0) || !cost.isFinite() || !(cost >= 0)) { skip("數量或成本不是有效數字"); continue }
                if (!seen.add(if (entry.margin) code + "\u0000融資" else code)) throw AppDataError("$code 有多列，請先將同帳戶同一檔合併為一筆庫存。")
                if (lots && (code.endsWith("C") || code.endsWith("K"))) throw AppDataError("$code 為外幣級別，交易單位可能不是 1,000 股；請將數量改為實際股數再匯入。")
                val shares = qty * (if (lots) 1000 else 1)
                val fund = funds.firstOrNull { it.id == code }
                val listed = fund?.name
                if (listed == null) {
                    if (!skipInvalid) throw AppDataError("${entry.place} $code 不在目前股票或 ETF 名單；請先更新名單，或移除該列。")
                    skip("不在目前股票或 ETF 名單"); continue
                }
                // 融資 is a holding of its own beside 現股, so the two never replace each other on a later import.
                val holding = Holding(
                    id = StableID.make("broker-position", source + "\u0000" + code + (if (entry.margin) "\u0000融資" else "")),
                    symbol = code, name = entry.name.ifEmpty { listed }, shares = shares,
                    unitCost = if (totalCost) cost / shares else cost, broker = if (entry.margin) "$name（融資）" else name,
                    strategy = fund.strategy, sourceAccount = source,
                )
                holding.validate()
                holdings.add(holding)
            }
            if (holdings.isEmpty()) throw AppDataError("沒有可匯入的列。" + (skipped.firstOrNull()?.let { "例如$it。" } ?: ""))
            return BrokerPreview(holdings, source, name, skipped, skippedCodes)
        }
    }
}
