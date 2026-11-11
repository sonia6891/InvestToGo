import XCTest
@testable import PocketCore

final class ResearchTests: XCTestCase {
    func testQuoteValidation() throws {
        let bytes = Data(#"{"symbol":"0050","date":"2026-10-15","closePrice":55.0,"changePercent":0.4}"#.utf8)
        XCTAssertEqual(try FugleDecode.quote(bytes, expectedSymbol: "0050").price, 55)
        XCTAssertThrowsError(try FugleDecode.quote(bytes, expectedSymbol: "00878"))
        XCTAssertThrowsError(try FugleDecode.quote(Data(#"{"symbol":"0050","date":"2026-10-15"}"#.utf8), expectedSymbol: "0050"))
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
        XCTAssertThrowsError(try FugleDecode.components(Data(#"{"symbol":"0050","data":[]}"#.utf8), symbol:"0050"))
    }
    func testPricePerformanceUsesDrawdownsAndRealTimeInterval() throws {
        let h = PriceHistory(symbol:"0050",adjusted:true,points:[PricePoint(date:"2024-01-01",close:100),PricePoint(date:"2024-06-01",close:120),PricePoint(date:"2024-08-01",close:90),PricePoint(date:"2025-01-01",close:110)],fetchedDay:"2025-01-02",source:"test")
        let stats = try PerformanceStats(h)
        XCTAssertEqual(stats.change,0.1,accuracy:0.000001); XCTAssertEqual(stats.drawdown,0.25,accuracy:0.000001)
        XCTAssertEqual(stats.annualized!,pow(1.1,365.25/366)-1,accuracy:0.000001)
        XCTAssertNil(stats.volatility)
    }
    func testHistoryRejectsUnadjustedDataAndDuplicateDates() {
        XCTAssertThrowsError(try FugleDecode.history(Data(#"{"symbol":"0050","timeframe":"D","data":[]}"#.utf8),symbol:"0050"))
        let h = PriceHistory(symbol:"0050",adjusted:true,points:[PricePoint(date:"2025-01-01",close:100),PricePoint(date:"2025-01-01",close:101)],fetchedDay:"2025-01-02",source:"test")
        XCTAssertThrowsError(try h.validate())
    }
    func testFeeRecordRequiresYearAndSource() {
        var fee = FeeRecord(symbol:"0050",effectiveDate:"2026-01-01",management:"級距費率",custody:"級距費率",annualExpensePercent:0.2,expenseYear:nil,sourceURL:"https://example.com",note:"")
        XCTAssertThrowsError(try fee.validate()); fee.expenseYear=2025; XCTAssertNoThrow(try fee.validate())
        fee.sourceURL="javascript:alert(1)"; XCTAssertThrowsError(try fee.validate())
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
}
