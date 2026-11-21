package com.sonia.etftogo.core.importing

import com.sonia.etftogo.core.importing.ScreenshotImport.Basis
import com.sonia.etftogo.core.importing.ScreenshotImport.Draft
import com.sonia.etftogo.core.importing.ScreenshotImport.Kind
import com.sonia.etftogo.core.importing.ScreenshotImport.Row
import com.sonia.etftogo.core.models.Fund
import com.sonia.etftogo.core.models.Strategy
import com.sonia.etftogo.core.support.cFixed
import com.sonia.etftogo.core.support.swiftDescription
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** PortedAppTests' testScreenshotCostPerShareOrTotal, plus the text helpers the Draft and warnings write with. */
class ScreenshotImportTests {
    private val funds = Fund.starters + Fund("00991A", "主動測試", Strategy.UNCLASSIFIED)
    private val lots = ScreenshotImport.Listing(listOf("00991A" to "主動測試"))

    @Test fun costPerShareOrTotal() {
        val read = ScreenshotImport.parse(listOf("主動測試 00991A", "股數 1,000", "成本價 17.35"), lots)
        assertEquals(listOf(Row("00991A", shares = 1000.0, cost = 17.35, basis = Basis.PER_SHARE)), read)
        assertEquals(read, ScreenshotImport.parse(listOf("主動測試 00991A", "現股庫存 1,000", "成交價 17.35"), lots), "國泰證券 calls the price paid per share 成交價")
        assertEquals(read, ScreenshotImport.parse(listOf("主動測試 00991A", "現股庫存 成交價", "1,000 17.35"), lots), "Titles in a row above the figures")
        val labelled = Draft.of(read[0], price = 17.5)
        assertTrue(labelled.perShare)
        assertEquals(17350.0, labelled.totalCost!!, 0.001, "成本價 17.35 × 1,000 shares")
        assertEquals(17.35, labelled.averageCost!!, 1e-9)
        assertEquals(listOf(Row("00991A", shares = 1000.0, cost = 17.35)), ScreenshotImport.parse(listOf("主動測試 00991A", "股數 1,000", "成本 17.35"), lots), "A plain 成本 does not say which it is")
        assertTrue(Draft.of(Row("00991A", shares = 1000.0, cost = 17.35), price = 17.5).perShare, "Near the price itself: a price per share")
        assertFalse(Draft.of(Row("00991A", shares = 1000.0, cost = 17350.0), price = 17.5).perShare, "Near the price once divided by the shares: a total")
        for (unsure in listOf(Draft.of(Row("00991A", shares = 1000.0, cost = 3.0), price = 17.5), Draft.of(Row("00991A", shares = 1000.0, cost = 17.35)))) {
            assertEquals("", unsure.cost, "Neither reading fits the price, or there is no price: not filled in")
            assertNotNull(unsure.costNote)
        }
        assertNotNull(BrokerPreview.costWarning(0.017, 17.5), "An average cost far under the price is always warned about")
        assertNull(BrokerPreview.costWarning(17.35, 17.5))
        val lotsOfMargin = listOf(
            Draft.of(Row("00991A", shares = 1000.0, cost = 17.0, kind = Kind.MARGIN, basis = Basis.PER_SHARE)),
            Draft.of(Row("00991A", shares = 1000.0, cost = 18000.0, kind = Kind.MARGIN, basis = Basis.TOTAL)),
            Draft.of(Row("00991A", shares = 500.0, cost = 17.5, basis = Basis.PER_SHARE)),
        )
        val preview = BrokerPreview.make(lotsOfMargin, "國泰證券", "主要", funds)
        assertEquals(listOf(2000.0, 500.0), preview.holdings.map { it.shares })
        assertEquals(35000.0, preview.holdings[0].cost, 0.001, "17 × 1,000 + 18,000")
        assertEquals(17.5, preview.holdings[0].unitCost, 1e-9)
        assertEquals("國泰證券（融資）", preview.holdings[0].broker)
        assertEquals(8750.0, preview.holdings[1].cost, 0.001)
        assertTrue(preview.warnings { if (it == "00991A") 17.5 else null }.isEmpty())
        val csv = BrokerPreview.make(CSVTable.parse("code,shares,cost\n00991A,1000,17.35".toByteArray()), BrokerMapping(0, -1, 1, 2), "國泰證券", "主要", funds)
        assertEquals(1, csv.warnings { if (it == "00991A") 17.5 else null }.size, "A CSV price per share imported as a total is warned about")
        assertTrue(csv.warnings { null }.isEmpty())
    }

    @Test fun draftsAreDistinctLots() {
        val row = Row("0050", shares = 1000.0, cost = 150000.0, basis = Basis.TOTAL)
        assertNotEquals(Draft.of(row), Draft.of(row), "Two lots with the same figures are still two rows to check")
    }

    @Test fun reviewDoesNotChangeTheRowsItWasGiven() {
        val full = Row("0050", shares = 1000.0, cost = 150000.0, basis = Basis.TOTAL)
        val part = Row("0050", shares = 1000.0)
        val pages = listOf(listOf(full), listOf(part))
        val reviewed = ScreenshotImport.review(pages)
        assertNotNull(reviewed.rows[1].note)
        assertNull(pages[1][0].note, "The pages read from the screenshots are left as they were")
    }

    @Test fun swiftTextOfNumbers() {
        assertEquals("17.35", swiftDescription(17.35))
        assertEquals("0.0001", swiftDescription(0.0001))
        assertEquals("1e-05", swiftDescription(0.00001))
        assertEquals("1.5e+16", swiftDescription(1.5e16))
        assertEquals("12345678.5", swiftDescription(12345678.5))
        assertEquals("1000.0", swiftDescription(1000.0))
        assertEquals("-2.5", swiftDescription(-2.5))
        assertEquals("nan", swiftDescription(Double.NaN))
        assertEquals("0.2", cFixed(0.25, 1), "printf ties to even on the exact value")
        assertEquals("0.3", cFixed(0.35, 1), "0.35 is stored a little under 0.35")
        assertEquals("1.2", cFixed(1.25, 1))
        assertEquals("10.0", cFixed(9.96, 1))
    }
}
