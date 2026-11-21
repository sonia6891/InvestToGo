package com.sonia.etftogo.core.game

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LobbyReplayTests {
    private fun snap(xp: Int, coins: Int? = null, month: String = "2026-11", quests: Set<String> = emptySet()) =
        LobbySnapshot(xp, coins ?: xp, month, quests)

    @Test fun noSnapshotNoReplay() {
        assertNull(LobbyReplay.between(null, snap(100)))
    }

    @Test fun equalSnapshotsHaveNoReplay() {
        assertNull(LobbyReplay.between(snap(100, quests = setOf("a")), snap(100, quests = setOf("a"))))
    }

    @Test fun gainReplays() {
        val r = assertNotNull(LobbyReplay.between(snap(260), snap(280)))
        assertEquals(260, r.xpFrom); assertEquals(280, r.xpTo)
        assertEquals(260, r.coinsFrom); assertEquals(280, r.coinsTo)
        assertEquals(3, r.levelFrom); assertEquals(3, r.levelTo)
        assertFalse(r.crossesLevel)
        assertEquals(emptyList(), r.newQuests)
    }

    @Test fun lowerNumbersNoReplay() {
        assertNull(LobbyReplay.between(snap(300), snap(200)))
        assertNull(LobbyReplay.between(snap(300, 300), snap(400, 200)))
    }

    @Test fun newQuestTicks() {
        val r = assertNotNull(LobbyReplay.between(snap(100, quests = setOf("a")), snap(100, quests = setOf("a", "b"))))
        assertEquals(listOf("b"), r.newQuests)
    }

    @Test fun questTicksFollowTheGivenOrder() {
        val r = assertNotNull(LobbyReplay.between(snap(100), snap(140, quests = setOf("a", "b", "c")), listOf("c", "a", "b")))
        assertEquals(listOf("c", "a", "b"), r.newQuests)
    }

    @Test fun replayAcrossMonthHasNoTicks() {
        val r = assertNotNull(LobbyReplay.between(snap(100, month = "2026-10", quests = setOf("a", "b", "c")), snap(200, month = "2026-11")))
        assertEquals(emptyList(), r.newQuests)
        // Quests done in the new month are not ticked either: the month changed under the card.
        val r2 = assertNotNull(LobbyReplay.between(snap(100, month = "2026-10"), snap(140, month = "2026-11", quests = setOf("a"))))
        assertEquals(emptyList(), r2.newQuests)
    }

    @Test fun replayCrossingTwoLevels() {
        val r = assertNotNull(LobbyReplay.between(snap(90), snap(300)))
        assertEquals(1, r.levelFrom); assertEquals(3, r.levelTo)
        assertTrue(r.crossesLevel)
    }

    @Test fun snapshotOfGame() {
        val now = taipei(2026, 11, 12)
        val month = YearMonth.of(now)
        val quests = Quests.forMonth(month, Habit.DCA, isNewbie = false)
        val done = quests.take(2).map { it.id }.toSet()
        val game = GameState(habit = Habit.DCA, dcaMonths = setOf(month.previous()), questsDone = mapOf(month.key to done), xp = 340, coins = 330)
        val s = LobbySnapshot.of(game, now)
        assertEquals(done, s.quests)
        assertEquals(340, s.xp); assertEquals(330, s.coins)
        assertEquals("2026-11", s.month)
    }

    // arrival (what the lobby plays on arriving)

    @Test fun arrivalCrossingGivesCrossesLevel() {
        assertTrue(GameRules.level(100) < GameRules.level(5000))
        val r = assertNotNull(LobbyReplay.arrival(snap(100), snap(5000), emptyList(), null, 1))
        assertTrue(r.crossesLevel)
        assertEquals(GameRules.level(100), r.levelFrom); assertEquals(GameRules.level(5000), r.levelTo)
    }

    @Test fun arrivalWithNothingShownPlaysNothingEvenWhenALevelIsDue() {
        assertNull(LobbyReplay.arrival(null, snap(5000), emptyList(), 9, 1))
    }

    @Test fun arrivalWithALevelStillDueFillsAgainToFull() {
        val xp = 5000
        val level = GameRules.level(xp)
        assertTrue(level > 1)
        val r = assertNotNull(LobbyReplay.arrival(snap(xp), snap(xp), emptyList(), level, level - 1))
        assertEquals(level - 1, r.levelFrom); assertEquals(level, r.levelTo)
        assertTrue(r.crossesLevel)
        assertEquals(xp, r.xpFrom); assertEquals(xp, r.xpTo)
        assertEquals(emptyList(), r.newQuests)
    }

    @Test fun arrivalKeepsTheEarlierLevelWhenADueLevelIsAlsoCrossed() {
        val r = assertNotNull(LobbyReplay.arrival(snap(5000), snap(5100), emptyList(), 9, 2))
        assertEquals(minOf(GameRules.level(5000), 2), r.levelFrom)
    }

    @Test fun arrivalWithNoLevelDueIsJustTheDifference() {
        assertNull(LobbyReplay.arrival(snap(300), snap(300), emptyList(), null, 1))
    }
}
