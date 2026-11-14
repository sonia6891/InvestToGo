import Foundation

/// The habit picked on the first onboarding page; steers which quests show up.
enum Habit: String, Codable, CaseIterable { case dca, dividends, savingGoal }

enum QuestTrigger: String, Hashable { case dcaLogged, dividendsViewed, newETFResearched, reminderSet, reconciled, firstPlanSet, firstDexCard }

struct Quest: Identifiable, Equatable {
    let id: String
    let title: String
    let trigger: QuestTrigger
}

enum Quests {
    static let dcaLogged = Quest(id: "dcaLogged", title: "本月定投一次", trigger: .dcaLogged)
    static let dividendsViewed = Quest(id: "dividendsViewed", title: "看一次配息", trigger: .dividendsViewed)
    static let newETFResearched = Quest(id: "newETFResearched", title: "研究 1 檔新 ETF", trigger: .newETFResearched)
    static let reminderSet = Quest(id: "reminderSet", title: "設定除息提醒", trigger: .reminderSet)
    static let reconciled = Quest(id: "reconciled", title: "完成一次對帳", trigger: .reconciled)
    static let firstPlanSet = Quest(id: "firstPlanSet", title: "設定第一筆定投", trigger: .firstPlanSet)
    static let firstDexCard = Quest(id: "firstDexCard", title: "收集第 1 張圖鑑卡", trigger: .firstDexCard)

    /// The fixed question bank: five monthly quests, then the two newbie ones.
    static let pool: [Quest] = [dcaLogged, dividendsViewed, newETFResearched, reminderSet, reconciled, firstPlanSet, firstDexCard]
    /// Earned once ever, never again in a later month.
    static let newbieOnly: Set<QuestTrigger> = [.firstPlanSet, .firstDexCard]
    private static let monthly = Array(pool.prefix(5))

    /// Each habit always keeps its own quest; the other two rotate through the rest by month.
    private static func core(_ h: Habit) -> Quest {
        switch h {
        case .dca: return dcaLogged
        case .dividends: return dividendsViewed
        case .savingGoal: return newETFResearched
        }
    }

    /// Always 3 quests. Same month + habit + newbie flag -> same result (seeded by year/month, no RNG).
    /// Newbies get 設定第一筆定投 and 收集第 1 張圖鑑卡 plus the habit's own quest.
    static func forMonth(_ m: YearMonth, habit: Habit, isNewbie: Bool) -> [Quest] {
        let c = core(habit)
        if isNewbie { return [firstPlanSet, firstDexCard, c] }
        let rest = monthly.filter { $0 != c }
        let seed = m.year * 12 + m.month
        return [c, rest[seed % rest.count], rest[(seed + 1) % rest.count]]
    }
}

extension GameState {
    /// Finishes this month's quest for `trigger`, only from the list the lobby shows this player
    /// (`Quests.forMonth` with `isNewbie`). `[.questDone]` once per quest per month; the newbie-only
    /// quests (設定第一筆定投, 收集第 1 張圖鑑卡) can be finished once ever. Otherwise `[]`.
    mutating func complete(_ q: QuestTrigger, now: Date) -> [XPEvent] {
        let m = YearMonth(now)
        guard let quest = Quests.forMonth(m, habit: habit ?? .dca, isNewbie: isNewbie).first(where: { $0.trigger == q }) else { return [] }
        if Quests.newbieOnly.contains(quest.trigger), questsDone.values.contains(where: { $0.contains(quest.id) }) { return [] }
        guard questsDone[m.key, default: []].insert(quest.id).inserted else { return [] }
        award(.questDone, at: now)
        return [.questDone]
    }
}

extension GameState {
    /// Whether the lobby's quest card ticks `quest` in `month`. Monthly quests count only in the month they were
    /// finished; the newbie-only ones stay done once finished in any month.
    func isDone(_ quest: Quest, in month: YearMonth) -> Bool {
        if Quests.newbieOnly.contains(quest.trigger) { return questsDone.values.contains { $0.contains(quest.id) } }
        return questsDone[month.key]?.contains(quest.id) ?? false
    }
}
