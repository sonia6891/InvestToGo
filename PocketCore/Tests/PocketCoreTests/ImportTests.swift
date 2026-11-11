import XCTest
#if canImport(Darwin)
import CoreFoundation
#endif
@testable import PocketCore

final class ImportTests: XCTestCase {
    let legacy = #"{"app":"ETF_CLASSIFIER","version":3,"planning":{"version":2,"holdings":[{"id":"pwa-001","code":"0050","name":"元大台灣50","shares":2000,"cost":100000,"price":55,"priceDate":"2026-10-01"}],"dividends":[{"id":"pwa-dividend-1","code":"0050","name":"元大台灣50","paymentDate":"2026-10-10","exDate":"2026-10-01","eligibleShares":2000,"perShare":1.2,"deductions":10,"status":"received","actualReceived":2385,"sourceUrl":"https://example.com/dividend"}],"plan":{"principal":100000,"monthly":5000,"years":10,"totalReturn":0.06,"distributionRate":0.04,"frequency":4,"reinvest":1,"deductionRate":0}},"favorites":["0050"],"comparison":["0050","00878"]}"#

    func testRealPWAShapeMigratesCostActualDividendAndMetadata() throws {
        let value = try BackupImport.decode(Data(legacy.utf8))
        XCTAssertEqual(value.holdings[0].unitCost, 50)
        XCTAssertEqual(value.cost, 100000)
        XCTAssertEqual(value.dividends[0].amount, 2385, "Actual receipt must win over shares × dividend minus fees")
        XCTAssertEqual(value.dividends[0].status, .paid)
        XCTAssertEqual(DataChecks.day(value.dividends[0].date), "2026-10-10")
        XCTAssertEqual(value.legacyPrices?["pwa-001"]?.price, 55)
        XCTAssertEqual(value.legacyDividends?["pwa-dividend-1"]?.deductions, 10)
        XCTAssertEqual(value.legacyPlan?.distributionRate, 0.04)
        XCTAssertEqual(value.comparison, ["0050", "00878"])
        XCTAssertTrue(value.quotes.isEmpty, "Manually entered prices must not become verified quotes")
    }
    func testPlannedDividendAndOlderNativeEnvelope() throws {
        let input = legacy.replacingOccurrences(of: "ETF_CLASSIFIER", with: "ETF_TOGO_NATIVE").replacingOccurrences(of: "\"version\":3", with: "\"version\":1").replacingOccurrences(of: "\"received\"", with: "\"planned\"")
        let value = try BackupImport.decode(Data(input.utf8))
        XCTAssertEqual(value.dividends[0].amount, 2390); XCTAssertEqual(value.dividends[0].status, .estimated)
    }
    func testLegacyRejectsNegativeCostsAndMissingActualPayment() {
        XCTAssertThrowsError(try BackupImport.decode(Data(legacy.replacingOccurrences(of: "\"cost\":100000", with: "\"cost\":-1").utf8)))
        XCTAssertThrowsError(try BackupImport.decode(Data(legacy.replacingOccurrences(of: "\"actualReceived\":2385", with: "\"actualReceived\":null").utf8)))
    }
    func testCSVQuotedCommasNewlinesAndTrailingLine() throws {
        let table = try CSVTable.parse(Data("代碼,名稱,股數,總成本\r\n0050,\"台灣,50\",1000,\"50,000\"\r\n".utf8))
        XCTAssertEqual(table.rows.count, 1); XCTAssertEqual(table.rows[0][1], "台灣,50")
        let p = try BrokerPreview.make(table: table, mapping: BrokerMapping(symbol: 0, name: 1, shares: 2, cost: 3), broker: "測試券商", account: "主要", funds: Fund.starters)
        XCTAssertEqual(p.holdings[0].unitCost, 50); XCTAssertEqual(p.totalCost, 50000)
        XCTAssertThrowsError(try CSVTable.parse(Data("a,b\n\"bad,x".utf8)))
    }
    func testCSVAcceptsBOMBeforeQuotedHeader() throws {
        let table = try CSVTable.parse(Data("\u{feff}\"code\",shares,cost\n0050,1000,50000".utf8))
        XCTAssertEqual(table.headers[0], "code")
        XCTAssertEqual(table.rows.count, 1)
    }
    func testCSVUTF16AndBig5Encoding() throws {
        let text = "代碼,股數,成本\n0050,1000,50000"
        let utf16 = try XCTUnwrap(text.data(using: .utf16))
        XCTAssertEqual(try CSVTable.parse(utf16).headers[0], "代碼")
        #if canImport(Darwin)
        let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        let bytes = try XCTUnwrap(text.data(using: big5))
        XCTAssertEqual(try CSVTable.parse(bytes).headers[0], "代碼")
        #endif
    }
    func testBrokerPreviewConvertsLotsAndUsesStableIDs() throws {
        let table = try CSVTable.parse(Data("代碼,張數,總成本\n0050,2,100000".utf8))
        let funds = [Fund(id: "0050", name: "元大台灣50", strategy: .saving)]
        let mapping = BrokerMapping(symbol: 0, name: -1, shares: 1, cost: 2, lots: true, totalCost: true)
        let a = try BrokerPreview.make(table: table, mapping: mapping, broker: "富邦證券", account: "主帳戶", funds: funds)
        XCTAssertEqual(a.holdings[0].shares, 2000); XCTAssertEqual(a.holdings[0].unitCost, 50)
        XCTAssertEqual(a.sourceAccount, "BC7184A2-8615-5B96-BBEF-6ACB785C7D4E")
        let b = try BrokerPreview.make(table: table, mapping: mapping, broker: "富邦證券", account: "主帳戶", funds: funds)
        XCTAssertEqual(a.holdings[0].id, b.holdings[0].id)
    }
}
