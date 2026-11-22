package com.sonia.etftogo.core.support

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Port of SupportTests.swift and TrendRoleTests.swift. */
class SupportTests {
    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }

    @Test fun sha256KnownVectors() {
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", hex(SHA256Digest.hash("abc".toByteArray())))
        assertEquals("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", hex(SHA256Digest.hash(ByteArray(0))))
        assertEquals("e4cf7624ee98d7a86f74171a55fa5f7afebd727c9986b7b23c05b5edcfe36e8b", hex(SHA256Digest.hash("代碼".toByteArray())))
        assertEquals("41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3", hex(SHA256Digest.hash(ByteArray(1_000) { 0x61 })))
    }

    @Test fun stableIdMatchesLegacyValues() {
        assertEquals("5FEF0885-6A6B-555C-8BEC-451862548983", StableID.make("legacy-holding", "pwa-001").uuidString)
        assertEquals("BC7184A2-8615-5B96-BBEF-6ACB785C7D4E", StableID.make("broker-account", "富邦證券\u0000主帳戶").uuidString)
    }

    @Test fun dataChecksDatesAndCodes() {
        assertEquals("2026-11-10", DataChecks.rocDay("1151110"))
        assertNull(DataChecks.date("2026-02-30"))
        assertTrue(DataChecks.code("00679B"))
        assertFalse(DataChecks.code("AAPL"))
    }

    @Test fun dayIsTaipeiNotDeviceZone() {
        // 16:30Z on the 31st is already 00:30 on 1 November in Taipei.
        assertEquals("2026-11-01", DataChecks.day(Instant.parse("2026-10-31T16:30:00Z")))
    }

    @Test fun paletteFollowsTaiwanConvention() {
        assertEquals(TrendRole.UP, TrendRole.of(0.01))
        assertEquals(TrendRole.DOWN, TrendRole.of(-0.01))
        assertEquals(TrendRole.FLAT, TrendRole.of(0.0))
        assertEquals("red", TrendRole.UP.colorName, "Taiwan shows gains in red")
        assertEquals("green", TrendRole.DOWN.colorName, "and losses in green")
    }

    @Test fun nanIsFlat() {
        assertEquals(TrendRole.FLAT, TrendRole.of(Double.NaN))
    }

    @Test fun upcomingStaysHidden() {
        assertFalse(Upcoming.visible)
    }

    @Test fun memoryStoreKeepsValues() {
        val store = MemoryKeyValueStore()
        assertNull(store.getString("a"))
        store.putString("a", "1")
        store.putBool("b", true)
        assertEquals("1", store.getString("a"))
        assertTrue(store.getBool("b"))
        store.remove("a")
        assertNull(store.getString("a"))
    }
}
