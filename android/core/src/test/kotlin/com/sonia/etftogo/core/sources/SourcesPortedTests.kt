package com.sonia.etftogo.core.sources

import com.sonia.etftogo.core.models.StoreError
import com.sonia.etftogo.core.support.AppDataError
import com.sonia.etftogo.core.support.CoreJson
import com.sonia.etftogo.core.support.DataChecks
import java.time.Instant
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The source parts of PortedAppTests.swift and NameNormalizationTests.swift. */
class SourcesPortedTests {
    private fun monthsAgo(n: Long): String = DataChecks.day(Instant.now().atZone(ZoneId.systemDefault()).minusMonths(n).toInstant())
    private fun daysAgo(n: Long): String = DataChecks.day(Instant.now().atZone(ZoneId.systemDefault()).minusDays(n).toInstant())

    @Test fun officialDistributionHelpers() {
        assertEquals("2026-10-22", OfficialDividends.rocDay("115年10月22日"))
        assertEquals("2026-10-16", OfficialDividends.rocDay("1151016"))
        assertNull(OfficialDividends.rocDay("abc"))
        val days = (1..4).map { monthsAgo(3L * it - 1) }
        assertEquals("季配", OfficialDividends.frequency(days.map { OfficialDistribution(it, "", 1.0) }))
        assertEquals("半年配", OfficialDividends.frequency(days.take(2).map { OfficialDistribution(it, "", 1.0) }))
    }

    @Test fun quoteValidation() {
        val bytes = """{"symbol":"0050","date":"2026-10-15","closePrice":55.0,"changePercent":0.4}""".toByteArray()
        assertEquals(55.0, Fugle.decode(bytes, "0050").price)
        assertFailsWith<StoreError> { Fugle.decode(bytes, "00878") }
        assertFailsWith<StoreError> { Fugle.decode("""{"symbol":"0050","date":"2026-10-15"}""".toByteArray(), "0050") }
    }

