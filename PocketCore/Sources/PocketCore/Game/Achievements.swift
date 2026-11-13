import Foundation

// Goals are counts, never money (spec 6.5: no "存到 50 萬"). Source for all: spec 6.5 / 2026-11-11 doc section 8.
/// Consecutive months with a paid dividend. Source: spec 6.5 連續領息 (controller ruling).
let dividendStreakGoal = 6
/// A holding kept this many days counts as an anniversary. Source: spec 6.5 持有週年紀念 (one year).
let anniversaryDays = 365
let holdingAnniversaryGoal = 1
/// Months with a recorded DCA. Source: spec 6.5 定期定額打卡 (Task 4 brief: 12).
let dcaPunchCardGoal = 12
/// Held a year with no sells in that year. Source: spec 6.5 一年不亂動.
let steadyYearGoal = 1
/// Reconciliations completed. Source: spec 6.5 對帳達人 (controller ruling).
let reconcileMasterGoal = 5
/// Fee comparisons made. Source: spec 6.5 省費達人 (controller ruling).
let feeSaverGoal = 3
/// Checkups finished. Source: spec 6.5 體檢完成.
let checkupDoneGoal = 1
/// Dex cards collected. Source: spec 6.5 ETF 圖鑑 (controller ruling).
let dexCollectorGoal = 10
/// Ex-dividend season skin unlocked. Source: spec 6.5 除息季限定皮膚.
let exDividendSkinGoal = 1
/// Year reports opened. Source: spec 6.5 口袋年報.
let yearReportGoal = 1
/// Number of paid dividend records (a count, not an amount). Source: spec 6.5 累計領息里程碑 (controller ruling).
let dividendMilestoneGoal = 12

struct Achievement: Identifiable {
    let id: String
    let title: String
    let goal: Int
    /// The feature that would count toward it is not in the app yet: the wall shows 「即將推出」 instead of a
    /// progress bar stuck at 0, and it never unlocks (ruling R31).
    var comingSoon = false
    /// Current value toward `goal`, evaluated at `now`.
    let progress: (GameState, Portfolio, Date) -> Int

    init(id: String, title: String, goal: Int, comingSoon: Bool = false, progress: @escaping (GameState, Portfolio, Date) -> Int) {
        self.id = id; self.title = title; self.goal = goal; self.comingSoon = comingSoon; self.progress = progress
    }
}

enum Achievements {
    /// Longest run of consecutive months that have at least one paid dividend.
    static func longestDividendRun(_ p: Portfolio) -> Int {
        let months = Set(p.dividends.filter { $0.status == .paid }.map { YearMonth($0.date) })
        var best = 0
        for m in months where !months.contains(m.previous()) {
            var n = 0, x = m
            while months.contains(x) { n += 1; x = x.next() }
            best = max(best, n)
        }
        return best
    }

    private static func cutoff(_ now: Date) -> Date {
        GameRules.taipei.date(byAdding: .day, value: -anniversaryDays, to: now) ?? now
    }
    static func hasAnniversary(_ p: Portfolio, now: Date) -> Bool {
        let c = cutoff(now)
        return p.holdings.contains { ($0.purchaseDate ?? .distantFuture) <= c }
    }
    static func steady(_ p: Portfolio, now: Date) -> Bool {
        let c = cutoff(now)
        return hasAnniversary(p, now: now) && !(p.trades ?? []).contains { $0.action == .sell && $0.date > c }
    }

    static let all: [Achievement] = [
        Achievement(id: "dividendStreak", title: "連續領息", goal: dividendStreakGoal) { _, p, _ in longestDividendRun(p) },
        Achievement(id: "holdingAnniversary", title: "持有週年紀念", goal: holdingAnniversaryGoal) { _, p, now in hasAnniversary(p, now: now) ? 1 : 0 },
        Achievement(id: "dcaPunchCard", title: "定期定額打卡", goal: dcaPunchCardGoal) { g, _, _ in g.dcaMonths.count },
        Achievement(id: "steadyYear", title: "一年不亂動", goal: steadyYearGoal) { _, p, now in steady(p, now: now) ? 1 : 0 },
        Achievement(id: "reconcileMaster", title: "對帳達人", goal: reconcileMasterGoal) { g, _, _ in g.counter(.reconciled) },
        Achievement(id: "feeSaver", title: "省費達人", goal: feeSaverGoal) { g, _, _ in g.counter(.feeCompared) },
        Achievement(id: "checkupDone", title: "體檢完成", goal: checkupDoneGoal, comingSoon: true) { g, _, _ in g.counter(.checkup) },
        Achievement(id: "dexCollector", title: "ETF 圖鑑", goal: dexCollectorGoal) { g, _, _ in g.collected.count },
        Achievement(id: "exDividendSkin", title: "除息季限定皮膚", goal: exDividendSkinGoal, comingSoon: true) { g, _, _ in g.counter(.exDividendSeason) },
        Achievement(id: "yearReport", title: "口袋年報", goal: yearReportGoal, comingSoon: true) { g, _, _ in g.counter(.yearReport) },
        Achievement(id: "dividendMilestone", title: "累計領息里程碑", goal: dividendMilestoneGoal) { _, p, _ in p.dividends.filter { $0.status == .paid }.count }
    ]
}

extension GameState {
    /// Achievements unlocked since the last LEVEL×UP was accepted, in catalog order.
    var achievementsSinceCelebration: [String] {
        Achievements.all.map(\.id).filter { unlocked[$0] != nil && !celebratedAchievements.contains($0) }
    }

    /// Unlocks every achievement whose goal is met and returns the newly unlocked ids (catalog order).
    mutating func refreshAchievements(_ p: Portfolio, now: Date) -> [String] {
        var fresh: [String] = []
        for a in Achievements.all where !a.comingSoon && unlocked[a.id] == nil && a.progress(self, p, now) >= a.goal {
            unlocked[a.id] = now
            fresh.append(a.id)
        }
        return fresh
    }
}
