import XCTest
@testable import ETFToGo

final class StockScenarioTests: XCTestCase {
    let tsmc = Holding(symbol: "2330", name: "台積電", shares: 100, unitCost: 600, broker: "國泰證券", strategy: .unclassified)
    func testBrokerCSVKeepsStocksAndETFsTogether() throws {
        let table = try CSVTable.parse(Data("代碼,名稱,股數,總成本\n0050,,1000,50000\n2330,台積電,100,60000\n2317,,1,100000".utf8))
        let p = try BrokerPreview.make(table: table, mapping: BrokerMapping(symbol: 0, name: 1, shares: 2, cost: 3), broker: "國泰證券", account: "主要", funds: Fund.starters)
        XCTAssertEqual(p.holdings.map(\.name), ["元大台灣50", "台積電", "2317"], "Stocks without a name column fall back to the code")
        XCTAssertEqual(p.stocks, ["2330", "2317"])
        XCTAssertEqual(p.holdings[0].strategy, .saving); XCTAssertEqual(p.holdings[1].strategy, .unclassified)
        XCTAssertEqual(p.holdings[1].unitCost, 600)
    }
    @MainActor func testBrokerReimportKeepsUserStrategy() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PortfolioStore(url: dir.appendingPathComponent("p.json"))
        let mapping = BrokerMapping(symbol: 0, name: 1, shares: 2, cost: 3)
        try store.importBroker(BrokerPreview.make(table: CSVTable.parse(Data("code,name,shares,cost\n2330,台積電,100,60000".utf8)), mapping: mapping, broker: "國泰證券", account: "主要", funds: Fund.starters), replaceAccount: true)
        var holding = try XCTUnwrap(store.data.holdings.first); holding.strategy = .saving; try store.save(holding)
        try store.importBroker(BrokerPreview.make(table: CSVTable.parse(Data("code,name,shares,cost\n2330,台積電,200,130000".utf8)), mapping: mapping, broker: "國泰證券", account: "主要", funds: Fund.starters), replaceAccount: true)
        XCTAssertEqual(store.data.holdings.count, 1); XCTAssertEqual(store.data.holdings[0].shares, 200)
        XCTAssertEqual(store.data.holdings[0].strategy, .saving)
    }
    func testDirectStockMergesWithETFLookThrough() throws {
        var data = Portfolio.demo
        data.components = ["0050": ComponentSnapshot(symbol: "0050", date: "2026-10-01", components: [FundComponent(symbol: "2330", name: "台積電", weight: 60)], source: "test")]
        data.holdings.append(tsmc)
        data.quotes["2330"] = Quote(symbol: "2330", price: 1000, changePercent: nil, date: "2026-10-23", fetchedAt: Date(), currency: "TWD")
        let row = try XCTUnwrap(ResearchMath.exposures(data, etfs: Set(Fund.starters.map(\.id))).first { $0.symbol == "2330" })
        XCTAssertEqual(row.value, 2000 * 55 * 0.6 + 100 * 1000, accuracy: 0.001)
        XCTAssertEqual(row.funds, ["0050", ResearchMath.direct])
        XCTAssertFalse(ResearchMath.exposures(data).contains { $0.funds.contains(ResearchMath.direct) }, "Without the ETF list, unknown codes are not assumed to be stocks")
    }
    func testScenarioStartsFromMarketValueAndFallsBackToCost() {
        var data = Portfolio.demo
        data.holdings.append(tsmc)
        data.holdings.append(Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "國泰證券", strategy: .saving))
        let positions = ScenarioMath.positions(data)
        XCTAssertEqual(positions.count, 4, "The same code across brokers is one position")
        XCTAssertEqual(positions.reduce(0) { $0 + $1.value }, 348500 + 55000 + 60000, accuracy: 0.001)
        XCTAssertEqual(positions.first { $0.symbol == "2330" }?.quoted, false)
        XCTAssertEqual(positions.first { $0.symbol == "2330" }?.value, 60000)
        XCTAssertEqual(positions.first { $0.symbol == "0050" }?.value, 165000)
    }
    func testScenarioCompoundingMatchesYearlyRate() {
        XCTAssertEqual(ScenarioMath.value(start: 1_000_000, monthly: 0, annual: 0.05, years: 10), 1_000_000 * pow(1.05, 10), accuracy: 0.01)
        XCTAssertEqual(ScenarioMath.value(start: 1_000_000, monthly: 0, annual: 0.07, years: 50), 1_000_000 * pow(1.07, 50), accuracy: 0.01)
        XCTAssertEqual(ScenarioMath.value(start: 100000, monthly: 5000, annual: 0, years: 3), 280000, accuracy: 0.001)
        XCTAssertLessThan(ScenarioMath.value(start: 100000, monthly: 0, annual: -0.05, years: 3), 100000)
    }
    func testScenarioPlanValidationAndBackupRoundTrip() throws {
        var plan = ScenarioPlan(); XCTAssertNoThrow(try plan.validate())
        plan.conservative = 0.06; XCTAssertThrowsError(try plan.validate(), "Conservative must not exceed balanced")
        XCTAssertThrowsError(try ScenarioPlan(aggressive: 0.5).validate())
        XCTAssertThrowsError(try ScenarioPlan(monthly: -1).validate())
        var data = Portfolio.demo; data.scenarioPlan = ScenarioPlan(conservative: 0.02, balanced: 0.04, aggressive: 0.08, monthly: 10000)
        XCTAssertEqual(try Portfolio.decodeBackup(JSONEncoder().encode(data)).scenarioPlan, data.scenarioPlan)
        data.scenarioPlan?.balanced = 0.1
        XCTAssertThrowsError(try Portfolio.decodeBackup(JSONEncoder().encode(data)))
    }
    func testHistoricalReferenceWeightsOnlyCoveredPositions() throws {
        var data = Portfolio.demo
        data.histories = ["0050": PriceHistory(symbol: "0050", adjusted: true, points: [PricePoint(date: "2020-01-01", close: 100), PricePoint(date: "2022-01-01", close: 121)], fetchedDay: "2026-10-01", source: "test")]
        let result = try XCTUnwrap(ScenarioMath.historical(data, positions: ScenarioMath.positions(data)))
        XCTAssertEqual(result.rate, pow(1.21, 365.25 / 731) - 1, accuracy: 0.000001)
        XCTAssertEqual(result.coverage, 110000 / 348500, accuracy: 0.000001)
    }
}
