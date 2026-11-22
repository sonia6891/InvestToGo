package com.sonia.etftogo.ui

import com.sonia.etftogo.core.game.GameState
import com.sonia.etftogo.core.game.streak
import java.time.Instant

/**
 * What the lobby's hero says: iPhone `LobbyHero` (spec 4.2, 5.3; ruling R15). A running streak shows its months; a
 * newbie, or anyone whose run broke, sees a lone 1 and 「今天開始」 — never a bare 0 — and after a break also their best run.
 */
data class LobbyHero(val value: Int, val caption: String, val tag: String, val record: String?, val label: String) {
    companion object {
        fun of(game: GameState, now: Instant): LobbyHero {
            val streak = game.streak(now)
            if (streak > 0) return LobbyHero(streak, "$streak 個月", "連續定期定額", null, "連續定投 $streak 個月")
            val record = if (game.isNewbie) null else "最長紀錄 ${maxOf(game.longestStreak, 1)} 個月"
            return LobbyHero(1, "第 1 個月", "今天開始", record, listOfNotNull("第 1 個月，今天開始", record).joinToString("，"))
        }
    }
}
