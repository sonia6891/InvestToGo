package com.sonia.etftogo.core.support

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.time.format.ResolverStyle

/** Taiwan's zone: every calendar day the app stores is a Taipei day (PocketCore's `TaiwanMarket.zone`). */
val TAIPEI: ZoneId = ZoneId.of("Asia/Taipei")

/** Port of PocketCore `DataChecks`. */
object DataChecks {
    private val codePattern = Regex("^[0-9]{4,6}[A-Z]?$")
    private val formatter: DateTimeFormatter = DateTimeFormatter.ofPattern("uuuu-MM-dd").withResolverStyle(ResolverStyle.STRICT)

    fun code(value: String): Boolean = codePattern.matches(value)

    /** `yyyy-MM-dd` of the instant in Taipei. */
    fun day(at: Instant = Instant.now()): String = formatter.format(at.atZone(TAIPEI))

    /** The start of that Taipei day, only when [text] is exactly a real `yyyy-MM-dd` date. */
    fun date(text: String): Instant? {
        val parsed = try { LocalDate.parse(text, formatter) } catch (_: DateTimeParseException) { return null }
        val value = parsed.atStartOfDay(TAIPEI).toInstant()
        return if (day(value) == text) value else null
    }

    /**
     * A 民國 `1151110` (seven digits) or western `20261110` (eight) date as `yyyy-MM-dd`; separators and labels are dropped.
     * A number written in any other script (全形數字, 一二三) makes the text unreadable, as on iPhone, where `isNumber`
     * keeps such characters and the result then fails to parse.
     */
    fun rocDay(text: String): String? {
        if (text.any { it.code > 127 && isNumberLike(it) }) return null
        val raw = text.filter { it in '0'..'9' }
        if (raw.length != 7 && raw.length != 8) return null
        val year = raw.dropLast(4).toInt() + if (raw.length == 7) 1911 else 0
        val value = "$year-${raw.dropLast(2).takeLast(2)}-${raw.takeLast(2)}"
        return if (date(value) == null) null else value
    }

    private const val CHINESE_NUMERALS = "〇零一二三四五六七八九十百千萬万億亿兩两壹貳贰參叁肆伍陸陆柒捌玖拾佰仟廿卅"

    private fun isNumberLike(c: Char): Boolean = when (Character.getType(c).toByte()) {
        Character.DECIMAL_DIGIT_NUMBER, Character.LETTER_NUMBER, Character.OTHER_NUMBER -> true
        else -> c in CHINESE_NUMERALS
    }

    /** JSON array rows; a UTF-8 byte-order mark is dropped first. Null when the bytes are not an array of objects. */
    fun jsonRows(bytes: ByteArray): List<JsonObject>? {
        val bom = bytes.size >= 3 && bytes[0] == 0xEF.toByte() && bytes[1] == 0xBB.toByte() && bytes[2] == 0xBF.toByte()
        val data = if (bom) bytes.copyOfRange(3, bytes.size) else bytes
        val element = try { CoreJson.json.parseToJsonElement(data.decodeToString(throwOnInvalidSequence = true)) } catch (_: Exception) { return null }
        val array = element as? JsonArray ?: return null
        return array.map { it as? JsonObject ?: return null }
    }
}
