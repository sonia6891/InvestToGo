package com.sonia.etftogo.core.importing

import com.sonia.etftogo.core.support.DataChecks
import com.sonia.etftogo.core.support.isUnicodeWhiteSpace
import com.sonia.etftogo.core.support.swiftDescription
import com.sonia.etftogo.core.support.swiftTrim
import java.util.UUID
import java.util.regex.Pattern

/** A rectangle in Vision's normalised coordinates (origin at the bottom left), as CGRect. */
data class Box(val x: Double, val y: Double, val width: Double, val height: Double) {
    val minX: Double get() = x
    val maxX: Double get() = x + width
    val maxY: Double get() = y + height
    val midY: Double get() = y + height / 2

    /** CGRect's `intersection`: null when the two do not meet; a rectangle of no width when they only touch. */
    fun intersection(other: Box): Box? {
        val left = maxOf(minX, other.minX)
        val right = minOf(maxX, other.maxX)
        val bottom = maxOf(y, other.y)
        val top = minOf(maxY, other.maxY)
        if (right < left || top < bottom) return null
        return Box(left, bottom, right - left, top - bottom)
    }
}

/** One piece of recognised text and where it was. */
data class TextBox(val text: String, val box: Box)

/**
 * Port of PocketCore Import/ScreenshotImport.swift. Reads holdings from the text of a broker's inventory screenshot: the
 * app runs on-device text recognition and passes the lines here, so this part works on plain text. A holding is found by a
 * listed code, else by a listed name. Each lot (one row or card of the screenshot) stays a row of its own for review. A
 * figure the text does not clearly label stays empty, and a name that fits no single code leaves the code for the user to
 * choose; nothing is estimated.
 */
object ScreenshotImport {
    /** 現股 (paid in full), 融資 (bought with a margin loan) or 融券 (sold short, not a holding, never imported). */
    enum class Kind(val rawValue: String) {
        CASH("現股"), MARGIN("融資"), SHORT("融券");

        companion object {
            fun of(rawValue: String): Kind? = entries.firstOrNull { it.rawValue == rawValue }
        }
    }

    /** What a cost figure is: the total paid, or a price per share (成本價、均價). */
    enum class Basis { TOTAL, PER_SHARE }

    data class Row(
        val symbol: String,
        val shares: Double? = null,
        val cost: Double? = null,
        /** The name the screenshot showed when it did not settle on one code; `choices` are the codes it may be. */
        val name: String? = null,
        val choices: List<String> = emptyList(),
        /** A hint for the user, such as a row cut off at a screenshot's edge. */
        val note: String? = null,
        val kind: Kind = Kind.CASH,
        /** What `cost` is, when its title said so. */
        val basis: Basis? = null,
    )

    /**
     * A row of the editable list the user checks before importing. Its cost is a total or, with `perShare`, a price per
     * share; `costNote` says why a cost read from the screenshot was not filled in.
     */
    data class Draft(
        val id: UUID = UUID.randomUUID(),
        val symbol: String = "",
        val shares: String = "",
        val cost: String = "",
        val perShare: Boolean = false,
        val kind: Kind = Kind.CASH,
        val seen: String = "",
        val choices: List<String> = emptyList(),
        val note: String? = null,
        val costNote: String? = null,
    ) {
        val shareCount: Double? get() = BrokerPreview.shareCount(shares)
        val costValue: Double? get() = BrokerPreview.number(cost)

        /** What this lot cost in all: the cost, or the price per share times the shares. */
        val totalCost: Double? get() {
            val count = shareCount ?: return null
            val value = costValue ?: return null
            return if (perShare) value * count else value
        }
        val averageCost: Double? get() {
            val count = shareCount ?: return null
            if (!(count > 0)) return null
            val total = totalCost ?: return null
            return total / count
        }

        companion object {
            /** `price` is the latest price, which tells a price per share from a total when the title did not say. */
            fun of(row: Row, price: Double? = null): Draft {
                val draft = Draft(symbol = row.symbol, shares = row.shares?.let(::plain) ?: "", kind = row.kind, seen = row.name ?: "", choices = row.choices, note = row.note)
                val read = row.cost ?: return draft
                val basis = row.basis ?: row.shares?.let { basis(read, it, price) }
                if (basis != null) return draft.copy(cost = plain(read), perShare = basis == Basis.PER_SHARE)
                val reason = if (price == null) "沒有現價可比對" else if (row.shares == null) "沒有股數可換算" else "當每股價格或總金額都跟現價對不起來"
                return draft.copy(costNote = "截圖讀到成本 ${plain(read)}，$reason，看不出是每股價格還是總金額，請確認後填入。")
            }

            private fun plain(value: Double): String =
                if (value == Math.rint(value) && Math.abs(value) < 1e15) value.toLong().toString() else swiftDescription(value)
        }
    }

