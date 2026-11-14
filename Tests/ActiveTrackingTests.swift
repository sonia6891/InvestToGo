import XCTest
@testable import ETFToGo

/// 主動式追蹤: which ETFs the screen follows, its launch route and the seeded holdings the UI test reads.
final class ActiveTrackingTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("active-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Held or favourite, an ETF, and active; by code, each once.
    @MainActor func testTrackedFundsAreTheActiveOnesHeldOrFavourite() throws {
        let store = PortfolioStore(url: directory.appendingPathComponent("p.json"))
        XCTAssertTrue(store.trackedActiveFunds.isEmpty)
        try store.save(Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "", strategy: .saving))
        try store.save(Holding(symbol: "00982A", name: "主動群益台灣強棒", shares: 1000, unitCost: 10, broker: "", strategy: .unclassified))
        store.favorite("00981A")
        store.favorite("00982A")
        store.favorite("00878")
        XCTAssertEqual(store.trackedActiveFunds.map(\.id), ["00981A", "00982A"])
    }

    func testOpenRouteNeedsUITesting() {
        XCTAssertEqual(AppRoute.launchStack(["--ui-testing", "--open", "activeTracking"]), [.feature(.tools), .activeTracking])
        XCTAssertNil(AppRoute.launchStack(["--open", "activeTracking"]))
    }

    @MainActor func testDemoActiveSeedsAChangeToShow() throws {
        let store = PortfolioStore(url: directory.appendingPathComponent("p.json"))
        DemoArguments.seedActive(store, args: ["--demo-active"])
        XCTAssertTrue(store.trackedActiveFunds.isEmpty, "Ignored without --ui-testing")
        DemoArguments.seedActive(store, args: ["--ui-testing", "--demo-active"])
        XCTAssertEqual(store.trackedActiveFunds.map(\.id), ["00982A"])
        XCTAssertEqual(store.componentHistory(for: "00982A").map(\.date), ["2026-11-13", "2026-11-11"])
        let change = try XCTUnwrap(SnapshotDiff.latest(store.componentHistory(for: "00982A")))
        XCTAssertEqual(change.title, "11/13 與 11/11 相比")
        XCTAssertEqual(change.added.map(\.symbol), ["1005"])
        XCTAssertEqual(change.removed.map(\.symbol), ["1004"])
        XCTAssertEqual(change.changed.map { $0.component.symbol }, ["1001", "1003"])
        XCTAssertEqual(change.changed.map { $0.delta }, [2, -1])
        // Seeding twice changes nothing.
        DemoArguments.seedActive(store, args: ["--ui-testing", "--demo-active"])
        XCTAssertEqual(store.data.favorites, ["00982A"])
        XCTAssertEqual(store.componentHistory(for: "00982A").count, 2)
    }
}
