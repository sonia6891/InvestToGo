import Foundation

enum XPEvent: String, Hashable, Codable { case monthlyDCA, questDone, firstDexCard, dividendLogged, reconciled }

/// Keys of `GameState.counts`; shared by `award`, later feature code (`count(_:)`) and the achievements.
enum CounterKey: String {
    case monthlyDCA, questDone, firstDexCard, dividendLogged, reconciled
    case feeCompared, checkup, exDividendSeason, yearReport
}

extension XPEvent {
    /// The counter `award` increments.
    var counterKey: CounterKey {
        switch self {
        case .monthlyDCA: return .monthlyDCA
        case .questDone: return .questDone
        case .firstDexCard: return .firstDexCard
        case .dividendLogged: return .dividendLogged
        case .reconciled: return .reconciled
        }
    }
}

enum GameRules {
    /// Months are always counted in Taipei time so a debit near midnight lands in the month the user sees.
    static let taipei: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return c
    }()
    static let xpPerLevel = 300
    static let xp: [XPEvent: Int] = [.monthlyDCA: 100, .questDone: 40, .firstDexCard: 30, .dividendLogged: 20, .reconciled: 20]

    /// Starts at 1, no cap.
    static func level(xp: Int) -> Int { max(0, xp) / xpPerLevel + 1 }
    static func progress(xp: Int) -> (into: Int, needed: Int) { (max(0, xp) % xpPerLevel, xpPerLevel) }
}

extension GameState {
    /// Consecutive recorded months ending this month, or last month when this month's debit hasn't happened yet
    /// (a missing current month is not a break). Neither recorded -> 0.
    func streak(now: Date) -> Int {
        let this = YearMonth(now)
        var m = dcaMonths.contains(this) ? this : this.previous()
        var n = 0
        while dcaMonths.contains(m) { n += 1; m = m.previous() }
        return n
    }

    /// One monthly DCA per calendar month; a repeat in the same month earns nothing.
    mutating func recordDCA(on date: Date) -> [XPEvent] {
        let month = YearMonth(date)
        guard dcaMonths.insert(month).inserted else { return [] }
        // The run that contains this month (a backfilled month can join two runs).
        var run = 1
        var m = month.previous(); while dcaMonths.contains(m) { run += 1; m = m.previous() }
        m = month.next(); while dcaMonths.contains(m) { run += 1; m = m.next() }
        longestStreak = max(longestStreak, run)
        award(.monthlyDCA)
        return [.monthlyDCA]
    }

    /// One coin per XP point; coins only accumulate for now.
    mutating func award(_ e: XPEvent) {
        let gain = GameRules.xp[e] ?? 0
        xp += gain; coins += gain
        count(e.counterKey)
    }

    /// The level to celebrate with LEVEL×UP, or nil: the current level once experience has crossed a whole level
    /// above the last one celebrated. Several levels crossed at once are celebrated together, as the highest.
    var levelUpDue: Int? {
        nil // RED: not implemented yet
    }

    /// Records that LEVEL×UP for `level` was shown; it never goes back down.
    mutating func celebrate(_ level: Int) {
        // RED: not implemented yet
    }
}
