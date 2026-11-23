import XCTest
@testable import PocketCore

/// 除息季: a dividend paid in July to September (Taipei time) counts once and unlocks 收成 for good.
final class DividendSeasonTests: XCTestCase {
    private func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
    /// 2026-11-21 12:00 Taipei.
    private var now: Date { instant("2026-11-21T04:00:00Z") }

    private func dividend(_ iso: String, status: DividendStatus = .paid, id: UUID = UUID()) -> Dividend {
        Dividend(id: id, symbol: "0056", date: instant(iso), amount: 1000, status: status)
    }
    private func portfolio(_ dividends: [Dividend]) -> Portfolio {
        var p = Portfolio(); p.dividends = dividends; return p
    }

    func testPaymentInSeasonUnlocks() {
        var g = GameState(); let p = portfolio([dividend("2026-08-15T02:00:00Z")])
        XCTAssertTrue(g.recordDividendSeason(p, now: now))
        XCTAssertEqual(g.counter(.exDividendSeason), 1); XCTAssertEqual(g.unlocked["exDividendSkin"], now)
    }

    func testOutsideSeasonDoesNot() {
        for iso in ["2026-06-15T02:00:00Z", "2026-10-02T02:00:00Z", "2026-12-25T02:00:00Z"] {
            var g = GameState()
            XCTAssertFalse(g.recordDividendSeason(portfolio([dividend(iso)]), now: now), iso)
            XCTAssertEqual(g.counter(.exDividendSeason), 0, iso); XCTAssertNil(g.unlocked["exDividendSkin"], iso)
        }
    }

    func testSeasonUsesTaipeiMonths() {
        var a = GameState()
        XCTAssertTrue(a.recordDividendSeason(portfolio([dividend("2026-06-30T16:30:00Z")]), now: now), "7/1 00:30 in Taipei")
        var b = GameState()
        XCTAssertFalse(b.recordDividendSeason(portfolio([dividend("2026-09-30T16:30:00Z")]), now: now), "10/1 00:30 in Taipei")
    }

    func testAnyYearAndAnyStatusCount() {
        var a = GameState()
        XCTAssertTrue(a.recordDividendSeason(portfolio([dividend("2023-09-10T02:00:00Z", status: .paid)]), now: now))
        var b = GameState()
        XCTAssertTrue(b.recordDividendSeason(portfolio([dividend("2027-07-20T02:00:00Z", status: .estimated)]), now: now))
    }

    func testOnlyOnce() {
        var g = GameState(); let p = portfolio([dividend("2026-08-15T02:00:00Z")])
        XCTAssertTrue(g.recordDividendSeason(p, now: now))
        XCTAssertFalse(g.recordDividendSeason(p, now: now.addingTimeInterval(86_400)))
        XCTAssertEqual(g.counter(.exDividendSeason), 1); XCTAssertEqual(g.unlocked["exDividendSkin"], now)
    }

    func testPaysNoExperience() {
        var g = GameState(); let before = g
        XCTAssertTrue(g.recordDividendSeason(portfolio([dividend("2026-08-15T02:00:00Z")]), now: now))
        XCTAssertEqual(g.xp, before.xp); XCTAssertEqual(g.coins, before.coins); XCTAssertEqual(g.xpByMonth, before.xpByMonth)
    }

    func testEditedDateCounts() {
        let id = UUID(); var g = GameState()
        XCTAssertFalse(g.recordDividendSeason(portfolio([dividend("2026-06-10T02:00:00Z", id: id)]), now: now))
        XCTAssertTrue(g.recordDividendSeason(portfolio([dividend("2026-07-10T02:00:00Z", id: id)]), now: now))
    }

    func testMigrateCountsOldRecords() {
        var g = GameState(); g.migration = GameMigration.current   // already migrated before this version
        g.migrate(portfolio([dividend("2025-08-05T02:00:00Z")]), now: now)
        XCTAssertNotNil(g.unlocked["exDividendSkin"])
    }

    func testMigrateTwiceIsStable() {
        var g = GameState(); let p = portfolio([dividend("2025-08-05T02:00:00Z")])
        g.migrate(p, now: now); let first = g
        g.migrate(p, now: now.addingTimeInterval(86_400))
        XCTAssertEqual(g, first)
    }

    func testAchievementDecodesAndUnlocks() throws {
        let ok = try JSONDecoder().decode(SkinUnlock.self, from: Data(#"{"kind":"achievement","id":"exDividendSkin"}"#.utf8))
        XCTAssertEqual(ok, .achievement("exDividendSkin"))
        XCTAssertThrowsError(try JSONDecoder().decode(SkinUnlock.self, from: Data(#"{"kind":"achievement"}"#.utf8)))
        var skin = Skins.default; skin.unlock = .achievement("exDividendSkin")
        XCTAssertFalse(Skins.isUnlocked(skin, level: 1, member: false, achievements: []))
        XCTAssertTrue(Skins.isUnlocked(skin, level: 1, member: false, achievements: ["exDividendSkin"]))
        XCTAssertTrue(Skins.isUnlocked(skin, level: 1, member: true, achievements: []))
    }
}
