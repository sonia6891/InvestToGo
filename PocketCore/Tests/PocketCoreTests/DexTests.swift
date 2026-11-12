import XCTest
@testable import PocketCore

final class DexTests: XCTestCase {
    private func fund(_ id: String, _ name: String = "測試", _ s: Strategy = .saving, type: String? = nil) -> Fund {
        Fund(id: id, name: name, strategy: s, fundType: type)
    }

    func testSeriesPrecedence() {
        XCTAssertEqual(DexSeries.of(fund("a", "元大美債20年", .saving)), .bond)
        XCTAssertEqual(DexSeries.of(fund("b", "某ETF", .income, type: "債券型")), .bond)
        XCTAssertEqual(DexSeries.of(fund("c", "元大高股息", .saving)), .highDividend)
        XCTAssertEqual(DexSeries.of(fund("d", "某ETF", .income)), .highDividend)
        XCTAssertEqual(DexSeries.of(fund("e", "元大台灣50", .saving)), .marketCap)
        XCTAssertEqual(DexSeries.of(fund("f", "台灣50正2", .risk)), .theme)
        XCTAssertEqual(DexSeries.of(fund("g", "某ETF", .unclassified)), .theme)
    }

    func testRankIntoTenBands() {
        let funds = (1...10).map { fund("f\($0)") }
        var facts = DexFacts()
        for (i, f) in funds.enumerated() { facts.aum[f.id] = Double(i + 1) }
        for (i, f) in funds.enumerated() {
            XCTAssertEqual(Dex.stats(for: f, among: funds, facts: facts).size, i + 1)
        }
        XCTAssertEqual(Dex.stats(for: funds[0], among: [funds[0]], facts: facts).size, 10)
        facts.aum = Dictionary(uniqueKeysWithValues: funds.map { ($0.id, 5.0) })
        XCTAssertEqual(funds.map { Dex.stats(for: $0, among: funds, facts: facts).size }, Array(repeating: 10, count: 10))
    }

    func testTiedCheapestFeeBothGetTen() {
        let a = fund("a"), b = fund("b"), c = fund("c")
        let facts = DexFacts(feeRate: ["a": 0.1, "b": 0.1, "c": 0.5])
        XCTAssertEqual(Dex.stats(for: a, among: [a, b, c], facts: facts).fee, 10)
        XCTAssertEqual(Dex.stats(for: b, among: [a, b, c], facts: facts).fee, 10)
        XCTAssertLessThan(Dex.stats(for: c, among: [a, b, c], facts: facts).fee, 10)
    }

    func testHigherVolatilityMoreBars() {
        let a = fund("a"), b = fund("b")
        let facts = DexFacts(volatility: ["a": 30, "b": 10])
        XCTAssertGreaterThan(Dex.stats(for: a, among: [a, b], facts: facts).volatility,
                             Dex.stats(for: b, among: [a, b], facts: facts).volatility)
    }

    func testMissingSizeAndHistoryAreZero() {
        let a = fund("a")
        let s = Dex.stats(for: a, among: [a], facts: DexFacts())
        XCTAssertEqual(s.size, 0); XCTAssertEqual(s.history, 0); XCTAssertEqual(s.fee, 0)
    }

    func testNonFiniteIsZeroAndExcluded() {
        let a = fund("a"), b = fund("b"), c = fund("c")
        let facts = DexFacts(aum: ["a": .nan, "b": 1, "c": 2])
        XCTAssertEqual(Dex.stats(for: a, among: [a, b, c], facts: facts).size, 0)
        XCTAssertEqual(Dex.stats(for: b, among: [a, b, c], facts: facts).size, 5)
        XCTAssertEqual(Dex.stats(for: c, among: [a, b, c], facts: facts).size, 10)
    }

    func testDuplicateIdsInAmongDoNotSkew() {
        let a = fund("a"), b = fund("b")
        let facts = DexFacts(aum: ["a": 1, "b": 2])
        XCTAssertEqual(Dex.stats(for: a, among: [a, a, a, b], facts: facts), Dex.stats(for: a, among: [a, b], facts: facts))
        XCTAssertEqual(Dex.stats(for: a, among: [a, b], facts: facts).size, 5)
    }

    func testEachNewCardEarnsXP() {
        var g = GameState()
        let now = Date()
        XCTAssertEqual(g.collect("0050", now: now), [.firstDexCard])
        XCTAssertEqual(g.collect("0056", now: now), [.firstDexCard])
        XCTAssertEqual(g.xp, 60)
    }

    func testLowerFeeMoreBars() {
        let a = fund("a"), b = fund("b")
        let facts = DexFacts(feeRate: ["a": 0.1, "b": 0.5])
        XCTAssertGreaterThan(Dex.stats(for: a, among: [a, b], facts: facts).fee,
                             Dex.stats(for: b, among: [a, b], facts: facts).fee)
    }

    func testOlderListingMoreBars() {
        let a = fund("a"), b = fund("b")
        let facts = DexFacts(listed: ["a": Date(timeIntervalSince1970: 1_000), "b": Date(timeIntervalSince1970: 2_000)])
        XCTAssertGreaterThan(Dex.stats(for: a, among: [a, b], facts: facts).history,
                             Dex.stats(for: b, among: [a, b], facts: facts).history)
    }

    func testYieldRanksWithinSeriesOnly() {
        let bond = fund("b1", "美債", .saving), eq1 = fund("e1"), eq2 = fund("e2")
        let facts = DexFacts(yield: ["b1": 9, "e1": 1, "e2": 2])
        let all = [bond, eq1, eq2]
        XCTAssertEqual(Dex.stats(for: bond, among: all, facts: facts).yield, 10)
        XCTAssertEqual(Dex.stats(for: eq1, among: all, facts: facts).yield, 5)
        XCTAssertEqual(Dex.stats(for: eq2, among: all, facts: facts).yield, 10)
    }

    func testMissingFactIsZero() {
        let a = fund("a")
        let s = Dex.stats(for: a, among: [a], facts: DexFacts(feeRate: ["a": 0.3]))
        XCTAssertEqual(s.yield, 0)
        XCTAssertEqual(s.volatility, 0)
        XCTAssertEqual(s.fee, 10)
    }

    func testCollectOnce() {
        var g = GameState()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(g.collect("0050", now: now), [.firstDexCard])
        XCTAssertEqual(g.xp, 30)
        XCTAssertEqual(g.collect("0050", now: now.addingTimeInterval(60)), [])
        XCTAssertEqual(g.xp, 30)
        XCTAssertEqual(g.collected["0050"], now)
    }

    func testSeriesProgress() {
        var g = GameState()
        let funds = [fund("0050", "元大台灣50"), fund("006208", "富邦台50"), fund("0056", "元大高股息", .income)]
        _ = g.collect("0050", now: Date())
        let p = g.seriesProgress(.marketCap, funds: funds)
        XCTAssertEqual(p.got, 1); XCTAssertEqual(p.total, 2)
        XCTAssertEqual(g.seriesProgress(.highDividend, funds: funds).got, 0)
    }
}
