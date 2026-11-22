package com.sonia.etftogo.ui

import com.sonia.etftogo.core.game.GameState
import com.sonia.etftogo.core.game.YearMonth
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals

/** iPhone `LobbyHero.of`: a running streak shows its months; a newbie or a broken run sees 1 and 今天開始, never 0. */
class LobbyHeroTest {
    private val now = Instant.parse("2026-11-22T04:00:00Z")

    @Test
    fun aNewbieSeesOneAndTodayStarts() {
        assertEquals(LobbyHero(1, "第 1 個月", "今天開始", null, "第 1 個月，今天開始"), LobbyHero.of(GameState(), now))
    }

    @Test
    fun aRunningStreakShowsItsMonths() {
        val game = GameState(dcaMonths = setOf(YearMonth(2026, 10), YearMonth(2026, 11)), longestStreak = 2)
        assertEquals(LobbyHero(2, "2 個月", "連續定期定額", null, "連續定投 2 個月"), LobbyHero.of(game, now))
    }

    @Test
    fun aBrokenRunAlsoShowsTheBestRun() {
        val game = GameState(dcaMonths = setOf(YearMonth(2026, 1), YearMonth(2026, 2), YearMonth(2026, 3)), longestStreak = 3)
        assertEquals(
            LobbyHero(1, "第 1 個月", "今天開始", "最長紀錄 3 個月", "第 1 個月，今天開始，最長紀錄 3 個月"),
            LobbyHero.of(game, now),
        )
    }
}
