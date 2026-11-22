package com.sonia.etftogo.core.analytics

import com.sonia.etftogo.core.support.DataChecks
import com.sonia.etftogo.core.support.MemoryKeyValueStore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** PortedAppTests' selling-cost part, plus the settings kept in a [com.sonia.etftogo.core.support.KeyValueStore]. */
class SellCostsTests {
    @Test fun sellCostsMatchTheBroker() {
        // 國泰證券 showed 34,653 for 2,000 shares of an ETF at 17.35 with its 2.8 折 rate: fee 34,700 × 0.1425% × 0.28
        // = 13.8 → 13, tax 0.1% = 34.7 → 34.
        val cathay = FeeRate(2.8, 1.0)
        assertEquals(34653.0, SellCosts.net(34700.0, stock = false, bond = false, rate = cathay))
        assertEquals(100_000.0 - 39 - 300, SellCosts.net(100_000.0, stock = true, bond = false, rate = cathay), "Stocks pay 0.3% tax")
        assertEquals(100_000.0 - 142 - 100, SellCosts.net(100_000.0, stock = false, bond = false, rate = SellCosts.standard), "The list price")
        assertEquals(1000.0 - 20 - 1, SellCosts.net(1000.0, stock = false, bond = false, rate = SellCosts.standard), "The minimum fee applies to a small sale")
        val day = DataChecks.date("2026-10-17")!!
        val later = DataChecks.date("2027-01-02")!!
        assertEquals(50_000.0 - 19, SellCosts.net(50_000.0, stock = false, bond = true, rate = cathay, day = day), "Bond ETFs pay no tax through 2026")
        assertEquals(50_000.0 - 19 - 50, SellCosts.net(50_000.0, stock = false, bond = true, rate = cathay, day = later))
        assertEquals(0.0, SellCosts.net(0.0, stock = false, bond = false, rate = SellCosts.standard), "Nothing to sell, nothing deducted")
    }

    @Test fun ratesLiveInTheStoreUnderTheIPhoneKeys() {
        val store = MemoryKeyValueStore()
        assertTrue(SellCosts.enabled(store), "On unless turned off")
        store.putBool(SellCosts.netKey, false)
        assertFalse(SellCosts.enabled(store))
        assertEquals(SellCosts.standard, SellCosts.rate("統一證券", store))
        SellCosts.remember(FeeRate(3.0, 1.0), "統一證券（融資）", store)
        assertEquals(mapOf("統一證券" to FeeRate(3.0, 1.0)), SellCosts.rates(store))
        assertEquals(FeeRate(3.0, 1.0), SellCosts.rate("統一證券", store))
        assertTrue(SellCosts.isSet("統一證券", store))
        store.putString(SellCosts.ratesKey, "not json")
        assertEquals(emptyMap(), SellCosts.rates(store), "A store that cannot be read is no rates, not a crash")
    }
}
