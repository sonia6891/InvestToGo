import Foundation

/// The stretch of time one 口袋月報／年報 covers (spec 5.5), in Taipei months like the rest of the game layer.
enum ReportPeriod: Equatable {
    /// One calendar month.
    case month(YearMonth)
    /// One calendar year, January to December.
    case year(Int)
    /// 今年到目前: the year from January up to `now`.
    case yearToDate(Int)
}

extension ReportPeriod {
    /// Whether a Taipei month is part of the period. 今年到目前 stops at the month `now` is in.
    func contains(_ month: YearMonth, now: Date) -> Bool {
        switch self {
        case .month(let own): return month == own
        case .year(let year): return month.year == year
        case .yearToDate(let year): return month.year == year && month <= YearMonth(now)
        }
    }

    /// Whether a moment is part of the period. 今年到目前 leaves out anything dated after `now`.
    func contains(_ date: Date, now: Date) -> Bool {
        if case .yearToDate = self, date > now { return false }
        return contains(YearMonth(date), now: now)
    }

    /// 「2026 年 10 月」, 「2026 年」 or 「2026 年 1 月 1 日至 11 月 14 日」.
    func title(now: Date) -> String {
        switch self {
        case .month(let month): return "\(month.year) 年 \(month.month) 月"
        case .year(let year): return "\(year) 年"
        case .yearToDate(let year):
            let today = GameRules.taipei.dateComponents([.year, .month, .day], from: now)
            // A year that is over (or has not begun) has no "so far": it is named as the year.
            guard today.year == year, let month = today.month, let day = today.day else { return "\(year) 年" }
            return "\(year) 年 1 月 1 日至 \(month) 月 \(day) 日"
        }
    }
}

/// What one report card says. Only what the person did and received: never what the holdings are worth, what they
/// cost or what they gained, so the card can be shared (spec 5.5).
struct ReportCard: Equatable {
    /// The period, in words (`ReportPeriod.title`).
    var title: String
    /// Dividends received in the period, after deductions.
    var dividends: Double
    /// Months of the period with a 定期定額.
    var dcaMonths: Int
    /// 對帳 done in the period (once a month at most, as it is rewarded).
    var reconciles: Int
    /// 圖鑑 cards collected in the period.
    var newDexCards: Int
    /// The level held now.
    var level: Int
    /// Experience earned in the period; nil when no month of it was recorded (before `GameState.xpByMonth` existed),
    /// and the card then leaves the line out.
    var xpEarned: Int?
    /// One-line remarks under the figures.
    var notes: [String]
}

enum PocketReport {
    /// The card for `period`, from the records and the game progress as they are at `now`.
    static func make(_ period: ReportPeriod, portfolio: Portfolio, now: Date) -> ReportCard {
        let game = portfolio.game ?? GameState()
        let paid = portfolio.dividends.filter { $0.status == .paid && period.contains($0.date, now: now) }
        let dividends = paid.reduce(0) { $0 + $1.amount }
        let dcaMonths = game.dcaMonths.filter { period.contains($0, now: now) }.count
        let reconciles = reconciledMonths(game).filter { period.contains($0, now: now) }.count
        let newDexCards = game.collected.values.filter { period.contains($0, now: now) }.count
        let logged = xpMonths(game).filter { period.contains($0.month, now: now) }
        let xpEarned: Int? = logged.isEmpty ? nil : logged.reduce(0) { $0 + $1.xp }

        var notes: [String] = []
        if !paid.isEmpty { notes.append("領息 \(paid.count) 筆，來自 \(Set(paid.map(\.symbol)).count) 檔。") }
        if paid.isEmpty, dcaMonths == 0, reconciles == 0, newDexCards == 0, (xpEarned ?? 0) == 0 {
            notes.append("這段時間還沒有紀錄。記一筆配息或定期定額，下一張就有內容。")
        }
        return ReportCard(title: period.title(now: now), dividends: dividends, dcaMonths: dcaMonths, reconciles: reconciles,
                          newDexCards: newDexCards, level: GameRules.level(xp: game.xp), xpEarned: xpEarned, notes: notes)
    }

    /// The months whose 對帳 was rewarded: the 「reconciled|yyyy-MM」 reward keys.
    private static func reconciledMonths(_ game: GameState) -> [YearMonth] {
        game.rewardKeys.compactMap { key -> YearMonth? in
            guard key.hasPrefix(GameState.reconciledKey) else { return nil }
            return YearMonth(key: String(key.dropFirst(GameState.reconciledKey.count)))
        }
    }

    /// `GameState.xpByMonth` with its keys read back as months; a key that is not a month is left out.
    private static func xpMonths(_ game: GameState) -> [(month: YearMonth, xp: Int)] {
        game.xpByMonth.compactMap { entry -> (month: YearMonth, xp: Int)? in
            guard let month = YearMonth(key: entry.key) else { return nil }
            return (month: month, xp: entry.value)
        }
    }

    /// The first month anything a report counts happened in, never after `now`'s month; nil when nothing has. The
    /// screen does not step back past it.
    static func earliestMonth(_ portfolio: Portfolio, now: Date) -> YearMonth? {
        let game = portfolio.game ?? GameState()
        var months: [YearMonth] = portfolio.dividends.filter { $0.status == .paid }.map { YearMonth($0.date) }
        months += game.dcaMonths
        months += reconciledMonths(game)
        months += game.collected.values.map { YearMonth($0) }
        months += xpMonths(game).map { $0.month }
        let current = YearMonth(now)
        return months.filter { $0 <= current }.min()
    }

    /// Whether the lobby says 「上個月的口袋月報出爐了」 now: to a member, once for each month that has ended. `seen`
    /// is the month (「2026-10」) whose report was last announced, empty when none was.
    static func noticeDue(now: Date, seen: String, isMember: Bool) -> Bool {
        isMember && seen != noticeMonth(now: now).key
    }

    /// The month the lobby's notice is about: the one before `now`'s.
    static func noticeMonth(now: Date) -> YearMonth { YearMonth(now).previous() }
}
