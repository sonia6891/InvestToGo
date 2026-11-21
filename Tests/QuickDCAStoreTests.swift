import XCTest
@testable import ETFToGo

/// The quick DCA through the store: the draft it starts from, and the one write that saves it.
final class QuickDCAStoreTests: XCTestCase {
    private lazy var directory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }()
    @MainActor private func store(_ name: String = "p.json") -> PortfolioStore { PortfolioStore(url: directory.appendingPathComponent(name)) }
    private func suite() -> UserDefaults {
        let name = "QuickDCAStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
    private func holding(_ symbol: String = "0050", shares: Double = 1000) -> Holding {
        Holding(symbol: symbol, name: "元大台灣50", shares: shares, unitCost: 50, broker: "", strategy: .saving)
    }
    private func draft(symbol: String = "0050", amount: Int? = 5000, shares: Int? = 50, now: Date = Date()) -> QuickDCADraft {
        QuickDCADraft(symbol: symbol, amount: amount, shares: shares, date: now, broker: "", closeNote: nil)
    }

    @MainActor func testDraftFromPresetOnboardingOrLatestHolding() throws {
        let s = store()
        let defaults = suite()
        // Nothing yet: no fund, no amount.
        var d = s.quickDCADraft(defaults: defaults)
        XCTAssertEqual(d.symbol, "")
        XCTAssertNil(d.amount)
        // The latest buy of a held fund.
        try s.save(holding("00878"))
        try s.applyTrade(.buy, symbol: "00878", date: Date(), shares: 10, amount: 200, broker: "")
        XCTAssertEqual(s.quickDCADraft(defaults: defaults).symbol, "00878")
        // Onboarding beats the latest holding.
        defaults.set("0050", forKey: Onboarding.symbolKey)
        defaults.set(3000, forKey: Onboarding.monthlyKey)
        d = s.quickDCADraft(defaults: defaults)
        XCTAssertEqual(d.symbol, "0050")
        XCTAssertEqual(d.amount, 3000)
        // The saved preset beats onboarding.
        try s.save(holding("006208"))
        try s.logQuickDCA(draft(symbol: "006208", amount: 7000, shares: 70))
        d = s.quickDCADraft(defaults: defaults)
        XCTAssertEqual(d.symbol, "006208")
        XCTAssertEqual(d.amount, 7000)
    }

    @MainActor func testDraftEstimatesWholeSharesFromTheQuote() throws {
        let s = store()
        let defaults = suite()
        let now = Date()
        var next = s.data
        next.quotes["0050"] = Quote(symbol: "0050", price: 100, date: "2026-11-20", fetchedAt: now, currency: "TWD")
        try s.commit(next)
        defaults.set("0050", forKey: Onboarding.symbolKey)
        defaults.set(5000, forKey: Onboarding.monthlyKey)
        var d = s.quickDCADraft(now: now, defaults: defaults)
        XCTAssertEqual(d.shares, 50)
        XCTAssertEqual(d.closeNote, "以 11/20 收盤價估算，可改成實際成交股數")
        XCTAssertEqual(d.date, now)
        defaults.set(50, forKey: Onboarding.monthlyKey)
        d = s.quickDCADraft(now: now, defaults: defaults)
        XCTAssertNil(d.shares, "50 buys less than one share")
        XCTAssertNil(d.closeNote)
    }

    @MainActor func testQuickDCAMergesIntoTheHoldingAndPays() throws {
        let s = store()
        let now = Date()
        try s.save(holding())
        try s.updateGame { $0.habit = .dca; $0.dcaMonths = [YearMonth(now).previous()] }
        let xp = try XCTUnwrap(s.data.game).xp
        try s.logQuickDCA(draft(now: now), now: now)
        XCTAssertEqual(s.data.holdings.count, 1)
        XCTAssertEqual(s.data.holdings.first?.shares, 1050)
        let trade = try XCTUnwrap(s.data.trades?.last)
        XCTAssertEqual(trade.action, .buy)
        XCTAssertEqual(trade.amount, 5000)
        XCTAssertEqual(trade.shares, 50)
        let game = try XCTUnwrap(s.data.game)
        XCTAssertTrue(game.dcaMonths.contains(YearMonth(now)))
        XCTAssertEqual(game.xp - xp, 140, "+100 monthly DCA, +40 本月定投一次")
        XCTAssertEqual(s.data.quickDCA, QuickDCAPreset(symbol: "0050", amount: 5000, broker: ""))
    }

    @MainActor func testSecondQuickDCAThisMonthEarnsNothingMore() throws {
        let s = store()
        let now = Date()
        try s.save(holding())
        try s.updateGame { $0.habit = .dca; $0.dcaMonths = [YearMonth(now).previous()] }
        try s.logQuickDCA(draft(now: now), now: now)
        let xp = try XCTUnwrap(s.data.game).xp
        let buys = s.data.trades?.filter { $0.action == .buy }.count ?? 0
        try s.logQuickDCA(draft(now: now), now: now)
        XCTAssertEqual(s.data.trades?.filter { $0.action == .buy }.count, buys + 1)
        XCTAssertEqual(s.data.game?.xp, xp)
    }

    @MainActor func testUnknownCodeIsRefused() throws {
        let s = store()
        XCTAssertFalse(s.quickDCAKnows("9999"))
        XCTAssertThrowsError(try s.logQuickDCA(draft(symbol: "9999"))) {
            XCTAssertEqual($0.localizedDescription, "找不到這檔 ETF")
        }
        XCTAssertEqual(s.data.trades?.count ?? 0, 0)
        XCTAssertNil(s.data.quickDCA)
    }

    @MainActor func testBackupCarriesThePreset() throws {
        let old = store("old.json")
        try old.save(holding())
        try old.logQuickDCA(draft())
        let backup = try Data(contentsOf: old.export())
        let phone = store("new.json")
        try phone.importBackup(backup)
        XCTAssertEqual(phone.data.quickDCA, QuickDCAPreset(symbol: "0050", amount: 5000, broker: ""))
    }

    @MainActor func testOldBackupStillRestores() throws {
        let old = store("old.json")
        try old.save(holding())
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: old.export())) as? [String: Any])
        root.removeValue(forKey: "quickDCA")
        let phone = store("new.json")
        try phone.importBackup(JSONSerialization.data(withJSONObject: root))
        XCTAssertEqual(phone.data.holdings.map(\.symbol), ["0050"])
        XCTAssertNil(phone.data.quickDCA)
    }
}