    @Test fun openDataDistributions() {
        // Shapes of October 2026: TWSE 上市股票除權除息預告表 (息/權, amount empty until set, stocks and ETNs too) and
        // TPEx 上櫃股票除權除息預告表 (除息/除權/除權息).
        val twse = """
        [{"Date":"1151022","Code":"0056","Name":"元大高股息","Exdividend":"息","StockDividendRatio":"","CashDividend":""},
         {"Date":"1151019","Code":"00878","Name":"國泰永續高股息","Exdividend":"息","StockDividendRatio":"","CashDividend":"0.400000"},
         {"Date":"1151020","Code":"1711","Name":"永光","Exdividend":"權","StockDividendRatio":"","CashDividend":"0"},
         {"Date":"1151104","Code":"020036","Name":"元大金融配息N","Exdividend":"息","StockDividendRatio":"","CashDividend":"0.400000"}]
        """.toByteArray()
        val tpex = """
        [{"ExRrightsExDividendDate":"1151016","SecuritiesCompanyCode":"00679B","CompanyName":"元大美債20年","ExRrightsExDividend":"除息","CashDividend":"0.36000000"},
         {"ExRrightsExDividendDate":"1151007","SecuritiesCompanyCode":"6129","CompanyName":"普誠","ExRrightsExDividend":"除權","CashDividend":"0.00000000"},
         {"ExRrightsExDividendDate":"1151016","SecuritiesCompanyCode":"0056","CompanyName":"不同市場","ExRrightsExDividend":"除息","CashDividend":"1.00000000"}]
        """.toByteArray()
        val markets = mapOf("0056" to "TWSE", "00878" to "TWSE", "00679B" to "TPEx")
        val listed = OfficialDividends.decode(twse, "TWSE", markets)
        assertEquals(setOf("0056", "00878"), listed.keys)
        assertEquals(listOf(OfficialDistribution("2026-10-22", "", null)), listed["0056"], "Announced before the amount is set")
        assertEquals(listOf(OfficialDistribution("2026-10-19", "", 0.4)), listed["00878"])
        val otc = OfficialDividends.decode(tpex, "TPEx", markets)
        assertEquals(mapOf("00679B" to listOf(OfficialDistribution("2026-10-16", "", 0.36))), otc)
        assertFailsWith<AppDataError> { OfficialDividends.decode("<html>維護中</html>".toByteArray(), "TWSE", markets) }
        assertFailsWith<AppDataError>("TPEx fields under the TWSE name are refused") { OfficialDividends.decode(tpex, "TWSE", markets) }
        // A known ex-dividend day keeps its payment day, and its amount until the notice sets one; the record stays.
        val known = OfficialDividends(
            events = mapOf(
                "0056" to listOf(OfficialDistribution("2026-10-22", "2026-11-11", null), OfficialDistribution("2026-07-21", "2026-08-10", 1.35)),
                "00878" to listOf(OfficialDistribution("2026-10-19", "2026-11-14", 0.5)),
            ),
            freq = mapOf("00878" to "季配"),
        )
        val merged = known.merging(listed, false).merging(otc, false)
        assertEquals(listOf(OfficialDistribution("2026-10-22", "2026-11-11", null), OfficialDistribution("2026-07-21", "2026-08-10", 1.35)), merged.list("0056"))
        assertEquals(listOf(OfficialDistribution("2026-10-19", "2026-11-14", 0.4)), merged.list("00878"))
        assertEquals(listOf(OfficialDistribution("2026-10-16", "", 0.36)), merged.list("00679B"))
        assertEquals(mapOf("00878" to "季配"), merged.freq, "Frequencies change only when asked")
        // Past-year figures wait until the record covers the year.
        val quarters = (1..4).map { monthsAgo(3L * it - 1) }
        val started = OfficialDividends(sources = mapOf("since" to DataChecks.day()), events = mapOf("0056" to quarters.map { OfficialDistribution(it, "", 1.0) }))
        assertFalse(started.coversYear())
        assertNull(started.trailingAmount("0056"))
        assertNull(started.merging(mapOf("0056" to emptyList()), true).frequency("0056"), "No frequency from part of a year")
        val whole = started.copy(sources = mapOf("since" to daysAgo(366)))
        assertTrue(whole.coversYear())
        assertEquals(4.0, whole.trailingAmount("0056"))
        assertEquals("季配", whole.merging(mapOf("0056" to emptyList()), true).frequency("0056"))
        assertEquals("季配", whole.merging(mapOf("00919" to emptyList()), true).frequency("0056"), "Every ETF in the record is labelled, not only those in the notice")
    }

    @Test fun bundledCatalogCoversBothMarketsAndNoDuplicateCodes() {
        val catalog = assertNotNull(CatalogSnapshot.bundled())
        catalog.validate()
        assertTrue(catalog.funds.count { it.market == "TWSE" } > 200)
        assertTrue(catalog.funds.count { it.market == "TPEx" } > 100)
        assertTrue(catalog.funds.any { it.id == "00679B" && it.market == "TPEx" })
        assertEquals(catalog.funds.size, catalog.funds.map { it.id }.toSet().size)
    }

