import XCTest
@testable import ETFToGo

/// The app's copy of the widget's file: written after saves, returns and skin changes, never when nothing differs.
@MainActor final class WidgetSyncTests: XCTestCase {
    private var directory: URL!
    private var reloads = 0
    private var skin = "stitch"
    private var clock = WidgetSyncTests.at(2026, 11, 21)
    private var isLocked = false

    private static func at(_ y: Int, _ m: Int, _ d: Int) -> Date {
        GameRules.taipei.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reloads = 0; skin = "stitch"; clock = Self.at(2026, 11, 21); isLocked = false
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeSync(noContainer: Bool = false) -> WidgetSync {
        WidgetSync(directory: noContainer ? nil : directory, reload: { [unowned self] in reloads += 1 },
                   skinID: { [unowned self] in skin }, locked: { [unowned self] in isLocked }, now: { [unowned self] in clock })
    }

    private func portfolio(buy: Bool = false) -> Portfolio {
        var p = Portfolio()
        let h = Holding(symbol: "0050", name: "測試", shares: 100, unitCost: 80, broker: "", strategy: .saving)
        p.holdings = [h]
        if buy { p.trades = [Trade(date: Self.at(2026, 11, 5), action: .buy, holding: h)] }
        var g = GameState(); g.habit = .dca
        g.insertMonth(YearMonth(year: 2026, month: 11))
        g.questsDone = ["2026-11": ["dcaLogged"]]
        p.game = g
        return p
    }

    private var file: URL { directory.appendingPathComponent(WidgetSync.fileName) }

    func testWritesTheSnapshot() throws {
        let sync = makeSync(); let p = portfolio(buy: true)
        sync.sync(p)
        let decoded = try XCTUnwrap(WidgetSnapshot.decode(Data(contentsOf: file)))
        XCTAssertEqual(decoded, WidgetSnapshot.of(p, skinID: "stitch", now: clock))
        XCTAssertEqual(sync.writes, 1)
        XCTAssertEqual(reloads, 1)
    }

    func testWritesOnlyWhenChanged() {
        let sync = makeSync(); let p = portfolio(buy: true)
        sync.sync(p)
        clock = clock.addingTimeInterval(60)
        sync.sync(p)
        XCTAssertEqual(sync.writes, 1)
        XCTAssertEqual(reloads, 1)
    }

    func testSkinChangeWrites() throws {
        let sync = makeSync(); let p = portfolio(buy: true)
        sync.sync(p)
        skin = "sketch"
        sync.sync(p)
        XCTAssertEqual(sync.writes, 2)
        XCTAssertEqual(try XCTUnwrap(WidgetSnapshot.decode(Data(contentsOf: file))).skinID, "sketch")
    }

    func testDeletedDCAUnticks() throws {
        let sync = makeSync()
        sync.sync(portfolio(buy: true))
        XCTAssertTrue(try XCTUnwrap(WidgetSnapshot.decode(Data(contentsOf: file))).quests[0].done)
        sync.sync(portfolio(buy: false))
        XCTAssertFalse(try XCTUnwrap(WidgetSnapshot.decode(Data(contentsOf: file))).quests[0].done)
        XCTAssertEqual(sync.writes, 2)
    }

    func testLockedRecordsDoNotWrite() {
        isLocked = true
        let sync = makeSync()
        sync.sync(portfolio(buy: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(sync.writes, 0)
        XCTAssertEqual(reloads, 0)
    }

    func testNoContainerDoesNothing() {
        let sync = makeSync(noContainer: true)
        sync.sync(portfolio(buy: true))
        XCTAssertEqual(sync.writes, 0)
        XCTAssertEqual(reloads, 0)
    }

    func testFileProtectionClass() throws {
        let sync = makeSync()
        sync.sync(portfolio(buy: true))
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        let protection = attrs[.protectionKey] as? FileProtectionType
        XCTAssertTrue(protection == nil || protection == .completeUntilFirstUserAuthentication)
    }

    func testStoreCommitCallsOnCommit() {
        let store = PortfolioStore(url: directory.appendingPathComponent("p.json"))
        var seen: [Portfolio] = []
        store.onCommit = { seen.append($0) }
        store.favorite("0050")
        XCTAssertEqual(seen.count, 1)
        XCTAssertTrue(seen.first?.favorites.contains("0050") ?? false)
    }
}
