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
    /// The habit picked in onboarding; nil until then (callers use `habit ?? .dca`).
    var habit: Habit? = nil
    /// Event counters for achievements whose data source has no record of its own (see `count(_:)`).
    var counts: [String: Int] = [:]

    mutating func count(_ key: CounterKey) { counts[key.rawValue, default: 0] += 1 }
    func counter(_ key: CounterKey) -> Int { counts[key.rawValue, default: 0] }

    /// Spec 5.3: a newbie is someone who has not started a DCA yet.
    var isNewbie: Bool { dcaMonths.isEmpty }
}

/// Every field falls back to its default so progress saved by an older build never fails to decode
/// when a field is added. (In an extension to keep the memberwise `GameState()`; encode stays synthesized.)
extension GameState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? 0
        coins = try c.decodeIfPresent(Int.self, forKey: .coins) ?? 0
        dcaMonths = try c.decodeIfPresent(Set<YearMonth>.self, forKey: .dcaMonths) ?? []
        longestStreak = try c.decodeIfPresent(Int.self, forKey: .longestStreak) ?? 0
        collected = try c.decodeIfPresent([String: Date].self, forKey: .collected) ?? [:]
        unlocked = try c.decodeIfPresent([String: Date].self, forKey: .unlocked) ?? [:]
        questsDone = try c.decodeIfPresent([String: Set<String>].self, forKey: .questsDone) ?? [:]
        habit = try c.decodeIfPresent(Habit.self, forKey: .habit)
        counts = try c.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
    }
}
