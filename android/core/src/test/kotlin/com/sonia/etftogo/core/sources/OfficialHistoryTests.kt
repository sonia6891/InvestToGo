package com.sonia.etftogo.core.sources

import com.sonia.etftogo.core.Fixtures
import com.sonia.etftogo.core.game.YearMonth
import com.sonia.etftogo.core.support.AppDataError
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class OfficialHistoryTests {
    private fun fx(n: String) = Fixtures.bytes("member/official/$n")
    private fun json(s: String) = s.toByteArray()

    @Test fun rocDates() {
        assertEquals("2025-06-18", OfficialHistory.rocDate("114/06/18"))
        assertEquals("2025-01-17", OfficialHistory.rocDate("114年01月17日"))
        assertNull(OfficialHistory.rocDate("abc"))
    }

    @Test fun twseMonth() {
        val bars = OfficialHistory.twseMonth(fx("A_twse_STOCK_DAY_0050_202506.json"))
        assertEquals(4, bars.size)
        assertEquals(DailyBar("2025-06-02", 175.90), bars.first())
        assertTrue(DailyBar("2025-06-10", 188.65) in bars)
        assertEquals(emptyList(), OfficialHistory.twseMonth(json("{\"stat\":\"很抱歉，沒有符合條件的資料!\"}")))
    }

    @Test fun tpexMonth() {
        val bars = OfficialHistory.tpexMonth(fx("B_tpex_tradingStock_00679B_202506.json"))
        assertEquals(3, bars.size)
        assertEquals(DailyBar("2025-06-02", 25.21), bars.first())
        assertEquals(emptyList(), OfficialHistory.tpexMonth(json("{\"stat\":\"ok\",\"tables\":[{\"data\":[],\"fields\":[]}]}")))
    }

    @Test fun twseDividends() {
        val ev = OfficialHistory.twseDividends(fx("C_twse_TWT49U_2025_sample.json"))
        assertTrue(DividendEvent("0050", "2025-01-17", 2.7) in ev)
        assertTrue(DividendEvent("00878", "2025-02-20", 0.5) in ev)
    }

    @Test fun tpexDividends() {
        assertEquals(DividendEvent("00937B", "2025-01-22", 0.082), OfficialHistory.tpexDividends(fx("C_tpex_exDailyQ_2025_sample.json")).first())
    }

    @Test fun splits() {
        val ev = OfficialHistory.splits(fx("D_twse_TWTCAU_2015_2026.json"))
        assertEquals(12, ev.size)
        val s50 = assertNotNull(ev.firstOrNull { it.symbol == "0050" })
        assertEquals("2025-06-18", s50.resumeDate)
        assertEquals(4.0, s50.ratio)
        val r = assertNotNull(ev.firstOrNull { it.symbol == "00632R" })
        assertEquals(1.0 / 7.0, r.ratio, 1e-9)
    }

    @Test fun suspectedSplitFlagged() {
        val bars = listOf(DailyBar("2025-06-17", 100.0), DailyBar("2025-06-18", 25.0))
        assertEquals(listOf("2025-06-18"), OfficialHistory.suspectedSplits(bars, emptyList(), emptyList()))
        assertEquals(emptyList(), OfficialHistory.suspectedSplits(bars, emptyList(), listOf(SplitEvent("0050", "2025-06-18", 4.0))))
    }

    @Test fun urls() {
        val m = YearMonth(2025, 6)
        assertEquals("https://www.twse.com.tw/rwd/zh/afterTrading/STOCK_DAY?date=20250601&stockNo=0050&response=json", OfficialHistory.twseMonthURL("0050", m).toString())
        assertTrue(OfficialHistory.tpexMonthURL("00679B", m).toString().contains("date=2025/06/01"))
    }

    @Test fun malformedResponsesThrow() {
        val bodies: List<() -> Any> = listOf(
            { OfficialHistory.twseMonth(json("{\"stat\":\"查詢日期錯誤\"}")) },
            { OfficialHistory.twseDividends(json("{\"stat\":\"error\"}")) },
            { OfficialHistory.splits(json("{\"stat\":\"error\"}")) },
            { OfficialHistory.tpexMonth(json("{\"stat\":\"ok\"}")) },
            { OfficialHistory.tpexDividends(json("{\"stat\":\"ok\"}")) },
            { OfficialHistory.tpexMonth(json("{\"tables\":[{\"fields\":[]}]}")) },
            { OfficialHistory.twseMonth(json("{\"stat\":\"OK\",\"fields\":[\"Date\",\"Close\"],\"data\":[[\"114/06/02\",\"1\"]]}")) },
            { OfficialHistory.tpexMonth(json("{\"tables\":[{\"fields\":[\"d\",\"c\"],\"data\":[[\"114/06/02\",\"1\"]]}]}")) },
            { OfficialHistory.twseDividends(json("{\"stat\":\"OK\",\"fields\":[\"x\"],\"data\":[[\"1\"]]}")) },
            { OfficialHistory.splits(json("{\"stat\":\"OK\",\"fields\":[\"x\"],\"data\":[[\"1\"]]}")) },
            { OfficialHistory.twseMonth(json("{\"stat\":\"OK\",\"fields\":[\"日期\",\"收盤價\"],\"data\":[[\"bad\",\"--\"]]}")) },
            { OfficialHistory.tpexMonth(json("{\"tables\":[{\"fields\":[\"日 期\",\"收盤\"],\"data\":[[\"bad\",\"--\"]]}]}")) },
            { OfficialHistory.tpexDividends(json("{\"tables\":[{\"fields\":[\"除權息日期\",\"代號\",\"現金股利\"],\"data\":[[\"bad\",\"1\",\"x\"]]}]}")) },
            { OfficialHistory.splits(json("{\"stat\":\"OK\",\"fields\":[\"恢復買賣日期\",\"ETF代號\",\"停止買賣前收盤價格\",\"恢復買賣參考價\"],\"data\":[[\"bad\",\"0050\",\"x\",\"y\"]]}")) },
        )
        bodies.forEachIndexed { i, body -> assertFailsWith<AppDataError>("body $i") { body() } }
    }

    @Test fun genuineEmptyResponsesAreEmpty() {
        assertEquals(emptyList(), OfficialHistory.twseMonth(json("{\"stat\":\"很抱歉，沒有符合條件的資料!\"}")))
        assertEquals(emptyList(), OfficialHistory.tpexMonth(json("{\"stat\":\"ok\",\"tables\":[{\"data\":[]}]}")))
    }

    /** Swift's `Double(String)` refuses what Kotlin's `toDoubleOrNull` takes: "5d" is not a close. */
    @Test fun closesAreReadAsSwiftReadsThem() {
        val body = json("{\"stat\":\"OK\",\"fields\":[\"日期\",\"收盤價\"],\"data\":[[\"114/06/02\",\"5d\"],[\"114/06/03\",\" 1,180.5 \"]]}")
        assertEquals(listOf(DailyBar("2025-06-03", 1180.5)), OfficialHistory.twseMonth(body))
    }
}