    @Test fun catalogRejectsMissingMarketAndDuplicates() {
        val rows = """[{"基金代號":"0050","基金簡稱":"元大台灣50","出表日期":"1151014","上市日期":"0920630"}]""".toByteArray()
        val twse = """[{"Date":"1151015","Code":"0050","Name":"元大台灣50"}]""".toByteArray()
        val otc = """[{"Date":"1151016","SecuritiesCompanyCode":"00679B","CompanyName":"元大美債20年"}]""".toByteArray()
        val stocksOnly = """[{"Date":"1151016","SecuritiesCompanyCode":"6488","CompanyName":"環球晶"}]""".toByteArray()
        CatalogAPI.decode(rows, twse, otc, today = "2026-10-15")
        assertFailsWith<AppDataError>("An empty OTC list is refused") { CatalogAPI.decode(rows, twse, "[]".toByteArray()) }
        assertFailsWith<AppDataError>("An OTC list without ETFs is refused") { CatalogAPI.decode(rows, twse, stocksOnly) }
        assertFailsWith<AppDataError>("A code in both markets is refused") {
            CatalogAPI.decode(rows, twse, """[{"SecuritiesCompanyCode":"0050","CompanyName":"元大台灣50"}]""".toByteArray())
        }
        assertFailsWith<AppDataError>("Renamed fields are refused") {
            CatalogAPI.decode(rows, """[{"Date":"1151015","Symbol":"0050","Title":"元大台灣50"}]""".toByteArray(), otc)
        }
        val twice = """[{"基金代號":"0050","出表日期":"1151014"},{"基金代號":"0050","出表日期":"1151014"}]""".toByteArray()
        assertFailsWith<AppDataError>("A fund listed twice is refused") { CatalogAPI.decode(twice, twse, otc) }
    }

    @Test fun historyRejectsUnadjustedData() {
        assertFailsWith<AppDataError> { Fugle.decodeHistory("""{"symbol":"0050","timeframe":"D","data":[]}""".toByteArray(), "0050") }
    }

    @Test fun annualFeeSnapshotUsesReportedTotalsAndCorrectYear() {
        val catalog = assertNotNull(AnnualFeeCatalog.bundled)
        assertTrue(catalog.records.size > 280)
        val fee = assertNotNull(catalog.records["0050"])
        assertEquals(2025, fee.year)
        assertEquals("98764389", fee.fundID)
        assertEquals(0.22, fee.total, 0.00001)
        assertEquals(0.11, fee.management, 0.00001)
        assertNotNull(catalog.records["00679B"])
        assertNull(catalog.records["00415A"])
    }

    // NameNormalizationTests: official lists spell 金 來 益 as CJK compatibility ideographs (U+F90A, U+F92D, U+FA17).

    private fun hasCompatibility(text: String) = text.any { it.code in 0xF900..0xFAFF }

    @Test fun annualFeeNamesDecodeInNFC() {
        val json = """{"symbol":"00679B","fundID":"12345678","fundName":"債券ETF基金(收益平準金)","year":2025,"commission":0.01,"tax":0,"subscriptionOffset":0,"management":0.1,"custody":0.03,"guarantee":0,"other":0.01,"total":0.15}"""
        val record = CoreJson.decode(AnnualExpense.serializer(), json)
        assertFalse(hasCompatibility(record.fundName))
        assertTrue(record.fundName.contains('益'))
        assertEquals(0.15, record.total)
    }

    @Test fun twseEntitiesUnescapeInNFC() {
        assertEquals('金', CatalogAPI.unescape("基&#63754;").last())
        assertEquals("S&P 500", CatalogAPI.unescape("S&amp;P 500"))
    }

    @Test fun bundledDataHasNoCompatibilityIdeographs() {
        val catalog = assertNotNull(CatalogSnapshot.bundled())
        for (fund in catalog.funds) {
            assertFalse(hasCompatibility(fund.name), fund.id)
            assertFalse(hasCompatibility(fund.fullName ?: ""), fund.id)
        }
        val fees = assertNotNull(AnnualFeeCatalog.bundled)
        for (record in fees.records.values) assertFalse(hasCompatibility(record.fundName), record.symbol)
    }

    /** iPhone counts the past year on its own calendar; a device far from Taipei still gets the same label for a fixed day. */
    @Test fun frequencyUsesTheGivenNow() {
        val now = Instant.parse("2026-11-15T04:00:00Z")
        val list = listOf("2026-11-10", "2026-08-10", "2026-05-10", "2026-02-10").map { OfficialDistribution(it, "") }
        assertEquals("季配", OfficialDividends.frequency(list, now))
        assertEquals("半年配", OfficialDividends.frequency(list, Instant.parse("2027-06-01T04:00:00Z")))
    }
}
