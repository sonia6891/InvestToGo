package com.sonia.etftogo.core.models

import com.sonia.etftogo.core.support.AppDataError
import com.sonia.etftogo.core.support.decimal
import java.time.Instant
import java.time.ZonedDateTime
import com.sonia.etftogo.core.support.TAIPEI
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** `AlertEngine` and `Portfolio.alerts`: 到價提醒. */
class PriceAlertTests {
    private fun alert(price: Double, symbol: String = "0050", above: Boolean = true, enabled: Boolean = true) =
        PriceAlert(symbol = symbol, above = above, price = price, enabled = enabled)

    @Test fun aboveFiresAtOrOver() {
        val watch = alert(100.0, above = true)
        assertEquals(listOf(watch.id), AlertEngine.due(listOf(watch), mapOf("0050" to 100.0), true), "At the target counts")
        assertEquals(listOf(watch.id), AlertEngine.due(listOf(watch), mapOf("0050" to 100.5), true))
        assertEquals(emptyList(), AlertEngine.due(listOf(watch), mapOf("0050" to 99.9), true))
    }

    @Test fun belowFires() {
        val watch = alert(50.0, above = false)
        assertEquals(listOf(watch.id), AlertEngine.due(listOf(watch), mapOf("0050" to 49.0), true))
        assertEquals(listOf(watch.id), AlertEngine.due(listOf(watch), mapOf("0050" to 50.0), true), "At the target counts")
        assertEquals(emptyList(), AlertEngine.due(listOf(watch), mapOf("0050" to 50.01), true))
    }

    @Test fun firedAlertDoesNotRepeat() {
        var (data, watch) = Portfolio().addAlert("0050", true, 100.0)
        val prices = mapOf("0050" to 120.0)
        val due = AlertEngine.due(data.alerts ?: emptyList(), prices, true)
        assertEquals(listOf(watch.id), due)
        val now = Instant.ofEpochSecond(1_800_000_000)
        val (after, fired) = data.fireAlerts(due, now)
        data = after
        assertEquals(due, fired.map { it.id })
        assertEquals(false, data.alerts?.first()?.enabled, "Fired once, then switched off")
        assertEquals(now, data.alerts?.first()?.firedAt)
        assertEquals(emptyList(), AlertEngine.due(data.alerts ?: emptyList(), prices, true), "The price is still over: no second notice")
        data = data.copy(alerts = data.alerts!!.mapIndexed { i, a -> if (i == 0) a.copy(enabled = true) else a })
        assertEquals(due, AlertEngine.due(data.alerts ?: emptyList(), prices, true))
    }

    @Test fun nonMemberNeverFires() {
        val list = listOf(alert(100.0, above = true), alert(20.0, "00878", above = false))
        val prices = mapOf("0050" to 150.0, "00878" to 18.0)
        assertEquals(emptyList(), AlertEngine.due(list, prices, false))
        assertEquals(list.map { it.id }, AlertEngine.due(list, prices, true))
    }

    @Test fun missingPriceSkipped() {
        val known = alert(100.0, above = true)
        val unknown = alert(20.0, "00878", above = false)
        assertEquals(listOf(known.id), AlertEngine.due(listOf(unknown, known), mapOf("0050" to 100.0), true))
        assertEquals(emptyList(), AlertEngine.due(listOf(unknown), emptyMap(), true))
        assertEquals(emptyList(), AlertEngine.due(listOf(unknown), mapOf("00878" to 0.0), true))
        assertEquals(emptyList(), AlertEngine.due(listOf(unknown), mapOf("00878" to Double.NaN), true))
    }

    @Test fun limitTwentyAndNoTwins() {
        assertEquals(20, AlertEngine.limit)
        var data = Portfolio()
        for (i in 1..20) data = data.addAlert("0050", true, (100 + i).toDouble()).first
        assertEquals(20, data.alerts?.size)
        val full = assertFailsWith<AppDataError> { data.addAlert("0056", true, 40.0) }
        assertEquals("最多 20 個提醒，請先刪除不用的。", full.text)
        var other = Portfolio().addAlert("0050", true, 200.0).first
        val twin = assertFailsWith<AppDataError> { other.addAlert("0050", true, 200.0) }
        assertEquals("已經有一樣的提醒。", twin.text)
        other = other.addAlert("0050", false, 200.0).first
        assertFailsWith<AppDataError> { other.addAlert("0050", true, 0.0) }
        assertFailsWith<AppDataError> { other.addAlert("0050", true, Double.NEGATIVE_INFINITY) }
        assertFailsWith<AppDataError> { other.addAlert("not a code", true, 10.0) }
        assertEquals(2, other.alerts?.size)
    }

