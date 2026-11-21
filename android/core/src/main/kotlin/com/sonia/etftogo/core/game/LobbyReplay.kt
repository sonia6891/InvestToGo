package com.sonia.etftogo.core.game

import kotlinx.serialization.Required
import kotlinx.serialization.Serializable
import java.time.Instant

/** What the lobby last showed: experience, coins and this month's ticked quests. Saved, so the next visit replays only what grew. */
@Serializable
data class LobbySnapshot(
    @Required val xp: Int,
    @Required val coins: Int,
    /** `YearMonth.key` of the month `quests` belong to. */
    @Required val month: String,
    @Required val quests: Set<String>,
) {
    companion object {
        /** The lobby's quests that are done this Taipei month, by the same list the quest card shows. */
        fun of(game: GameState, now: Instant): LobbySnapshot {
            val month = YearMonth.of(now)
            val done = Quests.forMonth(month, game.habit ?: Habit.DCA, game.isNewbie).filter { game.isDone(it, month) }.map { it.id }
            return LobbySnapshot(game.xp, game.coins, month.key, done.toSet())
        }
    }
}

/** The difference between what the lobby showed last time and what is true now. */
data class LobbyReplay(
    val newQuests: List<String>,
    val coinsFrom: Int,
    val coinsTo: Int,
    val xpFrom: Int,
    val xpTo: Int,
    val levelFrom: Int,
    val levelTo: Int,
) {
    val crossesLevel: Boolean get() = levelTo > levelFrom

    companion object {
        /**
         * null when there is nothing to replay: nothing shown before, numbers that went down (an older backup was
         * restored), or nothing that grew. Quest ticks are only compared inside the same month.
         */
        fun between(shown: LobbySnapshot?, now: LobbySnapshot, questOrder: List<String> = emptyList()): LobbyReplay? {
            if (shown == null || now.xp < shown.xp || now.coins < shown.coins) return null
            var fresh: List<String> = emptyList()
            if (shown.month == now.month) {
                val added = now.quests - shown.quests
                fresh = questOrder.filter { it in added } + (added - questOrder.toSet()).sorted()
            }
            if (!(now.xp > shown.xp || now.coins > shown.coins || fresh.isNotEmpty())) return null
            return LobbyReplay(fresh, shown.coins, now.coins, shown.xp, now.xp, GameRules.level(shown.xp), GameRules.level(now.xp))
        }

        /**
         * What the lobby plays on arriving: the difference since `shown`, plus a LEVEL×UP still due from an earlier
         * visit (the bar fills to full again first). Not on a first launch or after a restore (nothing `shown`).
         * null: nothing to play.
         */
        fun arrival(shown: LobbySnapshot?, now: LobbySnapshot, questOrder: List<String>, levelUpDue: Int?, celebratedLevel: Int): LobbyReplay? {
            val replay = between(shown, now, questOrder)
            if (shown == null || levelUpDue == null) return replay
            return replay?.copy(levelFrom = minOf(replay.levelFrom, celebratedLevel))
                ?: LobbyReplay(emptyList(), now.coins, now.coins, now.xp, now.xp, celebratedLevel, GameRules.level(now.xp))
        }
    }
}
