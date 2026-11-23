import XCTest
@testable import ETFToGo

/// The app's copy of the widget's file: written after saves, returns and skin changes, never when nothing differs.
@MainActor final class WidgetSyncTests: XCTestCase {
    private var directory: URL!
    private var reloads = 0
    private var skin = "stitch"
    private var clock = WidgetSyncTests.at(2026, 11, 21)
    private var isLocked = false
    private var reported: [WidgetSyncError] = []

    private static func at(_ y: Int, _ m: Int, _ d: Int) -> Date {
        GameRules.taipei.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reloads = 0; skin = "stitch"; clock = Self.at(2026, 11, 21); isLocked = false; reported = []
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeSync(noContainer: Bool = false, in folder: URL? = nil) -> WidgetSync {
        WidgetSync(directory: noContainer ? nil : (folder ?? directory), reload: { [unowned self] in reloads += 1 },
                   skinID: { [unowned self] in skin }, locked: { [unowned self] in isLocked }, now: { [unowned self] in clock },
                   report: { [unowned self] in reported.append($0) })
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

    private var file: URL { directory.appendingPathComponent(WidgetFile.name) }

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

    /// A build without its App Group says so once (to Sentry, in Release), with nothing of the snapshot.
    func testNoContainerIsReportedOnce() {
        let sync = makeSync(noContainer: true)
        sync.sync(portfolio(buy: true))
        sync.sync(portfolio(buy: false))
        XCTAssertEqual(reported, [.noContainer])
        XCTAssertEqual(WidgetSyncError.noContainer.context, "widget-container")
    }

    func testFailedWriteIsReportedWithoutTheSnapshot() {
        let gone = directory.appendingPathComponent("no-such-folder", isDirectory: true)
        let sync = makeSync(in: gone)
        sync.sync(portfolio(buy: true))
        XCTAssertEqual(sync.writes, 0)
        XCTAssertEqual(reloads, 0)
        XCTAssertEqual(reported.count, 1)
        guard case .writeFailed(let domain, _) = reported.first else { return XCTFail("\(reported)") }
        XCTAssertFalse(domain.isEmpty)
        let info = (reported[0] as NSError).userInfo
        XCTAssertNotNil(info["underlyingDomain"]); XCTAssertNotNil(info["underlyingCode"])
        XCTAssertNil(info[NSFilePathErrorKey]); XCTAssertNil(info[NSUnderlyingErrorKey])
        XCTAssertEqual(reported[0].context, "widget-write")
    }

    func testLockedRecordsReportNothing() {
        isLocked = true
        let sync = makeSync(noContainer: true)
        sync.sync(portfolio(buy: true))
        XCTAssertEqual(reported, [])
    }

    /// A return to the foreground asks the widget to read its file again even when nothing changed (I-2: a tile drawn
    /// before the first unlock is replaced as soon as the app is opened).
    func testReturnReloadsEvenWhenUnchanged() {
        let sync = makeSync(); let p = portfolio(buy: true)
        sync.returned(p)
        XCTAssertEqual(sync.writes, 1)
        XCTAssertEqual(reloads, 1, "a write reloads once, not twice")
        sync.returned(p)
        XCTAssertEqual(sync.writes, 1)
        XCTAssertEqual(reloads, 2)
    }

    func testReturnReloadsWhileLocked() {
        isLocked = true
        let sync = makeSync()
        sync.returned(portfolio(buy: true))
        XCTAssertEqual(sync.writes, 0)
        XCTAssertEqual(reloads, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    /// M-1: records that failed to read (a damaged file) leave `data` empty; the widget's file is never written from it.
    func testReadFailedStoreNeverWrites() throws {
        let records = directory.appendingPathComponent("damaged.json")
        try Data("not json".utf8).write(to: records)
        let store = PortfolioStore(url: records)
        XCTAssertTrue(store.readFailed)
        XCTAssertFalse(store.recordsLocked)
        let sync = makeSync()
        sync.locked = WidgetSync.locked(by: store)
        sync.sync(store.data)
        sync.returned(store.data)
        XCTAssertEqual(sync.writes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testReadableStoreWrites() {
        let store = PortfolioStore(url: directory.appendingPathComponent("fresh.json"))
        XCTAssertFalse(store.readFailed)
        let sync = makeSync()
        sync.locked = WidgetSync.locked(by: store)
        sync.sync(portfolio(buy: true))
        XCTAssertEqual(sync.writes, 1)
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