    /**
     * A cost with no title saying what it is: a total when cost ÷ shares is near the latest price, a price per share when
     * the cost itself is; null when neither is, or there is no price to compare with.
     */
    fun basis(cost: Double, shares: Double, price: Double?): Basis? {
        if (price == null || !(price > 0) || !(shares > 0)) return null
        if (plausible(cost / shares, price)) return Basis.TOTAL
        if (plausible(cost, price)) return Basis.PER_SHARE
        return null
    }

    /** An average cost between 0.3 and 3 times the latest price. */
    fun plausible(average: Double, price: Double): Boolean = (average / price).let { it >= 0.3 && it <= 3.0 }

    /**
     * The stock and ETF lists by code and by name. Names are compared by Unicode scalar where iPhone compares by
     * Character; the two differ only for combining marks, which listed names do not have.
     */
    class Listing(entries: List<Pair<String, String>>) {
        private val codes = mutableSetOf<String>()
        private val byName = mutableMapOf<String, MutableList<String>>()
        private val names = mutableListOf<Pair<List<Int>, String>>()

        init {
            for ((code, name) in entries) {
                if (!DataChecks.code(code) || code in codes) continue
                codes.add(code)
                val key = key(name)
                if (key.isEmpty()) continue
                byName.getOrPut(key) { mutableListOf() }.add(code)
                names.add(key.codePoints().toArray().toList() to code)
            }
        }

        fun knows(code: String): Boolean = code in codes

        /** Codes whose name is exactly this, ignoring spaces, full-width letters and 臺／台. */
        fun exact(name: String): List<String> = byName[key(name)]?.toList() ?: emptyList()

        /** Codes whose name is one misread character away, or begins with this cut-off name: choices, never a match. */
        fun near(name: String): List<String> {
            val key = key(name).codePoints().toArray().toMutableList()
            while (key.isNotEmpty() && (key.last() == '…'.code || key.last() == '.'.code)) key.removeAt(key.size - 1)
            if (key.size < 3) return emptyList()
            return names.filter { (k, _) -> (k.size >= key.size && k.subList(0, key.size) == key) || (k.size >= 3 && oneEdit(key, k)) }
                .map { it.second }.take(8)
        }

        companion object {
            fun key(text: String): String {
                val out = StringBuilder()
                text.codePoints().forEach { scalar ->
                    if (isUnicodeWhiteSpace(scalar)) return@forEach
                    when (scalar) {
                        in 0xFF01..0xFF5E -> out.appendCodePoint(scalar - 0xFEE0)
                        0x81FA -> out.append('台')
                        else -> out.appendCodePoint(scalar)
                    }
                }
                return out.toString().uppercase()
            }

            /** One character replaced, added or left out. */
            private fun oneEdit(a: List<Int>, b: List<Int>): Boolean {
                if (a.size == b.size) return a.indices.count { a[it] != b[it] } == 1
                if (Math.abs(a.size - b.size) != 1) return false
                val short = if (a.size < b.size) a else b
                val long = if (a.size < b.size) b else a
                var i = 0
                var j = 0
                var skipped = false
                while (i < short.size && j < long.size) {
                    if (short[i] == long[j]) { i += 1; j += 1 } else if (skipped) return false else { skipped = true; j += 1 }
                }
                return true
            }
        }
    }

