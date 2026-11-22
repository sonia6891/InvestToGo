package com.sonia.etftogo.core.models

import com.sonia.etftogo.core.Fixtures
import com.sonia.etftogo.core.Samples
import com.sonia.etftogo.core.importing.BackupImport
import com.sonia.etftogo.core.importing.LegacyPlan
import com.sonia.etftogo.core.support.CoreJson
import com.sonia.etftogo.core.support.DataChecks
import kotlinx.serialization.json.jsonObject
import kotlin.math.pow
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The model parts of PortedAppTests.swift; the source, import and analytics parts are ported with those areas. */
class PortedAppTests {
    private val legacy = """{"app":"ETF_CLASSIFIER","version":3,"planning":{"version":2,"holdings":[{"id":"pwa-001","code":"0050","name":"元大台灣50","shares":2000,"cost":100000,"price":55,"priceDate":"2026-10-01"}],"dividends":[{"id":"pwa-dividend-1","code":"0050","name":"元大台灣50","paymentDate":"2026-10-10","exDate":"2026-10-01","eligibleShares":2000,"perShare":1.2,"deductions":10,"status":"received","actualReceived":2385,"sourceUrl":"https://example.com/dividend"}],"plan":{"principal":100000,"monthly":5000,"years":10,"totalReturn":0.06,"distributionRate":0.04,"frequency":4,"reinvest":1,"deductionRate":0}},"favorites":["0050"],"comparison":["0050","00878"]}"""

    @Test fun noMarketValueWithoutCompleteQuotes() {
        val data = Samples.portfolio
        assertEquals(348500.0, data.marketValue)
        assertNull(data.copy(quotes = data.quotes - "0050").marketValue, "Missing prices must not silently use cost as market value")
    }

    @Test fun projectionZeroReturnAndMonthlyTiming() {
        assertEquals(700000.0, Projection.value(100000.0, 5000.0, 10, 0.0), 0.01)
        assertTrue(Projection.value(100000.0, 0.0, 10, -5.0) < 100000)
    }

    @Test fun backupRejectsInvalidData() {
        val data = Samples.portfolio
        assertFailsWith<StoreError> { Portfolio.decodeBackup(data.copy(holdings = listOf(data.holdings[0].copy(shares = -1.0)) + data.holdings.drop(1)).encode()) }
        assertFailsWith<StoreError> { Portfolio.decodeBackup(data.copy(schema = 99).encode()) }
        assertFailsWith<StoreError> { Portfolio.decodeBackup(data.copy(holdings = data.holdings + data.holdings[0]).encode()) }
    }

    @Test fun comboProjectionMatchesTemplate() {
        val settings = ComboSettings(monthly = 10000.0, stockReturn = 5.0, etfReturn = 5.0)
        for ((years, expected) in listOf(3 to 734180.51, 5 to 1061021.85, 10 to 2032300.0)) {
            val result = ComboMath.project(120000.0, 180000.0, settings, 0.4, years, ComboScenario.BASE)
            assertEquals(expected, result.end, 1.0)
            assertEquals(10000.0 * years * 12, result.invested, 0.001)
        }
        assertEquals(908735.8, ComboMath.project(120000.0, 180000.0, settings, 0.4, 5, ComboScenario.STRESS).end, 1.0)
        val flat = settings.copy(stockReturn = 0.0, etfReturn = 0.0)
        assertEquals(1500000.0, ComboMath.project(120000.0, 180000.0, flat, 0.4, 10, ComboScenario.BASE).end, 0.01)
        val cash = settings.copy(reinvest = false, stockYield = 2.0, etfYield = 4.0)
        assertEquals(1049649.13, ComboMath.project(120000.0, 180000.0, cash, 0.4, 5, ComboScenario.BASE).end, 1.0)
        assertEquals(-2.0, ComboScenario.CONSERVATIVE.rate(5.0))
        assertEquals(8.0, ComboScenario.OPTIMISTIC.rate(5.0))
    }

    @Test fun realPWAShapeMigratesCostActualDividendAndMetadata() {
        val value = BackupImport.decode(legacy.toByteArray())
        assertEquals(50.0, value.holdings[0].unitCost)
        assertEquals(100000.0, value.cost)
        assertEquals(2385.0, value.dividends[0].amount, "Actual receipt must win over shares × dividend minus fees")
        assertEquals(DividendStatus.PAID, value.dividends[0].status)
        assertEquals("2026-10-10", DataChecks.day(value.dividends[0].date))
        assertEquals(55.0, value.legacyPrices?.get("pwa-001")?.price)
        assertEquals(10.0, value.legacyDividends?.get("pwa-dividend-1")?.deductions)
        assertEquals(0.04, value.legacyPlan?.distributionRate)
        assertEquals(listOf("0050", "00878"), value.comparison)
        assertTrue(value.quotes.isEmpty(), "Manually entered prices must not become verified quotes")
    }

    @Test fun plannedDividendAndOlderNativeEnvelope() {
        val input = legacy.replace("ETF_CLASSIFIER", "ETF_TOGO_NATIVE").replace("\"version\":3", "\"version\":1").replace("\"received\"", "\"planned\"")
        val value = BackupImport.decode(input.toByteArray())
        assertEquals(2390.0, value.dividends[0].amount)
        assertEquals(DividendStatus.ESTIMATED, value.dividends[0].status)
    }

