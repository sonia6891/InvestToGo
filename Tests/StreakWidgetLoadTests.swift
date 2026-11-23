import XCTest
@testable import ETFToGo

/// What the widget makes of the App Group's folder (I-2): no file is a newbie until the month turns; a file it cannot
/// read is a redacted placeholder tried again in 15 minutes; a good file is its snapshot.
@MainActor final class StreakWidgetLoadTests: XCTestCase {
    private var directory: URL!
    private let now = GameRules.taipei.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 12))!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("widget-load-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private var file: URL { directory.appendingPathComponent(WidgetFile.name) }

    func testMissingFileIsNewbieUntilTheMonthTurns() {
        let load = StreakWidgetLoad.load(directory: directory, now: now)
        XCTAssertEqual(load, .missing)
        XCTAssertEqual(load.snapshot(now: now), .newbie(now: now))
        XCTAssertFalse(load.redacted)
        XCTAssertEqual(load.reloadDate(after: now), WidgetSnapshot.nextMonthStart(after: now))
        XCTAssertEqual(load.reloadDate(after: now), GameRules.taipei.date(from: DateComponents(year: 2026, month: 12, day: 1)))
    }

    func testNoContainerIsMissing() {
        XCTAssertEqual(StreakWidgetLoad.load(directory: nil, now: now), .missing)
    }

    func testGarbageFileIsUnreadableAndRetriedIn15Minutes() throws {
        try Data("{ not a snapshot".utf8).write(to: file)
        let load = StreakWidgetLoad.load(directory: directory, now: now)
        XCTAssertEqual(load, .unreadable)
        XCTAssertTrue(load.redacted)
        XCTAssertEqual(load.reloadDate(after: now), now.addingTimeInterval(15 * 60))
        XCTAssertNotEqual(load.snapshot(now: now), .newbie(now: now), "an unreadable file is never drawn as 今天開始")
    }

    func testNewerVersionIsUnreadable() throws {
        var s = WidgetSnapshot.sample(streak: 3, done: 1, now: now); s.version = WidgetSnapshot.version + 1
        try JSONEncoder().encode(s).write(to: file)
        XCTAssertEqual(StreakWidgetLoad.load(directory: directory, now: now), .unreadable)
    }

    func testGoodFileIsItsSnapshot() throws {
        let s = WidgetSnapshot.sample(streak: 7, longest: 9, done: 1, skinID: "voxel", now: now)
        try JSONEncoder().encode(s).write(to: file)
        let load = StreakWidgetLoad.load(directory: directory, now: now)
        XCTAssertEqual(load, .snapshot(s))
        XCTAssertEqual(load.snapshot(now: now), s)
        XCTAssertFalse(load.redacted)
        XCTAssertEqual(load.reloadDate(after: now), WidgetSnapshot.nextMonthStart(after: now))
    }

    /// The writer and the reader use one name (`WidgetFile.name`, compiled into both targets).
    func testWriterAndReaderShareTheFile() throws {
        let at = now
        let sync = WidgetSync(directory: directory, reload: {}, skinID: { "sketch" }, locked: { false }, now: { at })
        var p = Portfolio(); var g = GameState(); g.habit = .dca; g.insertMonth(YearMonth(year: 2026, month: 11)); p.game = g
        sync.sync(p)
        guard case .snapshot(let read) = StreakWidgetLoad.load(directory: directory, now: now) else { return XCTFail("the widget did not read the app's file") }
        XCTAssertEqual(read, WidgetSnapshot.of(p, skinID: "sketch", now: now))
        XCTAssertEqual(WidgetFile.name, "widget.json")
    }
}