    private enum class Field { SHARES, LOTS, TOTAL, PER_SHARE, ANY_COST }

    /** Titles of a share count; a count in 張 (1,000 shares) is converted. */
    val shareLabels: Set<String> = setOf("股數", "庫存股數", "現股庫存", "持有股數", "現股股數", "集保股數", "集保庫存")
    val lotLabels: Set<String> = setOf("張數", "庫存張數", "持有張數", "現股張數")

    /** Titles of the total amount paid. */
    val costLabels: Set<String> = setOf("付出成本", "持有成本", "總成本", "成本金額", "投資成本", "成本總額")

    /** Titles of a price per share. 國泰證券's holdings screen calls the price paid per share 成交價. */
    val unitCostLabels: Set<String> = setOf(
        "成本價", "均價", "平均成本", "平均成本價", "成交均價", "買進均價", "持有均價", "成本均價", "平均價", "成本單價",
        "成交價", "成交單價", "成交價格", "買進價", "買入價", "買進單價",
    )

    /**
     * Language correction reads Chinese better but may "correct" codes and figures, so each screenshot is read both ways
     * and every word with a digit is taken from the uncorrected reading of the same place.
     */
    fun combine(corrected: List<TextBox>, raw: List<TextBox>): List<TextBox> = corrected.map { item ->
        val twin = raw.maxByOrNull { overlap(it.box, item.box) }
        if (twin == null || overlap(twin.box, item.box) < 0.5) return@map item
        val words = item.text.split(" ").filter { it.isNotEmpty() }
        val plain = twin.text.split(" ").filter { it.isNotEmpty() }
        if (words.size != plain.size) return@map if (hasDigit(twin.text)) TextBox(twin.text, item.box) else item
        TextBox(words.zip(plain).joinToString(" ") { (fixed, read) -> if (hasDigit(fixed) || hasDigit(read)) read else fixed }, item.box)
    }

    private fun overlap(a: Box, b: Box): Double {
        val shared = a.intersection(b) ?: return 0.0
        if (!(shared.width > 0) || !(shared.height > 0)) return 0.0
        val both = shared.width * shared.height
        return both / (a.width * a.height + b.width * b.height - both)
    }

    private fun hasDigit(word: String): Boolean = word.any { it in '0'..'9' || it in '０'..'９' }

    private class Line(val middle: Double, val height: Double, val items: MutableList<Pair<Double, String>>)

    /**
     * Groups recognised text boxes (Vision's normalised boxes, origin at the bottom left) into lines, top to bottom: a box
     * joins the line whose middle is nearest, if within half the smaller text height.
     */
    fun lines(boxes: List<TextBox>): List<String> {
        val rows = mutableListOf<Line>()
        for (item in boxes.sortedByDescending { it.box.midY }) {
            if (item.text.swiftTrim().isEmpty()) continue
            fun distance(i: Int) = Math.abs(rows[i].middle - item.box.midY)
            val near = rows.indices.filter { distance(it) < minOf(rows[it].height, item.box.height) / 2 }
            val i = near.minByOrNull { distance(it) }
            if (i != null) rows[i].items.add(item.box.minX to item.text)
            else rows.add(Line(item.box.midY, item.box.height, mutableListOf(item.box.minX to item.text)))
        }
        return rows.map { row -> row.items.sortedBy { it.first }.joinToString(" ") { it.second } }
    }

