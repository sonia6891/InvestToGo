import XCTest
@testable import PocketCore

/// `SnapshotDiff`: two days of one ETF's holdings compared, for 主動式 ETF 追蹤.
final class SnapshotDiffTests: XCTestCase {
    private func snapshot(_ date: String, _ weights: [(String, Double)]) -> ComponentSnapshot {
        ComponentSnapshot(symbol: "00982A", date: date, components: weights.map { FundComponent(symbol: $0.0, name: "名稱" + $0.0, weight: $0.1) }, source: "test")
    }

    func testDiff() {
        let old = snapshot("2026-11-11", [("A", 10), ("B", 5), ("C", 3)])
        let new = snapshot("2026-11-13", [("A", 12), ("B", 5), ("D", 4)])
        let change = SnapshotDiff.compare(old: old, new: new)
        XCTAssertEqual(change.from, "2026-11-11")
        XCTAssertEqual(change.to, "2026-11-13")
        XCTAssertEqual(change.added, [FundComponent(symbol: "D", name: "名稱D", weight: 4)])
        XCTAssertEqual(change.removed, [FundComponent(symbol: "C", name: "名稱C", weight: 3)])
        XCTAssertEqual(change.changed.map { $0.component }, [FundComponent(symbol: "A", name: "名稱A", weight: 12)], "The later day's weight")
        XCTAssertEqual(change.changed.first?.delta ?? 0, 2, accuracy: 1e-9)
        XCTAssertFalse(change.isEmpty)
        XCTAssertFalse(change.changedCut, "The one weight that moved is listed")
        XCTAssertEqual(change.title, "11/13 與 11/11 相比")
    }

    func testTinyChangeIgnored() {
        let change = SnapshotDiff.compare(old: snapshot("2026-11-11", [("A", 10)]), new: snapshot("2026-11-13", [("A", 10.005)]))
        XCTAssertTrue(change.changed.isEmpty)
        XCTAssertTrue(change.isEmpty)
        // A hundredth of a point does count, up or down, however the doubles round.
        let up = SnapshotDiff.compare(old: snapshot("2026-11-11", [("A", 10)]), new: snapshot("2026-11-13", [("A", 10.01)]))
        XCTAssertEqual(up.changed.map { $0.component.symbol }, ["A"])
        let down = SnapshotDiff.compare(old: snapshot("2026-11-11", [("A", 10.01)]), new: snapshot("2026-11-13", [("A", 10)]))
        XCTAssertEqual(down.changed.map { $0.component.symbol }, ["A"])
        XCTAssertLessThan(down.changed.first?.delta ?? 0, 0)
    }

    func testTopTen() {
        // S01 moves by 0.1, S02 by −0.2, S03 by 0.3 … S15 by 1.5.
        let codes = (1...15).map { String(format: "S%02d", $0) }
        let old = snapshot("2026-11-11", codes.map { ($0, 5) })
        var moved: [(String, Double)] = []
        for (i, code) in codes.enumerated() {
            let step = Double(i + 1) * 0.1
            moved.append((code, i % 2 == 0 ? 5 + step : 5 - step))
        }
        let new = snapshot("2026-11-13", moved)
        let change = SnapshotDiff.compare(old: old, new: new)
        XCTAssertEqual(change.changed.count, 10)
        XCTAssertTrue(change.changedCut, "Fifteen moved and ten are listed: the heading says so")
        // Exactly ten moved: all of them are listed, so nothing was cut. Eleven: one was.
        func firstMoved(_ count: Int) -> SnapshotChange {
            SnapshotDiff.compare(old: snapshot("2026-11-11", codes.prefix(count).map { ($0, 5) }), new: snapshot("2026-11-13", Array(moved.prefix(count))))
        }
        XCTAssertEqual(firstMoved(10).changed.count, 10)
        XCTAssertFalse(firstMoved(10).changedCut)
        XCTAssertEqual(firstMoved(11).changed.count, 10)
        XCTAssertTrue(firstMoved(11).changedCut)
        XCTAssertEqual(change.changed.map { $0.component.symbol }, (6...15).reversed().map { String(format: "S%02d", $0) }, "Largest move first, up or down")
        XCTAssertEqual(change.changed[0].delta, 1.5, accuracy: 1e-9)
        XCTAssertEqual(change.changed[1].delta, -1.4, accuracy: 1e-9)
        XCTAssertTrue(change.added.isEmpty)
        XCTAssertTrue(change.removed.isEmpty)
    }

    func testAddedAndRemovedAreHeaviestFirst() {
        let old = snapshot("2026-11-11", [("A", 1), ("B", 7), ("C", 3)])
        let new = snapshot("2026-11-13", [("X", 2), ("Y", 9), ("Z", 2)])
        let change = SnapshotDiff.compare(old: old, new: new)
        XCTAssertEqual(change.added.map(\.symbol), ["Y", "X", "Z"], "Equal weights go by code")
        XCTAssertEqual(change.removed.map(\.symbol), ["B", "C", "A"])
        XCTAssertTrue(change.changed.isEmpty)
    }

    /// The screen compares the two newest days kept, whatever order they come in; one day alone has nothing to compare.
    func testLatestTakesTheTwoNewestDays() {
        XCTAssertNil(SnapshotDiff.latest([]))
        XCTAssertNil(SnapshotDiff.latest([snapshot("2026-11-13", [("A", 10)])]))
        // The same day twice is still one day.
        XCTAssertNil(SnapshotDiff.latest([snapshot("2026-11-13", [("A", 10)]), snapshot("2026-11-13", [("A", 11)])]))
        let history = [snapshot("2026-11-10", [("A", 1)]), snapshot("2026-11-13", [("A", 12), ("D", 4)]), snapshot("2026-11-11", [("A", 10), ("C", 3)])]
        let change = SnapshotDiff.latest(history)
        XCTAssertEqual(change?.from, "2026-11-11")
        XCTAssertEqual(change?.to, "2026-11-13")
        XCTAssertEqual(change?.added.map(\.symbol), ["D"])
        XCTAssertEqual(change?.removed.map(\.symbol), ["C"])
        XCTAssertEqual(change?.changed.first?.delta ?? 0, 2, accuracy: 1e-9)
    }

    func testTitleSaysBothDays() {
        XCTAssertEqual(SnapshotDiff.shortDay("2026-11-03"), "11/3")
        XCTAssertEqual(SnapshotDiff.shortDay("2026-01-13", year: true), "2026/1/13")
        XCTAssertEqual(SnapshotDiff.shortDay("somewhen"), "somewhen")
        let acrossYears = SnapshotDiff.compare(old: snapshot("2025-12-30", [("A", 10)]), new: snapshot("2026-01-02", [("A", 10)]))
        XCTAssertEqual(acrossYears.title, "2026/1/2 與 2025/12/30 相比")
    }
}
