package com.sonia.etftogo.core.game

import com.sonia.etftogo.core.models.Portfolio
import com.sonia.etftogo.core.support.CoreJson
import java.time.Instant
import java.time.ZoneId
import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GameStateTests {
    private fun date(y: Int, m: Int, d: Int) = taipei(y, m, d)
    private fun decode(text: String) = CoreJson.json.decodeFromString(GameState.serializer(), text)
    private fun roundTrip(g: GameState) = decode(CoreJson.json.encodeToString(GameState.serializer(), g))

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
        val game = decode("""{"xp":460,"coins":300,"unlocked":{"a":1},"lastAward":"futureEvent"}""")
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

    @Test fun frontLoadedLevelCurve() {
        assertEquals(1, GameRules.level(0)); assertEquals(1, GameRules.level(99))
        assertEquals(2, GameRules.level(100)); assertEquals(2, GameRules.level(249))
        assertEquals(3, GameRules.level(250)); assertEquals(5, GameRules.level(700))
        assertEquals(10, GameRules.level(2200)); assertEquals(10, GameRules.level(2499)); assertEquals(11, GameRules.level(2500))
        assertEquals(1300, GameRules.xpToReach(7))
        assertEquals(0, GameRules.xpToReach(1))
        assertEquals(450, GameRules.xpToReach(4))
        assertEquals(LevelProgress(0, 200), GameRules.progress(250)); assertEquals(LevelProgress(199, 200), GameRules.progress(449))
        assertEquals(LevelProgress(0, 300), GameRules.progress(1000))
    }

    @Test fun oldSaveKeepsXPAndCelebratesOnce() {
        var g = decode("""{"xp":900,"coins":900,"celebratedLevel":4}""")
        assertEquals(5, GameRules.level(g.xp))
        assertEquals(5, g.levelUpDue)
        g = g.celebrate(5)
        assertNull(g.levelUpDue)
    }

    @Test fun streakAcrossYearBoundaryAndGaps() {
        var g = GameState()
        g = g.recordDCA(date(2025, 11, 5)).first
        g = g.recordDCA(date(2025, 12, 5)).first
        g = g.recordDCA(date(2026, 1, 5)).first
        assertEquals(3, g.streak(date(2026, 1, 15)))
        g = g.recordDCA(date(2026, 3, 5)).first
        assertEquals(1, g.streak(date(2026, 3, 10)))
        assertEquals(3, g.longestStreak)
    }

    @Test fun streakStillAliveBeforeThisMonthsDebit() {
        var g = GameState()
        for (m in 8..10) g = g.recordDCA(date(2026, m, 5)).first
        assertEquals(3, g.streak(date(2026, 11, 2)))
        assertEquals(0, g.streak(date(2026, 12, 1)))
    }

    @Test fun sameMonthCountsOnce() {
        var g = GameState()
        val (first, e1) = g.recordDCA(date(2026, 5, 3)); g = first
        assertEquals(listOf(XPEvent.MONTHLY_DCA), e1)
        assertEquals(100, g.xp)
        val (second, e2) = g.recordDCA(date(2026, 5, 20)); g = second
        assertEquals(emptyList(), e2)
        assertEquals(100, g.xp)
        assertEquals(100, g.coins)
    }

    @Test fun twelveMonthDemoStreak() {
        var g = GameState()
        for (i in 0 until 12) g = g.recordDCA(date(2025 + i / 12, 1 + i % 12, 8)).first
        assertEquals(12, g.streak(date(2025, 12, 20)))
        assertEquals(12, g.longestStreak)
    }

    @Test fun awardAddsXPAndCoins() {
        val g = GameState().award(XPEvent.QUEST_DONE).award(XPEvent.DIVIDEND_LOGGED)
        assertEquals(60, g.xp)
        assertEquals(60, g.coins)
    }

    @Test fun gameStateRoundTripsThroughJSON() {
        var g = GameState().recordDCA(date(2026, 2, 3)).first
        g = g.copy(collected = g.collected + ("0050" to date(2026, 2, 3)), questsDone = g.questsDone + ("2026-02" to setOf("a", "b")))
        assertEquals(g, roundTrip(g))
        assertEquals(GameState(), roundTrip(GameState()))
    }

    // Importing a backup (final review A6)

    /** A phone with no progress yet takes the backup's whole; the months 月報 and 年報 read come with it. */
    @Test fun freshGameAdoptsTheBackups() {
        var backup = GameState().recordDCA(date(2026, 10, 5), date(2026, 10, 5)).first
        backup = backup.award(XPEvent.DIVIDEND_LOGGED, date(2026, 11, 3))
        backup = backup.copy(collected = backup.collected + ("0050" to date(2026, 10, 6)), rewardKeys = setOf("dividend|00878|2026-11"))
        assertFalse(backup.isFresh)
        assertTrue(backup.xp > 0)

        assertTrue(GameState().isFresh)
        // A phone just set up: onboarding and the launch migration have run, nothing has been earned.
        val local = GameState(habit = Habit.DCA, migration = 3, migratedAt = date(2026, 11, 14))
        assertTrue(local.isFresh)

        for (start in listOf(null, GameState(), local)) {
            val result = GameState.afterImport(start, backup)
            assertEquals(backup, result.game, "Adopted whole: level, streak, cards, reward keys")
            assertFalse(result.skipped)
            assertEquals(backup.xp, result.game?.xpByMonth?.values?.sum(), "The experience by month still adds up to the experience")
        }
    }

    /** A phone that has its own progress keeps it untouched: nothing is merged, and the caller is told. */
    @Test fun gameWithProgressIsKept() {
        var backup = GameState().award(XPEvent.QUEST_DONE, date(2026, 10, 3))
        backup = backup.copy(collected = mapOf("0056" to date(2026, 10, 6)))
        for (change in 0 until 4) {
            val local = when (change) {
                0 -> GameState().award(XPEvent.DIVIDEND_LOGGED, date(2026, 11, 3))
                1 -> GameState(dcaMonths = setOf(YearMonth(2026, 11)))
                2 -> GameState(collected = mapOf("0050" to date(2026, 11, 2)))
                else -> GameState(rewardKeys = setOf("reconciled|2026-11"))
            }
            assertFalse(local.isFresh, "case $change")
            val result = GameState.afterImport(local, backup)
            assertEquals(local, result.game, "case $change: not a point, month or card is added")
            assertTrue(result.skipped, "case $change")
        }
        // Nothing to say when the backup has no progress, none at all, or the very same one.
        val local = GameState().award(XPEvent.DIVIDEND_LOGGED, date(2026, 11, 3))
        assertFalse(GameState.afterImport(local, null).skipped)
        assertEquals(local, GameState.afterImport(local, null).game)
        assertFalse(GameState.afterImport(local, GameState()).skipped)
        assertFalse(GameState.afterImport(local, local).skipped)
        assertNull(GameState.afterImport(null, null).game)
    }

    /** A backup whose months add up to more than its experience (or go below zero) loses the months, not the total. */
    @Test fun adoptedExperienceByMonthNeverExceedsTheTotal() {
        var odd = GameState(xp = 100, xpByMonth = mapOf("2026-10" to 80, "2026-11" to 90))
        assertEquals(emptyMap(), GameState.afterImport(null, odd).game?.xpByMonth)
        assertEquals(100, GameState.afterImport(null, odd).game?.xp)
        odd = odd.copy(xpByMonth = mapOf("2026-10" to -5))
        assertEquals(emptyMap(), odd.checkedForAdoption().xpByMonth)
        odd = odd.copy(xpByMonth = mapOf("2026-10" to Int.MAX_VALUE, "2026-11" to Int.MAX_VALUE))
        assertEquals(emptyMap(), odd.checkedForAdoption().xpByMonth, "No overflow on a file made to break the sum")
        odd = odd.copy(xpByMonth = mapOf("2026-10" to 60, "2026-11" to 40))
        assertEquals(mapOf("2026-10" to 60, "2026-11" to 40), odd.checkedForAdoption().xpByMonth)
        odd = odd.copy(xp = -30, coins = -1, xpByMonth = emptyMap())
        assertEquals(0, odd.checkedForAdoption().xp)
        assertEquals(0, odd.checkedForAdoption().coins)
    }

    @Test fun portfolioWithoutGameDecodes() {
        val p = CoreJson.json.decodeFromString(Portfolio.serializer(), """{"schema":1,"holdings":[],"dividends":[],"favorites":[],"quotes":{}}""")
        assertNull(p.game)
        assertEquals(GameState(), p.game ?: GameState())
    }
}
