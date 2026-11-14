import Foundation

/// What changed between two days of one ETF's holdings (主動式 ETF 追蹤).
struct SnapshotChange {
    /// The earlier day and the later day, "yyyy-MM-dd".
    var from: String
    var to: String
    /// In the later day's holdings only, heaviest first.
    var added: [FundComponent]
    /// In the earlier day's holdings only (with the weight it had then), heaviest first.
    var removed: [FundComponent]
    /// In both, with a weight that moved: the later day's component and how many percentage points it moved by.
    var changed: [(component: FundComponent, delta: Double)]
    /// More weights moved than `changed` lists: it holds only the `SnapshotDiff.limit` largest moves.
    var changedCut = false
    /// The two days came from different places (a fund company's page against 富果 or an imported file): they list
    /// holdings differently, so nothing is compared and the lists above are empty. The screen says
    /// `SnapshotDiff.mixedSources` instead.
    var mixedSources = false

    /// Nothing was added or removed and no weight moved enough to list.
    var isEmpty: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }

    /// 「11/13 與 11/11 相比」: the two days in plain words, with the years when they differ.
    var title: String {
        let years = from.prefix(4) != to.prefix(4)
        return "\(SnapshotDiff.shortDay(to, year: years)) 與 \(SnapshotDiff.shortDay(from, year: years)) 相比"
    }
}

enum SnapshotDiff {
    /// A weight has to move by at least this many percentage points to count as changed.
    static let threshold = 0.01
    /// How many weight changes are listed.
    static let limit = 10
    /// Said in place of the lists when the two days are not from the same source.
    static let mixedSources = "兩次資料來源不同，暫不比較。"

    /// `changed` holds what is in both with |Δweight| ≥ 0.01, the largest move first, ten at most. Two days from
    /// different sources are not compared (`mixedSources`): one source's missing rows would read as 剔除, the
    /// other's extra ones as 新增.
    static func compare(old: ComponentSnapshot, new: ComponentSnapshot) -> SnapshotChange {
        guard old.source == new.source else {
            return SnapshotChange(from: old.date, to: new.date, added: [], removed: [], changed: [], mixedSources: true)
        }
        let before = Dictionary(old.components.map { ($0.symbol, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Set(new.components.map(\.symbol))
        var added: [FundComponent] = []
        var changed: [(component: FundComponent, delta: Double)] = []
        for component in new.components {
            guard let was = before[component.symbol] else { added.append(component); continue }
            let delta = component.weight - was.weight
            // 10 → 10.01 is a hundredth of a point however the two doubles round.
            if abs(delta) >= threshold - 1e-9 { changed.append((component: component, delta: delta)) }
        }
        let removed = old.components.filter { !after.contains($0.symbol) }
        changed.sort { a, b in
            let x = abs(a.delta), y = abs(b.delta)
            return x != y ? x > y : a.component.symbol < b.component.symbol
        }
        return SnapshotChange(from: old.date, to: new.date, added: added.sorted(by: heavier), removed: removed.sorted(by: heavier),
                              changed: Array(changed.prefix(limit)), changedCut: changed.count > limit)
    }

    /// The newest day against the newest day before it; nil until two different days are kept.
    static func latest(_ history: [ComponentSnapshot]) -> SnapshotChange? {
        let days = history.sorted { $0.date > $1.date }
        guard let new = days.first, let old = days.first(where: { $0.date < new.date }) else { return nil }
        return compare(old: old, new: new)
    }

    /// "2026-11-13" as 「11/13」, or 「2026/11/13」 with `year`; anything else as it came.
    static func shortDay(_ day: String, year: Bool = false) -> String {
        let parts = day.split(separator: "-").map { Int($0) }
        guard parts.count == 3, let y = parts[0], let m = parts[1], let d = parts[2] else { return day }
        return year ? "\(y)/\(m)/\(d)" : "\(m)/\(d)"
    }

    private static func heavier(_ a: FundComponent, _ b: FundComponent) -> Bool {
        a.weight != b.weight ? a.weight > b.weight : a.symbol < b.symbol
    }
}