    /**
     * The lots in the order they appear. A listed code or name starts a lot; a share count or total cost is taken when its
     * title is beside it (付出成本 580,365) or above it in a row of titles. The same holding named again before any figure
     * (a card's title and its name line) is the same lot; after a figure it is the next lot.
     */
    fun parse(lines: List<String>, listing: Listing): List<Row> {
        val rows = mutableListOf<Row>()
        var current: Int? = null
        var header: List<Field?>? = null
        var headerFresh = false
        for (line in lines) {
            val words = tokens(line)
            if (words.isEmpty()) continue
            // Totals belong to no single lot.
            if (words.any { "合計" in it || "總計" in it || "小計" in it }) { current = null; headerFresh = false; continue }
            val found = holding(words, listing)
            if (found != null) {
                val row = Row(symbol = found.code ?: "", name = if (found.code == null) found.name else null, choices = found.choices)
                val continues = current?.let { rows[it].symbol == row.symbol && rows[it].name == row.name && rows[it].shares == null && rows[it].cost == null } ?: false
                if (!continues) { rows.add(row); current = rows.size - 1 }
            } else if (unlisted(words)) {
                current = null
            }
            // 融資 or 融券 written anywhere in a lot's lines marks that lot (融券 wins).
            fun mark() {
                val i = current ?: return
                val marked = kind(words) ?: return
                if (marked == Kind.SHORT || rows[i].kind == Kind.CASH) rows[i] = rows[i].copy(kind = marked)
            }
            val fields = words.map(::field)
            if (fields.any { it != null }) {
                var paired = false
                for (j in 0 until words.size - 1) {
                    val kind = fields[j] ?: continue
                    val value = amount(words[j + 1]) ?: continue
                    paired = true
                    current?.let { rows[it] = fill(rows[it], kind, value) }
                }
                // Titles with no value beside them head the values on the lines below.
                if (!paired && found == null) { header = fields; headerFresh = true } else headerFresh = false
                mark(); continue
            }
            // Under a row of titles: the line right below it, or a table row of its own. Values line up from the right,
            // since a name may take two words; a line shorter than the titles is left alone.
            val titles = header
            if (titles != null && words.size >= titles.size && (found != null || headerFresh || leadingName(words) != null)) {
                val offset = words.size - titles.size
                var figures = Row(symbol = "")
                for ((k, kind) in titles.withIndex()) {
                    if (kind == null || found?.words?.contains(k + offset) == true) continue
                    val value = amount(words[k + offset]) ?: continue
                    figures = fill(figures, kind, value)
                }
                if (found == null && !headerFresh) {
                    // A table row whose name fits nothing in the lists: its figures are kept, the code left to the user.
                    val name = leadingName(words)
                    if (figures.shares == null || name == null) { mark(); headerFresh = false; continue }
                    rows.add(Row(symbol = "", name = name)); current = rows.size - 1
                }
                current?.let { c ->
                    if (rows[c].shares == null) rows[c] = rows[c].copy(shares = figures.shares)
                    figures.cost?.let { cost -> rows[c] = setCost(rows[c], cost, figures.basis) }
                }
            }
            mark(); headerFresh = false
        }
        return rows
    }

    data class Reviewed(val rows: List<Row>, val short: List<Row>)

    /**
     * All screenshots' lots for review. A long list is captured in several overlapping screenshots, so a row that matches
     * an earlier screenshot's row exactly (code, shares, cost and kind) is that row again and appears once; rows within one
     * screenshot are separate lots and are all kept. A row with a figure missing that fits a fuller row of another
     * screenshot is probably cut off at the edge, and says so. 融券 rows are returned apart.
     */
    fun review(pages: List<List<Row>>): Reviewed {
        val result = mutableListOf<Row>()
        val page = mutableListOf<Int>()
        for ((number, rows) in pages.withIndex()) {
            val matched = mutableSetOf<Int>()
            for (row in rows) {
                val i = result.indices.firstOrNull { page[it] < number && it !in matched && result[it] == row }
                if (i != null) { matched.add(i); continue }
                result.add(row); page.add(number)
            }
        }
        for (i in result.indices) {
            if (result[i].shares != null && result[i].cost != null) continue
            if (result.indices.any { page[it] != page[i] && covers(result[it], result[i]) }) {
                result[i] = result[i].copy(note = "這一列可能是截圖邊緣只拍到一部分的重複列；若與其他列是同一批，請刪除。")
            }
        }
        return Reviewed(result.filter { it.kind != Kind.SHORT }, result.filter { it.kind == Kind.SHORT })
    }

