import XCTest
import CoreFoundation
@testable import ETFToGo

final class RestoredFeaturesTests: XCTestCase {
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
    func testPlannedDividendAndOlderNativeEnvelope() throws {
        let input = legacy.replacingOccurrences(of: "ETF_CLASSIFIER", with: "ETF_TOGO_NATIVE").replacingOccurrences(of: "\"version\":3", with: "\"version\":1").replacingOccurrences(of: "\"received\"", with: "\"planned\"")
        let value = try BackupImport.decode(Data(input.utf8))
        XCTAssertEqual(value.dividends[0].amount, 2390); XCTAssertEqual(value.dividends[0].status, .estimated)
    }
    func testLegacyRejectsNegativeCostsAndMissingActualPayment() {
        XCTAssertThrowsError(try BackupImport.decode(Data(legacy.replacingOccurrences(of: "\"cost\":100000", with: "\"cost\":-1").utf8)))
        XCTAssertThrowsError(try BackupImport.decode(Data(legacy.replacingOccurrences(of: "\"actualReceived\":2385", with: "\"actualReceived\":null").utf8)))
    }
    func testBundledCatalogCoversBothMarketsAndNoDuplicateCodes() throws {
        let catalog = try XCTUnwrap(CatalogSnapshot.bundled())
        try catalog.validate()
        XCTAssertGreaterThan(catalog.funds.filter { $0.market == "TWSE" }.count, 200)
        XCTAssertGreaterThan(catalog.funds.filter { $0.market == "TPEx" }.count, 100)
        XCTAssertTrue(catalog.funds.contains { $0.id == "00679B" && $0.market == "TPEx" })
        XCTAssertEqual(Set(catalog.funds.map(\.id)).count, catalog.funds.count)
    }
    func testCatalogRejectsMissingMarketAndDuplicates() {
        let rows = Data(#"[{"基金代號":"0050","基金簡稱":"元大台灣50","出表日期":"1151014","上市日期":"0920630"}]"#.utf8)
        let active = Data(#"{"status":"success","data":[{"stockNo":"0050","stockName":"元大台灣50","listingDate":"2003.06.30"}]}"#.utf8)
        XCTAssertThrowsError(try CatalogAPI.decode(listed:rows,otc:Data(#"{"status":"success","data":[]}"#.utf8),active:active))
        XCTAssertThrowsError(try CatalogAPI.decode(listed:rows,otc:active,active:active))
    }
    func testCatalogExcludesHistoricalAndFutureListings() throws {
        let rows = Data(#"[{"基金代號":"0054","出表日期":"1151014"}]"#.utf8)
        let active = Data(#"{"status":"success","data":[{"stockNo":"0050","stockName":"元大台灣50","listingDate":"2003.06.30"},{"stockNo":"00415A","stockName":"尚未掛牌","listingDate":"2026.10.20"}]}"#.utf8)
        let otc = Data(#"{"status":"success","data":[{"stockNo":"00679B","stockName":"元大美債20年","listingDate":"20170117"}]}"#.utf8)
        let result = try CatalogAPI.decode(listed:rows,otc:otc,active:active,today:"2026-10-15")
        XCTAssertEqual(result.funds.map(\.id),["0050","00679B"])
    }
    func snapshot(_ symbol: String, _ values: [(String, Double)]) -> ComponentSnapshot {
        ComponentSnapshot(symbol: symbol, date: "2026-10-01", components: values.map { FundComponent(symbol: $0.0, name: $0.0, weight: $0.1) }, source: "test")
    }
    func testOverlapAndExposureUseWeightsAndExcludeMissingQuotes() throws {
        let a = snapshot("0050", [("2330",60),("2454",10)])
        let b = snapshot("00878", [("2330",20),("2317",5)])
        let rows = ResearchMath.overlap(a,b)
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.reduce(0) { $0 + min($1.left,$1.right) }, 20)
        var data = Portfolio.demo; data.components = ["0050":a,"00878":b]
        let exposure = ResearchMath.exposures(data)
        XCTAssertEqual(exposure.first?.value, 91200)
        data.quotes.removeValue(forKey: "00878")
        XCTAssertEqual(ResearchMath.exposures(data).first?.value, 66000)
        data.quotes["0050"]?.currency = "USD"
        XCTAssertTrue(ResearchMath.exposures(data).isEmpty); XCTAssertNil(data.marketValue)
    }
    func testComponentsRejectFutureDatesInvalidWeightsAndUnknownSymbol() {
        var value = snapshot("0050", [("2330",110)])
        XCTAssertThrowsError(try value.validate())
        value = snapshot("0050", [("2330",60)]); value.date = "2099-01-01"
        XCTAssertThrowsError(try value.validate())
        XCTAssertThrowsError(try Fugle.decodeComponents(Data(#"{"symbol":"0050","data":[]}"#.utf8), symbol:"0050"))
    }
    func testPricePerformanceUsesDrawdownsAndRealTimeInterval() throws {
        let h = PriceHistory(symbol:"0050",adjusted:true,points:[PricePoint(date:"2024-01-01",close:100),PricePoint(date:"2024-06-01",close:120),PricePoint(date:"2024-08-01",close:90),PricePoint(date:"2025-01-01",close:110)],fetchedDay:"2025-01-02",source:"test")
        let stats = try PerformanceStats(h)
        XCTAssertEqual(stats.change,0.1,accuracy:0.000001); XCTAssertEqual(stats.drawdown,0.25,accuracy:0.000001)
        XCTAssertEqual(stats.annualized!,pow(1.1,365.25/366)-1,accuracy:0.000001)
        XCTAssertNil(stats.volatility)
    }
    func testHistoryRejectsOutOfOrderDatesAndInvalidCalendarDays() {
        let h = PriceHistory(symbol:"0050",adjusted:true,points:[PricePoint(date:"2025-01-02",close:100),PricePoint(date:"2025-01-01",close:101)],fetchedDay:"2025-01-03",source:"test")
        XCTAssertThrowsError(try h.validate())
        XCTAssertNil(DataChecks.date("2025-02-30")); XCTAssertNil(DataChecks.date("2025-1-05"))
        XCTAssertEqual(DataChecks.date("2025-01-05").map { DataChecks.day($0) }, "2025-01-05")
    }
    func testHistoryRejectsUnadjustedDataAndDuplicateDates() {
        XCTAssertThrowsError(try Fugle.decodeHistory(Data(#"{"symbol":"0050","timeframe":"D","data":[]}"#.utf8),symbol:"0050"))
        let h = PriceHistory(symbol:"0050",adjusted:true,points:[PricePoint(date:"2025-01-01",close:100),PricePoint(date:"2025-01-01",close:101)],fetchedDay:"2025-01-02",source:"test")
        XCTAssertThrowsError(try h.validate())
    }
    func testCSVQuotedCommasNewlinesAndTrailingLine() throws {
        let table = try CSVTable.parse(Data("代碼,名稱,股數,總成本\r\n0050,\"台灣,50\",1000,\"50,000\"\r\n".utf8))
        XCTAssertEqual(table.rows.count,1); XCTAssertEqual(table.rows[0][1],"台灣,50")
        let p = try BrokerPreview.make(table:table,mapping:BrokerMapping(symbol:0,name:1,shares:2,cost:3),broker:"測試券商",account:"主要",funds:Fund.starters)
        XCTAssertEqual(p.holdings[0].unitCost,50); XCTAssertEqual(p.totalCost,50000)
        XCTAssertThrowsError(try CSVTable.parse(Data("a,b\n\"bad,x".utf8)))
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
    func testFeeRecordRequiresYearAndSource() {
        var fee = FeeRecord(symbol:"0050",effectiveDate:"2026-01-01",management:"級距費率",custody:"級距費率",annualExpensePercent:0.2,expenseYear:nil,sourceURL:"https://example.com",note:"")
        XCTAssertThrowsError(try fee.validate()); fee.expenseYear=2025; XCTAssertNoThrow(try fee.validate())
        fee.sourceURL="javascript:alert(1)"; XCTAssertThrowsError(try fee.validate())
    }
    func testSchemaOneStillDecodesWithoutNewFields() throws {
        let bytes = Data(#"{"schema":1,"holdings":[],"dividends":[],"favorites":[],"quotes":{}}"#.utf8)
        let value=try Portfolio.decodeBackup(bytes); XCTAssertNil(value.components); XCTAssertTrue(value.holdings.isEmpty)
    }
    func testPlanReinvestmentDoesNotCountDividendsTwice() throws {
        var plan = LegacyPlan(principal:100000,monthly:0,years:1,totalReturn:0.06,distributionRate:0.04,frequency:4,reinvest:1,deductionRate:0)
        let full = try XCTUnwrap(PlanMath.project(plan).last)
        XCTAssertEqual(full.total,106000,accuracy:0.001)
        XCTAssertEqual(full.cash,0)
        plan.totalReturn=0; plan.reinvest=0
        let cash = try XCTUnwrap(PlanMath.project(plan).last)
        XCTAssertEqual(cash.total,100000,accuracy:0.001)
        XCTAssertEqual(cash.cash,100000 * (1-pow(0.99,4)),accuracy:0.001)
        plan.deductionRate=0.1
        XCTAssertLessThan(try XCTUnwrap(PlanMath.project(plan).last).total,100000)
    }
    func testCSVAcceptsBOMBeforeQuotedHeader() throws {
        let table=try CSVTable.parse(Data("\u{feff}\"code\",shares,cost\n0050,1000,50000".utf8))
        XCTAssertEqual(table.headers[0],"code")
        XCTAssertEqual(table.rows.count,1)
    }

    func testAnnualFeeSnapshotUsesReportedTotalsAndCorrectYear() throws {
        let catalog = try XCTUnwrap(AnnualFeeCatalog.bundled)
        XCTAssertGreaterThan(catalog.records.count,280)
        let fee = try XCTUnwrap(catalog.records["0050"])
        XCTAssertEqual(fee.year,2025); XCTAssertEqual(fee.fundID,"98764389")
        XCTAssertEqual(fee.total,0.22,accuracy:0.00001)
        XCTAssertEqual(fee.management,0.11,accuracy:0.00001)
        XCTAssertNotNil(catalog.records["00679B"])
        XCTAssertNil(catalog.records["00415A"])
    }

    func testCSVUTF16AndBig5Encoding() throws {
        let text = "代碼,股數,成本\n0050,1000,50000"
        let utf16 = try XCTUnwrap(text.data(using:.utf16))
        XCTAssertEqual(try CSVTable.parse(utf16).headers[0],"代碼")
        let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        let bytes = try XCTUnwrap(text.data(using:big5))
        XCTAssertEqual(try CSVTable.parse(bytes).headers[0],"代碼")
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
