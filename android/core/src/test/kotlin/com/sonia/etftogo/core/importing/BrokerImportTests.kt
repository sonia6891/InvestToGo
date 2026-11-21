package com.sonia.etftogo.core.importing

import com.sonia.etftogo.core.models.Fund
import com.sonia.etftogo.core.support.AppDataError
import java.nio.charset.Charset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/** PortedAppTests' CSV tests: a broker's holdings file read into holdings. */
class BrokerImportTests {
    private fun csv(text: String) = CSVTable.parse(text.toByteArray())

    @Test fun trailingCellsShortRowsAndBadRowsAreSkippedNotFatal() {
        val table = csv("代碼,名稱,股數,總成本,\n0050,元大台灣50,1000,50000,\n00878,國泰永續高股息,abc,20000\n00919,群益台灣精選高息,1,000,22000\n合計,,,72000\n備註\n")
        assertEquals(listOf("代碼", "名稱", "股數", "總成本"), table.headers, "A trailing empty title cell is dropped")
        assertTrue(table.rows.all { it.size >= 4 }, "Short rows are padded")
        val p = BrokerPreview.make(table, BrokerMapping.guessing(table), "測試券商", "主要", Fund.starters)
        assertEquals(listOf("0050"), p.holdings.map { it.symbol })
        assertEquals(4, p.skipped.size)
        assertTrue("00878" in p.skipped[0] && "數量" in p.skipped[0])
        assertTrue("00919" in p.skipped[1] && "逗號" in p.skipped[1])
        assertEquals(setOf("00878", "00919"), p.skippedCodes)
        val error = assertFailsWith<AppDataError> {
            BrokerPreview.make(csv("代碼,股數,總成本\n合計,1,1"), BrokerMapping(0, -1, 1, 2), "測試券商", "主要", Fund.starters)
        }
        assertTrue("沒有可匯入" in error.text)
    }

    @Test fun quotedCommasNewlinesAndTrailingLine() {
        val table = csv("代碼,名稱,股數,總成本\r\n0050,\"台灣,50\",1000,\"50,000\"\r\n")
        assertEquals(1, table.rows.size)
        assertEquals("台灣,50", table.rows[0][1])
        val p = BrokerPreview.make(table, BrokerMapping(0, 1, 2, 3), "測試券商", "主要", Fund.starters)
        assertEquals(50.0, p.holdings[0].unitCost)
        assertEquals(50000.0, p.totalCost)
        assertFailsWith<AppDataError> { csv("a,b\n\"bad,x") }
    }

    @Test fun acceptsBOMBeforeQuotedHeader() {
        val table = csv("﻿\"code\",shares,cost\n0050,1000,50000")
        assertEquals("code", table.headers[0])
        assertEquals(1, table.rows.size)
    }

    /** iPhone checks Big5 only on Apple systems; here it always runs, through code page 950. */
    @Test fun utf16AndBig5Encoding() {
        val text = "代碼,股數,成本\n0050,1000,50000"
        assertEquals("代碼", CSVTable.parse(text.toByteArray(Charsets.UTF_16)).headers[0], "Java's UTF-16 writes a byte-order mark, as Swift's does")
        assertEquals("代碼", CSVTable.parse(text.toByteArray(Charset.forName("x-windows-950"))).headers[0])
        val eten = CSVTable.parse("代碼,名稱\n0050,碁\n".toByteArray(Charset.forName("x-windows-950")))
        assertEquals("碁", eten.rows[0][1], "An ETEN character Excel writes and plain Big5 lacks")
    }

    @Test fun overFiveMegabytesIsRefused() {
        val big = ByteArray(5_000_001) { 'a'.code.toByte() }
        assertEquals("CSV 不可超過 5 MB。", assertFailsWith<AppDataError> { CSVTable.parse(big) }.text)
        val limit = ("a,b\n1," + "x".repeat(5_000_000 - 7) + "\n").toByteArray()
        assertEquals(5_000_000, limit.size)
        assertEquals(listOf("a", "b"), CSVTable.parse(limit).headers, "Exactly 5 MB is read")
    }

    @Test fun mappingGuessesCathayColumns() {
        val table = csv("股票代號,商品名稱,現股庫存,付出成本\n0050,元大台灣50,1000,150000\n")
        assertEquals(BrokerMapping(0, 1, 2, 3), BrokerMapping.guessing(table))
        assertEquals(-1, table.guess(listOf("沒有")))
    }

    @Test fun shareCountReadsLotsAndShares() {
        assertEquals(2000.0, BrokerPreview.shareCount("2張"))
        assertEquals(1000.0, BrokerPreview.shareCount("1,000股"))
        assertEquals(null, BrokerPreview.shareCount("張"))
    }
}
