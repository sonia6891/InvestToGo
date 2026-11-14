import Foundation

/// Launch arguments that set up game progress for UI tests and screenshots; ignored without `--ui-testing`.
///
/// - `--demo-streak <n>`: DCA recorded in each of the n months up to and including this one.
/// - `--demo-level <n>`: experience at the start of level n, `(n - 1) × GameRules.xpPerLevel`.
/// - `--demo-xp <n>`: experience n (wins over `--demo-level`).
/// - `--open levelup`: the current level's LEVEL×UP is still to be shown (needs a level above 1).
/// - `--demo-pocket`: four sample holdings, one of them at a loss, and a year of received dividends (`seedPocket`).
/// - `--demo-active`: 00982A in the favourites with two days of holdings (`seedActive`), for 主動式追蹤.
/// - `--quiet-toasts`: no first-time notices (「收進圖鑑 +30 經驗」), so screenshots are the same every run.
/// - `--demo-store`: the App Store screenshots' state. `--demo-member`, `--demo-pocket` and `--demo-active` in one, and
///   on top of them someone a year in (`seedStoreGame`, `seedStore`).
///
/// Read elsewhere: `--skin <id>` (SkinStore), `--open <feature>` (the root view), `--skip-onboarding`,
/// `--open splash` and `--open onboarding [--page n]` (`Onboarding.start`), `--offline` and `--reduce-motion`.
enum DemoArguments {
    /// `--quiet-toasts` with `--ui-testing`: the CI skin matrix captures pages without first-time notices.
    static let quietToasts: Bool = {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--quiet-toasts")
    }()

    /// What `--demo-store` switches on besides its own state.
    static let storeImplies: Set<String> = ["--demo-member", "--demo-pocket", "--demo-active"]

    /// Whether a demo flag is on: never without `--ui-testing`; given itself, or implied by `--demo-store`.
    static func has(_ flag: String, in args: [String]) -> Bool {
        guard args.contains("--ui-testing") else { return false }
        return args.contains(flag) || (storeImplies.contains(flag) && args.contains("--demo-store"))
    }

