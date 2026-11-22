import XCTest
@testable import ETFToGo

/// Nothing runs without a reason: no live loop without a key, one shared 3D lighting environment.
final class IdleWorkTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("idle-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor func testNoKeyNoLoop() {
        let store = PortfolioStore(url: directory.appendingPathComponent("p.json"))
        let feed = LiveFeed(store: store, readKey: { "" }, marketOpen: { false })
        feed.start()
        XCTAssertFalse(feed.isLooping)
        XCTAssertFalse(store.liveStatus.hasKey)
        feed.stop()
        XCTAssertFalse(feed.isLooping)
    }

    @MainActor func testKeyAddedStartsTheLoop() {
        let store = PortfolioStore(url: directory.appendingPathComponent("p.json"))
        var key = ""
        let feed = LiveFeed(store: store, readKey: { key }, marketOpen: { false })
        feed.start()
        XCTAssertFalse(feed.isLooping)
        key = "abc"
        feed.restart()
        XCTAssertTrue(feed.isLooping)
        XCTAssertTrue(store.liveStatus.hasKey)
        key = ""
        feed.restart()
        XCTAssertFalse(feed.isLooping)
        XCTAssertFalse(store.liveStatus.hasKey)
        key = "abc"
        feed.restart()
        feed.stop()
        XCTAssertFalse(feed.isLooping)
    }

    @MainActor func testEnvironmentIsBuiltOnce() async {
        let before = PocketHero.environmentBuilds
        async let a = PocketHero.environment()
        async let b = PocketHero.environment()
        let (x, y) = await (a, b)
        let z = await PocketHero.environment()
        XCTAssertLessThanOrEqual(PocketHero.environmentBuilds - before, 1)
        XCTAssertGreaterThanOrEqual(PocketHero.environmentBuilds, 1)
        if let x, let y, let z { XCTAssertTrue(x === y && y === z) }
    }
}
