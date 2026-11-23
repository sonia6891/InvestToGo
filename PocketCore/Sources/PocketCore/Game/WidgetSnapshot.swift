import Foundation

/// One quest as the widget shows it: no amounts, only an id, a title and a tick.
struct WidgetQuest: Codable, Equatable {
    var id: String
    var title: String
    var done: Bool
}

/// What the 「連續定投」 home-screen widget reads: a small file the app writes, with no amount in it. The app
/// and the widget extension compile this same file. `habit` and the quest ids are kept so a new month's quests
/// can be built without the app running.
struct WidgetSnapshot: Codable, Equatable {
    static let version = 1
    /// The newest months kept; the widget only needs the run that ends now.
    static let monthWindow = 24

    var version: Int
    var writtenAt: Date
    /// `YearMonth.key` of the month the quests belong to.
    var month: String
    var streak: Int
    var longestStreak: Int
    var isNewbie: Bool
    var habit: Habit
    /// The newest 24 DCA month keys, ascending.
    var dcaMonths: [String]
    var quests: [WidgetQuest]
    var skinID: String

    static func of(_ p: Portfolio, skinID: String, now: Date) -> WidgetSnapshot {
        let g = p.game ?? GameState()
        let habit = g.habit ?? .dca
        let month = YearMonth(now)
        let quests = Quests.forMonth(month, habit: habit, isNewbie: g.isNewbie).map {
            WidgetQuest(id: $0.id, title: $0.title, done: g.isDone($0, in: month, records: p))
        }
        let keys = g.dcaMonths.sorted().map(\.key)
        return WidgetSnapshot(version: version, writtenAt: now, month: month.key, streak: g.streak(now: now),
                              longestStreak: g.longestStreak, isNewbie: g.isNewbie, habit: habit,
                              dcaMonths: Array(keys.suffix(monthWindow)), quests: quests, skinID: skinID)
    }

    /// The snapshot as the widget shows it at `date`. In the written month (or an earlier one, the clock having
    /// gone back) it is itself; in a later month the quests reset and the streak is read again from the months.
    func display(at date: Date) -> WidgetSnapshot {
        let now = YearMonth(date)
        guard let written = YearMonth(key: month), now > written else { return self }
        var out = self
        out.month = now.key
        let months = Set(dcaMonths.compactMap { YearMonth(key: $0) })
        var g = GameState()
        g.dcaMonths = months
        let run = g.streak(now: date)
        // A run that reaches the oldest stored month may go on beyond the window: trust the stored count then.
        let reachesOldest = months.count >= Self.monthWindow && run == months.count
        out.streak = reachesOldest ? max(run, streak) : run
        out.quests = Quests.forMonth(now, habit: habit, isNewbie: isNewbie).map { q in
            let kept = Quests.newbieOnly.contains(q.trigger) && quests.contains { $0.id == q.id && $0.done }
            return WidgetQuest(id: q.id, title: q.title, done: kept)
        }
        return out
    }

    /// A copy with `writtenAt` zeroed, so two writes can be compared without the time.
    var unchanged: WidgetSnapshot {
        var c = self
        c.writtenAt = Date(timeIntervalSince1970: 0)
        return c
    }

    /// Nil when the data does not decode or comes from a newer app than this widget understands.
    static func decode(_ data: Data) -> WidgetSnapshot? {
        guard let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: data), s.version <= version else { return nil }
        return s
    }

    /// The placeholder for a missing or unreadable file.
    static func newbie(now: Date) -> WidgetSnapshot {
        let month = YearMonth(now)
        let quests = Quests.forMonth(month, habit: .dca, isNewbie: true).map { WidgetQuest(id: $0.id, title: $0.title, done: false) }
        return WidgetSnapshot(version: version, writtenAt: now, month: month.key, streak: 0, longestStreak: 0, isNewbie: true,
                              habit: .dca, dcaMonths: [], quests: quests, skinID: "blackgold")
    }

    /// The first instant of the next Taipei month; when the widget's timeline moves on.
    static func nextMonthStart(after date: Date) -> Date {
        let n = YearMonth(date).next()
        return GameRules.taipei.date(from: DateComponents(year: n.year, month: n.month, day: 1)) ?? date.addingTimeInterval(86_400)
    }
}

/// The big number on the widget and the words around it; never a bare 0.
struct WidgetHero: Equatable {
    var top: String
    var value: Int
    var bottom: String?

    static func of(_ s: WidgetSnapshot) -> WidgetHero {
        if s.streak > 0 { return WidgetHero(top: "連續定投", value: s.streak, bottom: "個月") }
        if s.isNewbie { return WidgetHero(top: "今天開始", value: 1, bottom: nil) }
        return WidgetHero(top: "今天開始", value: 1, bottom: "最長紀錄 \(max(s.longestStreak, 1)) 個月")
    }
}

extension WidgetSnapshot {
    var questLine: String { "本月任務 \(quests.filter(\.done).count)/\(quests.count)" }
}
