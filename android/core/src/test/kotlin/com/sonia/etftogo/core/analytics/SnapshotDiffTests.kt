package com.sonia.etftogo.core.analytics

import com.sonia.etftogo.core.models.ComponentSnapshot
import com.sonia.etftogo.core.models.FundComponent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** `SnapshotDiff`: two days of one ETF's holdings compared, for 主動式 ETF 追蹤. */
class SnapshotDiffTests {
    private fun snapshot(date: String, weights: List<Pair<String, Double>>, source: String? = "test") =
        ComponentSnapshot("00982A", date, weights.map { FundComponent(it.first, "名稱" + it.first, it.second) }, source)
    private fun snapshot(date: String, vararg weights: Pair<String, Double>) = snapshot(date, weights.toList())

    @Test fun diff() {
        val change = SnapshotDiff.compare(snapshot("2026-11-11", "A" to 10.0, "B" to 5.0, "C" to 3.0), snapshot("2026-11-13", "A" to 12.0, "B" to 5.0, "D" to 4.0))
        assertEquals("2026-11-11", change.from)
        assertEquals("2026-11-13", change.to)
        assertEquals(listOf(FundComponent("D", "名稱D", 4.0)), change.added)
        assertEquals(listOf(FundComponent("C", "名稱C", 3.0)), change.removed)
        assertEquals(listOf(FundComponent("A", "名稱A", 12.0)), change.changed.map { it.component }, "The later day's weight")
        assertEquals(2.0, change.changed.firstOrNull()?.delta ?: 0.0, 1e-9)
        assertFalse(change.isEmpty)
        assertFalse(change.changedCut, "The one weight that moved is listed")
        assertEquals("11/13 與 11/11 相比", change.title)
    }

    @Test fun tinyChangeIgnored() {
        val change = SnapshotDiff.compare(snapshot("2026-11-11", "A" to 10.0), snapshot("2026-11-13", "A" to 10.005))
        assertTrue(change.changed.isEmpty())
        assertTrue(change.isEmpty)
        // A hundredth of a point does count, up or down, however the doubles round.
        val up = SnapshotDiff.compare(snapshot("2026-11-11", "A" to 10.0), snapshot("2026-11-13", "A" to 10.01))
        assertEquals(listOf("A"), up.changed.map { it.component.symbol })
        val down = SnapshotDiff.compare(snapshot("2026-11-11", "A" to 10.01), snapshot("2026-11-13", "A" to 10.0))
        assertEquals(listOf("A"), down.changed.map { it.component.symbol })
        assertTrue((down.changed.firstOrNull()?.delta ?: 0.0) < 0)
    }

    @Test fun topTen() {
        // S01 moves by 0.1, S02 by −0.2, S03 by 0.3 … S15 by 1.5.
        val codes = (1..15).map { "S%02d".format(it) }
        val old = snapshot("2026-11-11", codes.map { it to 5.0 })
        val moved = codes.mapIndexed { i, code -> val step = (i + 1) * 0.1; code to if (i % 2 == 0) 5 + step else 5 - step }
        val change = SnapshotDiff.compare(old, snapshot("2026-11-13", moved))
        assertEquals(10, change.changed.size)
        assertTrue(change.changedCut, "Fifteen moved and ten are listed: the heading says so")
        // Exactly ten moved: all of them are listed, so nothing was cut. Eleven: one was.
        fun firstMoved(count: Int) = SnapshotDiff.compare(snapshot("2026-11-11", codes.take(count).map { it to 5.0 }), snapshot("2026-11-13", moved.take(count)))
        assertEquals(10, firstMoved(10).changed.size)
        assertFalse(firstMoved(10).changedCut)
        assertEquals(10, firstMoved(11).changed.size)
        assertTrue(firstMoved(11).changedCut)
        assertEquals((6..15).reversed().map { "S%02d".format(it) }, change.changed.map { it.component.symbol }, "Largest move first, up or down")
        assertEquals(1.5, change.changed[0].delta, 1e-9)
        assertEquals(-1.4, change.changed[1].delta, 1e-9)
        assertTrue(change.added.isEmpty())
        assertTrue(change.removed.isEmpty())
    }