    @Test fun watchingNeedsAnEnabledAlertAndAMember() {
        assertFalse(AlertEngine.watching(emptyList(), true))
        assertFalse(AlertEngine.watching(listOf(alert(100.0, enabled = false)), true))
        assertFalse(AlertEngine.watching(listOf(alert(100.0)), false))
        assertTrue(AlertEngine.watching(listOf(alert(100.0, enabled = false), alert(120.0)), true))
    }

    @Test fun onlyARecentPriceIsJudged() {
        val now = ZonedDateTime.of(2026, 11, 14, 12, 0, 0, 0, TAIPEI).toInstant()
        assertTrue(AlertEngine.isCurrent("2026-11-14", now))
        assertTrue(AlertEngine.isCurrent("2026-11-13", now))
        assertTrue(AlertEngine.isCurrent("2026-11-07", now))
        assertFalse(AlertEngine.isCurrent("2026-11-06", now))
        assertFalse(AlertEngine.isCurrent("2026-08-01", now))
        assertFalse(AlertEngine.isCurrent("", now))
        assertFalse(AlertEngine.isCurrent("20261114", now))
    }

    @Test fun messageSaysTheCodeThePriceAndTheTarget() {
        val up = AlertEngine.message(alert(200.0, above = true), 205.5)
        assertEquals("0050 已到 ${decimal(205.5)}，你設定的是高於 ${decimal(200.0)}。", up)
        val down = AlertEngine.message(alert(18.5, "00878", above = false), 18.2)
        assertEquals("00878 已到 ${decimal(18.2)}，你設定的是低於 ${decimal(18.5)}。", down)
        for (word in listOf("買", "賣", "建議", "進場", "出場", "機會")) assertFalse(word in up || word in down, "No advice: $word")
        assertEquals("高於 ${decimal(200.0)}", alert(200.0, above = true).condition)
        assertEquals("低於 ${decimal(18.5)}", alert(18.5, above = false).condition)
    }

    @Test fun filesWithAndWithoutAlertsDecode() {
        assertNull(Portfolio.decodeBackup("""{"schema":1,"holdings":[],"dividends":[],"favorites":[],"quotes":{}}""".toByteArray()).alerts)
        var data = Portfolio().addAlert("0050", true, 200.0).first
        val (withSecond, second) = data.addAlert("00679B", false, 27.5)
        data = withSecond.fireAlerts(listOf(second.id), Instant.ofEpochSecond(1_800_000_000)).first
        val back = Portfolio.decodeBackup(data.encode())
        assertEquals(data.alerts, back.alerts)
        assertEquals(listOf(true, false), back.alerts?.map { it.enabled })
        val bare = """{"schema":1,"holdings":[],"dividends":[],"favorites":[],"quotes":{},"alerts":[{"id":"11111111-2222-3333-4444-555555555555","symbol":"0050","above":true,"price":200,"enabled":true}]}"""
        val read = Portfolio.decodeBackup(bare.toByteArray())
        assertEquals("0050", read.alerts?.first()?.symbol)
        assertNull(read.alerts?.first()?.firedAt)
    }

    @Test fun backupRejectsBadAlerts() {
        fun encoded(alerts: List<PriceAlert>) = Portfolio(alerts = alerts).encode()
        Portfolio.decodeBackup(encoded(listOf(alert(200.0), alert(20.0, "00878", above = false))))
        assertFailsWith<StoreError> { Portfolio.decodeBackup(encoded(listOf(alert(200.0, "abc")))) }
        assertFailsWith<StoreError> { Portfolio.decodeBackup(encoded(listOf(alert(0.0)))) }
        assertFailsWith<StoreError> { Portfolio.decodeBackup(encoded(listOf(alert(2_000_000.0)))) }
        val twin = alert(200.0)
        assertFailsWith<StoreError> { Portfolio.decodeBackup(encoded(listOf(twin, twin))) }
        assertFailsWith<StoreError> { Portfolio.decodeBackup(encoded((1..21).map { alert(it.toDouble()) })) }
    }

    @Test fun mergeKeepsWhatIsHereAndStopsAtTheLimit() {
        val (start, mine) = Portfolio().addAlert("0050", true, 200.0)
        val theirs = mine.copy(enabled = false)
        val extra = (1..25).map { alert(it.toDouble(), "0056", above = false) }
        val data = start.mergeAlerts(listOf(theirs) + extra)
        assertEquals(20, data.alerts?.size)
        assertEquals(theirs, data.alerts?.first(), "The backup's copy of a known alert replaces it")
        assertEquals(extra.take(19).map { it.id }, data.alerts?.drop(1)?.map { it.id })
        Portfolio.decodeBackup(data.encode())
        assertNull(Portfolio().mergeAlerts(emptyList()).alerts, "Nothing to merge leaves an older file as it was")
    }
}
