import XCTest
@testable import ETFToGo

/// The game triggers wired at the real actions (final review C1, I1, I2, M3): each saves with its record, in one write.
final class GameTriggerStoreTests: XCTestCase {
    private lazy var directory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }()
    /// The store on this test's file; a second call reopens the same file (what a relaunch reads).
    @MainActor private func store() -> PortfolioStore { PortfolioStore(url: directory.appendingPathComponent("p.json")) }
    @MainActor private func game(_ s: PortfolioStore) -> GameState { s.data.game ?? GameState() }

    // MARK: Buys (新增持有, 新增交易紀錄)

    @MainActor func testNewHoldingWithAPurchaseDateRecordsThisMonthsDCA() throws {
        let s = store()
        var h = Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "", strategy: .saving)
        h.purchaseDate = Date()
        try s.save(h, logBuy: true)
        XCTAssertEqual(game(s).dcaMonths, [YearMonth(Date())])
        XCTAssertFalse(game(s).isNewbie, "The lobby leaves the newbie state")
        XCTAssertTrue(game(s).isDone(Quests.dcaLogged, in: YearMonth(Date())), "本月定投一次 is ticked")
        XCTAssertEqual(game(s).xp, 140, "+100 DCA, +40 quest")
        XCTAssertEqual(store().data.game?.dcaMonths.count, 1, "Saved with the holding")
        h.shares = 2000
        try s.save(h, logBuy: true)
        XCTAssertEqual(game(s).xp, 140, "Editing a holding earns nothing")
    }

    @MainActor func testHoldingSavedWithoutLogBuyEarnsNothing() throws {
        let s = store()
        var h = Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "", strategy: .saving)
        h.purchaseDate = Date()
        try s.save(h)
        XCTAssertNil(s.data.game, "Seeding and imports do not play")
    }

    @MainActor func testTradeBuyRecordsDCAAndSellDoesNot() throws {
        let s = store()
        // An existing holding takes the buy, so the test does not depend on the bundled fund list.
        try s.save(Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "", strategy: .saving))
        XCTAssertNil(s.data.game)
        try s.applyTrade(.buy, symbol: "0050", date: Date(), shares: 1000, amount: 50000, broker: "", logBuy: true)
        XCTAssertEqual(game(s).dcaMonths, [YearMonth(Date())])
        XCTAssertEqual(game(s).counter(.monthlyDCA), 1)
        try s.applyTrade(.sell, symbol: "0050", date: Date(), shares: 500, amount: 26000, broker: "", logBuy: true)
        XCTAssertEqual(game(s).counter(.monthlyDCA), 1, "A sell is not a DCA")
    }

    // MARK: Plan, dex, reconciliation, dividends

    @MainActor func testFundVisitCollectsOnceAndTheToastFollowsTheCap() throws {
        let s = store()
        let first = s.collectDexCard("0050")
        XCTAssertEqual(first, FundVisit(new: true, cardXP: 30))
        XCTAssertEqual(FundDetail.toastText(first), "收進圖鑑 +30 經驗")
        XCTAssertTrue(game(s).isDone(Quests.firstDexCard, in: YearMonth(Date())), "收集第 1 張圖鑑卡 is ticked")
        XCTAssertEqual(s.collectDexCard("0050"), FundVisit(), "A second visit collects nothing")
        _ = s.collectDexCard("0056"); _ = s.collectDexCard("00878")
        let fourth = s.collectDexCard("006208")
        XCTAssertEqual(fourth, FundVisit(new: true, cardXP: 0))
        XCTAssertEqual(FundDetail.toastText(fourth), "收進圖鑑", "Past this month's three, no experience is promised")
    }

    @MainActor func testBrokerImportReconcilesOncePerDay() throws {
        let s = store()
        let holding = Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "A", strategy: .saving)
        let preview = BrokerPreview(holdings: [holding], sourceAccount: "主", broker: "A")
        try s.importBroker(preview, replaceAccount: true)
        XCTAssertEqual(game(s).counter(.reconciled), 1)
        XCTAssertEqual(game(s).lastAward, .reconciled)
        try s.importBroker(preview, replaceAccount: true)
        XCTAssertEqual(game(s).counter(.reconciled), 1, "The same day again earns nothing")
        try s.importBroker(BrokerPreview(holdings: [], sourceAccount: "空", broker: "B"), replaceAccount: false)
        XCTAssertEqual(game(s).counter(.reconciled), 1)
    }

    @MainActor func testDeletingAndLoggingADividendAgainEarnsNothing() throws {
        let s = store()
        let record = Dividend(symbol: "00878", date: Date(), amount: 1500, status: .paid)
        try s.saveDividend(record, rewardNew: true)
        XCTAssertEqual(game(s).xp, 20)
        try s.removeDividend(record)
        try s.saveDividend(Dividend(symbol: "00878", date: Date(), amount: 1500, status: .paid), rewardNew: true)
        XCTAssertEqual(game(s).xp, 20, "Same code, same payment month: the key was already paid")
        XCTAssertEqual(s.pendingReward, 20, "Nothing earned, no second toast")
        XCTAssertEqual(store().data.game?.rewardKeys.count, 1, "The awarded key is saved with the game")
    }

    // MARK: Launch

    @MainActor func testMigrationBackfillsAtLaunchWithoutExperience() throws {
        let s = store()
        var h = Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "", strategy: .saving)
        h.purchaseDate = GameRules.taipei.date(byAdding: .month, value: -2, to: Date())
        try s.save(h)
        try s.updateGame { $0.migrate(s.data) }
        XCTAssertEqual(game(s).dcaMonths.count, 1)
        XCTAssertEqual(game(s).xp, 0)
        XCTAssertNil(game(s).levelUpDue)
        XCTAssertEqual(store().data.game?.migration, GameMigration.current, "Saved, so it runs once")
    }

    @MainActor func testExistingRecordsCountAsOnboarded() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "onboarding-\(UUID().uuidString)"))
        Onboarding.adoptExisting(Portfolio(), defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: Onboarding.doneKey), "A fresh install sees the first-launch flow")
        Onboarding.adoptExisting(Portfolio.sample, defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: Onboarding.doneKey), "Upgrading with holdings skips it")
        var dividendsOnly = Portfolio()
        dividendsOnly.dividends = [Dividend(symbol: "00878", date: Date(), amount: 1, status: .paid)]
        let other = try XCTUnwrap(UserDefaults(suiteName: "onboarding-\(UUID().uuidString)"))
        Onboarding.adoptExisting(dividendsOnly, defaults: other)
        XCTAssertTrue(other.bool(forKey: Onboarding.doneKey))
    }

    // MARK: Membership lapse (I1)

    @MainActor func testLapsedMembershipTakesOffMemberSkinsAfterStoreKitAnswers() {
        let savedSkin = UserDefaults.standard.string(forKey: SkinStore.skinKey)
        defer {
            if let savedSkin { UserDefaults.standard.set(savedSkin, forKey: SkinStore.skinKey) } else { UserDefaults.standard.removeObject(forKey: SkinStore.skinKey) }
            SkinStore.current = SkinStore.shared.skin
        }
        let skins = SkinStore()
        let membership = MembershipStore()
        membership.skins = skins
        membership.checksWornSkin = true
        var level = 1
        membership.level = { level }
        var notices: [String] = []
        membership.onLapse = { notices.append($0) }

        skins.select("stitch")
        membership.apply([MembershipProducts.pocketMonthly])
        XCTAssertEqual(skins.skin.id, "stitch", "A member keeps the member skin")
        XCTAssertTrue(notices.isEmpty)
        membership.apply([])
        XCTAssertEqual(skins.skin.id, "blackgold", "Lapsed: back to black-gold")
        XCTAssertEqual(notices, ["會員已到期，已換回黑金"])

        // A level skin worn early through membership goes too, unless the level has been reached since.
        let voxel = Skins.named("voxel")
        guard case .level(let needed) = voxel.unlock else { return XCTFail("像素 unlocks by level") }
        skins.select("voxel")
        membership.apply([])
        XCTAssertEqual(skins.skin.id, "blackgold")
        level = needed
        skins.select("voxel")
        membership.apply([])
        XCTAssertEqual(skins.skin.id, "voxel", "Its level reached: still worn")
        XCTAssertEqual(notices.count, 2)
    }

    @MainActor func testWornSkinIsNotCheckedInUITests() {
        let membership = MembershipStore()
        let skins = SkinStore()
        let savedSkin = UserDefaults.standard.string(forKey: SkinStore.skinKey)
        defer {
            if let savedSkin { UserDefaults.standard.set(savedSkin, forKey: SkinStore.skinKey) } else { UserDefaults.standard.removeObject(forKey: SkinStore.skinKey) }
            SkinStore.current = SkinStore.shared.skin
        }
        membership.skins = skins
        membership.checksWornSkin = false
        skins.select("stitch")
        membership.apply([])
        XCTAssertEqual(skins.skin.id, "stitch")
    }

    @MainActor func testOnlyThePocketPlanIsSold() {
        XCTAssertEqual(MembershipProducts.sold, [MembershipProducts.pocketMonthly])
        XCTAssertTrue(MembershipProducts.all.contains(MembershipProducts.aiMonthly), "An AI purchase already held still counts")
        XCTAssertTrue(MemberView.Plan.ai.comingSoon)
        XCTAssertNil(MemberView.Plan.allCases.first { $0.detail.contains("無限") || $0.detail.contains("1 個") }, "No unenforced limits or absent features")
        XCTAssertEqual(MemberView.privacy.absoluteString, "https://sonia6891.github.io/etftogo/privacy")
    }
}
