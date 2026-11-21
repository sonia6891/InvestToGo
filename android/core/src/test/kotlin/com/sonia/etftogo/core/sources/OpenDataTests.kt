package com.sonia.etftogo.core.sources

import com.sonia.etftogo.core.Fixtures
import com.sonia.etftogo.core.models.Quote
import com.sonia.etftogo.core.support.CoreJson
import com.sonia.etftogo.core.support.DataChecks
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/** Official open-data parsing against real 2026-11-10/11 responses kept in SharedFixtures (shared with iPhone). */
class OpenDataTests {
    @Serializable
    data class Expected(val symbol: String, val price: Double, val date: String, val currency: String)

    private fun quotes(): Map<String, Quote> {
        val all = LinkedHashMap(OpenData.decodeTWSE(Fixtures.bytes("official/twse-stock-day-all.json")))
        for ((k, v) in OpenData.decodeTPEx(Fixtures.bytes("official/tpex-daily-close.json"))) all.putIfAbsent(k, v)
        return all
    }

    @Test fun etfClosesMatchSharedExpectation() {
        val all = quotes()
        val expected = CoreJson.decode(ListSerializer(Expected.serializer()), Fixtures.bytes("official/expected-quotes.json"))
        assertEquals(7, expected.size)
        for (e in expected) {
            val q = assertNotNull(all[e.symbol], e.symbol)
            assertEquals(e.price, q.price, e.symbol)
            assertEquals(e.date, q.date, e.symbol)
            assertEquals(e.currency, q.currency, e.symbol)
            assertEquals(OpenData.source, q.source)
        }
    }

    @Test fun noTradeRowsAreSkipped() {
        val all = quotes()
        assertNull(all["00625K"], "Empty ClosingPrice must not become a price")
        assertNull(all["00986B"], "TPEx ' ---' close must be skipped")
    }

    @Test fun openDataMarksCAndKAsForeign() {
        val all = quotes()
        assertEquals(false, all["00636K"]?.isTWD)
        assertEquals(false, all["00687C"]?.isTWD)
        assertEquals(true, all["00635U"]?.isTWD, "U suffix is a TWD-traded futures ETF")
        assertEquals(true, all["0050"]?.isTWD)
    }

    @Test fun closeIsStampedAtTheEndOfItsTradingDay() {
        val q = assertNotNull(quotes()["0050"])
        assertEquals(DataChecks.date("2026-11-10")!!.plusSeconds(13 * 3600 + 1800), q.fetchedAt, "A later live quote must win over the close")
    }

    @Test fun cashAmountsAndBlankAmount() {
        val events = OfficialDividends.decode(Fixtures.bytes("official/twse-twt48u.json"), "TWSE", mapOf("0051" to "TWSE", "00690" to "TWSE", "4562" to "TWSE"))
        assertEquals(listOf(OfficialDistribution("2026-11-17", "", 2.0)), events["00690"])
        assertEquals(listOf(OfficialDistribution("2026-11-20", "", null)), events["0051"], "A blank amount is unknown, not zero")
        assertNull(events["4562"], "A stock-dividend (權) notice is not a cash distribution")
        assertNull(events["01007T"], "Codes outside the catalogue are ignored")
    }

    @Test fun expectedDayIsTaipeiWhateverTheDeviceZone() {
        val saved = java.util.TimeZone.getDefault()
        try {
            java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("America/Los_Angeles"))
            assertEquals("2026-11-13", OpenData.expectedDay(java.time.Instant.parse("2026-11-15T23:30:00Z")))
        } finally {
            java.util.TimeZone.setDefault(saved)
        }
    }
}
