package com.sonia.etftogo.core.game

import com.sonia.etftogo.core.models.Portfolio
import com.sonia.etftogo.core.models.TradeAction
import java.time.Instant

// The real actions that move the game (final review C1, ruling R31), as pure state changes the app calls through
// the store. Experience is capped where repeating an action would farm it (ruling R34).

/** The one-time migrations run on saved progress at launch, in order. */
object GameMigration {
    /** 1: DCA months backfilled from the records already on the phone (months only, no experience). */
    const val current = 1
}

/** What the first visit to a fund's page did. `cardXP`: experience the card itself earned (quests not included). */
data class FundVisit(val new: Boolean = false, val cardXP: Int = 0)

/** The reward key of a month's 對帳 is this and the month: 「reconciled|2026-11」. 口袋月報 counts them. */
const val reconciledKey = "reconciled|"

/** Runs the migrations this progress has not had yet. Safe to call at every launch. */
fun GameState.migrate(p: Portfolio, now: Instant = Instant.now()): GameState {
    var game = if (migration < 1) backfillDCA(p) else this
    if (game.migratedAt == null) game = game.copy(migratedAt = now)
    return game.copy(migration = maxOf(game.migration, GameMigration.current))
}

/**
 * Every month with a buy in the records (the trade log's buys and the holdings' purchase dates) becomes a DCA
 * month. Months only: no experience, coins, counters or quests. A holding saved without a purchase date logged its
 * first buy on the day it was typed in, so that entry is not a DCA month (re-review N6); later buys still are.
 */
fun GameState.backfillDCA(p: Portfolio): GameState {
    val undated = p.holdings.filter { it.purchaseDate == null }.map { it.symbol }.toSet()
    val skipped = mutableSetOf<String>()
    val buys = (p.trades ?: emptyList()).filter { it.action == TradeAction.BUY }.sortedBy { it.date }.filter { trade ->
        if (trade.symbol !in undated || trade.symbol in skipped) return@filter true
        skipped += trade.symbol
        false
    }
    val dates = buys.map { it.date } + p.holdings.mapNotNull { it.purchaseDate }
    var game = this
    for (date in dates) game = game.insertMonth(YearMonth.of(date)).first
    return game
}

/**
 * A buy the user saved. This month's or last month's debit earns the monthly DCA experience once; an older month is
 * recorded for the streak with nothing paid. A buy dated this month also finishes 本月定投一次. A future date
 * counts for nothing yet.
 */
fun GameState.logBuy(on: Instant, now: Instant): Pair<GameState, List<XPEvent>> {
    val month = YearMonth.of(on)
    val current = YearMonth.of(now)
    if (month > current) return this to emptyList()
    val events = mutableListOf<XPEvent>()
    var game = this
    if (month == current || month == current.previous()) {
        val (next, earned) = game.recordDCA(on, now)
        game = next; events += earned
    } else {
        game = game.insertMonth(month).first
    }
    if (month == current) {
        val (next, earned) = game.complete(QuestTrigger.DCA_LOGGED, now)
        game = next; events += earned
    }
    return game to events
}

/**
 * The first visit to a fund's page: collects its card (experience capped per month, see `collect`) and finishes
 * 收集第 1 張圖鑑卡 and 研究 1 檔新 ETF when they are this month's quests. A fund already collected does nothing.
 */
fun GameState.visitFund(symbol: String, now: Instant): Pair<GameState, FundVisit> {
    if (symbol in collected) return this to FundVisit()
    val (collectedGame, card) = collect(symbol, now)
    val game = collectedGame.complete(QuestTrigger.FIRST_DEX_CARD, now).first.complete(QuestTrigger.NEW_ETF_RESEARCHED, now).first
    return game to FundVisit(new = true, cardXP = if (card.isEmpty()) 0 else GameRules.xp[XPEvent.FIRST_DEX_CARD] ?: 0)
}

/**
 * 記一筆配息: +20, whatever the amount (ruling R34), only for a dividend that could be this month's news
 * (re-review N1): a held code; paid this or last Taipei month, not in the future, not before the game started on this
 * phone (`migratedAt`); once per code and payment month; at most `GameRules.dividendXPPerMonth` paid in one month.
 */
fun GameState.logDividend(symbol: String, paid: Instant, held: Boolean, now: Instant): Pair<GameState, List<XPEvent>> {
    val month = YearMonth.of(paid)
    val current = YearMonth.of(now)
    if (!held || paid > now || !(month == current || month == current.previous())) return this to emptyList()
    migratedAt?.let { started ->
        val startOfDay = started.atZone(GameRules.taipei).toLocalDate().atStartOfDay(GameRules.taipei).toInstant()
        if (paid < startOfDay) return this to emptyList()
    }
    val paidIn = "dividendPaidIn|${current.key}|"
    if (rewardKeys.count { it.startsWith(paidIn) } >= GameRules.dividendXPPerMonth) return this to emptyList()
    val (game, events) = awardOnce(XPEvent.DIVIDEND_LOGGED, "dividend|$symbol|${month.key}", now)
    if (events.isEmpty()) return game to events
    return game.copy(rewardKeys = game.rewardKeys + (paidIn + "$symbol|${month.key}")) to events
}

/**
 * A broker statement imported over the holdings: 對帳 experience and its counter once per Taipei month (re-review
 * N2), and the 完成一次對帳 quest when it is this month's.
 */
fun GameState.reconcile(now: Instant): Pair<GameState, List<XPEvent>> {
    val (paid, first) = awardOnce(XPEvent.RECONCILED, reconciledKey + YearMonth.of(now).key, now)
    val (game, second) = paid.complete(QuestTrigger.RECONCILED, now)
    return game to first + second
}

/** 費用比較 opened with at least two funds: counts toward 省費達人 once per Taipei day. */
fun GameState.compareFees(now: Instant): Pair<GameState, Boolean> {
    val key = "feeCompared|${gameDay(now)}"
    if (key in rewardKeys) return this to false
    return copy(rewardKeys = rewardKeys + key).count(CounterKey.FEE_COMPARED) to true
}

/** Pays `event` the first time `key` is seen, never again. */
fun GameState.awardOnce(event: XPEvent, key: String, now: Instant): Pair<GameState, List<XPEvent>> {
    if (key in rewardKeys) return this to emptyList()
    return copy(rewardKeys = rewardKeys + key).award(event, now) to listOf(event)
}

/** 「2026-11-12」 in Taipei time (Swift `GameState.day`). */
fun gameDay(date: Instant): String {
    val d = date.atZone(GameRules.taipei)
    return "%04d-%02d-%02d".format(d.year, d.monthValue, d.dayOfMonth)
}
