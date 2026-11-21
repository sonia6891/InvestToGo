package com.sonia.etftogo.core.analytics

import com.sonia.etftogo.core.game.GameState
import com.sonia.etftogo.core.game.Habit
import com.sonia.etftogo.core.game.XPEvent
import com.sonia.etftogo.core.game.YearMonth
import com.sonia.etftogo.core.game.award
import com.sonia.etftogo.core.game.collect
import com.sonia.etftogo.core.game.logBuy
import com.sonia.etftogo.core.game.reconcile
import com.sonia.etftogo.core.game.taipei
import com.sonia.etftogo.core.models.Dividend
import com.sonia.etftogo.core.models.DividendStatus
import com.sonia.etftogo.core.models.Portfolio
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 口袋月報／年報 (spec 5.5): what a card counts for a period, and when the lobby announces a new one. */
class PocketReportTests {
    private fun date(y: Int, m: Int, d: Int, hour: Int = 12) = taipei(y, m, d, hour)
    private val now = taipei(2026, 11, 14)
    private fun month(y: Int, m: Int) = YearMonth(y, m)
    private fun dividend(y: Int, m: Int, d: Int, amount: Double, status: DividendStatus = DividendStatus.PAID, symbol: String = "00878") =
        Dividend(symbol = symbol, date = date(y, m, d), amount = amount, status = status)
    private val emptyLine = "這段時間還沒有紀錄。記一筆配息或定期定額，下一張就有內容。"
    private fun withGame(game: GameState, dividends: List<Dividend> = emptyList()) = Portfolio(dividends = dividends, game = game)

    // The card

    @Test fun monthTotals() {
        val p = Portfolio(dividends = listOf(dividend(2026, 10, 5, 300.0), dividend(2026, 10, 20, 200.0, symbol = "0056"), dividend(2026, 11, 1, 999.0),
            dividend(2026, 10, 25, 50.0, DividendStatus.ANNOUNCED)))
        val card = PocketReport.make(ReportPeriod.Month(month(2026, 10)), p, now)
        assertEquals(500.0, card.dividends, "Only what was paid in October: not November's, not what is still to come")
        assertEquals("2026 年 10 月", card.title)
        assertEquals(listOf("領息 2 筆，來自 2 檔。"), card.notes)
    }

    /** 顯示領息金額 off: the note that counts the payments goes with the amount. A period with payments is still not called empty. */
    @Test fun dividendNoteIsLeftOutWhenDividendsAreHidden() {
        val p = Portfolio(dividends = listOf(dividend(2026, 10, 5, 300.0), dividend(2026, 10, 20, 200.0, symbol = "0056")))
        val october = ReportPeriod.Month(month(2026, 10))
        assertEquals(listOf("領息 2 筆，來自 2 檔。"), PocketReport.make(october, p, now, showDividends = true).notes)
        val hidden = PocketReport.make(october, p, now, showDividends = false)
        assertEquals(emptyList(), hidden.notes, "Neither the count of payments nor the line for an empty period")
        assertFalse(hidden.notes.any { "領息" in it })
        val empty = PocketReport.make(october, Portfolio(), now, showDividends = false)
        assertEquals(listOf(emptyLine), empty.notes, "A period with nothing in it keeps its line")
    }

    @Test fun yearCountsDcaAndReconciles() {
        val game = GameState(dcaMonths = setOf(month(2025, 12), month(2026, 1), month(2026, 3)),
            rewardKeys = setOf("reconciled|2026-01", "reconciled|2026-03", "reconciled|2025-12", "dividend|00878|2026-02", "reconciled|", "reconciled|2026-13"))
        val card = PocketReport.make(ReportPeriod.Year(2026), withGame(game), date(2027, 1, 5))
        assertEquals(2, card.dcaMonths)
        assertEquals(2, card.reconciles, "Only the 對帳 keys of 2026; other rewards and keys that are no month count for nothing")
        assertEquals("2026 年", card.title)
    }

    @Test fun xpOmittedWithoutLog() {
        val card = PocketReport.make(ReportPeriod.Year(2026), withGame(GameState(xp = 640)), now)
        assertNull(card.xpEarned, "Experience earned before it was recorded by month is not guessed at")
        assertEquals(4, card.level, "The level held now is still shown")
    }

