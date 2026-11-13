import Foundation

// The real actions that move the game (final review C1, ruling R31), as pure state changes the app calls through
// `PortfolioStore.updateGame`. Experience is capped where repeating an action would farm it (ruling R34).

/// The one-time migrations run on saved progress at launch, in order.
enum GameMigration {
    /// 1: DCA months backfilled from the records already on the phone (months only, no experience).
    static let current = 1
}

/// What the first visit to a fund's page did.
struct FundVisit: Equatable {
    /// The card was not collected before this visit.
    var new = false
    /// Experience the card itself earned (0 once this month's capped cards are used up); quests are not included.
    var cardXP = 0
}

extension GameState {
    /// Runs the migrations this progress has not had yet. Safe to call at every launch.
    mutating func migrate(_ p: Portfolio) {
        if migration < 1 { backfillDCA(from: p) }
        migration = max(migration, GameMigration.current)
    }

    /// Every month with a buy in the records (the trade log's buys and the holdings' purchase dates) becomes a DCA
    /// month. Months only: no experience, coins, counters or quests, so an upgrade or a backfill earns nothing.
    mutating func backfillDCA(from p: Portfolio) {
        let dates = (p.trades ?? []).filter { $0.action == .buy }.map(\.date) + p.holdings.compactMap(\.purchaseDate)
        for date in dates { insertMonth(YearMonth(date)) }
    }

    /// A buy the user saved (新增持有 with a purchase date, or 新增交易紀錄 買進). This month's or last month's debit
    /// earns the monthly DCA experience once; an older month is recorded for the streak with nothing paid, so typing in
    /// years of history does not farm levels. A buy dated this month also finishes 本月定投一次. A future date counts
    /// for nothing yet.
    mutating func logBuy(on date: Date, now: Date) -> [XPEvent] {
        let month = YearMonth(date), current = YearMonth(now)
        guard month <= current else { return [] }
        var events: [XPEvent] = []
        if month == current || month == current.previous() { events += recordDCA(on: date) } else { insertMonth(month) }
        if month == current { events += complete(.dcaLogged, now: now) }
        return events
    }

    /// The first visit to a fund's page: collects its card (experience capped per month, see `collect`) and finishes
    /// 收集第 1 張圖鑑卡 and 研究 1 檔新 ETF when they are this month's quests. A fund already collected does nothing.
    mutating func visitFund(_ symbol: String, now: Date) -> FundVisit {
        guard collected[symbol] == nil else { return FundVisit() }
        let card = collect(symbol, now: now)
        _ = complete(.firstDexCard, now: now)
        _ = complete(.newETFResearched, now: now)
        return FundVisit(new: true, cardXP: card.isEmpty ? 0 : (GameRules.xp[.firstDexCard] ?? 0))
    }

    /// 記一筆配息: +20 once per code and payment month, whatever the amount; the key stays after the record is deleted,
    /// so deleting and adding it again earns nothing (ruling R34).
    mutating func logDividend(symbol: String, paid date: Date) -> [XPEvent] {
        awardOnce(.dividendLogged, key: "dividend|\(symbol)|\(YearMonth(date).key)")
    }

    /// A broker statement imported over the holdings: 對帳 experience and its counter once per Taipei day, and the
    /// 完成一次對帳 quest when it is this month's.
    mutating func reconcile(now: Date) -> [XPEvent] {
        awardOnce(.reconciled, key: "reconciled|\(Self.day(now))") + complete(.reconciled, now: now)
    }

    /// 費用比較 opened with at least two funds: counts toward 省費達人 once per Taipei day.
    @discardableResult mutating func compareFees(now: Date) -> Bool {
        guard rewardKeys.insert("feeCompared|\(Self.day(now))").inserted else { return false }
        count(.feeCompared)
        return true
    }

    /// Pays `event` the first time `key` is seen, never again.
    mutating func awardOnce(_ event: XPEvent, key: String) -> [XPEvent] {
        guard rewardKeys.insert(key).inserted else { return [] }
        award(event)
        return [event]
    }

    /// 「2026-11-13」 in Taipei time.
    static func day(_ date: Date) -> String {
        let c = GameRules.taipei.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }
}
