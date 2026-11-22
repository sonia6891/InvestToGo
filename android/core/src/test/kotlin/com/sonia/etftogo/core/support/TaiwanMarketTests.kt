package com.sonia.etftogo.core.support

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TaiwanMarketTests {
    private fun at(text: String) = Instant.parse(text)

    @Test fun openWindowIsInclusive() {
        assertTrue(TaiwanMarket.isOpen(at("2026-11-23T08:55:00+08:00")))
        assertTrue(TaiwanMarket.isOpen(at("2026-11-23T13:40:00+08:00")))
        assertFalse(TaiwanMarket.isOpen(at("2026-11-23T08:54:00+08:00")))
        assertFalse(TaiwanMarket.isOpen(at("2026-11-23T13:41:00+08:00")))
    }

    @Test fun weekendIsClosed() {
        assertFalse(TaiwanMarket.isOpen(at("2026-11-22T10:00:00+08:00")))
        assertFalse(TaiwanMarket.isOpen(at("2026-11-21T10:00:00+08:00")))
    }
}