    @Test fun xpIsTheSumOfTheMonthsRecordedInThePeriod() {
        val p = withGame(GameState(xpByMonth = mapOf("2025-12" to 500, "2026-09" to 100, "2026-10" to 60, "2026-11" to 40, "junk" to 7)))
        assertEquals(60, PocketReport.make(ReportPeriod.Month(month(2026, 10)), p, now).xpEarned)
        assertEquals(200, PocketReport.make(ReportPeriod.Year(2026), p, now).xpEarned)
        assertEquals(200, PocketReport.make(ReportPeriod.YearToDate(2026), p, now).xpEarned)
        assertNull(PocketReport.make(ReportPeriod.Month(month(2026, 8)), p, now).xpEarned, "August has no entry")
        assertNull(PocketReport.make(ReportPeriod.Year(2024), p, now).xpEarned)
    }

    @Test fun newDexCardsAreTheOnesCollectedInThePeriod() {
        // 00:30 on 1 November in Taipei is still 31 October in UTC: the Taipei month is the one that counts.
        val p = withGame(GameState(collected = mapOf("0050" to date(2026, 10, 3), "0056" to date(2026, 10, 31, 23), "00878" to date(2026, 11, 1, 0), "006208" to date(2025, 10, 9))))
        assertEquals(2, PocketReport.make(ReportPeriod.Month(month(2026, 10)), p, now).newDexCards)
        assertEquals(1, PocketReport.make(ReportPeriod.Month(month(2026, 11)), p, now).newDexCards)
        assertEquals(3, PocketReport.make(ReportPeriod.Year(2026), p, now).newDexCards)
    }

    @Test fun yearToDateStopsAtNow() {
        val game = GameState(dcaMonths = setOf(month(2025, 12), month(2026, 1), month(2026, 11), month(2026, 12)), xpByMonth = mapOf("2026-11" to 100, "2026-12" to 100))
        val p = withGame(game, listOf(dividend(2026, 1, 15, 100.0), dividend(2026, 11, 14, 40.0), dividend(2026, 11, 20, 70.0), dividend(2025, 12, 31, 900.0)))
        val card = PocketReport.make(ReportPeriod.YearToDate(2026), p, now)
        assertEquals(140.0, card.dividends, "A payment dated after today is not received yet")
        assertEquals(2, card.dcaMonths, "January and November; December has not come")
        assertEquals(100, card.xpEarned)
        assertEquals("2026 年 1 月 1 日至 11 月 14 日", card.title)
        assertEquals("2025 年", ReportPeriod.YearToDate(2025).title(now), "A year that is over is named as the year")
    }

    /** Nothing done and nothing received: a card of zeros with one friendly line, never an empty one. */
    @Test fun emptyPeriodStillMakesACard() {
        val card = PocketReport.make(ReportPeriod.Month(month(2026, 10)), Portfolio(), now)
        assertEquals(ReportCard("2026 年 10 月", 0.0, 0, 0, 0, 1, null, listOf(emptyLine)), card)
        val p = withGame(GameState(dcaMonths = setOf(month(2026, 10))))
        assertEquals(emptyList(), PocketReport.make(ReportPeriod.Month(month(2026, 10)), p, now).notes, "A month with something in it needs no such line")
    }

    @Test fun earliestMonthIsTheFirstThingAReportCounts() {
        assertNull(PocketReport.earliestMonth(Portfolio(), now))
        val game = GameState(dcaMonths = setOf(month(2026, 3)), collected = mapOf("0050" to date(2026, 2, 3)), rewardKeys = setOf("reconciled|2026-01"), xpByMonth = mapOf("2026-05" to 20))
        var p = withGame(game, listOf(dividend(2025, 9, 9, 10.0, DividendStatus.ESTIMATED), dividend(2026, 4, 9, 10.0), dividend(2027, 1, 9, 10.0)))
        assertEquals(month(2026, 1), PocketReport.earliestMonth(p, now), "Estimates are not received; the 對帳 of January is the first")
        p = p.copy(dividends = p.dividends + dividend(2025, 11, 9, 10.0))
        assertEquals(month(2025, 11), PocketReport.earliestMonth(p, now))
    }

    // Experience by month