    /** `full` is the same lot as `part` with more of its figures read. */
    private fun covers(full: Row, part: Row): Boolean =
        full.symbol == part.symbol && full.name == part.name && full.kind == part.kind &&
            (part.shares == null || part.shares == full.shares) && (part.cost == null || (part.cost == full.cost && part.basis == full.basis)) &&
            listOfNotNull(full.shares, full.cost).size > listOfNotNull(part.shares, part.cost).size

    /** 融券 when a lot's text says 融券, 券賣 or a lone 券; 融資 when it says 融資, 資買 or a lone 資. */
    private fun kind(words: List<String>): Kind? {
        if (words.any { "融券" in it || "券賣" in it || it == "券" }) return Kind.SHORT
        if (words.any { "融資" in it || "資買" in it || it == "資" }) return Kind.MARGIN
        return null
    }

    /** The holding a line names; `words` are the indices of the words naming it. */
    private class Found(val words: IntRange, val code: String?, val name: String, val choices: List<String>)

    /** A listed code, else a listed name of up to three words (the longest first), else names one misread character away, offered as choices. */
    private fun holding(words: List<String>, listing: Listing): Found? {
        val upper = words.map { it.uppercase() }
        upper.indices.firstOrNull { DataChecks.code(upper[it]) && listing.knows(upper[it]) }?.let { return Found(it..it, upper[it], "", emptyList()) }
        val parts = words.map(::namePart)
        for (i in words.indices) {
            for (count in minOf(3, words.size - i) downTo 1) {
                val piece = parts.subList(i, i + count)
                if (piece.any { it == null }) continue
                val name = piece.filterNotNull().joinToString("")
                val codes = listing.exact(name)
                if (codes.size == 1) return Found(i until i + count, codes[0], name, emptyList())
                if (codes.size > 1) return Found(i until i + count, null, name, codes)
            }
        }
        for (i in words.indices) {
            val word = parts[i] ?: continue
            if (ideographs(word) < 2) continue
            val near = listing.near(word)
            if (near.isNotEmpty()) return Found(i..i, null, word, near)
        }
        return null
    }

    private val bracketNote = Regex("[(（][^)）]*[)）]$")

    /**
     * A word that may be part of a name: not a title, amount, code, kind, signed figure or percentage. A trailing note in
     * brackets, as in 台積電(現股), is dropped.
     */
    private fun namePart(word: String): String? {
        if (field(word) != null || amount(word) != null || DataChecks.code(word.uppercase()) || kind(listOf(word)) != null || word == "現股" ||
            "," in word || "%" in word || word.startsWith("+") || word.startsWith("-")) return null
        return bracketNote.replace(word, "")
    }

    /** The words before a line's figures, when they read as a name (two or more Chinese characters). */
    private fun leadingName(words: List<String>): String? {
        val name = words.takeWhile { namePart(it) != null }.mapNotNull(::namePart).joinToString("")
        return if (ideographs(name) >= 2) name else null
    }

    private fun ideographs(text: String): Int = text.codePoints().filter { Character.isIdeographic(it) }.count().toInt()

    /** ICU's patterns as iPhone writes them; Java spells the Han script \p{IsHan} and needs Unicode classes for \s. */
    private fun icu(pattern: String): Regex = Pattern.compile(pattern.replace("\\p{Han}", "\\p{IsHan}"), Pattern.UNICODE_CHARACTER_CLASS).toRegex()

    private val rewrites: List<Pair<Regex, String>> by lazy {
        val labels = (shareLabels + lotLabels + costLabels + unitCostLabels + setOf("成本")).sortedByDescending { it.length }.joinToString("|")
        listOf(
            icu("[(（]([0-9]{4,6}[A-Z]?)[)）]") to " $1 ", // 台積電(2330)
            icu("\\s+(?=[(（])") to "", // 付出成本 (元)
            icu("(?<![0-9,.])([0-9]{4,6}[A-Z]?)(?=\\p{Han})(?![股張])(?!元(?!大))") to "$1 ", // 2330台積電, 0050元大台灣50
            icu("(?<=\\p{Han})(?=[0-9]{4,6}[A-Z]?(?![0-9,.]))") to " ", // 台積電2330
            icu("($labels)((?:[(（][^)）]*[)）])?)(?=[0-9])") to "$1$2 ", // 股數1,000
        )
    }

