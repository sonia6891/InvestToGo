import XCTest
@testable import ETFToGo

/// The cached catalogue, official dividends and day's closes are read after the first screen (`ensureSideFiles`),
/// not by `PortfolioStore.init`.
final class LaunchPerformanceTests: XCTestCase {
    private lazy var directory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("launch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }()
    private var file: URL { directory.appendingPathComponent("p.json") }
    private let extraID = "00999"

    /// The bundled list plus one fund it does not have, saved as the `.catalog` file.
    private func writeCatalog(fetchedDay: String) throws {
        var snapshot = try XCTUnwrap(CatalogSnapshot.bundled())
        XCTAssertFalse(snapshot.funds.contains { $0.id == extraID })
        snapshot.funds.append(Fund(id: extraID, name: "測試新基金", strategy: .unclassified, market: "TWSE"))
        snapshot.fetchedDay = fetchedDay
        try JSONEncoder().encode(snapshot).write(to: file.appendingPathExtension("catalog"))
    }

    @MainActor func testSideFilesWaitForFirstScreen() async throws {
        try writeCatalog(fetchedDay: DataChecks.day())
        let store = PortfolioStore(url: file)
        XCTAssertEqual(store.catalog?.funds.count, CatalogSnapshot.bundled()?.funds.count, "init does not read the cache")
        XCTAssertFalse(store.funds.contains { $0.id == extraID })
        XCTAssertEqual(store.sideFileReads, 0)
        await store.ensureSideFiles()
        XCTAssertTrue(store.funds.contains { $0.id == extraID })
    }

    @MainActor func testEnsureSideFilesIsIdempotent() async throws {
        try writeCatalog(fetchedDay: DataChecks.day())
        let store = PortfolioStore(url: file)
        async let first: Void = store.ensureSideFiles()
        async let second: Void = store.ensureSideFiles()
        _ = await (first, second)
        let catalog = store.catalog
        await store.ensureSideFiles()
        XCTAssertEqual(store.sideFileReads, 1)
        XCTAssertEqual(store.catalog?.funds.map(\.id), catalog?.funds.map(\.id))
        XCTAssertTrue(store.funds.contains { $0.id == extraID })
    }

    @MainActor func testRefreshWaitsForSideFiles() async throws {
        try writeCatalog(fetchedDay: DataChecks.day())
        let store = PortfolioStore(url: file)
        await store.refreshCatalog(automatic: true)
        XCTAssertTrue(store.funds.contains { $0.id == extraID })
        XCTAssertNil(store.catalogMessage, "Today's cached list was seen, so the network was not asked")
    }

    /// 記一筆 fills its default price from the cached close once the side files are in.
    @MainActor func testQuickDCADraftUsesTheCachedCloseAfterEnsure() async throws {
        let quote = Quote(symbol: "0050", price: 123.45, changePercent: nil, date: DataChecks.day(), fetchedAt: Date())
        let day = OpenData.Day(quotes: ["0050": quote], indices: [:], fetchedAt: Date())
        try JSONEncoder().encode(day).write(to: file.appendingPathExtension("daily"))
        let name = "LaunchPerformanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        defaults.set("0050", forKey: Onboarding.symbolKey)
        defaults.set(5000, forKey: Onboarding.monthlyKey)
        let store = PortfolioStore(url: file)
        XCTAssertNil(store.daily)
        await store.ensureSideFiles()
        XCTAssertEqual(store.quote("0050")?.price, 123.45)
        XCTAssertEqual(store.quickDCADraft(defaults: defaults).shares, QuickDCA.estimatedShares(amount: 5000, close: 123.45))
    }

    /// A close a refresh already published is not replaced by the older cached one.
    @MainActor func testPublishedDailyWinsOverTheCache() async throws {
        let old = Quote(symbol: "0050", price: 100, changePercent: nil, date: "2026-01-02", fetchedAt: Date(timeIntervalSinceNow: -86400))
        try JSONEncoder().encode(OpenData.Day(quotes: ["0050": old], indices: [:], fetchedAt: Date())).write(to: file.appendingPathExtension("daily"))
        let store = PortfolioStore(url: file)
        let fresh = Quote(symbol: "0050", price: 130, changePercent: nil, date: DataChecks.day(), fetchedAt: Date())
        store.daily = OpenData.Day(quotes: ["0050": fresh], indices: [:], fetchedAt: Date())
        await store.ensureSideFiles()
        XCTAssertEqual(store.daily?.quotes["0050"]?.price, 130)
    }

    /// A cached official record older than the bundled one does not replace it.
    @MainActor func testOlderCachedOfficialDoesNotReplaceBundled() async throws {
        let bundled = OfficialDividends.bundled()
        _ = try XCTUnwrap(bundled.sources["twse"], "the bundled record names its TWSE source day")
        var old = bundled
        old.sources["twse"] = "2000-01-01"
        old.sources["tpex"] = "2000-01-01"
        old.sources["since"] = "2000-01-01"
        old.events["0050"] = [OfficialDistribution(ex: "2000-01-01", pay: "2000-01-02", amount: 1)]
        try JSONEncoder().encode(old).write(to: file.appendingPathExtension("official"))
        let store = PortfolioStore(url: file)
        await store.ensureSideFiles()
        XCTAssertEqual(store.official.sources, bundled.sources)
        XCTAssertFalse((store.official.events["0050"] ?? []).contains { $0.ex == "2000-01-01" })
    }

    /// An index quote the live feed already published is not replaced by the older cached one.
    @MainActor func testNewerLiveIndexWinsOverCachedIndex() async throws {
        let cached = Quote(symbol: "taiex", price: 100, changePercent: nil, date: "2026-01-02", fetchedAt: Date(timeIntervalSinceNow: -86400))
        try JSONEncoder().encode(OpenData.Day(quotes: [:], indices: ["taiex": cached], fetchedAt: Date())).write(to: file.appendingPathExtension("daily"))
        let store = PortfolioStore(url: file)
        store.indices["taiex"] = Quote(symbol: "taiex", price: 150, changePercent: nil, date: DataChecks.day(), fetchedAt: Date())
        await store.ensureSideFiles()
        XCTAssertEqual(store.indices["taiex"]?.price, 150)
    }

    /// The `--demo-store` announcements stay on top of a newer cached official record that is read later.
    @MainActor func testDemoOfficialOverlaySurvivesTheSideFileRead() async throws {
        var newer = OfficialDividends.bundled()
        newer.sources["twse"] = "9999-12-31"
        newer.sources["since"] = newer.sources["since"] ?? "2026-01-01"
        try JSONEncoder().encode(newer).write(to: file.appendingPathExtension("official"))
        let store = PortfolioStore(url: file)
        store.showOfficial(["0050": [OfficialDistribution(ex: "2099-01-01", pay: "2099-02-01", amount: 1)]])
        await store.ensureSideFiles()
        XCTAssertEqual(store.official.sources["twse"], "9999-12-31", "the newer cached record was applied")
        XCTAssertTrue(store.official.list("0050").contains { $0.ex == "2099-01-01" })
    }

    @MainActor func testMigrateTwiceWritesOnce() throws {
        let store = PortfolioStore(url: file)
        try store.save(Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "", strategy: .saving))
        try store.updateGame { $0.migrate(store.data) }
        func modified() throws -> Date { try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) }
        let first = try modified()
        Thread.sleep(forTimeInterval: 0.05)
        try store.updateGame { $0.migrate(store.data) }
        XCTAssertEqual(try modified(), first)
    }
}
