import XCTest
import PocketCore
@testable import ETFToGo

final class RestoredFeaturesTests: XCTestCase {
    let legacy = #"{"app":"ETF_CLASSIFIER","version":3,"planning":{"version":2,"holdings":[{"id":"pwa-001","code":"0050","name":"元大台灣50","shares":2000,"cost":100000,"price":55,"priceDate":"2026-10-01"}],"dividends":[{"id":"pwa-dividend-1","code":"0050","name":"元大台灣50","paymentDate":"2026-10-10","exDate":"2026-10-01","eligibleShares":2000,"perShare":1.2,"deductions":10,"status":"received","actualReceived":2385,"sourceUrl":"https://example.com/dividend"}],"plan":{"principal":100000,"monthly":5000,"years":10,"totalReturn":0.06,"distributionRate":0.04,"frequency":4,"reinvest":1,"deductionRate":0}},"favorites":["0050"],"comparison":["0050","00878"]}"#
    @MainActor func testPWARepeatedImportKeepsCurrentDataAndStableIDs() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PortfolioStore(url: dir.appendingPathComponent("portfolio.json"))
        try store.save(Portfolio.demo.holdings[1])
        try store.importBackup(Data(legacy.utf8)); try store.importBackup(Data(legacy.utf8))
        XCTAssertEqual(store.data.holdings.count, 2); XCTAssertEqual(store.data.dividends.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Recovery").path).count, 2)
        let reopened = PortfolioStore(url: dir.appendingPathComponent("portfolio.json"))
        XCTAssertEqual(reopened.data.legacyDividends?.count, 1)
        XCTAssertEqual(reopened.data.holdings.count, 2)
    }
    @MainActor func testBrokerReimportReplacesOnlySelectedAccount() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let store = PortfolioStore(url:dir.appendingPathComponent("p.json")); try store.save(Portfolio.demo.holdings[2])
        let table = try CSVTable.parse(Data("code,shares,cost\n0050,2,100000\n00878,1,20000".utf8))
        let mapping = BrokerMapping(symbol:0,name:-1,shares:1,cost:2,lots:true)
        let a = try BrokerPreview.make(table:table,mapping:mapping,broker:"A",account:"主",funds:Fund.starters)
        try store.importBroker(a,replaceAccount:false); try store.importBroker(a,replaceAccount:false)
        XCTAssertEqual(store.data.holdings.count,3); XCTAssertEqual(a.holdings[0].shares,2000)
        let b = try BrokerPreview.make(table:CSVTable.parse(Data("code,shares,cost\n0050,1,50000".utf8)),mapping:mapping,broker:"A",account:"主",funds:Fund.starters)
        try store.importBroker(b,replaceAccount:true)
        XCTAssertEqual(store.data.holdings.count,2); XCTAssertTrue(store.data.holdings.contains { $0.symbol == "00919" })
    }
    @MainActor func testBackupRestoresQuotesWithoutOverwritingExistingQuotes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let store = PortfolioStore(url:dir.appendingPathComponent("p.json"))
        var incoming = Portfolio.demo
        try store.importBackup(JSONEncoder().encode(incoming))
        XCTAssertEqual(store.data.quotes["0050"]?.price,55)
        incoming.quotes["0050"]?.price=1
        try store.importBackup(JSONEncoder().encode(incoming))
        XCTAssertEqual(store.data.quotes["0050"]?.price,55)
    }
}
