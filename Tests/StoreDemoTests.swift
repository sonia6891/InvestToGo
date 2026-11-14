import XCTest
@testable import ETFToGo

/// `--demo-store`: the state the App Store screenshots are taken in, and the member page's pieces that go with it.
final class StoreDemoTests: XCTestCase {
    private let store = ["--ui-testing", "--demo-store"]
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func noon(_ year: Int, _ month: Int, _ day: Int) -> Date {
        GameRules.taipei.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// Everything `--demo-store` seeds, in the order the app does it at launch.
    @MainActor private func seed(_ records: PortfolioStore, args: [String], now: Date) throws {
        try records.updateGame { DemoArguments.apply(to: &$0, args: args, now: now) }
        DemoArguments.seedPocket(records, args: args, now: now)
        DemoArguments.seedActive(records, args: args)
        DemoArguments.seedStore(records, args: args, now: now)
    }

    // MARK: The argument

    func testDemoStoreImpliesTheOtherDemosOnlyWithUITesting() {
        for flag in ["--demo-store", "--demo-member", "--demo-pocket", "--demo-active"] {
            XCTAssertTrue(DemoArguments.has(flag, in: store), "\(flag) is on with --ui-testing --demo-store")
            XCTAssertFalse(DemoArguments.has(flag, in: ["--demo-store"]), "\(flag) is ignored without --ui-testing")
        }
        XCTAssertFalse(DemoArguments.has("--demo-held", in: store), "Only the three it names are implied")
        XCTAssertFalse(DemoArguments.has("--demo-member", in: ["--ui-testing"]))
        XCTAssertTrue(MembershipStore.demoMember(from: store))
        XCTAssertFalse(MembershipStore.demoMember(from: ["--demo-store"]))
    }

    @MainActor func testDemoStoreDoesNothingWithoutUITesting() throws {
        let records = PortfolioStore(url: directory.appendingPathComponent("p.json"))
        try seed(records, args: ["--demo-store"], now: Date())
        XCTAssertEqual(records.data.game ?? GameState(), GameState(), "No game progress")
        XCTAssertTrue(records.data.holdings.isEmpty)
        XCTAssertTrue(records.data.dividends.isEmpty)
        XCTAssertTrue(records.alerts.isEmpty)
        XCTAssertTrue(records.data.favorites.isEmpty)
        XCTAssertTrue(records.official.list("00878").isEmpty, "No announcement is made up")
    }

    // MARK: Game progress

    /// The lobby: level 7 with the bar part-way, coins, 「12 個月」 and two of this month's three quests ticked,
    /// whatever month the pictures are taken in.
    func testDemoStoreGameIsAYearIn() {
        for month in 0..<12 {
            let now = GameRules.taipei.date(byAdding: .month, value: month, to: noon(2026, 11, 14))!
            var game = GameState()
            DemoArguments.apply(to: &game, args: store, now: now)
            XCTAssertEqual(GameRules.level(xp: game.xp), 7, "\(now)")
            let progress = GameRules.progress(xp: game.xp)
            XCTAssertGreaterThan(progress.into * 4, progress.needed, "The bar is visibly begun")
            XCTAssertLessThan(progress.into * 4, progress.needed * 3, "and visibly not full")
            XCTAssertGreaterThan(game.coins, 0)
            XCTAssertEqual(game.streak(now: now), 12)
            XCTAssertEqual(LobbyHero.of(game, now: now).caption, "12 個月")
            XCTAssertNil(game.levelUpDue, "Set-up is not an earned level")

            let this = YearMonth(now)
            let quests = Quests.forMonth(this, habit: game.habit ?? .dca, isNewbie: game.isNewbie)
            XCTAssertEqual(quests.map { game.isDone($0, in: this) }, [true, true, false], "本月任務 2/3")

            XCTAssertEqual(game.xpByMonth.values.reduce(0, +), game.xp, "The months add up to the experience held")
            XCTAssertEqual(game.xpByMonth.count, 12)
            XCTAssertTrue(game.xpByMonth.values.allSatisfy { $0 > 0 }, "Every month of the year earned something: \(game.xpByMonth)")
            XCTAssertEqual(Set(game.xpByMonth.keys), Set(game.dcaMonths.map(\.key)))
        }
    }

    func testExplicitProgressStillWinsOverDemoStore() {
        var game = GameState()
        DemoArguments.apply(to: &game, args: store + ["--demo-streak", "3", "--demo-level", "2"], now: noon(2026, 11, 14))
        XCTAssertEqual(game.streak(now: noon(2026, 11, 14)), 3)
        XCTAssertEqual(game.xp, GameRules.xpPerLevel)
    }

    // MARK: Records

    @MainActor func testDemoStoreSeedsAlertsDividendsAndAReport() throws {
        // The real clock: 「即將除息」 reads today's date itself.
        let now = Date()
        let records = PortfolioStore(url: directory.appendingPathComponent("p.json"))
        try seed(records, args: store, now: now)

        XCTAssertEqual(records.data.holdings.map(\.symbol), ["0050", "00878", "006208", "00679B"], "The demo pocket")
        XCTAssertEqual(records.trackedActiveFunds.map(\.id), ["00982A"], "and the demo active ETF")

        // 到價提醒: two watching, one fired and switched off.
        XCTAssertEqual(records.alerts.map(\.symbol), ["0050", "00878", "006208"])
        XCTAssertEqual(records.alerts.map(\.condition), ["高於 200", "低於 21", "高於 120"])
        XCTAssertEqual(records.alerts.map(\.enabled), [true, true, false])
        XCTAssertEqual(PriceAlertsView.status(records.alerts[0]), "監看中")
        XCTAssertEqual(PriceAlertsView.status(records.alerts[1]), "監看中")
        XCTAssertTrue(PriceAlertsView.status(records.alerts[2]).hasSuffix("已到價，提醒已停用"), PriceAlertsView.status(records.alerts[2]))
        let fired = try XCTUnwrap(records.alerts[2].firedAt)
        XCTAssertLessThan(fired, now, "It fired before now")
        XCTAssertGreaterThan(fired, now.addingTimeInterval(-3 * 86_400), "and recently")

        // 配息: 「即將除息」 has the announced ex-dividends, with an estimate for the shares held.
        let upcoming = UpcomingDividend.from(records.officialForHoldings(), today: DataChecks.day(now), logged: records.data.dividends)
        XCTAssertEqual(upcoming.map(\.symbol), ["00878", "00679B"])
        XCTAssertEqual(upcoming.map(\.estimate), [1100, 330])
        XCTAssertTrue(upcoming.allSatisfy { $0.ex > DataChecks.day(now) }, "Both are still ahead")
        // 今年已領 is the sum of the list's received records of this year.
        let year = DividendYear.of(records.data.dividends, now: now)
        XCTAssertGreaterThan(year.total, 0)
        XCTAssertGreaterThan(year.count, 0)

        // 口袋月報 for the month it opens on.
        let card = PocketReport.make(.month(PocketReportView.lastMonth(now)), portfolio: records.data, now: now)
        XCTAssertTrue((1_000..<5_000).contains(card.dividends), "領息 in the low thousands: \(card.dividends)")
        XCTAssertEqual(card.dcaMonths, 1, "定期定額 有做到")
        XCTAssertEqual(card.reconciles, 1)
        XCTAssertEqual(card.newDexCards, 2)
        XCTAssertEqual(card.level, 7)
        XCTAssertGreaterThan(try XCTUnwrap(card.xpEarned), 0, "獲得經驗 is on the card")

        // Seeding again (a relaunch without --reset) adds nothing.
        let dividends = records.data.dividends.count
        try seed(records, args: store, now: now)
        XCTAssertEqual(records.alerts.count, 3)
        XCTAssertEqual(records.data.dividends.count, dividends)
        XCTAssertEqual(records.official.list("00878").count, 1)
    }

    func testUpcomingExDividendsFallOnWeekdays() {
        // 14 November 2026 is a Saturday.
        XCTAssertEqual(DemoArguments.weekday(after: 5, from: noon(2026, 11, 14)), "2026-11-19")
        XCTAssertEqual(DemoArguments.weekday(after: 7, from: noon(2026, 11, 14)), "2026-11-23", "A Saturday moves on to Monday")
        XCTAssertEqual(DemoArguments.weekday(after: 8, from: noon(2026, 11, 14)), "2026-11-23", "and so does a Sunday")
    }

    // MARK: Member page

    /// The price slot: the App Store's price whenever it has one; without one only `--demo-store` shows a figure.
    func testPriceSlot() {
        XCTAssertEqual(PlanPrice.text(product: nil, loading: false, demoStore: true), "NT$120 / 月")
        XCTAssertEqual(PlanPrice.text(product: nil, loading: true, demoStore: true), "NT$120 / 月", "Never 「…」 in a store picture")
        XCTAssertEqual(PlanPrice.text(product: "NT$150 / 月", loading: false, demoStore: true), "NT$150 / 月", "A real product's price wins")
        XCTAssertEqual(PlanPrice.text(product: "NT$150 / 月", loading: false, demoStore: false), "NT$150 / 月")
        XCTAssertEqual(PlanPrice.text(product: nil, loading: false, demoStore: false), "—", "A real launch never shows a made-up price")
        XCTAssertEqual(PlanPrice.text(product: nil, loading: true, demoStore: false), "…")
    }

    /// The detail line breaks only after a 「・」, into lines of about the same length.
    @MainActor func testPlanDetailBreaksAtTheDot() {
        let detail = MemberView.Plan.pocket.detail
        XCTAssertEqual(detail, "成分重疊・回測・目標反推・到價提醒・月報年報・全部皮膚", "The line itself is unchanged")
        XCTAssertEqual(MemberView.detailLines(detail, count: 2), ["成分重疊・回測・目標反推・", "到價提醒・月報年報・全部皮膚"])
        let three = MemberView.detailLines(detail, count: 3)
        XCTAssertEqual(three, ["成分重疊・回測・", "目標反推・到價提醒・", "月報年報・全部皮膚"])
        XCTAssertEqual(three.joined(), detail, "Nothing is lost or added")
        XCTAssertEqual(MemberView.detailLines(MemberView.Plan.free.detail, count: 2), [MemberView.Plan.free.detail], "Nothing to cut at")
        XCTAssertEqual(MemberView.detailLines("甲・乙", count: 3), ["甲・乙"], "Too few parts for three lines")
    }

    /// The first screenful ends above the buy button's block, and is never a negative height.
    @MainActor func testFirstScreenStopsAboveTheBuyButton() {
        XCTAssertEqual(MemberView.firstScreen(height: 700, footer: 100), 578)
        XCTAssertEqual(MemberView.firstScreen(height: 60, footer: 100), 0)
        XCTAssertLessThan(MemberView.stageSizes.lowerBound, MemberView.stageSizes.upperBound)
    }

    // MARK: 回測's form

    func testBacktestFormResetNeedsUITesting() throws {
        let suite = "backtest-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("0056,00878", forKey: BacktestSettings.symbolsKey)
        defaults.set(10, forKey: BacktestSettings.yearsKey)
        BacktestSettings.reset(["--reset"], defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: BacktestSettings.symbolsKey), "0056,00878", "A stray --reset changes nothing")
        BacktestSettings.reset(["--ui-testing", "--reset"], defaults: defaults)
        XCTAssertNil(defaults.object(forKey: BacktestSettings.symbolsKey))
        XCTAssertNil(defaults.object(forKey: BacktestSettings.yearsKey))
    }
}
