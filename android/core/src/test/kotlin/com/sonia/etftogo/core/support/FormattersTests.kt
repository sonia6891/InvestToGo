package com.sonia.etftogo.core.support

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals

class FormattersTests {
    @Test fun signedAddsPlusOnlyWhenPositive() {
        assertEquals("+1,200", signed(1200.0))
        assertEquals("-5", signed(-5.0))
        assertEquals("0", signed(0.0))
    }

    @Test fun hiddenTextIsMasked() {
        assertEquals("＊＊＊＊", shown("1,234", hidden = true))
        assertEquals("1,234", shown("1,234", hidden = false))
    }

    @Test fun dateTextFollowsTheGivenZone() {
        // Like iPhone these use the device's zone; the zone is passed here so the test does not depend on the machine.
        val at = Instant.parse("2026-10-31T16:30:00Z")
        assertEquals("週日", weekdayText(at, TAIPEI))
        assertEquals("2026/11/01", ymdText(at, TAIPEI))
        assertEquals("11/1", monthDay(at, TAIPEI))
        assertEquals("2026/10/31", ymdText(at, java.time.ZoneId.of("America/Los_Angeles")))
    }

    @Test fun halfEvenRounding() {
        assertEquals("2", money(2.5))
        assertEquals("4", money(3.5))
        assertEquals("1.22", decimal(1.225))
    }
}
