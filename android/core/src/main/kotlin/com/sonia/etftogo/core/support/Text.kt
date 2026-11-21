package com.sonia.etftogo.core.support

import java.text.BreakIterator
import java.text.Normalizer
import java.util.UUID

/** Unicode NFC, Swift's `precomposedStringWithCanonicalMapping`: compatibility ideographs become the unified characters. */
val String.nfc: String get() = Normalizer.normalize(this, Normalizer.Form.NFC)

/** Swift's `String.count`: user-perceived characters, not UTF-16 units, so length limits match iPhone's. */
val String.charCount: Int get() {
    if (all { it.code < 0x300 }) return length
    val iterator = BreakIterator.getCharacterInstance().also { it.setText(this) }
    var count = 0
    while (iterator.next() != BreakIterator.DONE) count++
    return count
}

private val uuidPattern = Regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")

/** Swift's `UUID(uuidString:)`: only the 8-4-4-4-12 hex form, in either case; null for anything else. */
fun parseUUID(text: String): UUID? = if (uuidPattern.matches(text)) UUID.fromString(text) else null

private fun isSwiftWhitespace(c: Char): Boolean = c == '\t' || Character.getType(c) == Character.SPACE_SEPARATOR.toInt()

private fun isSwiftNewline(c: Char): Boolean = c in '\u000A'..'\u000D' || c == '\u0085' || c == ' ' || c == ' '

/** Swift's `trimmingCharacters(in: .whitespaces)`: spaces (Unicode Zs, so also U+00A0) and tabs, not newlines. */
fun String.swiftTrim(): String = trim(::isSwiftWhitespace)

/** Swift's `trimmingCharacters(in: .whitespacesAndNewlines)`. */
fun String.swiftTrimAll(): String = trim { isSwiftWhitespace(it) || isSwiftNewline(it) }

/** Removes every character of `.whitespacesAndNewlines`, as `components(separatedBy:).joined()` does. */
fun String.swiftStripAll(): String = filterNot { isSwiftWhitespace(it) || isSwiftNewline(it) }

private val swiftDecimal = Regex("""^[+-]?(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$""")
private val swiftSpecial = Regex("^[+-]?(?:inf|infinity|nan)$", RegexOption.IGNORE_CASE)

/**
 * Swift's `Double(String)`: a plain decimal (or inf / nan) with nothing around it. Kotlin's `toDoubleOrNull` also takes
 * "5d", "5f" and surrounding whitespace, which Swift refuses. Hexadecimal floats are not read.
 */
fun swiftDouble(text: String): Double? {
    if (swiftDecimal.matches(text)) return text.toDouble()
    if (!swiftSpecial.matches(text)) return null
    val negative = text.startsWith("-")
    return when {
        text.contains("nan", ignoreCase = true) -> Double.NaN
        negative -> Double.NEGATIVE_INFINITY
        else -> Double.POSITIVE_INFINITY
    }
}

private val swiftInteger = Regex("^[+-]?[0-9]+$")

/** Swift's `Int(String)`: ASCII digits with an optional sign; null on overflow. */
fun swiftInt(text: String): Int? = if (swiftInteger.matches(text)) text.toIntOrNull() else null