    /** The words of a line, with full-width digits and punctuation made plain and codes split from names. */
    private fun tokens(line: String): List<String> {
        val plain = StringBuilder()
        line.codePoints().forEach { scalar ->
            when (scalar) {
                in 0xFF10..0xFF19 -> plain.appendCodePoint(scalar - 0xFF10 + 0x30)
                0xFF08 -> plain.append('(')
                0xFF09 -> plain.append(')')
                0xFF0C -> plain.append(',')
                0xFF0E -> plain.append('.')
                0x3A, 0xFF1A, 0x3000 -> plain.append(' ')
                else -> plain.appendCodePoint(scalar)
            }
        }
        var text = plain.toString()
        for ((pattern, template) in rewrites) text = pattern.replace(text, template)
        val words = mutableListOf<String>()
        val word = StringBuilder()
        text.codePoints().forEach { scalar ->
            if (isUnicodeWhiteSpace(scalar)) {
                if (word.isNotEmpty()) { words.add(word.toString()); word.clear() }
            } else word.appendCodePoint(scalar)
        }
        if (word.isNotEmpty()) words.add(word.toString())
        return words
    }

    /** What a title labels; a unit in brackets such as (張) is read too. */
    private fun field(word: String): Field? {
        var title = word
        var inLots = false
        bracketNote.find(title)?.let { unit -> inLots = "張" in unit.value; title = title.removeRange(unit.range) }
        if (title in costLabels) return Field.TOTAL
        if (title in unitCostLabels) return Field.PER_SHARE
        if (title == "成本") return Field.ANY_COST
        if (title in lotLabels) return Field.LOTS
        if (title in shareLabels) return if (inLots) Field.LOTS else Field.SHARES
        return null
    }

    private class Amount(val number: Double, val lots: Boolean)

    private val plainAmount = Regex("^([0-9]{1,3}(,[0-9]{3})+|[0-9]+)(\\.[0-9]+)?$")

    /** A plain amount such as 1,000 or 580,365; signed figures and percentages are gains, not holdings. */
    private fun amount(word: String): Amount? {
        var text = word
        var lots = false
        if (text.endsWith("張")) { lots = true; text = text.dropLast(1) } else if (text.endsWith("股") || text.endsWith("元")) text = text.dropLast(1)
        if (!plainAmount.matches(text)) return null
        val number = text.replace(",", "").toDoubleOrNull() ?: return null
        return if (number.isFinite()) Amount(number, lots) else null
    }

    /**
     * A code missing from the lists beside a company name: a holding the app cannot import, so the figures after it must
     * not go to the holding before it.
     */
    private fun unlisted(words: List<String>): Boolean = words.indices.take(2).any { i ->
        DataChecks.code(words[i].uppercase()) && listOf(i - 1, i + 1).any { j ->
            j in words.indices && field(words[j]) == null && ideographs(words[j]) >= 2
        }
    }

    private fun fill(row: Row, kind: Field, value: Amount): Row = when (kind) {
        Field.TOTAL -> setCost(row, value.number, Basis.TOTAL)
        Field.PER_SHARE -> setCost(row, value.number, Basis.PER_SHARE)
        Field.ANY_COST -> setCost(row, value.number, null)
        Field.SHARES, Field.LOTS -> {
            val shares = value.number * (if (kind == Field.LOTS || value.lots) 1000 else 1)
            if (row.shares == null && shares > 0 && shares == Math.rint(shares)) row.copy(shares = shares) else row
        }
    }

    /** A total read under its title beats a price per share, which beats a cost whose title does not say which; of equal standing the first is kept. */
    private fun setCost(row: Row, cost: Double, basis: Basis?): Row {
        fun standing(b: Basis?) = when (b) { Basis.TOTAL -> 3; Basis.PER_SHARE -> 2; null -> 1 }
        return if (row.cost == null || standing(basis) > standing(row.basis)) row.copy(cost = cost, basis = basis) else row
    }
}
