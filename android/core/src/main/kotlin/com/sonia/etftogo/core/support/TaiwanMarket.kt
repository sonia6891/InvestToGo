package com.sonia.etftogo.core.support

import java.time.DayOfWeek
import java.time.Instant

/** Port of PocketCore `TaiwanMarket`. */
object TaiwanMarket {
    val zone = TAIPEI

    /** Weekdays 08:55 to 13:40 Taipei time, both ends included. */
    fun isOpen(at: Instant = Instant.now()): Boolean {
        val time = at.atZone(zone)
        if (time.dayOfWeek == DayOfWeek.SATURDAY || time.dayOfWeek == DayOfWeek.SUNDAY) return false
        val minutes = time.hour * 60 + time.minute
        return minutes >= 8 * 60 + 55 && minutes <= 13 * 60 + 40
    }
}