    static func apply(to game: inout GameState, args: [String], now: Date) {
        guard args.contains("--ui-testing") else { return }
        // First, so `--demo-streak`, `--demo-level` and `--demo-xp` still have the last word.
        if has("--demo-store", in: args) { seedStoreGame(&game, now: now) }
        func number(_ flag: String) -> Int? {
            guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1), let n = Int(args[i + 1]), n >= 0 else { return nil }
            return n
        }
        if let streak = number("--demo-streak") {
            var months = Set<YearMonth>(), month = YearMonth(now)
            for _ in 0..<streak { months.insert(month); month = month.previous() }
            game.dcaMonths = months
            game.longestStreak = max(game.longestStreak, streak)
        }
        if let level = number("--demo-level"), level >= 1 { game.xp = (level - 1) * GameRules.xpPerLevel }
        if let xp = number("--demo-xp") { game.xp = xp }
        // Demo progress is set-up, not an earned level: no LEVEL×UP for it (spec 5.12 celebrates crossing a level).
        if number("--demo-level") != nil || number("--demo-xp") != nil { game.celebrate(GameRules.level(xp: game.xp)); game.celebratedLevel = GameRules.level(xp: game.xp) }
        // `--open levelup`: the current level is still to be celebrated, earned by this month's DCA (screenshots).
        if let i = args.firstIndex(of: "--open"), args.indices.contains(i + 1), args[i + 1] == "levelup" {
            game.celebratedLevel = max(1, GameRules.level(xp: game.xp) - 1)
            game.lastAward = .monthlyDCA
            // As if this month's DCA (+100) had crossed the level.
            game.celebratedCoins = game.coins - (GameRules.xp[.monthlyDCA] ?? 0)
        }
    }

    /// The holdings of the pocket canvas (spec 5.7) for screenshots and UI tests: shares and the gain or loss on cost,
    /// priced from the current quote. 00679B is at a loss, to show one honestly.
    static let pocketSample: [(symbol: String, shares: Double, gain: Double)] = [
        ("0050", 1000, 0.182), ("00878", 2000, 0.061), ("006208", 200, 0.154), ("00679B", 1000, -0.06),
    ]
    /// Received dividends of the dividends canvas (spec 5.8): month, code and amount, this year and last year (for
    /// 「比去年多」). `seedPocket` never dates one in the future: a month not reached yet is moved to today.
    static let dividendSample: [(month: Int, symbol: String, amount: Double)] = [
        (1, "00878", 1500), (2, "0050", 1000), (4, "00878", 1500), (5, "006208", 940), (7, "00878", 1500), (8, "0050", 700), (10, "00878", 1500),
    ]
    static let lastYearSample: [(month: Int, symbol: String, amount: Double)] = [
        (1, "00878", 1200), (2, "0050", 800), (4, "00878", 1200), (5, "006208", 1000), (7, "00878", 1200), (8, "0050", 600), (10, "00878", 720),
    ]

    /// `--demo-pocket` (with `--ui-testing`): fills an empty pocket with `pocketSample` and `dividendSample`. Seeding
    /// is not logging, so it earns no experience.
    /// `--demo-held` with `--ui-testing`: one 0050 holding, saved without playing, so a UI test can log a dividend that
    /// earns (only a held code pays, re-review N1).
    @MainActor static func seedHeld(_ store: PortfolioStore, args: [String]) {
        guard args.contains("--ui-testing"), args.contains("--demo-held"), !store.data.holdings.contains(where: { $0.symbol == "0050" }) else { return }
        try? store.save(Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "", strategy: .saving))
    }

    /// Two days of made-up holdings for 00982A (the stocks are not real ones): between them one is added, one removed
    /// and two weights move.
    static let activeSample: [ComponentSnapshot] = [
        ComponentSnapshot(symbol: "00982A", date: "2026-11-11", components: [
            FundComponent(symbol: "1001", name: "範例股票 A", weight: 10), FundComponent(symbol: "1002", name: "範例股票 B", weight: 5),
            FundComponent(symbol: "1003", name: "範例股票 C", weight: 4.5), FundComponent(symbol: "1004", name: "範例股票 D", weight: 3),
        ], source: "示意資料"),
        ComponentSnapshot(symbol: "00982A", date: "2026-11-13", components: [
            FundComponent(symbol: "1001", name: "範例股票 A", weight: 12), FundComponent(symbol: "1002", name: "範例股票 B", weight: 5),
            FundComponent(symbol: "1003", name: "範例股票 C", weight: 3.5), FundComponent(symbol: "1005", name: "範例股票 E", weight: 4),
        ], source: "示意資料"),
    ]

    /// `--demo-active` with `--ui-testing`: 00982A (an active ETF) in the favourites with `activeSample` as its
    /// holdings history, so 主動式追蹤 has a change to show without asking anyone.
    @MainActor static func seedActive(_ store: PortfolioStore, args: [String]) {
        guard has("--demo-active", in: args), store.componentHistory(for: "00982A").isEmpty else { return }
        if !store.data.favorites.contains("00982A") { store.favorite("00982A") }
        for day in activeSample { try? store.saveComponents(day) }
    }

    @MainActor static func seedPocket(_ store: PortfolioStore, args: [String], now: Date, calendar: Calendar = .current) {
        guard has("--demo-pocket", in: args), store.data.holdings.isEmpty else { return }
        for item in pocketSample {
            let price = store.quote(item.symbol)?.price ?? 100
            let fund = store.funds.first { $0.id == item.symbol }
            try? store.save(Holding(symbol: item.symbol, name: fund?.name ?? item.symbol, shares: item.shares, unitCost: price / (1 + item.gain),
                                    broker: "", strategy: fund?.strategy ?? .unclassified))
        }
        // Every sample record is kept, so this year always has received dividends (even in January) and the totals
        // match the canvas. Each date is the 15th of its month, or today when that is still ahead; last year's records
        // likewise stop at today's date a year ago, so they all fall in the period 「比去年」 compares with.
        let year = calendar.component(.year, from: now)
        let aYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        let records = dividendSample.map { (year, now, $0) } + lastYearSample.map { (year - 1, aYearAgo, $0) }
        for (y, latest, item) in records {
            guard let fifteenth = calendar.date(from: DateComponents(year: y, month: item.month, day: 15)) else { continue }
            let date = min(fifteenth, latest)
            try? store.saveDividend(Dividend(symbol: item.symbol, date: date, amount: item.amount, status: .paid, source: DividendSource.broker.rawValue))
        }
    }

    // MARK: `--demo-store`

    /// The level and the months of 定期定額 the store screenshots show.
    static let storeLevel = 7, storeStreak = 12
    /// 到價提醒 of the store screenshots: two being watched and one that fired the day before.
    static let alertSample: [(symbol: String, above: Bool, price: Double, fired: Bool)] = [
        ("0050", true, 200, false), ("00878", false, 21, false), ("006208", true, 120, true),
    ]
    /// A second dividend received last month, so 口袋月報 has an amount to show whatever month the pictures are taken in.
    static let lastMonthDividend: (symbol: String, day: Int, amount: Double) = ("0050", 20, 1280)
    /// Ex-dividends announced for the days ahead, for 配息's 「即將除息」: code, days from today and amount per unit.
    static let upcomingSample: [(symbol: String, days: Int, perShare: Double)] = [("00878", 5, 0.55), ("00679B", 12, 0.33)]

    /// `--demo-store`'s game progress, in the real fields the lobby and 口袋月報 read: `storeStreak` months of 定期定額
    /// up to this one, `storeLevel` with the bar three fifths of the way, all but the last of this month's quests done,
    /// and last month complete (every quest, a 對帳 and two new 圖鑑 cards). The experience of each month is what
    /// `GameRules` pays for those actions; the earlier months share the rest, so `xpByMonth` adds up to `xp`.
    static func seedStoreGame(_ game: inout GameState, now: Date) {
        var months = [YearMonth(now)]
        while months.count < storeStreak { months.append(months[months.count - 1].previous()) }
        let this = months[0], last = months[1], earlier = Array(months.dropFirst(2))
        game.dcaMonths = Set(months)
        game.longestStreak = max(game.longestStreak, storeStreak)

        let habit = game.habit ?? .dca
        let quests = Quests.forMonth(this, habit: habit, isNewbie: false)
        game.questsDone[this.key] = Set(quests.dropLast().map(\.id))
        game.questsDone[last.key] = Set(Quests.forMonth(last, habit: habit, isNewbie: false).map(\.id))
        game.rewardKeys.insert(GameState.reconciledKey + last.key)
        // The pocket's four cards: two collected in the first months, two last month.
        func noon(_ month: YearMonth, _ day: Int) -> Date {
            GameRules.taipei.date(from: DateComponents(year: month.year, month: month.month, day: day, hour: 12)) ?? now
        }
        let collected = [noon(months[storeStreak - 1], 15), noon(months[storeStreak - 2], 15), noon(last, 8), noon(last, 22)]
        for (item, date) in zip(pocketSample, collected) { game.collected[item.symbol] = date }

        func pays(_ event: XPEvent) -> Int { GameRules.xp[event] ?? 0 }
        let total = (storeLevel - 1) * GameRules.xpPerLevel + GameRules.xpPerLevel * 3 / 5
        var byMonth = [
            this.key: pays(.monthlyDCA) + (quests.count - 1) * pays(.questDone),
            last.key: pays(.monthlyDCA) + quests.count * pays(.questDone) + pays(.reconciled) + 2 * pays(.firstDexCard),
        ]
        let rest = total - byMonth.values.reduce(0, +)
        for (i, month) in earlier.enumerated() { byMonth[month.key] = rest / earlier.count + (i == 0 ? rest % earlier.count : 0) }
        game.xpByMonth = byMonth
        game.xp = total
        game.coins = total
        // Set-up, not an earned level: no LEVEL×UP for it.
        game.celebrate(GameRules.level(xp: total)); game.celebratedLevel = GameRules.level(xp: total)
    }

    /// The weekday `days` after `now` (a Saturday or Sunday moves on to Monday), as "2026-11-19".
    static func weekday(after days: Int, from now: Date) -> String {
        var date = GameRules.taipei.date(byAdding: .day, value: days, to: now) ?? now
        for _ in 0..<2 where GameRules.taipei.isDateInWeekend(date) { date = GameRules.taipei.date(byAdding: .day, value: 1, to: date) ?? date }
        return DataChecks.day(date)
    }

    /// `--demo-store` with `--ui-testing`, after `seedPocket`: `alertSample` in an empty 到價提醒 list (saved as a list,
    /// so nothing is checked, posted or asked of the notification settings), `lastMonthDividend`, and `upcomingSample`
    /// as announcements kept in memory for this launch. Like every seed it goes to the UI tests' own records file.
    @MainActor static func seedStore(_ store: PortfolioStore, args: [String], now: Date) {
        guard has("--demo-store", in: args) else { return }
        if store.alerts.isEmpty {
            var fired: [UUID] = []
            for item in alertSample {
                guard (try? store.addAlert(symbol: item.symbol, above: item.above, price: item.price)) != nil, let alert = store.alerts.last else { continue }
                if item.fired { fired.append(alert.id) }
            }
            _ = try? store.fireAlerts(fired, now: GameRules.taipei.date(byAdding: .day, value: -1, to: now) ?? now)
        }
        var next = store.data
        let last = YearMonth(now).previous(), extra = lastMonthDividend
        if !next.dividends.contains(where: { $0.symbol == extra.symbol && $0.amount == extra.amount && YearMonth($0.date) == last }),
           let date = GameRules.taipei.date(from: DateComponents(year: last.year, month: last.month, day: extra.day, hour: 12)) {
            next.dividends.append(Dividend(symbol: extra.symbol, date: date, amount: extra.amount, status: .paid, source: DividendSource.broker.rawValue))
        }
        try? store.commit(next)
        var announced: [String: [OfficialDistribution]] = [:]
        for item in upcomingSample {
            announced[item.symbol, default: []].append(OfficialDistribution(ex: weekday(after: item.days, from: now), pay: "", amount: item.perShare))
        }
        store.showOfficial(announced)
    }
}