    @Test fun legacyRejectsNegativeCostsAndMissingActualPayment() {
        assertFailsWith<StoreError> { BackupImport.decode(legacy.replace("\"cost\":100000", "\"cost\":-1").toByteArray()) }
        assertFailsWith<StoreError> { BackupImport.decode(legacy.replace("\"actualReceived\":2385", "\"actualReceived\":null").toByteArray()) }
    }

    @Test fun pricePerformanceUsesDrawdownsAndRealTimeInterval() {
        val h = PriceHistory("0050", true, listOf(PricePoint("2024-01-01", 100.0), PricePoint("2024-06-01", 120.0), PricePoint("2024-08-01", 90.0), PricePoint("2025-01-01", 110.0)), "2025-01-02", "test")
        val stats = PerformanceStats(h)
        assertEquals(0.1, stats.change, 0.000001)
        assertEquals(0.25, stats.drawdown, 0.000001)
        assertEquals(1.1.pow(365.25 / 366) - 1, stats.annualized!!, 0.000001)
        assertNull(stats.volatility)
    }

    @Test fun historyRejectsOutOfOrderDatesAndInvalidCalendarDays() {
        val h = PriceHistory("0050", true, listOf(PricePoint("2025-01-02", 100.0), PricePoint("2025-01-01", 101.0)), "2025-01-03", "test")
        assertFailsWith<Exception> { h.validate() }
        assertNull(DataChecks.date("2025-02-30"))
        assertNull(DataChecks.date("2025-1-05"))
        assertEquals("2025-01-05", DataChecks.date("2025-01-05")?.let { DataChecks.day(it) })
    }

    @Test fun historyRejectsDuplicateDates() {
        val h = PriceHistory("0050", true, listOf(PricePoint("2025-01-01", 100.0), PricePoint("2025-01-01", 101.0)), "2025-01-02", "test")
        assertFailsWith<Exception> { h.validate() }
    }

    @Test fun feeRecordRequiresYearAndSource() {
        var fee = FeeRecord("0050", "2026-01-01", "級距費率", "級距費率", 0.2, null, "https://example.com", "")
        assertFailsWith<Exception> { fee.validate() }
        fee = fee.copy(expenseYear = 2025); fee.validate()
        assertFailsWith<Exception> { fee.copy(sourceURL = "javascript:alert(1)").validate() }
        fee.copy(sourceURL = "").validate()
    }

    @Test fun schemaOneStillDecodesWithoutNewFields() {
        val value = Portfolio.decodeBackup("""{"schema":1,"holdings":[],"dividends":[],"favorites":[],"quotes":{}}""".toByteArray())
        assertNull(value.components)
        assertTrue(value.holdings.isEmpty())
    }

    @Test fun planReinvestmentDoesNotCountDividendsTwice() {
        var plan = LegacyPlan(100000.0, 0.0, 1, 0.06, 0.04, 4, 1.0, 0.0)
        val full = PlanMath.project(plan).last()
        assertEquals(106000.0, full.total, 0.001)
        assertEquals(0.0, full.cash)
        plan = plan.copy(totalReturn = 0.0, reinvest = 0.0)
        val cash = PlanMath.project(plan).last()
        assertEquals(100000.0, cash.total, 0.001)
        assertEquals(100000 * (1 - 0.99.pow(4)), cash.cash, 0.001)
        assertTrue(PlanMath.project(plan.copy(deductionRate = 0.1)).last().total < 100000)
    }

    // Review Focus: not ported from Swift.

    @Test fun backupWithUnknownKeyStillDecodes() {
        val p = Portfolio.decodeBackup(Fixtures.bytes("vectors/models/backups/unknown-key.json"))
        assertEquals(1, p.schema)
    }

    @Test fun absentOptionalsStayAbsentAfterRoundTrip() {
        val bytes = Fixtures.bytes("vectors/models/backups/old-no-optionals.json")
        val again = CoreJson.json.parseToJsonElement(Portfolio.decodeBackup(bytes).encode().decodeToString()).jsonObject
        assertFalse("trades" in again)
        assertFalse("game" in again)
    }

    @Test fun keysSwiftRequiresAreRequired() {
        assertFailsWith<Exception> { Portfolio.decodeBackup("""{"schema":1,"holdings":[],"dividends":[],"favorites":[]}""".toByteArray()) }
    }

    @Test fun componentFileOverOneMegabyteIsRefused() {
        val error = assertFailsWith<com.sonia.etftogo.core.support.AppDataError> { ComponentSnapshot.imported(ByteArray(1_000_001) { ' '.code.toByte() }, "0050") }
        assertEquals("成分檔不可超過 1 MB。", error.text)
    }

    @Test fun limitsCountCharactersNotUtf16Units() {
        // 20 emoji are 40 UTF-16 units but 20 characters, as iPhone counts them.
        val emoji = "😀".repeat(20)
        Holding(symbol = emoji, name = "n", shares = 1.0, unitCost = 1.0, broker = "b", strategy = Strategy.SAVING).validate()
    }
}