    @Test fun awardsAreFiledUnderTheTaipeiMonthTheyWereEarnedIn() {
        var g = GameState(habit = Habit.DCA)
        val october = date(2026, 10, 31, 23)
        val november = date(2026, 11, 1, 0)
        // A debit of October typed in on 1 November: the month is October's, the experience is November's.
        g.logBuy(october, november).let { (next, e) -> assertEquals(listOf(XPEvent.MONTHLY_DCA), e); g = next }
        assertEquals(mapOf("2026-11" to 100), g.xpByMonth)
        g.collect("0050", october).let { (next, e) -> assertEquals(listOf(XPEvent.FIRST_DEX_CARD), e); g = next }
        g.reconcile(november).let { (next, e) -> assertEquals(XPEvent.RECONCILED, e.first()); g = next }
        g = g.award(XPEvent.QUEST_DONE, november)
        assertEquals(30, g.xpByMonth["2026-10"])
        assertEquals(g.xp, g.xpByMonth.values.sum(), "Every point earned is in some month")
        assertEquals(30, PocketReport.make(ReportPeriod.Month(month(2026, 10)), withGame(g), date(2026, 11, 14)).xpEarned)
    }

    /** Progress saved before experience was kept by month has no such key: it loads, with nothing recorded. */
    @Test fun progressSavedBeforeXpByMonthStillLoads() {
        val old = """{"schema":1,"holdings":[],"dividends":[],"favorites":[],"quotes":{},"game":{"xp":640,"coins":640,"rewardKeys":["reconciled|2026-10"],"migration":1}}"""
        val p = Portfolio.decodeBackup(old.toByteArray())
        assertEquals(640, p.game?.xp)
        assertEquals(emptyMap(), p.game?.xpByMonth)
        val card = PocketReport.make(ReportPeriod.Month(month(2026, 10)), p, now)
        assertNull(card.xpEarned)
        assertEquals(1, card.reconciles)
        // What is saved now comes back the same, as a records file and as a backup.
        val game = assertNotNull(p.game).award(XPEvent.RECONCILED, now)
        val back = Portfolio.decodeBackup(p.copy(game = game).encode())
        assertEquals(mapOf("2026-11" to 20), back.game?.xpByMonth)
    }

    @Test fun monthKeysAreReadBack() {
        assertEquals(month(2026, 11), YearMonth.fromKey("2026-11"))
        assertEquals(month(2025, 1), YearMonth.fromKey(month(2025, 1).key))
        for (junk in listOf("", "2026", "2026-13", "2026-00", "2026-1", "26-11", "2026-11-12", "abcd-ef", "-026-11", "+026-11", "2026-+1", "２０２６-11")) {
            assertNull(YearMonth.fromKey(junk), junk)
        }
    }

    // The lobby's notice

    @Test fun noticeIsForMembersOncePerNewMonth() {
        // Records since September: October has a report.
        val p = Portfolio(dividends = listOf(dividend(2026, 9, 15, 100.0)))
        assertTrue(PocketReport.noticeDue(now, "2026-09", true, p), "A new month has ended since the last notice")
        assertTrue(PocketReport.noticeDue(now, "", true, p), "Never announced before")
        assertFalse(PocketReport.noticeDue(now, "2026-10", true, p), "October's report was announced already")
        assertFalse(PocketReport.noticeDue(now, "2026-09", false, p), "Not a member")
        assertEquals(month(2026, 10), PocketReport.noticeMonth(now))
        // The month turns in Taipei time: 00:00 on 1 December there is the first moment November's report exists.
        assertFalse(PocketReport.noticeDue(date(2026, 11, 30, 23), "2026-10", true, p))
        assertTrue(PocketReport.noticeDue(date(2026, 12, 1, 0), "2026-10", true, p))
        assertEquals(month(2026, 12), PocketReport.noticeMonth(date(2027, 1, 3)))
    }

    /** 「有新月報時」: a member whose records begin this month, or who has none, has no report of last month to open. */
    @Test fun noticeNeedsRecordsThatReachBackToTheMonth() {
        assertFalse(PocketReport.noticeDue(now, "", true, Portfolio()), "No records at all")
        var game = GameState(dcaMonths = setOf(month(2026, 11)), xpByMonth = mapOf("2026-11" to 100))
        var p = withGame(game, listOf(dividend(2026, 11, 3, 100.0), dividend(2026, 9, 3, 100.0, DividendStatus.ESTIMATED)))
        assertFalse(PocketReport.noticeDue(now, "", true, p), "Started this month: last month has nothing")
        assertTrue(PocketReport.noticeDue(date(2026, 12, 2), "", true, p), "Next month there is a report of this one")
        // Anything a report counts in last month is enough.
        game = game.copy(collected = mapOf("0050" to date(2026, 10, 31, 23)))
        p = p.copy(game = game)
        assertTrue(PocketReport.noticeDue(now, "", true, p))
    }
}
