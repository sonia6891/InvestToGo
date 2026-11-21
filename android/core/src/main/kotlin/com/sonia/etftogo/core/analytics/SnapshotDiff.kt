package com.sonia.etftogo.core.analytics

import com.sonia.etftogo.core.models.ComponentSnapshot
import com.sonia.etftogo.core.models.FundComponent
import com.sonia.etftogo.core.support.swiftInt
import kotlin.math.abs

/** A weight that moved: the later day's component and how many percentage points it moved by. */
data class WeightChange(val component: FundComponent, val delta: Double)

/** What changed between two days of one ETF's holdings (主動式 ETF 追蹤). */
data class SnapshotChange(
    /** The earlier day and the later day, "yyyy-MM-dd". */
    val from: String,
    val to: String,
    /** In the later day's holdings only, heaviest first. */
    val added: List<FundComponent>,
    /** In the earlier day's holdings only (with the weight it had then), heaviest first. */
    val removed: List<FundComponent>,
    /** In both, with a weight that moved. */
    val changed: List<WeightChange>,
    /** More weights moved than `changed` lists: it holds only the `SnapshotDiff.limit` largest moves. */
    val changedCut: Boolean = false,
    /** The two days came from different places, so nothing is compared and the lists are empty. */
    val mixedSources: Boolean = false,
) {
    /** Nothing was added or removed and no weight moved enough to list. */
    val isEmpty: Boolean get() = added.isEmpty() && removed.isEmpty() && changed.isEmpty()

    /** 「11/13 與 11/11 相比」: the two days in plain words, with the years when they differ. */
    val title: String get() {
        val years = from.take(4) != to.take(4)
        return "${SnapshotDiff.shortDay(to, years)} 與 ${SnapshotDiff.shortDay(from, years)} 相比"
    }
}

object SnapshotDiff {
    /** A weight has to move by at least this many percentage points to count as changed. */
    const val threshold = 0.01
    /** How many weight changes are listed. */
    const val limit = 10
    /** Said in place of the lists when the two days are not from the same source. */
    const val mixedSources = "兩次資料來源不同，暫不比較。"

    /**
     * `changed` holds what is in both with |Δweight| ≥ 0.01, the largest move first, ten at most. Two days from
     * different sources are not compared (`mixedSources`).
     */
    fun compare(old: ComponentSnapshot, new: ComponentSnapshot): SnapshotChange {
        if (old.source != new.source) return SnapshotChange(old.date, new.date, emptyList(), emptyList(), emptyList(), mixedSources = true)
        val before = LinkedHashMap<String, FundComponent>()
        for (c in old.components) before.putIfAbsent(c.symbol, c)
        val after = new.components.map { it.symbol }.toSet()
        val added = mutableListOf<FundComponent>()
        val changed = mutableListOf<WeightChange>()
        for (component in new.components) {
            val was = before[component.symbol]
            if (was == null) { added += component; continue }
            val delta = component.weight - was.weight
            // 10 → 10.01 is a hundredth of a point however the two doubles round.
            if (abs(delta) >= threshold - 1e-9) changed += WeightChange(component, delta)
        }
        val removed = old.components.filter { it.symbol !in after }
        val sorted = changed.sortedWith { a, b ->
            val x = abs(a.delta)
            val y = abs(b.delta)
            if (x != y) y.compareTo(x) else a.component.symbol.compareTo(b.component.symbol)
        }
        return SnapshotChange(old.date, new.date, added.sortedWith(heavier), removed.sortedWith(heavier), sorted.take(limit), changedCut = sorted.size > limit)
    }

    /** The newest day against the newest day before it; null until two different days are kept. */
    fun latest(history: List<ComponentSnapshot>): SnapshotChange? {
        val days = history.sortedByDescending { it.date }
        val new = days.firstOrNull() ?: return null
        val old = days.firstOrNull { it.date < new.date } ?: return null
        return compare(old, new)
    }

    /** "2026-11-13" as 「11/13」, or 「2026/11/13」 with `year`; anything else as it came. */
    fun shortDay(day: String, year: Boolean = false): String {
        // Swift `split(separator: "-")` drops empty pieces.
        val parts = day.split("-").filter { it.isNotEmpty() }.map(::swiftInt)
        if (parts.size != 3) return day
        val y = parts[0] ?: return day
        val m = parts[1] ?: return day
        val d = parts[2] ?: return day
        return if (year) "$y/$m/$d" else "$m/$d"
    }

    private val heavier = Comparator<FundComponent> { a, b -> if (a.weight != b.weight) b.weight.compareTo(a.weight) else a.symbol.compareTo(b.symbol) }
}
