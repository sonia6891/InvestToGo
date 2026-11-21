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

private val swiftHex = Regex("""^[+-]?0[xX](?:[0-9a-fA-F]+\.?[0-9a-fA-F]*|\.[0-9a-fA-F]+)(?:[pP][+-]?[0-9]+)?$""")

/**
 * Swift's `Double(String)`: a plain decimal, a hexadecimal float (0x10, 0x1.8p1) or inf / nan, with nothing around it.
 * Kotlin's `toDoubleOrNull` also takes "5d", "5f" and surrounding whitespace, which Swift refuses.
 */
fun swiftDouble(text: String): Double? {
    if (swiftDecimal.matches(text)) return text.toDouble()
    // Java reads a hexadecimal float only with its binary exponent written out.
    if (swiftHex.matches(text)) return (if (text.contains('p', ignoreCase = true)) text else text + "p0").toDouble()
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

/** Unicode White_Space, Swift's `Unicode.Scalar.Properties.isWhitespace` and `Character.isWhitespace`. */
fun isUnicodeWhiteSpace(codePoint: Int): Boolean = codePoint in 0x09..0x0D || codePoint == 0x85 || Character.isSpaceChar(codePoint)

/**
 * Swift's `String(Double)`: the shortest digits that name the double, written plainly from 1e-4 up to 1e16 and with an
 * exponent (1e+16, 1e-05) outside that, "nan" and "inf" for the rest.
 */
fun swiftDescription(value: Double): String {
    if (value.isNaN()) return "nan"
    if (value.isInfinite()) return if (value > 0) "inf" else "-inf"
    if (value == 0.0) return if (1 / value < 0) "-0.0" else "0.0"
    val exact = java.math.BigDecimal(value.toString()).stripTrailingZeros()
    val magnitude = Math.abs(value)
    if (magnitude >= 1e16 || magnitude < 1e-4) {
        val digits = exact.unscaledValue().abs().toString()
        val exponent = digits.length - 1 - exact.scale()
        val mantissa = digits.take(1) + (if (digits.length > 1) "." + digits.drop(1) else "")
        val sign = if (exponent < 0) "-" else "+"
        return (if (value < 0) "-" else "") + mantissa + "e" + sign + "%02d".format(Math.abs(exponent))
    }
    val text = exact.toPlainString()
    return if ('.' in text) text else "$text.0"
}
