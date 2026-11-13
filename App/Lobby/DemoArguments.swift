import Foundation

/// Launch arguments that set up game progress for UI tests and screenshots; ignored without `--ui-testing`.
///
/// - `--demo-streak <n>`: DCA recorded in each of the n months up to and including this one.
/// - `--demo-level <n>`: experience at the start of level n, `(n - 1) × GameRules.xpPerLevel`.
/// - `--demo-xp <n>`: experience n (wins over `--demo-level`).
/// - `--open levelup`: the current level's LEVEL×UP is still to be shown (needs a level above 1).
/// - `--demo-pocket`: four sample holdings, one of them at a loss, and a year of received dividends (`seedPocket`).
/// - `--quiet-toasts`: no first-time notices (「收進圖鑑 +30 經驗」), so screenshots are the same every run.
///
/// Read elsewhere: `--skin <id>` (SkinStore), `--open <feature>` (the root view), `--skip-onboarding`,
/// `--open splash` and `--open onboarding [--page n]` (`Onboarding.start`), `--offline` and `--reduce-motion`.
enum DemoArguments {
    /// `--quiet-toasts` with `--ui-testing`: the CI skin matrix captures pages without first-time notices.
    static let quietToasts: Bool = {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--quiet-toasts")
    }()

    static func apply(to game: inout GameState, args: [String], now: Date) {
        guard args.contains("--ui-testing") else { return }
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
    @MainActor static func seedPocket(_ store: PortfolioStore, args: [String], now: Date, calendar: Calendar = .current) {
        guard args.contains("--ui-testing"), args.contains("--demo-pocket"), store.data.holdings.isEmpty else { return }
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
}
