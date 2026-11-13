import XCTest
import CoreFoundation
@testable import PocketCore

/// Pure-logic tests ported verbatim from the app test target (Tests/*.swift).
final class PortedAppTests: XCTestCase {
    let legacy = #"{"app":"ETF_CLASSIFIER","version":3,"planning":{"version":2,"holdings":[{"id":"pwa-001","code":"0050","name":"元大台灣50","shares":2000,"cost":100000,"price":55,"priceDate":"2026-10-01"}],"dividends":[{"id":"pwa-dividend-1","code":"0050","name":"元大台灣50","paymentDate":"2026-10-10","exDate":"2026-10-01","eligibleShares":2000,"perShare":1.2,"deductions":10,"status":"received","actualReceived":2385,"sourceUrl":"https://example.com/dividend"}],"plan":{"principal":100000,"monthly":5000,"years":10,"totalReturn":0.06,"distributionRate":0.04,"frequency":4,"reinvest":1,"deductionRate":0}},"favorites":["0050"],"comparison":["0050","00878"]}"#
    func testNoMarketValueWithoutCompleteQuotes() {
        var data = Portfolio.sample
        XCTAssertEqual(data.marketValue, 348500)
        data.quotes.removeValue(forKey: "0050")
        XCTAssertNil(data.marketValue, "Missing prices must not silently use cost as market value")
    }
    func testProjectionZeroReturnAndMonthlyTiming() {
        XCTAssertEqual(Projection.value(initial: 100000, monthly: 5000, years: 10, annualPercent: 0), 700000, accuracy: 0.01)
        XCTAssertLessThan(Projection.value(initial: 100000, monthly: 0, years: 10, annualPercent: -5), 100000)
    }
    func testBackupRejectsInvalidData() throws {
        var data = Portfolio.sample
        data.holdings[0].shares = -1
        XCTAssertThrowsError(try Portfolio.decodeBackup(JSONEncoder().encode(data)))
        data = .sample; data.schema = 99
        XCTAssertThrowsError(try Portfolio.decodeBackup(JSONEncoder().encode(data)))
        data = .sample; data.holdings.append(data.holdings[0])
        XCTAssertThrowsError(try Portfolio.decodeBackup(JSONEncoder().encode(data)))
    }
    func testOfficialDistributionHelpers() {
        XCTAssertEqual(OfficialDividends.rocDay("115年10月22日"), "2026-10-22")
        XCTAssertEqual(OfficialDividends.rocDay("1151016"), "2026-10-16")
        XCTAssertNil(OfficialDividends.rocDay("abc"))
        let days = (1...4).map { DataChecks.day(Calendar.current.date(byAdding: .month, value: -3 * $0 + 1, to: Date())!) }
        XCTAssertEqual(OfficialDividends.frequency(of: days.map { OfficialDistribution(ex: $0, pay: "", amount: 1) }), "季配")
        XCTAssertEqual(OfficialDividends.frequency(of: Array(days.prefix(2)).map { OfficialDistribution(ex: $0, pay: "", amount: 1) }), "半年配")
    }
    func testComboProjectionMatchesTemplate() {
        var settings = ComboSettings()
        settings.monthly = 10000; settings.stockReturn = 5; settings.etfReturn = 5
        for (years, expected) in [(3, 734180.51), (5, 1061021.85), (10, 2032300.0)] {
            let result = ComboMath.project(stockStart: 120000, etfStart: 180000, settings: settings, stockShare: 0.4, years: years, scenario: .base)
            XCTAssertEqual(result.end, expected, accuracy: 1)
            XCTAssertEqual(result.invested, 10000 * Double(years * 12), accuracy: 0.001)
        }
        XCTAssertEqual(ComboMath.project(stockStart: 120000, etfStart: 180000, settings: settings, stockShare: 0.4, years: 5, scenario: .stress).end, 908735.8, accuracy: 1)
        var flat = settings; flat.stockReturn = 0; flat.etfReturn = 0
        XCTAssertEqual(ComboMath.project(stockStart: 120000, etfStart: 180000, settings: flat, stockShare: 0.4, years: 10, scenario: .base).end, 1500000, accuracy: 0.01)
        var cash = settings; cash.reinvest = false; cash.stockYield = 2; cash.etfYield = 4
        XCTAssertEqual(ComboMath.project(stockStart: 120000, etfStart: 180000, settings: cash, stockShare: 0.4, years: 5, scenario: .base).end, 1049649.13, accuracy: 1)  // ETF only: all money earns the ETF yield
        XCTAssertEqual(ComboScenario.conservative.rate(5), -2); XCTAssertEqual(ComboScenario.optimistic.rate(5), 8)
    }
    func testQuoteValidation() throws {
        let bytes = Data(#"{"symbol":"0050","date":"2026-10-15","closePrice":55.0,"changePercent":0.4}"#.utf8)
        XCTAssertEqual(try Fugle.decode(bytes, expectedSymbol: "0050").price, 55)
        XCTAssertThrowsError(try Fugle.decode(bytes, expectedSymbol: "00878"))
        XCTAssertThrowsError(try Fugle.decode(Data(#"{"symbol":"0050","date":"2026-10-15"}"#.utf8), expectedSymbol: "0050"))
    }
    func testOpenDataDistributions() throws {
        // Shapes of October 2026: TWSE 上市股票除權除息預告表 (息/權, amount empty until set, stocks and ETNs too) and
        // TPEx 上櫃股票除權除息預告表 (除息/除權/除權息).
        let twse = Data(#"""
        [{"Date":"1151022","Code":"0056","Name":"元大高股息","Exdividend":"息","StockDividendRatio":"","CashDividend":""},
         {"Date":"1151019","Code":"00878","Name":"國泰永續高股息","Exdividend":"息","StockDividendRatio":"","CashDividend":"0.400000"},
         {"Date":"1151020","Code":"1711","Name":"永光","Exdividend":"權","StockDividendRatio":"","CashDividend":"0"},
         {"Date":"1151104","Code":"020036","Name":"元大金融配息N","Exdividend":"息","StockDividendRatio":"","CashDividend":"0.400000"}]
        """#.utf8)
        let tpex = Data(#"""
        [{"ExRrightsExDividendDate":"1151016","SecuritiesCompanyCode":"00679B","CompanyName":"元大美債20年","ExRrightsExDividend":"除息","CashDividend":"0.36000000"},
         {"ExRrightsExDividendDate":"1151007","SecuritiesCompanyCode":"6129","CompanyName":"普誠","ExRrightsExDividend":"除權","CashDividend":"0.00000000"},
         {"ExRrightsExDividendDate":"1151016","SecuritiesCompanyCode":"0056","CompanyName":"不同市場","ExRrightsExDividend":"除息","CashDividend":"1.00000000"}]
        """#.utf8)
        let markets = ["0056": "TWSE", "00878": "TWSE", "00679B": "TPEx"]
        let listed = try OfficialDividends.decode(twse, market: "TWSE", markets: markets)
        XCTAssertEqual(Set(listed.keys), ["0056", "00878"])
        XCTAssertEqual(listed["0056"], [OfficialDistribution(ex: "2026-10-22", pay: "", amount: nil)], "Announced before the amount is set")
        XCTAssertEqual(listed["00878"], [OfficialDistribution(ex: "2026-10-19", pay: "", amount: 0.4)])
        let otc = try OfficialDividends.decode(tpex, market: "TPEx", markets: markets)
        XCTAssertEqual(otc, ["00679B": [OfficialDistribution(ex: "2026-10-16", pay: "", amount: 0.36)]])
        XCTAssertThrowsError(try OfficialDividends.decode(Data("<html>維護中</html>".utf8), market: "TWSE", markets: markets))
        XCTAssertThrowsError(try OfficialDividends.decode(tpex, market: "TWSE", markets: markets), "TPEx fields under the TWSE name are refused")
        // A known ex-dividend day keeps its payment day, and its amount until the notice sets one; the record stays.
        var known = OfficialDividends()
        known.events["0056"] = [OfficialDistribution(ex: "2026-10-22", pay: "2026-11-11", amount: nil), OfficialDistribution(ex: "2026-07-21", pay: "2026-08-10", amount: 1.35)]
        known.events["00878"] = [OfficialDistribution(ex: "2026-10-19", pay: "2026-11-14", amount: 0.5)]
        known.freq["00878"] = "季配"
        let merged = known.merging(listed, frequency: false).merging(otc, frequency: false)
        XCTAssertEqual(merged.list("0056"), [OfficialDistribution(ex: "2026-10-22", pay: "2026-11-11", amount: nil), OfficialDistribution(ex: "2026-07-21", pay: "2026-08-10", amount: 1.35)])
        XCTAssertEqual(merged.list("00878"), [OfficialDistribution(ex: "2026-10-19", pay: "2026-11-14", amount: 0.4)])
        XCTAssertEqual(merged.list("00679B"), [OfficialDistribution(ex: "2026-10-16", pay: "", amount: 0.36)])
        XCTAssertEqual(merged.freq, ["00878": "季配"], "Frequencies change only when asked")
        // Past-year figures wait until the record covers the year.
        let quarters = (1...4).map { DataChecks.day(Calendar.current.date(byAdding: .month, value: -3 * $0 + 1, to: Date())!) }
        var started = OfficialDividends(sources: ["since": DataChecks.day()])
        started.events["0056"] = quarters.map { OfficialDistribution(ex: $0, pay: "", amount: 1) }
        XCTAssertFalse(started.coversYear); XCTAssertNil(started.trailingAmount("0056"))
        XCTAssertNil(started.merging(["0056": []], frequency: true).frequency("0056"), "No frequency from part of a year")
        var whole = started
        whole.sources["since"] = DataChecks.day(Calendar.current.date(byAdding: .day, value: -366, to: Date())!)
        XCTAssertTrue(whole.coversYear); XCTAssertEqual(whole.trailingAmount("0056"), 4)
        XCTAssertEqual(whole.merging(["0056": []], frequency: true).frequency("0056"), "季配")
        XCTAssertEqual(whole.merging(["00919": []], frequency: true).frequency("0056"), "季配", "Every ETF in the record is labelled, not only those in the notice")
        var quiet = whole; quiet.freq["0056"] = "月配"
        XCTAssertEqual(quiet.merging([:], frequency: true).frequency("0056"), "季配", "A label from before is corrected from the record")
        XCTAssertNil(OfficialDividends().since, "A record kept from before has no start day")
        // The bundled record comes from the open data alone: it says where it starts and has no payment days.
        let bundled = OfficialDividends.bundled()
        XCTAssertNotNil(bundled.since)
        XCTAssertTrue(bundled.events.values.joined().allSatisfy { $0.pay.isEmpty })
    }
    func testTaiwanTradingHours() {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd HH:mm"; format.timeZone = TaiwanMarket.zone; format.locale = Locale(identifier: "en_US_POSIX")
        func at(_ text: String) -> Date { format.date(from: text)! }
        XCTAssertFalse(TaiwanMarket.isOpen(at("2026-10-16 08:54")))
        XCTAssertTrue(TaiwanMarket.isOpen(at("2026-10-16 08:55")), "Friday, opening trial match")
        XCTAssertTrue(TaiwanMarket.isOpen(at("2026-10-16 13:40")))
        XCTAssertFalse(TaiwanMarket.isOpen(at("2026-10-16 13:41")))
        XCTAssertFalse(TaiwanMarket.isOpen(at("2026-10-17 10:00")), "Saturday")
    }
    func testSellCostsMatchTheBroker() {
        // 國泰證券 showed 34,653 for 2,000 shares of an ETF at 17.35 with its 2.8 折 rate: fee 34,700 × 0.1425% × 0.28
        // = 13.8 → 13, tax 0.1% = 34.7 → 34.
        let cathay = FeeRate(discount: 2.8, minimum: 1)
        XCTAssertEqual(SellCosts.net(34700, stock: false, bond: false, rate: cathay), 34653)
        XCTAssertEqual(SellCosts.net(100_000, stock: true, bond: false, rate: cathay), 100_000 - 39 - 300, "Stocks pay 0.3% tax")
        XCTAssertEqual(SellCosts.net(100_000, stock: false, bond: false, rate: SellCosts.standard), 100_000 - 142 - 100, "The list price")
        XCTAssertEqual(SellCosts.net(1000, stock: false, bond: false, rate: SellCosts.standard), 1000 - 20 - 1, "The minimum fee applies to a small sale")
        let day = DataChecks.date("2026-10-17")!, later = DataChecks.date("2027-01-02")!
        XCTAssertEqual(SellCosts.net(50_000, stock: false, bond: true, rate: cathay, on: day), 50_000 - 19, "Bond ETFs pay no tax through 2026")
        XCTAssertEqual(SellCosts.net(50_000, stock: false, bond: true, rate: cathay, on: later), 50_000 - 19 - 50)
        XCTAssertEqual(SellCosts.net(0, stock: false, bond: false, rate: SellCosts.standard), 0, "Nothing to sell, nothing deducted")
    }
    func testScreenshotCostPerShareOrTotal() throws {
        let funds = Fund.starters + [Fund(id: "00991A", name: "主動測試", strategy: .unclassified)]
        let lots = ScreenshotImport.Listing([(code: "00991A", name: "主動測試")])
        let read = ScreenshotImport.parse(["主動測試 00991A", "股數 1,000", "成本價 17.35"], in: lots)
        XCTAssertEqual(read, [.init(symbol: "00991A", shares: 1000, cost: 17.35, basis: .perShare)])
        XCTAssertEqual(ScreenshotImport.parse(["主動測試 00991A", "現股庫存 1,000", "成交價 17.35"], in: lots), read, "國泰證券 calls the price paid per share 成交價")
        XCTAssertEqual(ScreenshotImport.parse(["主動測試 00991A", "現股庫存 成交價", "1,000 17.35"], in: lots), read, "Titles in a row above the figures")
        let labelled = ScreenshotImport.Draft(read[0], price: 17.5)
        XCTAssertTrue(labelled.perShare)
        XCTAssertEqual(try XCTUnwrap(labelled.totalCost), 17350, accuracy: 0.001, "成本價 17.35 × 1,000 shares")
        XCTAssertEqual(try XCTUnwrap(labelled.averageCost), 17.35, accuracy: 1e-9)
        XCTAssertEqual(ScreenshotImport.parse(["主動測試 00991A", "股數 1,000", "成本 17.35"], in: lots), [.init(symbol: "00991A", shares: 1000, cost: 17.35)], "A plain 成本 does not say which it is")
        XCTAssertTrue(ScreenshotImport.Draft(.init(symbol: "00991A", shares: 1000, cost: 17.35), price: 17.5).perShare, "Near the price itself: a price per share")
        XCTAssertFalse(ScreenshotImport.Draft(.init(symbol: "00991A", shares: 1000, cost: 17350), price: 17.5).perShare, "Near the price once divided by the shares: a total")
        for unsure in [ScreenshotImport.Draft(.init(symbol: "00991A", shares: 1000, cost: 3), price: 17.5), ScreenshotImport.Draft(.init(symbol: "00991A", shares: 1000, cost: 17.35))] {
            XCTAssertEqual(unsure.cost, "", "Neither reading fits the price, or there is no price: not filled in")
            XCTAssertNotNil(unsure.costNote)
        }
        XCTAssertNotNil(BrokerPreview.costWarning(average: 0.017, price: 17.5), "An average cost far under the price is always warned about")
        XCTAssertNil(BrokerPreview.costWarning(average: 17.35, price: 17.5))
        let lotsOfMargin = [ScreenshotImport.Draft(.init(symbol: "00991A", shares: 1000, cost: 17, kind: .margin, basis: .perShare)),
                            ScreenshotImport.Draft(.init(symbol: "00991A", shares: 1000, cost: 18000, kind: .margin, basis: .total)),
                            ScreenshotImport.Draft(.init(symbol: "00991A", shares: 500, cost: 17.5, basis: .perShare))]
        let preview = try BrokerPreview.make(drafts: lotsOfMargin, broker: "國泰證券", account: "主要", funds: funds)
        XCTAssertEqual(preview.holdings.map(\.shares), [2000, 500])
        XCTAssertEqual(preview.holdings[0].cost, 35000, accuracy: 0.001, "17 × 1,000 + 18,000")
        XCTAssertEqual(preview.holdings[0].unitCost, 17.5, accuracy: 1e-9); XCTAssertEqual(preview.holdings[0].broker, "國泰證券（融資）")
        XCTAssertEqual(preview.holdings[1].cost, 8750, accuracy: 0.001)
        XCTAssertTrue(preview.warnings(price: { $0 == "00991A" ? 17.5 : nil }).isEmpty)
        let csv = try BrokerPreview.make(table: CSVTable.parse(Data("code,shares,cost\n00991A,1000,17.35".utf8)), mapping: BrokerMapping(symbol: 0, name: -1, shares: 1, cost: 2), broker: "國泰證券", account: "主要", funds: funds)
        XCTAssertEqual(csv.warnings(price: { $0 == "00991A" ? 17.5 : nil }).count, 1, "A CSV price per share imported as a total is warned about")
        XCTAssertTrue(csv.warnings(price: { _ in nil }).isEmpty)
    }
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
        let twse = Data(#"[{"Date":"1151015","Code":"0050","Name":"元大台灣50"}]"#.utf8)
        let otc = Data(#"[{"Date":"1151016","SecuritiesCompanyCode":"00679B","CompanyName":"元大美債20年"}]"#.utf8)
        let stocksOnly = Data(#"[{"Date":"1151016","SecuritiesCompanyCode":"6488","CompanyName":"環球晶"}]"#.utf8)
        XCTAssertNoThrow(try CatalogAPI.decode(listed: rows, twse: twse, otc: otc, today: "2026-10-15"))
        XCTAssertThrowsError(try CatalogAPI.decode(listed: rows, twse: twse, otc: Data("[]".utf8)), "An empty OTC list is refused")
        XCTAssertThrowsError(try CatalogAPI.decode(listed: rows, twse: twse, otc: stocksOnly), "An OTC list without ETFs is refused")
        XCTAssertThrowsError(try CatalogAPI.decode(listed: rows, twse: twse, otc: Data(#"[{"SecuritiesCompanyCode":"0050","CompanyName":"元大台灣50"}]"#.utf8)), "A code in both markets is refused")
        XCTAssertThrowsError(try CatalogAPI.decode(listed: rows, twse: Data(#"[{"Date":"1151015","Symbol":"0050","Title":"元大台灣50"}]"#.utf8), otc: otc), "Renamed fields are refused")
        let twice = Data(#"[{"基金代號":"0050","出表日期":"1151014"},{"基金代號":"0050","出表日期":"1151014"}]"#.utf8)
        XCTAssertThrowsError(try CatalogAPI.decode(listed: twice, twse: twse, otc: otc), "A fund listed twice is refused")
    }
    func testPricePerformanceUsesDrawdownsAndRealTimeInterval() throws {
        let h = PriceHistory(symbol:"0050",adjusted:true,points:[PricePoint(date:"2024-01-01",close:100),PricePoint(date:"2024-06-01",close:120),PricePoint(date:"2024-08-01",close:90),PricePoint(date:"2025-01-01",close:110)],fetchedDay:"2025-01-02",source:"test")
        let stats = try PerformanceStats(h)
        XCTAssertEqual(stats.change,0.1,accuracy:0.000001); XCTAssertEqual(stats.drawdown,0.25,accuracy:0.000001)
        XCTAssertEqual(stats.annualized!,pow(1.1,365.25/366)-1,accuracy:0.000001)
        XCTAssertNil(stats.volatility)
    }
    func testCSVTrailingCellsShortRowsAndBadRowsAreSkippedNotFatal() throws {
        let table = try CSVTable.parse(Data("代碼,名稱,股數,總成本,\n0050,元大台灣50,1000,50000,\n00878,國泰永續高股息,abc,20000\n00919,群益台灣精選高息,1,000,22000\n合計,,,72000\n備註\n".utf8))
        XCTAssertEqual(table.headers, ["代碼","名稱","股數","總成本"], "A trailing empty title cell is dropped")
        XCTAssertTrue(table.rows.allSatisfy { $0.count >= 4 }, "Short rows are padded")
        let p = try BrokerPreview.make(table: table, mapping: BrokerMapping(guessing: table), broker: "測試券商", account: "主要", funds: Fund.starters)
        XCTAssertEqual(p.holdings.map(\.symbol), ["0050"])
        XCTAssertEqual(p.skipped.count, 4)
        XCTAssertTrue(p.skipped[0].contains("00878") && p.skipped[0].contains("數量"))
        XCTAssertTrue(p.skipped[1].contains("00919") && p.skipped[1].contains("逗號"))
        XCTAssertEqual(p.skippedCodes, ["00878", "00919"])
        XCTAssertThrowsError(try BrokerPreview.make(table: CSVTable.parse(Data("代碼,股數,總成本\n合計,1,1".utf8)), mapping: BrokerMapping(symbol: 0, name: -1, shares: 1, cost: 2), broker: "測試券商", account: "主要", funds: Fund.starters)) {
            XCTAssertTrue($0.localizedDescription.contains("沒有可匯入"))
        }
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
    func testFeeRecordRequiresYearAndSource() {
        var fee = FeeRecord(symbol:"0050",effectiveDate:"2026-01-01",management:"級距費率",custody:"級距費率",annualExpensePercent:0.2,expenseYear:nil,sourceURL:"https://example.com",note:"")
        XCTAssertThrowsError(try fee.validate()); fee.expenseYear=2025; XCTAssertNoThrow(try fee.validate())
        fee.sourceURL="javascript:alert(1)"; XCTAssertThrowsError(try fee.validate())
        fee.sourceURL=""; XCTAssertNoThrow(try fee.validate(), "The reference address is optional")
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
        #if canImport(Darwin) // Linux Foundation cannot convert Big5
        let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        let bytes = try XCTUnwrap(text.data(using:big5))
        XCTAssertEqual(try CSVTable.parse(bytes).headers[0],"代碼")
        #endif
    }
}
