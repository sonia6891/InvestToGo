import XCTest
@testable import PocketCore

/// 口袋月報／年報 (spec 5.5): what a card counts for a period, and when the lobby announces a new one.
final class PocketReportTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        GameRules.taipei.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }
    private let now = GameRules.taipei.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12))!
    private func month(_ y: Int, _ m: Int) -> YearMonth { YearMonth(year: y, month: m) }
    private func dividend(_ y: Int, _ m: Int, _ d: Int, _ amount: Double, _ status: DividendStatus = .paid, symbol: String = "00878") -> Dividend {
        Dividend(symbol: symbol, date: date(y, m, d), amount: amount, status: status)
    }

    // MARK: The card

    func testMonthTotals() {
        var p = Portfolio()
        p.dividends = [dividend(2026, 10, 5, 300), dividend(2026, 10, 20, 200, symbol: "0056"), dividend(2026, 11, 1, 999),
                       dividend(2026, 10, 25, 50, .announced)]
        let card = PocketReport.make(.month(month(2026, 10)), portfolio: p, now: now)
        XCTAssertEqual(card.dividends, 500, "Only what was paid in October: not November's, not what is still to come")
        XCTAssertEqual(card.title, "2026 年 10 月")
        XCTAssertEqual(card.notes, ["領息 2 筆，來自 2 檔。"])
    }

    /// 顯示領息金額 off: the note that counts the payments goes with the amount. A period with payments in it is
    /// still not called empty.
    func testDividendNoteIsLeftOutWhenDividendsAreHidden() {
        var p = Portfolio()
        p.dividends = [dividend(2026, 10, 5, 300), dividend(2026, 10, 20, 200, symbol: "0056")]
        let october = ReportPeriod.month(month(2026, 10))
        XCTAssertEqual(PocketReport.make(october, portfolio: p, now: now, showDividends: true).notes, ["領息 2 筆，來自 2 檔。"])
        let hidden = PocketReport.make(october, portfolio: p, now: now, showDividends: false)
        XCTAssertEqual(hidden.notes, [], "Neither the count of payments nor the line for an empty period")
        XCTAssertFalse(hidden.notes.contains { $0.contains("領息") })
        let empty = PocketReport.make(october, portfolio: Portfolio(), now: now, showDividends: false)
        XCTAssertEqual(empty.notes, ["這段時間還沒有紀錄。記一筆配息或定期定額，下一張就有內容。"], "A period with nothing in it keeps its line")
    }

    func testYearCountsDcaAndReconciles() {
        var game = GameState()
        game.dcaMonths = [month(2025, 12), month(2026, 1), month(2026, 3)]
        game.rewardKeys = ["reconciled|2026-01", "reconciled|2026-03", "reconciled|2025-12", "dividend|00878|2026-02", "reconciled|", "reconciled|2026-13"]
        var p = Portfolio()
        p.game = game
        let card = PocketReport.make(.year(2026), portfolio: p, now: date(2027, 1, 5))
        XCTAssertEqual(card.dcaMonths, 2)
        XCTAssertEqual(card.reconciles, 2, "Only the 對帳 keys of 2026; other rewards and keys that are no month count for nothing")
        XCTAssertEqual(card.title, "2026 年")
    }

    func testXpOmittedWithoutLog() {
        var game = GameState()
        game.xp = 640
        var p = Portfolio()
        p.game = game
        let card = PocketReport.make(.year(2026), portfolio: p, now: now)
        XCTAssertNil(card.xpEarned, "Experience earned before it was recorded by month is not guessed at")
        XCTAssertEqual(card.level, 3, "The level held now is still shown")
    }

    func testXpIsTheSumOfTheMonthsRecordedInThePeriod() {
        var game = GameState()
        game.xpByMonth = ["2025-12": 500, "2026-09": 100, "2026-10": 60, "2026-11": 40, "junk": 7]
        var p = Portfolio()
        p.game = game
        XCTAssertEqual(PocketReport.make(.month(month(2026, 10)), portfolio: p, now: now).xpEarned, 60)
        XCTAssertEqual(PocketReport.make(.year(2026), portfolio: p, now: now).xpEarned, 200)
        XCTAssertEqual(PocketReport.make(.yearToDate(2026), portfolio: p, now: now).xpEarned, 200)
        XCTAssertNil(PocketReport.make(.month(month(2026, 8)), portfolio: p, now: now).xpEarned, "August has no entry")
        XCTAssertNil(PocketReport.make(.year(2024), portfolio: p, now: now).xpEarned)
    }

    func testNewDexCardsAreTheOnesCollectedInThePeriod() {
        var game = GameState()
        // 00:30 on 1 November in Taipei is still 31 October in UTC: the Taipei month is the one that counts.
        game.collected = ["0050": date(2026, 10, 3), "0056": date(2026, 10, 31, hour: 23), "00878": date(2026, 11, 1, hour: 0), "006208": date(2025, 10, 9)]
        var p = Portfolio()
        p.game = game
        XCTAssertEqual(PocketReport.make(.month(month(2026, 10)), portfolio: p, now: now).newDexCards, 2)
        XCTAssertEqual(PocketReport.make(.month(month(2026, 11)), portfolio: p, now: now).newDexCards, 1)
        XCTAssertEqual(PocketReport.make(.year(2026), portfolio: p, now: now).newDexCards, 3)
    }

    func testYearToDateStopsAtNow() {
        var game = GameState()
        game.dcaMonths = [month(2025, 12), month(2026, 1), month(2026, 11), month(2026, 12)]
        game.xpByMonth = ["2026-11": 100, "2026-12": 100]
        var p = Portfolio()
        p.game = game
        p.dividends = [dividend(2026, 1, 15, 100), dividend(2026, 11, 14, 40), dividend(2026, 11, 20, 70), dividend(2025, 12, 31, 900)]
        let card = PocketReport.make(.yearToDate(2026), portfolio: p, now: now)
        XCTAssertEqual(card.dividends, 140, "A payment dated after today is not received yet")
        XCTAssertEqual(card.dcaMonths, 2, "January and November; December has not come")
        XCTAssertEqual(card.xpEarned, 100)
        XCTAssertEqual(card.title, "2026 年 1 月 1 日至 11 月 14 日")
        XCTAssertEqual(ReportPeriod.yearToDate(2025).title(now: now), "2025 年", "A year that is over is named as the year")
    }

    /// Nothing done and nothing received: a card of zeros with one friendly line, never an empty one.
    func testEmptyPeriodStillMakesACard() {
        let card = PocketReport.make(.month(month(2026, 10)), portfolio: Portfolio(), now: now)
        XCTAssertEqual(card, ReportCard(title: "2026 年 10 月", dividends: 0, dcaMonths: 0, reconciles: 0, newDexCards: 0, level: 1, xpEarned: nil,
                                        notes: ["這段時間還沒有紀錄。記一筆配息或定期定額，下一張就有內容。"]))
        var game = GameState()
        game.dcaMonths = [month(2026, 10)]
        var p = Portfolio()
        p.game = game
        XCTAssertEqual(PocketReport.make(.month(month(2026, 10)), portfolio: p, now: now).notes, [], "A month with something in it needs no such line")
    }

    func testEarliestMonthIsTheFirstThingAReportCounts() {
        XCTAssertNil(PocketReport.earliestMonth(Portfolio(), now: now))
        var game = GameState()
        game.dcaMonths = [month(2026, 3)]
        game.collected = ["0050": date(2026, 2, 3)]
        game.rewardKeys = ["reconciled|2026-01"]
        game.xpByMonth = ["2026-05": 20]
        var p = Portfolio()
        p.game = game
        p.dividends = [dividend(2025, 9, 9, 10, .estimated), dividend(2026, 4, 9, 10), dividend(2027, 1, 9, 10)]
        XCTAssertEqual(PocketReport.earliestMonth(p, now: now), month(2026, 1), "Estimates are not received; the 對帳 of January is the first")
        p.dividends.append(dividend(2025, 11, 9, 10))
        XCTAssertEqual(PocketReport.earliestMonth(p, now: now), month(2025, 11))
    }

    // MARK: Experience by month

    func testAwardsAreFiledUnderTheTaipeiMonthTheyWereEarnedIn() {
        var g = GameState()
        g.habit = .dca
        let october = date(2026, 10, 31, hour: 23), november = date(2026, 11, 1, hour: 0)
        // A debit of October typed in on 1 November: the month is October's, the experience is November's.
        XCTAssertEqual(g.logBuy(on: october, now: november), [.monthlyDCA])
        XCTAssertEqual(g.xpByMonth, ["2026-11": 100])
        XCTAssertEqual(g.collect("0050", now: october), [.firstDexCard])
        XCTAssertEqual(g.reconcile(now: november).first, .reconciled)
        g.award(.questDone, at: november)
        XCTAssertEqual(g.xpByMonth["2026-10"], 30)
        XCTAssertEqual(g.xpByMonth.values.reduce(0, +), g.xp, "Every point earned is in some month")
        var p = Portfolio()
        p.game = g
        XCTAssertEqual(PocketReport.make(.month(month(2026, 10)), portfolio: p, now: date(2026, 11, 14)).xpEarned, 30)
    }

    /// Progress saved before experience was kept by month has no such key: it loads, with nothing recorded.
    func testProgressSavedBeforeXpByMonthStillLoads() throws {
        let old = #"{"schema":1,"holdings":[],"dividends":[],"favorites":[],"quotes":{},"game":{"xp":640,"coins":640,"rewardKeys":["reconciled|2026-10"],"migration":1}}"#
        let p = try Portfolio.decodeBackup(Data(old.utf8))
        XCTAssertEqual(p.game?.xp, 640)
        XCTAssertEqual(p.game?.xpByMonth, [:])
        let card = PocketReport.make(.month(month(2026, 10)), portfolio: p, now: now)
        XCTAssertNil(card.xpEarned)
        XCTAssertEqual(card.reconciles, 1)
        // What is saved now comes back the same, as a records file and as a backup.
        var game = try XCTUnwrap(p.game)
        game.award(.reconciled, at: now)
        var next = p
        next.game = game
        let back = try Portfolio.decodeBackup(JSONEncoder().encode(next))
        XCTAssertEqual(back.game?.xpByMonth, ["2026-11": 20])
    }

    func testMonthKeysAreReadBack() {
        XCTAssertEqual(YearMonth(key: "2026-11"), month(2026, 11))
        XCTAssertEqual(YearMonth(key: month(2025, 1).key), month(2025, 1))
        for junk in ["", "2026", "2026-13", "2026-00", "2026-1", "26-11", "2026-11-12", "abcd-ef", "-026-11", "+026-11", "2026-+1", "２０２６-11"] {
            XCTAssertNil(YearMonth(key: junk), junk)
        }
    }

    // MARK: The lobby's notice

    func testNoticeIsForMembersOncePerNewMonth() {
        // Records since September: October has a report.
        var p = Portfolio()
        p.dividends = [dividend(2026, 9, 15, 100)]
        XCTAssertTrue(PocketReport.noticeDue(now: now, seen: "2026-09", isMember: true, portfolio: p), "A new month has ended since the last notice")
        XCTAssertTrue(PocketReport.noticeDue(now: now, seen: "", isMember: true, portfolio: p), "Never announced before")
        XCTAssertFalse(PocketReport.noticeDue(now: now, seen: "2026-10", isMember: true, portfolio: p), "October's report was announced already")
        XCTAssertFalse(PocketReport.noticeDue(now: now, seen: "2026-09", isMember: false, portfolio: p), "Not a member")
        XCTAssertEqual(PocketReport.noticeMonth(now: now), month(2026, 10))
        // The month turns in Taipei time: 00:00 on 1 December there is the first moment November's report exists.
        XCTAssertFalse(PocketReport.noticeDue(now: date(2026, 11, 30, hour: 23), seen: "2026-10", isMember: true, portfolio: p))
        XCTAssertTrue(PocketReport.noticeDue(now: date(2026, 12, 1, hour: 0), seen: "2026-10", isMember: true, portfolio: p))
        XCTAssertEqual(PocketReport.noticeMonth(now: date(2027, 1, 3)), month(2026, 12))
    }

    /// 「有新月報時」: a member whose records begin this month, or who has none, has no report of last month to open.
    func testNoticeNeedsRecordsThatReachBackToTheMonth() {
        XCTAssertFalse(PocketReport.noticeDue(now: now, seen: "", isMember: true, portfolio: Portfolio()), "No records at all")
        var game = GameState()
        game.dcaMonths = [month(2026, 11)]
        game.xpByMonth = ["2026-11": 100]
        var p = Portfolio()
        p.game = game
        p.dividends = [dividend(2026, 11, 3, 100), dividend(2026, 9, 3, 100, .estimated)]
        XCTAssertFalse(PocketReport.noticeDue(now: now, seen: "", isMember: true, portfolio: p), "Started this month: last month has nothing")
        XCTAssertTrue(PocketReport.noticeDue(now: date(2026, 12, 2), seen: "", isMember: true, portfolio: p), "Next month there is a report of this one")
        // Anything a report counts in last month is enough.
        game.collected = ["0050": date(2026, 10, 31, hour: 23)]
        p.game = game
        XCTAssertTrue(PocketReport.noticeDue(now: now, seen: "", isMember: true, portfolio: p))
    }
}
