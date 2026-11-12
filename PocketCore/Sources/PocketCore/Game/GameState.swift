import Foundation

/// A calendar month in Taipei time; the unit the DCA streak counts in.
struct YearMonth: Codable, Hashable, Comparable {
    var year: Int
    var month: Int
    init(_ date: Date, calendar: Calendar = GameRules.taipei) {
        let c = calendar.dateComponents([.year, .month], from: date)
        year = c.year ?? 1970; month = c.month ?? 1
    }
    func next() -> YearMonth { month == 12 ? YearMonth(year: year + 1, month: 1) : YearMonth(year: year, month: month + 1) }
    func previous() -> YearMonth { month == 1 ? YearMonth(year: year - 1, month: 12) : YearMonth(year: year, month: month - 1) }
    /// "2026-11", the key used by `GameState.questsDone`.
    var key: String { String(format: "%04d-%02d", year, month) }
    static func < (a: YearMonth, b: YearMonth) -> Bool { (a.year, a.month) < (b.year, b.month) }
    init(year: Int, month: Int) { self.year = year; self.month = month }
}

/// Everything the game layer remembers; lives in `Portfolio.game` (nil in files written before it existed).
struct GameState: Codable, Equatable {
    var xp = 0
    var coins = 0
    var dcaMonths: Set<YearMonth> = []
    var longestStreak = 0
    /// Dex card id -> when it was collected.
    var collected: [String: Date] = [:]
    /// Achievement id -> when it was unlocked.
    var unlocked: [String: Date] = [:]
    /// "2026-11" -> ids of that month's finished quests.
    var questsDone: [String: Set<String>] = [:]
}
