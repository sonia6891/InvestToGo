package com.sonia.etftogo.core.support

import java.math.RoundingMode
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.time.Instant
import java.time.ZoneId
import java.util.Locale

// Number and date text shared by screens and the logic that builds labels; port of PocketCore Formatters.swift.
// iPhone formats with the device locale; the app is Traditional Chinese (Taiwan) only, so zh-TW is fixed here and the
// expected text in SharedFixtures/vectors/format is iPhone's zh-TW output. Rounding is half-even, like Foundation.
// Dates use the device zone, like iPhone's Calendar.current; the zone parameter exists for tests.

private val symbols: DecimalFormatSymbols = DecimalFormatSymbols.getInstance(Locale.TAIWAN)

private fun pattern(text: String): ThreadLocal<DecimalFormat> =
    ThreadLocal.withInitial { DecimalFormat(text, symbols).apply { roundingMode = RoundingMode.HALF_EVEN } }

private val moneyFormat = pattern("#,##0")
private val decimalFormat = pattern("#,##0.##")
private val priceFormat = pattern("#,##0.00")

/** DecimalFormat writes "-0" for a small negative that rounds to zero; Foundation writes "0". */
private fun clean(text: String): String =
    if (text.startsWith("-") && text.drop(1).all { it == '0' || it == '.' || it == ',' }) text.drop(1) else text

/**
 * iPhone's ICU rounds the shortest decimal that names the double (1.225 → "1.225" → 1.22), while DecimalFormat rounds the
 * exact binary value (1.2250000000000000888 → 1.23); going through the shortest text gives iPhone's answer.
 */
private fun DecimalFormat.icu(value: Double): String =
    clean(if (value.isFinite()) format(java.math.BigDecimal.valueOf(value)) else format(value))

fun money(value: Double): String = moneyFormat.get().icu(value)
fun decimal(value: Double): String = decimalFormat.get().icu(value)
fun priceText(value: Double): String = priceFormat.get().icu(value)
fun signed(value: Double, format: (Double) -> String = ::money): String =
    (if (value > 0) "+" else if (value < 0) "-" else "") + format(Math.abs(value))
fun percentText(value: Double): String = signed(value, ::decimal) + "%"
fun shown(text: String, hidden: Boolean): String = if (hidden) "＊＊＊＊" else text

private val weekdays = listOf("週一", "週二", "週三", "週四", "週五", "週六", "週日")

fun weekdayText(at: Instant, zone: ZoneId = ZoneId.systemDefault()): String = weekdays[at.atZone(zone).dayOfWeek.value - 1]

fun ymdText(at: Instant, zone: ZoneId = ZoneId.systemDefault()): String =
    at.atZone(zone).let { "%04d/%02d/%02d".format(Locale.ROOT, it.year, it.monthValue, it.dayOfMonth) }

/** Large totals in 萬 so they fit inside a donut. */
fun wanText(value: Double): String =
    if (Math.abs(value) >= 1_000_000) "${decimal(swiftRounded(value / 1000) / 10)}萬" else money(value)

fun monthDay(at: Instant, zone: ZoneId = ZoneId.systemDefault()): String =
    at.atZone(zone).let { "${it.monthValue}/${it.dayOfMonth}" }

/** Swift's `Double.rounded()`: halves away from zero (Kotlin's `round` is half-even). */
fun swiftRounded(value: Double): Double = if (value < 0) -Math.floor(-value + 0.5) else Math.floor(value + 0.5)

/**
 * Swift's `String(format: "%.Nf")`: C's printf rounds the double's exact binary value, ties to even (0.25 → "0.2"),
 * where Java's `%.1f` rounds its shortest decimal half up ("0.3"). Always "." as the decimal point, no grouping.
 */
fun cFixed(value: Double, digits: Int): String {
    if (!value.isFinite()) return if (value.isNaN()) "nan" else if (value > 0) "inf" else "-inf"
    val text = java.math.BigDecimal(value).setScale(digits, RoundingMode.HALF_EVEN).toPlainString()
    return if (value < 0 && text.trimStart('-').all { it == '0' || it == '.' } && !text.startsWith("-")) "-$text" else text
}
