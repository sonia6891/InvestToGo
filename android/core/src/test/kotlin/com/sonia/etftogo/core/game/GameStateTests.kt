package com.sonia.etftogo.core.game

import com.sonia.etftogo.core.support.CoreJson
import java.time.Instant
import java.time.ZoneId
import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class GameStateTests {
    @Test fun yearMonthUsesTaipeiNotDeviceZone() {
        val saved = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"))
            assertEquals(ZoneId.of("America/Los_Angeles"), ZoneId.systemDefault())
            assertEquals(YearMonth(2026, 11), YearMonth.of(Instant.parse("2026-10-31T16:30:00Z")))
        } finally {
            TimeZone.setDefault(saved)
        }
    }

    @Test fun rollsOverYears() {
        assertEquals(YearMonth(2027, 1), YearMonth(2026, 12).next())
        assertEquals(YearMonth(2026, 12), YearMonth(2027, 1).previous())
        assertEquals("2026-01", YearMonth(2026, 1).key)
        assertEquals(YearMonth(2028, 2), YearMonth.of(Instant.parse("2028-02-29T12:00:00+08:00")))
    }

    @Test fun olderProgressFillsDefaultsFromWhatItHas() {
        val game = CoreJson.json.decodeFromString(GameState.serializer(), """{"xp":460,"coins":300,"unlocked":{"a":1},"lastAward":"futureEvent"}""")
        assertEquals(4, game.celebratedLevel, "Levels already held are not new")
        assertEquals(300, game.celebratedCoins)
        assertEquals(setOf("a"), game.celebratedAchievements)
        assertNull(game.lastAward, "An event a later build added reads as unknown")
    }

    @Test fun levelsAreFrontLoaded() {
        assertEquals(listOf(1, 2, 3, 4, 5, 6), listOf(0, 100, 250, 450, 700, 1000).map(GameRules::level))
        assertEquals(1, GameRules.level(-5))
        assertEquals(GameRules.Progress(30, 300), GameRules.progress(730))
    }
}