    @Test fun addedAndRemovedAreHeaviestFirst() {
        val change = SnapshotDiff.compare(snapshot("2026-11-11", "A" to 1.0, "B" to 7.0, "C" to 3.0), snapshot("2026-11-13", "X" to 2.0, "Y" to 9.0, "Z" to 2.0))
        assertEquals(listOf("Y", "X", "Z"), change.added.map { it.symbol }, "Equal weights go by code")
        assertEquals(listOf("B", "C", "A"), change.removed.map { it.symbol })
        assertTrue(change.changed.isEmpty())
    }

    /** The screen compares the two newest days kept, whatever order they come in; one day alone has nothing to compare. */
    @Test fun latestTakesTheTwoNewestDays() {
        assertNull(SnapshotDiff.latest(emptyList()))
        assertNull(SnapshotDiff.latest(listOf(snapshot("2026-11-13", "A" to 10.0))))
        // The same day twice is still one day.
        assertNull(SnapshotDiff.latest(listOf(snapshot("2026-11-13", "A" to 10.0), snapshot("2026-11-13", "A" to 11.0))))
        val history = listOf(snapshot("2026-11-10", "A" to 1.0), snapshot("2026-11-13", "A" to 12.0, "D" to 4.0), snapshot("2026-11-11", "A" to 10.0, "C" to 3.0))
        val change = SnapshotDiff.latest(history)
        assertEquals("2026-11-11", change?.from)
        assertEquals("2026-11-13", change?.to)
        assertEquals(listOf("D"), change?.added?.map { it.symbol })
        assertEquals(listOf("C"), change?.removed?.map { it.symbol })
        assertEquals(2.0, change?.changed?.firstOrNull()?.delta ?: 0.0, 1e-9)
    }

    /** B4. A fund company's day against a day from 富果 or an imported file is not compared. */
    @Test fun differentSourcesAreNotCompared() {
        assertEquals("兩次資料來源不同，暫不比較。", SnapshotDiff.mixedSources)
        var old = snapshot("2026-11-11", listOf("A" to 10.0, "B" to 5.0, "C" to 3.0), "群益投信")
        var new = snapshot("2026-11-13", listOf("A" to 12.0, "B" to 5.0, "D" to 4.0), "富果／投信揭露資料")
        val mixed = SnapshotDiff.compare(old, new)
        assertTrue(mixed.mixedSources)
        assertTrue(mixed.added.isEmpty() && mixed.removed.isEmpty() && mixed.changed.isEmpty(), "No 新增, 剔除 or 權重變化 is made up")
        assertEquals("2026-11-11", mixed.from)
        assertEquals("2026-11-13", mixed.to)
        assertEquals(true, SnapshotDiff.latest(listOf(new, old))?.mixedSources, "The screen's own comparison says so too")
        // An imported day, or one saved before the source was kept, is another source as well.
        new = new.copy(source = "使用者匯入；原來源：未提供")
        assertTrue(SnapshotDiff.compare(old, new).mixedSources)
        new = new.copy(source = null)
        assertTrue(SnapshotDiff.compare(old, new).mixedSources)
        // The same source on both days is compared as before.
        new = new.copy(source = "群益投信")
        val same = SnapshotDiff.compare(old, new)
        assertFalse(same.mixedSources)
        assertEquals(listOf("D"), same.added.map { it.symbol })
        assertEquals(listOf("C"), same.removed.map { it.symbol })
        old = old.copy(source = null); new = new.copy(source = null)
        assertFalse(SnapshotDiff.compare(old, new).mixedSources, "Two days with no source recorded are from the same build")
    }

    @Test fun titleSaysBothDays() {
        assertEquals("11/3", SnapshotDiff.shortDay("2026-11-03"))
        assertEquals("2026/1/13", SnapshotDiff.shortDay("2026-01-13", year = true))
        assertEquals("somewhen", SnapshotDiff.shortDay("somewhen"))
        val acrossYears = SnapshotDiff.compare(snapshot("2025-12-30", "A" to 10.0), snapshot("2026-01-02", "A" to 10.0))
        assertEquals("2026/1/2 與 2025/12/30 相比", acrossYears.title)
    }
}
