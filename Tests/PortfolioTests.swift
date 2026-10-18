import XCTest
import CoreGraphics
@testable import ETFToGo

final class PortfolioTests: XCTestCase {
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
    @MainActor func testPersistenceAndImportIdempotence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PortfolioStore(url: url)
        let holding = Portfolio.sample.holdings[0]
        try store.save(holding)
        let reopened = PortfolioStore(url: url)
        XCTAssertEqual(reopened.data.holdings.first?.shares, holding.shares)
        let bytes = try JSONEncoder().encode(Portfolio.sample)
        try reopened.importBackup(bytes)
        let count = reopened.data.holdings.count
        try reopened.importBackup(bytes)
        XCTAssertEqual(reopened.data.holdings.count, count)
        XCTAssertTrue(reopened.data.holdings.contains { $0.id == holding.id })
    }
    @MainActor func testTradeLogRecordsHoldingChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PortfolioStore(url: url)
        var holding = Portfolio.sample.holdings[0]
        try store.save(holding); try store.save(holding)
        holding.shares += 1000; try store.save(holding)
        try store.remove(holding)
        XCTAssertEqual(store.data.trades?.map(\.action), [.buy, .adjust, .remove], "Saving unchanged values adds no entry")
        XCTAssertEqual(store.data.trades?.last?.shares, 3000)
        XCTAssertEqual(PortfolioStore(url: url).data.trades?.count, 3)
    }
    @MainActor func testBuyAndSellAdjustHolding() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PortfolioStore(url: directory.appendingPathComponent("data.json"))
        let before = store.data.holdings.count
        try store.applyTrade(.buy, symbol: "0056", date: Date(), shares: 1000, amount: 30000, broker: "測試")
        XCTAssertEqual(store.data.holdings.count, before + 1)
        try store.applyTrade(.buy, symbol: "0056", date: Date(), shares: 1000, amount: 40000, broker: "測試")
        let holding = try XCTUnwrap(store.data.holdings.first { $0.symbol == "0056" && $0.broker == "測試" })
        XCTAssertEqual(holding.shares, 2000); XCTAssertEqual(holding.unitCost, 35, accuracy: 0.0001)
        XCTAssertThrowsError(try store.applyTrade(.sell, symbol: "0056", date: Date(), shares: 5000, amount: 1, broker: "測試"), "Selling more than held is refused")
        try store.applyTrade(.sell, symbol: "0056", date: Date(), shares: 500, amount: 20000, broker: "測試")
        XCTAssertEqual(store.data.trades?.last?.realized, 2500)
        try store.applyTrade(.sell, symbol: "0056", date: Date(), shares: 1500, amount: 60000, broker: "測試")
        XCTAssertNil(store.data.holdings.first { $0.symbol == "0056" && $0.broker == "測試" }, "A holding sold down to zero is removed")
        XCTAssertEqual(store.data.trades?.suffix(4).map(\.action), [.buy, .buy, .sell, .sell])
    }
    func testOfficialDistributionHelpers() {
        XCTAssertEqual(OfficialDividends.rocDay("115年10月22日"), "2026-10-22")
        XCTAssertEqual(OfficialDividends.rocDay("1151016"), "2026-10-16")
        XCTAssertNil(OfficialDividends.rocDay("abc"))
        let days = (1...4).map { DataChecks.day(Calendar.current.date(byAdding: .month, value: -3 * $0 + 1, to: Date())!) }
        XCTAssertEqual(OfficialDividends.frequency(of: days.map { OfficialDistribution(ex: $0, pay: "", amount: 1) }), "季配")
        XCTAssertEqual(OfficialDividends.frequency(of: Array(days.prefix(2)).map { OfficialDistribution(ex: $0, pay: "", amount: 1) }), "半年配")
    }
    @MainActor func testMalformedFileIsNotOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original = Data("invalid data".utf8)
        try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PortfolioStore(url: url)
        XCTAssertThrowsError(try store.save(Portfolio.sample.holdings[0]))
        XCTAssertEqual(try Data(contentsOf: url), original)
        let exported = try store.export()
        defer { try? FileManager.default.removeItem(at: exported) }
        XCTAssertEqual(try Data(contentsOf: exported), original)
    }
    /// Same numbers as the design: 300,000 now (stocks 120,000 / ETFs 180,000), 10,000 a month split 40/60, 5% a year.
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
        XCTAssertEqual(ComboMath.project(stockStart: 120000, etfStart: 180000, settings: cash, stockShare: 0.4, years: 5, scenario: .base).end, 1050621.51, accuracy: 1)
        XCTAssertEqual(ComboScenario.conservative.rate(5), -2); XCTAssertEqual(ComboScenario.optimistic.rate(5), 8)
    }
    func testBundledStocksAndCloses() throws {
        let snapshot = try XCTUnwrap(StockSnapshot.bundled, "stock-data.json is bundled")
        XCTAssertEqual(snapshot.byID["2330"]?.market, "TWSE")
        XCTAssertEqual(snapshot.byID["6488"]?.market, "TPEx")
        XCTAssertGreaterThan(snapshot.stocks.count, 1500)
        let quote = try XCTUnwrap(snapshot.close("2330"))
        XCTAssertGreaterThan(quote.price, 0); XCTAssertEqual(quote.currency, "TWD"); XCTAssertTrue(quote.isValid)
        XCTAssertNotNil(snapshot.indices["taiex"]?.close)
        XCTAssertNotNil(snapshot.indices["tpex"]?.close)
        XCTAssertNotNil(snapshot.exHistorySince, "The bundled ex-date history says where it starts")
        // No trailing cash until the ex-date history covers a year.
        let day = DataChecks.day(Calendar.current.date(byAdding: .month, value: -2, to: Date())!)
        func made(since: String) throws -> StockSnapshot {
            try XCTUnwrap(StockSnapshot(Data(#"{"stocks":[],"industries":[],"exHist":{"2330":[["\#(day)",5.0,"息"],["\#(day)",1.0,"權"]]},"since":{"exHist":"\#(since)"}}"#.utf8)))
        }
        XCTAssertNil(try made(since: DataChecks.day()).trailingCash("2330"))
        XCTAssertEqual(try made(since: "2024-01-01").trailingCash("2330"), 5)
    }
    @MainActor func testStockHoldingIsValuedAndComboPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PortfolioStore(url: url)
        let holding = Holding(symbol: "2330", name: "台積電", shares: 10, unitCost: 100, broker: "", strategy: .unclassified)
        try store.save(holding)
        XCTAssertTrue(store.isStock("2330")); XCTAssertFalse(store.isStock("0050")); XCTAssertFalse(store.isStock("00878"))
        XCTAssertNotNil(store.marketValue(of: holding), "A stock without a Fugle quote is valued at the bundled close")
        XCTAssertNotNil(store.summary.marketValue)
        var combo = store.combo
        combo.source = 1; combo.simulated = [ComboItem(symbol: "2330", amount: 50000), ComboItem(symbol: "0050", amount: 30000)]; combo.years = 10
        store.saveCombo(combo)
        let reopened = PortfolioStore(url: url)
        XCTAssertEqual(reopened.combo, combo)
        XCTAssertEqual(reopened.comboStarts(reopened.combo).stock, 50000, accuracy: 0.001)
        XCTAssertEqual(reopened.comboStarts(reopened.combo).etf, 30000, accuracy: 0.001)
    }
    func testQuoteValidation() throws {
        let bytes = Data(#"{"symbol":"0050","date":"2026-10-15","closePrice":55.0,"changePercent":0.4}"#.utf8)
        XCTAssertEqual(try Fugle.decode(bytes, expectedSymbol: "0050").price, 55)
        XCTAssertThrowsError(try Fugle.decode(bytes, expectedSymbol: "00878"))
        XCTAssertThrowsError(try Fugle.decode(Data(#"{"symbol":"0050","date":"2026-10-15"}"#.utf8), expectedSymbol: "0050"))
    }
    func testOpenDataQuotes() throws {
        // Shapes of the exchanges' open data in October 2026: TWSE 上市個股日成交資訊 (ROC date, volume in shares,
        // with a byte order mark), TPEx 上櫃股票收盤行情 (signed change), the TAIEX row of 每日收盤行情 (sign apart
        // from the size) and the TPEx index history (yyyyMMdd, latest last).
        let twse = Data([0xEF, 0xBB, 0xBF]) + Data(#"""
        [{"Date":"1151015","Code":"2330","Name":"台積電","TradeVolume":"35000123","TradeValue":"50750178350","OpeningPrice":"1460.00","HighestPrice":"1470.00","LowestPrice":"1440.00","ClosingPrice":"1450.00","Change":"-15.0000","Transaction":"80123"},
         {"Date":"1151015","Code":"0050","Name":"元大台灣50","TradeVolume":"85139000","OpeningPrice":"60.10","HighestPrice":"60.50","LowestPrice":"59.80","ClosingPrice":"60.20","Change":"0.3000"},
         {"Date":"1151015","Code":"9999","Name":"沒有成交","TradeVolume":"0","OpeningPrice":"","HighestPrice":"","LowestPrice":"","ClosingPrice":"","Change":""},
         {"Date":"1151015","Code":"00700K","Name":"外幣","TradeVolume":"1000","OpeningPrice":"12.00","HighestPrice":"12.00","LowestPrice":"12.00","ClosingPrice":"12.00","Change":"0.0000"}]
        """#.utf8)
        let listed = try OpenData.decodeTWSE(twse)
        XCTAssertEqual(Set(listed.keys), ["2330", "0050", "00700K"])
        let tsmc = try XCTUnwrap(listed["2330"])
        XCTAssertEqual(tsmc.price, 1450); XCTAssertEqual(tsmc.change, -15); XCTAssertEqual(tsmc.changePercent ?? 0, -1.02, accuracy: 0.001)
        XCTAssertEqual(tsmc.open, 1460); XCTAssertEqual(tsmc.high, 1470); XCTAssertEqual(tsmc.low, 1440); XCTAssertEqual(tsmc.volume, 35000)
        XCTAssertEqual(tsmc.date, "2026-10-15"); XCTAssertEqual(tsmc.fetchedAt, DataChecks.date("2026-10-15")!.addingTimeInterval(13.5 * 3600))
        XCTAssertTrue(tsmc.isTWD); XCTAssertTrue(tsmc.isDailyClose); XCTAssertEqual(tsmc.source, OpenData.source)
        XCTAssertEqual(listed["0050"]?.changePercent ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(listed["00700K"]?.isTWD, false, "K codes trade in a foreign currency")
        let tpex = Data(#"""
        [{"Date":"1151016","SecuritiesCompanyCode":"6488","CompanyName":"環球晶","Close":"430.50","Change":"-21.00","Open":"450.00","High":"452.00","Low":"428.00","TradingShares":"3,210,000"},
         {"Date":"1151016","SecuritiesCompanyCode":"00679B","CompanyName":"元大美債20年","Close":"28.15","Change":"+0.05","Open":"28.10","High":"28.20","Low":"28.05","TradingShares":"12000000"},
         {"Date":"1151016","SecuritiesCompanyCode":"1234","CompanyName":"暫停交易","Close":"----","Change":"0.00"}]
        """#.utf8)
        let otc = try OpenData.decodeTPEx(tpex)
        XCTAssertEqual(Set(otc.keys), ["6488", "00679B"])
        XCTAssertEqual(otc["6488"]?.changePercent ?? 0, -4.65, accuracy: 0.001); XCTAssertEqual(otc["6488"]?.volume, 3210); XCTAssertEqual(otc["6488"]?.date, "2026-10-16")
        XCTAssertEqual(otc["00679B"]?.change ?? 0, 0.05, accuracy: 0.0001)
        let index = Data(#"""
        [{"日期":"1151016","指數":"寶島股價指數","收盤指數":"51000.00","漲跌":"+","漲跌點數":"10.00","漲跌百分比":"0.02","特殊處理註記":""},
         {"日期":"1151016","指數":"發行量加權股價指數","收盤指數":"46,969.87","漲跌":"-","漲跌點數":"1,655.96","漲跌百分比":"-3.41","特殊處理註記":""}]
        """#.utf8)
        let taiex = try XCTUnwrap(OpenData.decodeTAIEX(index))
        XCTAssertEqual(taiex.price, 46969.87); XCTAssertEqual(taiex.change ?? 0, -1655.96, accuracy: 0.001); XCTAssertEqual(taiex.changePercent ?? 0, -3.41, accuracy: 0.001)
        XCTAssertEqual(taiex.date, "2026-10-16")
        let history = Data(#"[{"Date":"20261015","Open":"299.00","High":"301.00","Low":"298.00","Close":"300.10","Change":"3.36"},{"Date":"20261016","Open":"300.00","High":"301.00","Low":"275.00","Close":"276.87","Change":"-23.23"}]"#.utf8)
        let otcIndex = try XCTUnwrap(OpenData.decodeTPExIndex(history))
        XCTAssertEqual(otcIndex.date, "2026-10-16"); XCTAssertEqual(otcIndex.price, 276.87); XCTAssertEqual(otcIndex.changePercent ?? 0, -7.74, accuracy: 0.001)
        XCTAssertThrowsError(try OpenData.decodeTWSE(Data("<html>維護中</html>".utf8)))
        // The close expected by now: the same weekday after 14:30, else the weekday before.
        let friday = DataChecks.date("2026-10-16")!
        XCTAssertEqual(OpenData.expectedDay(friday.addingTimeInterval(15 * 3600)), "2026-10-16")
        XCTAssertEqual(OpenData.expectedDay(friday.addingTimeInterval(10 * 3600)), "2026-10-15")
        XCTAssertEqual(OpenData.expectedDay(friday.addingTimeInterval(27 * 3600)), "2026-10-16", "Saturday")
        XCTAssertEqual(OpenData.expectedDay(friday.addingTimeInterval(3 * 86400 + 9 * 3600)), "2026-10-16", "Monday morning")
        // TWSE's open data can lag TPEx's: the older exchange decides whether to fetch again.
        let day = OpenData.Day(quotes: listed.merging(otc) { a, _ in a }, indices: ["taiex": try XCTUnwrap(OpenData.decodeTAIEX(index)), "tpex": otcIndex], fetchedAt: Date())
        XCTAssertEqual(day.day, "2026-10-16")
        var lagging = day; lagging.indices["taiex"]?.date = "2026-10-15"
        XCTAssertEqual(lagging.settledDay, "2026-10-15"); XCTAssertEqual(day.settledDay, "2026-10-16")
        var oneIndex = day; oneIndex.indices["taiex"] = nil
        XCTAssertEqual(oneIndex.settledDay, "2026-10-16", "An index that did not decode does not make the closes look behind")
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
    func testLiveProtocolMessages() throws {
        XCTAssertEqual(LiveProtocol.parse(#"{"event":"authenticated","data":{"message":"Authenticated successfully"}}"#), .authenticated)
        XCTAssertEqual(LiveProtocol.parse(#"{"event":"subscribed","data":{"id":"abc","channel":"aggregates","symbol":"2330"}}"#), .subscribed(["2330": "abc"]))
        XCTAssertEqual(LiveProtocol.parse(#"{"event":"subscribed","data":[{"id":"a","channel":"aggregates","symbol":"2330"},{"id":"b","channel":"aggregates","symbol":"0050"}]}"#), .subscribed(["2330": "a", "0050": "b"]))
        XCTAssertEqual(LiveProtocol.parse(#"{"event":"error","data":{"code":1001,"message":"Subscription limit exceeded"}}"#), .error(code: 1001, message: "Subscription limit exceeded"))
        XCTAssertEqual(LiveProtocol.parse(#"{"event":"heartbeat","data":{"time":1}}"#), .heartbeat)
        XCTAssertEqual(LiveProtocol.parse("not json"), .other)
        let push = #"{"event":"data","channel":"aggregates","data":{"date":"2026-10-16","symbol":"2330","openPrice":1450,"highPrice":1465,"lowPrice":1445,"closePrice":1460,"lastPrice":1460,"change":15,"changePercent":1.04,"total":{"tradeVolume":21034},"isTrial":false}}"#
        guard case .tick(let tick) = LiveProtocol.parse(push) else { return XCTFail("aggregates push") }
        XCTAssertEqual(tick.price, 1460); XCTAssertEqual(tick.volume, 21034); XCTAssertEqual(tick.date, "2026-10-16"); XCTAssertFalse(tick.trial)
        let trial = #"{"event":"data","channel":"aggregates","data":{"symbol":"2330","lastPrice":1455,"closePrice":1440,"isTrial":true}}"#
        guard case .tick(let early) = LiveProtocol.parse(trial) else { return XCTFail("trial push") }
        XCTAssertEqual(early.price, 1455, "During the trial match the matched price is shown"); XCTAssertTrue(early.trial)
        XCTAssertEqual(LiveProtocol.parse(#"{"event":"data","channel":"aggregates","data":{"symbol":"../x","closePrice":1}}"#), .other)
        // The key only ever travels in the auth message, never in the address.
        let auth = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(LiveProtocol.auth(key: "k-123").utf8)) as? [String: Any])
        XCTAssertEqual((auth["data"] as? [String: String])?["apikey"], "k-123")
        XCTAssertFalse(LiveProtocol.endpoint.absoluteString.contains("k-123"))
        XCTAssertEqual(LiveProtocol.backoff(attempt: 1, random: 0), 0.5)
        XCTAssertEqual(LiveProtocol.backoff(attempt: 20, random: 1), 60)
        // JSONSerialization's 0 and 1 bridge to Bool; they are still numbers.
        let flat = #"{"event":"data","channel":"aggregates","data":{"date":"2026-10-16","symbol":"0050","closePrice":109,"change":0,"changePercent":0,"total":{"tradeVolume":1},"isTrial":false}}"#
        guard case .tick(let even) = LiveProtocol.parse(flat) else { return XCTFail("flat push") }
        XCTAssertEqual(even.change, 0); XCTAssertEqual(even.changePercent, 0); XCTAssertEqual(even.volume, 1)
        guard case .tick(let up) = LiveProtocol.parse(#"{"event":"data","channel":"aggregates","data":{"symbol":"0050","closePrice":110,"change":1}}"#) else { return XCTFail("up push") }
        XCTAssertEqual(up.change, 1)
        let saved = Quote(symbol: "0050", price: 108, changePercent: 1.2, date: "2026-10-16", fetchedAt: .distantPast, currency: "TWD", change: 1.3)
        XCTAssertEqual(LiveProtocol.merge(saved, even).change, 0, "A flat stock shows no change, not the previous one")
        XCTAssertEqual(LiveProtocol.parse(#"{"event":"subscribed","data":{"id":1,"channel":"aggregates","symbol":"0050"}}"#), .subscribed(["0050": "1"]))
    }
    func testFugleTrialMatchQuote() throws {
        let bytes = Data(#"{"date":"2026-10-16","symbol":"2330","lastPrice":1455,"changePercent":0.69,"isTrial":true}"#.utf8)
        let quote = try Fugle.decode(bytes, expectedSymbol: "2330")
        XCTAssertEqual(quote.price, 1455); XCTAssertEqual(quote.trial, true)
        let trade = try Fugle.decode(Data(#"{"date":"2026-10-16","symbol":"2330","closePrice":1460,"lastPrice":1460,"isTrial":false}"#.utf8), expectedSymbol: "2330")
        XCTAssertEqual(trade.price, 1460); XCTAssertNil(trade.trial)
    }
    func testRequestPaceKeepsWithinLimit() async {
        let start = ContinuousClock.now
        func at(_ seconds: Int) -> ContinuousClock.Instant { start + .seconds(seconds) }
        let exchange = RequestPace(limit: 1, window: 5)
        let first = await exchange.take(now: at(0))
        let second = await exchange.take(now: at(0))
        let third = await exchange.take(now: at(1))
        let fourth = await exchange.take(now: at(5))
        XCTAssertEqual(first, 0); XCTAssertEqual(second, 5, accuracy: 0.001)
        XCTAssertEqual(third, 4, accuracy: 0.001, "A caller that waited and gave up took no turn")
        XCTAssertEqual(fourth, 0)
        let fugle = RequestPace(limit: 3, window: 60)
        var waits: [TimeInterval] = []
        for _ in 0..<4 { waits.append(await fugle.take(now: at(0))) }
        XCTAssertEqual(Array(waits.prefix(3)), [0, 0, 0]); XCTAssertEqual(waits[3], 60, accuracy: 0.001)
        let later = await fugle.take(now: at(60))
        XCTAssertEqual(later, 0, "Old requests leave the window")
    }
    func testRealTradeBehindTrialMatch() throws {
        let tick = LiveTick(symbol: "2330", price: 1455, change: 15, changePercent: 1.04, open: nil, high: nil, low: nil, volume: nil, date: "2026-10-16", trial: true, lastTrade: 1460)
        let shown = LiveProtocol.merge(nil, tick)
        XCTAssertEqual(shown.price, 1455); XCTAssertEqual(shown.trial, true)
        let rebuilt = try XCTUnwrap(LiveProtocol.realTrade(shown, tick, known: nil))
        XCTAssertEqual(rebuilt.price, 1460); XCTAssertNil(rebuilt.trial)
        XCTAssertEqual(rebuilt.change ?? 0, 20, accuracy: 0.0001); XCTAssertEqual(rebuilt.changePercent ?? 0, 1.39, accuracy: 0.001)
        let same = Quote(symbol: "2330", price: 1460, changePercent: 1.39, date: "2026-10-16", fetchedAt: Date(), currency: "TWD", change: 20, volume: 5000)
        XCTAssertEqual(LiveProtocol.realTrade(shown, tick, known: same)?.volume, 5000, "The day's real trade is kept while it is still the latest")
        let morning = Quote(symbol: "2330", price: 1450, changePercent: 0.69, date: "2026-10-16", fetchedAt: Date(), currency: "TWD", change: 10)
        XCTAssertEqual(LiveProtocol.realTrade(shown, tick, known: morning)?.price, 1460, "A later trade from the push replaces an earlier one")
        var trade = tick; trade.trial = false; trade.lastTrade = nil
        XCTAssertEqual(LiveProtocol.realTrade(LiveProtocol.merge(nil, trade), trade, known: morning)?.price, 1455)
        guard case .tick(let parsed) = LiveProtocol.parse(#"{"event":"data","channel":"aggregates","data":{"symbol":"2330","lastPrice":1455,"closePrice":1460,"isTrial":true}}"#) else { return XCTFail("trial push") }
        XCTAssertEqual(parsed.lastTrade, 1460)
    }
    func testLiveMergeKeepsMissingFields() {
        let saved = Quote(symbol: "0050", price: 100, changePercent: 1, date: "2026-10-16", fetchedAt: Date(timeIntervalSince1970: 0), currency: "TWD", change: 1, open: 99, high: 101, low: 98, volume: 5000, source: OpenData.source)
        let now = Date()
        let tick = LiveTick(symbol: "0050", price: 102, change: 2, changePercent: 2, open: nil, high: 102, low: nil, volume: nil, date: "2026-10-16", trial: false)
        let merged = LiveProtocol.merge(saved, tick, now: now)
        XCTAssertEqual(merged.price, 102); XCTAssertEqual(merged.open, 99); XCTAssertEqual(merged.high, 102); XCTAssertEqual(merged.volume, 5000)
        XCTAssertEqual(merged.date, "2026-10-16"); XCTAssertEqual(merged.fetchedAt, now); XCTAssertNil(merged.trial); XCTAssertFalse(merged.isDailyClose); XCTAssertEqual(merged.currency, "TWD")
        var yesterday = saved; yesterday.date = "2026-10-15"
        let fresh = LiveProtocol.merge(yesterday, tick, now: now)
        XCTAssertNil(fresh.open, "Yesterday's open, low and volume do not carry into today"); XCTAssertNil(fresh.low); XCTAssertNil(fresh.volume)
        XCTAssertEqual(fresh.high, 102); XCTAssertEqual(fresh.currency, "TWD"); XCTAssertEqual(fresh.date, "2026-10-16")
        let foreign = LiveProtocol.merge(nil, LiveTick(symbol: "00953K", price: 10, change: nil, changePercent: nil, open: nil, high: nil, low: nil, volume: nil, date: nil, trial: true))
        XCTAssertEqual(foreign.currency, "UNKNOWN"); XCTAssertEqual(foreign.trial, true)
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
    @MainActor func testLiveQuotesWinWhenFresherAndAreKept() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PortfolioStore(url: url)
        try store.save(Holding(symbol: "2330", name: "台積電", shares: 10, unitCost: 100, broker: "", strategy: .unclassified))
        let close = try XCTUnwrap(StockSnapshot.bundled?.close("2330"))
        XCTAssertEqual(store.quote("2330")?.price, close.price)
        store.liveQuotes["2330"] = Quote(symbol: "2330", price: close.price + 5, changePercent: 0.3, date: DataChecks.day(), fetchedAt: Date(), currency: "TWD")
        XCTAssertEqual(store.quote("2330")?.price, close.price + 5, "A pushed price newer than the bundled close is shown")
        store.favorite("0050")
        store.liveQuotes["0050"] = Quote(symbol: "0050", price: 99, changePercent: 0.1, date: DataChecks.day(), fetchedAt: Date(), currency: "TWD", trial: true)
        store.liveQuotes["9999"] = Quote(symbol: "9999", price: 1, changePercent: nil, date: "2020-01-02", fetchedAt: .distantPast)
        store.live.stop()
        let reopened = PortfolioStore(url: url)
        let kept = try XCTUnwrap(reopened.data.quotes["2330"], "Holdings keep their last live price")
        XCTAssertEqual(kept.price, close.price + 5); XCTAssertNil(kept.trial)
        XCTAssertNil(reopened.data.quotes["0050"], "A trial-match price is not saved as the day's price")
        XCTAssertNil(store.liveQuotes["0050"], "Nor shown once the feed stops")
        store.liveQuotes["0056"] = Quote(symbol: "0056", price: 40, changePercent: nil, date: DataChecks.day(), fetchedAt: Date().addingTimeInterval(-3600), currency: "TWD", trial: true)
        XCTAssertNotEqual(store.quote("0056")?.price, 40, "An hour-old trial-match price is over")
        XCTAssertNil(reopened.data.quotes["9999"], "Only holdings and the watchlist are saved")
    }
    func testBrokerCSVImportsStocksAlongsideETFs() throws {
        let table = try CSVTable.parse(Data("股票代號,商品名稱,現股庫存,付出成本\n2330,,1000,\"580,000\"\n0050,元大台灣50,2000,\"100,000\"\n".utf8))
        let mapping = BrokerMapping(guessing: table)
        XCTAssertEqual([mapping.symbol, mapping.name, mapping.shares, mapping.cost], [0, 1, 2, 3], "國泰證券's column titles are recognised")
        let stocks = ["2330": StockInfo(id: "2330", name: "台積電", market: "TWSE", industry: "半導體業", fullName: "台灣積體電路製造股份有限公司", listingDate: "1994-09-05")]
        let preview = try BrokerPreview.make(table: table, mapping: mapping, broker: "國泰證券", account: "主要", funds: Fund.starters, stock: { stocks[$0] })
        XCTAssertEqual(preview.holdings.map(\.symbol), ["2330", "0050"])
        XCTAssertEqual(preview.holdings[0].name, "台積電", "A stock is named from the stock list")
        XCTAssertEqual(preview.holdings[0].strategy, .unclassified)
        XCTAssertEqual(preview.holdings[0].unitCost, 580)
        XCTAssertEqual(preview.holdings[1].name, "元大台灣50"); XCTAssertEqual(preview.holdings[1].strategy, .saving)
        XCTAssertEqual(preview.totalCost, 680000)
        let unlisted = try CSVTable.parse(Data("股票代號,現股庫存,付出成本\n2330,1000,580000\n1234,1000,10000".utf8))
        XCTAssertThrowsError(try BrokerPreview.make(table: unlisted, mapping: BrokerMapping(guessing: unlisted), broker: "國泰證券", account: "主要", funds: Fund.starters, stock: { stocks[$0] })) { error in
            XCTAssertTrue(error.localizedDescription.contains("1234"), "A code in neither list is still refused")
        }
        let bundled = try BrokerPreview.make(table: table, mapping: mapping, broker: "國泰證券", account: "主要", funds: Fund.starters)
        XCTAssertEqual(bundled.holdings[0].name, StockSnapshot.bundled?.byID["2330"]?.name, "By default stocks come from the bundled list")
    }
    private let listing = ScreenshotImport.Listing([(code: "2330", name: "台積電"), (code: "2308", name: "台達電"), (code: "0050", name: "元大台灣50"), (code: "0056", name: "元大高股息"),
                                                    (code: "00878", name: "國泰永續高股息"), (code: "2884", name: "玉山金"), (code: "9991", name: "測試股"), (code: "9992", name: "測試股")])
    func testScreenshotLinesGiveCodeSharesAndCost() {
        let cards = ["庫存損益", "付出成本 1,580,000", "台積電 2330 現股", "現股庫存 1,000股 現價 1,050.00", "付出成本：580,365 損益 +469,635",
                     "元大台灣50(0050)", "庫存股數 2張", "成本均價 50.12", "群創 3481", "付出成本 45,000", "玉山金2884", "股數3,000"]
        XCTAssertEqual(ScreenshotImport.parse(cards, in: listing), [
            .init(symbol: "2330", shares: 1000, cost: 580365, basis: .total),
            .init(symbol: "0050", shares: 2000, cost: 50.12, basis: .perShare),
            .init(symbol: "2884", shares: 3000, cost: nil)
        ], "Account totals and an unlisted company's figures are not taken; 成本均價 is a price per share")
        let table = ["商品名稱 庫存股數 成本均價 付出成本 市值", "國泰永續高股息 00878 6,000 20.50 123,000 132,000", "台積電 2330 1,000 580.00 580,000 1,050,000", "合計 703,000 1,182,000"]
        XCTAssertEqual(ScreenshotImport.parse(table, in: listing), [.init(symbol: "00878", shares: 6000, cost: 123000, basis: .total), .init(symbol: "2330", shares: 1000, cost: 580000, basis: .total)],
                       "With both a price per share and a total, the total is taken")
        let titlesAbove = ["台積電 2330", "庫存股數 成本均價 付出成本", "1,000 580.37 580,365", "損益 報酬率", "+469,635 80.92%"]
        XCTAssertEqual(ScreenshotImport.parse(titlesAbove, in: listing), [.init(symbol: "2330", shares: 1000, cost: 580365, basis: .total)])
        XCTAssertEqual(ScreenshotImport.parse(["００８７８　國泰永續高股息", "庫存張數（張）：６", "付出成本(元)123,000"], in: listing), [.init(symbol: "00878", shares: 6000, cost: 123000, basis: .total)])
        XCTAssertEqual(ScreenshotImport.parse(["0050元大台灣50", "股數 1,0O0", "付出成本 一百萬"], in: listing), [.init(symbol: "0050")], "Unreadable figures stay empty for the user")
    }
    func testScreenshotNamesWithoutCodes() {
        let cards = ["國泰證券 庫存", "台積電 現股", "庫存股數 1,000", "付出成本 580,365", "元大高股息", "庫存張數 3", "付出成本 105,000",
                     "台積雷", "股數 2,000", "測試股", "股數 500"]
        XCTAssertEqual(ScreenshotImport.parse(cards, in: listing), [
            .init(symbol: "2330", shares: 1000, cost: 580365, basis: .total),
            .init(symbol: "0056", shares: 3000, cost: 105000, basis: .total),
            .init(symbol: "", shares: 2000, name: "台積雷", choices: ["2330"]),
            .init(symbol: "", shares: 500, name: "測試股", choices: ["9991", "9992"])
        ], "An exact name gives the code; a misread or shared name leaves the code for the user to pick")
        let table = ["名稱 庫存股數 付出成本", "台積電 1,000 580,000", "國泰永續 高股息 6,000 123,000", "某某某 2,000 50,000", "合計 753,000"]
        XCTAssertEqual(ScreenshotImport.parse(table, in: listing), [
            .init(symbol: "2330", shares: 1000, cost: 580000, basis: .total),
            .init(symbol: "00878", shares: 6000, cost: 123000, basis: .total),
            .init(symbol: "", shares: 2000, cost: 50000, name: "某某某", basis: .total)
        ], "A table row whose name fits nothing keeps its figures, with the code left empty")
        XCTAssertEqual(ScreenshotImport.parse(["元大台灣…", "股數 1,000", "臺積電(現股)", "股數 2,000"], in: listing), [
            .init(symbol: "", shares: 1000, name: "元大台灣…", choices: ["0050"]),
            .init(symbol: "2330", shares: 2000)
        ], "A cut-off name offers choices; 臺 and a note in brackets still match")
    }
    func testScreenshotBoxesAndTwoReadings() {
        let boxes: [(text: String, box: CGRect)] = [
            ("1,000", CGRect(x: 0.55, y: 0.795, width: 0.15, height: 0.03)),
            ("台積電 2330", CGRect(x: 0.05, y: 0.8, width: 0.3, height: 0.03)),
            ("580,000", CGRect(x: 0.55, y: 0.7, width: 0.2, height: 0.03)),
            ("付出成本", CGRect(x: 0.05, y: 0.7, width: 0.2, height: 0.03))
        ]
        XCTAssertEqual(ScreenshotImport.lines(from: boxes), ["台積電 2330 1,000", "付出成本 580,000"])
        let place = CGRect(x: 0.05, y: 0.5, width: 0.4, height: 0.03), other = CGRect(x: 0.6, y: 0.5, width: 0.2, height: 0.03)
        let combined = ScreenshotImport.combine(corrected: [("台積電 233O", place), ("付出成本", other)], raw: [("台積霓 2330", place), ("付出成木", other)])
        XCTAssertEqual(combined.map { $0.text }, ["台積電 2330", "付出成本"], "Words with digits come from the uncorrected reading, the rest from the corrected one")
    }
    func testScreenshotLotsKeptAndOverlapsOnce() {
        let lots = ScreenshotImport.Listing([(code: "00991A", name: "主動測試"), (code: "2330", name: "台積電")])
        let table = ["名稱 類別 庫存股數 付出成本", "主動測試 00991A 現股 1,000 10,000", "主動測試 00991A 現股 1,000 10,000",
                     "主動測試 00991A 融資 3,000 33,000", "台積電 2330 融券 1,000 580,000"]
        XCTAssertEqual(ScreenshotImport.parse(table, in: lots), [
            .init(symbol: "00991A", shares: 1000, cost: 10000, basis: .total),
            .init(symbol: "00991A", shares: 1000, cost: 10000, basis: .total),
            .init(symbol: "00991A", shares: 3000, cost: 33000, kind: .margin, basis: .total),
            .init(symbol: "2330", shares: 1000, cost: 580000, kind: .short, basis: .total)
        ], "Every lot in one screenshot is kept, even two with the same figures")
        XCTAssertEqual(ScreenshotImport.parse(["主動測試 00991A 資", "股數 2,000", "付出成本 22,000", "主動測試 00991A", "股數 1,000", "付出成本 10,500"], in: lots), [
            .init(symbol: "00991A", shares: 2000, cost: 22000, kind: .margin, basis: .total),
            .init(symbol: "00991A", shares: 1000, cost: 10500, basis: .total)
        ], "A card's code seen again after its figures starts the next lot; a lone 資 means 融資")
        let a = ScreenshotImport.Row(symbol: "00991A", shares: 1000, cost: 10000)
        let b = ScreenshotImport.Row(symbol: "00991A", shares: 2000, cost: 21000)
        let m = ScreenshotImport.Row(symbol: "00991A", shares: 3000, cost: 33000, kind: .margin)
        let s = ScreenshotImport.Row(symbol: "2330", shares: 1000, cost: 580000, kind: .short)
        let cut = ScreenshotImport.Row(symbol: "2330", shares: 500)
        let review = ScreenshotImport.review([[a, a, b, cut], [b, m, s, .init(symbol: "2330", shares: 500, cost: 290000)]])
        XCTAssertEqual(review.rows, [a, a, b, .init(symbol: "2330", shares: 500, note: "這一列可能是截圖邊緣只拍到一部分的重複列；若與其他列是同一批，請刪除。"), m, .init(symbol: "2330", shares: 500, cost: 290000)],
                       "Rows repeated exactly in a later screenshot appear once; lots within one screenshot all stay")
        XCTAssertEqual(review.short, [s], "融券 is not a holding and is set apart")
    }
    @MainActor func testScreenshotLotsMergeByCodeAndKind() throws {
        let funds = Fund.starters + [Fund(id: "00991A", name: "主動測試", strategy: .unclassified)]
        var drafts = [ScreenshotImport.Draft(.init(symbol: "00991A", shares: 1000, cost: 10000, basis: .total)), ScreenshotImport.Draft(.init(symbol: "00991A", shares: 2000, cost: 21000, basis: .total)),
                      ScreenshotImport.Draft(.init(symbol: "00991A", shares: 3000, cost: 33000, kind: .margin, basis: .total)), ScreenshotImport.Draft(.init(symbol: "0050", cost: 100000, basis: .total))]
        XCTAssertEqual(drafts[2].kind, .margin); XCTAssertEqual(drafts[3].shares, "")
        XCTAssertThrowsError(try BrokerPreview.make(drafts: drafts, broker: "國泰證券", account: "主要", funds: funds)) { XCTAssertTrue($0.localizedDescription.contains("股數")) }
        drafts[3].shares = "2張"
        let preview = try BrokerPreview.make(drafts: drafts, broker: "國泰證券", account: "主要", funds: funds)
        XCTAssertEqual(preview.holdings.map(\.symbol), ["00991A", "00991A", "0050"])
        let cash = preview.holdings[0], margin = preview.holdings[1]
        XCTAssertEqual(cash.shares, 3000); XCTAssertEqual(cash.cost, 31000, accuracy: 0.001); XCTAssertEqual(cash.unitCost, 31000.0 / 3000, accuracy: 1e-9)
        XCTAssertEqual(cash.broker, "國泰證券")
        XCTAssertEqual(margin.shares, 3000); XCTAssertEqual(margin.unitCost, 11); XCTAssertEqual(margin.broker, "國泰證券（融資）")
        XCTAssertNotEqual(cash.id, margin.id, "融資 and 現股 never replace each other")
        XCTAssertEqual(preview.holdings[2].shares, 2000, "2張 is 2,000 shares")
        let csv = try BrokerPreview.make(table: CSVTable.parse(Data("code,shares,cost\n00991A,3000,31000".utf8)), mapping: BrokerMapping(symbol: 0, name: -1, shares: 1, cost: 2), broker: "國泰證券", account: "主要", funds: funds)
        XCTAssertEqual(csv.holdings[0].id, cash.id, "The 現股 holding is the same one a CSV import of the account updates")
        let named = ScreenshotImport.Draft(.init(symbol: "", shares: 1000, cost: 1, name: "測試股", choices: ["9991", "9992"]))
        XCTAssertEqual(named.seen, "測試股"); XCTAssertEqual(named.choices, ["9991", "9992"])
        XCTAssertThrowsError(try BrokerPreview.make(drafts: [named], broker: "國泰證券", account: "主要", funds: funds)) { XCTAssertTrue($0.localizedDescription.contains("代號")) }
        let short = ScreenshotImport.Draft(.init(symbol: "2330", shares: 1000, cost: 1, kind: .short))
        XCTAssertThrowsError(try BrokerPreview.make(drafts: [short], broker: "國泰證券", account: "主要", funds: funds)) { XCTAssertTrue($0.localizedDescription.contains("融券")) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PortfolioStore(url: dir.appendingPathComponent("p.json"))
        try store.importBroker(preview, replaceAccount: false); try store.importBroker(preview, replaceAccount: false)
        XCTAssertEqual(store.data.holdings.count, 3, "Importing the same account again updates the same holdings")
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
    func testFeeRatesPerBroker() throws {
        let suite = "SellCostsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(SellCosts.rate(for: "測試證券", in: defaults), SellCosts.standard, "A broker without a common rate: the list price")
        XCTAssertFalse(SellCosts.isSet(for: "測試證券", in: defaults))
        XCTAssertEqual(SellCosts.rate(for: "國泰證券", in: defaults), FeeRate(discount: 2.8, minimum: 1), "Picking 國泰 brings in its common rate")
        XCTAssertEqual(SellCosts.rate(for: "國泰綜合證券（融資）", in: defaults).discount, 2.8, "Any spelling, and 融資 sells through the same broker")
        XCTAssertEqual(SellCosts.rate(for: "元大", in: defaults), FeeRate(discount: 6, minimum: 20))
        XCTAssertTrue(SellCosts.isSet(for: "富邦證券", in: defaults))
        SellCosts.remember(FeeRate(discount: 2.8, minimum: 1), for: "國泰證券", in: defaults)
        XCTAssertTrue(SellCosts.rates(in: defaults).isEmpty, "Confirming the common rate stores nothing")
        SellCosts.remember(FeeRate(discount: 1.8, minimum: 1), for: "富邦證券（融資）", in: defaults)
        XCTAssertEqual(SellCosts.rate(for: "富邦證券", in: defaults).discount, 1.8, "The viewer's own rate wins over the common one")
        SellCosts.remember(FeeRate(discount: 3, minimum: 1), for: "測試證券", in: defaults)
        XCTAssertEqual(SellCosts.rate(for: "測試證券", in: defaults).discount, 3)
        SellCosts.save(["": FeeRate(discount: 25, minimum: -3)], in: defaults)
        XCTAssertEqual(SellCosts.rate(for: "", in: defaults), FeeRate(discount: 10, minimum: 0), "Out-of-range entries are clamped")
        XCTAssertEqual(SellCosts.rate(for: "另一家證券", in: defaults), FeeRate(discount: 10, minimum: 0), "The viewer's default for brokers without a common rate")
    }
    @MainActor func testDividendSharesFollowTheHolding() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PortfolioStore(url: dir.appendingPathComponent("p.json"))
        let cash = Holding(symbol: "0050", name: "元大台灣50", shares: 2000, unitCost: 50, broker: "國泰證券", strategy: .saving)
        let margin = Holding(symbol: "0050", name: "元大台灣50", shares: 3000, unitCost: 52, broker: "國泰證券（融資）", strategy: .saving)
        try store.save(cash); try store.save(margin)
        XCTAssertEqual(store.dividendShares("0050", holding: cash.id), 2000, "Recorded from the 現股 holding: only its 2,000 shares")
        XCTAssertEqual(store.dividendShares("0050", holding: margin.id), 3000)
        XCTAssertEqual(store.dividendShares("0050", holding: nil), 5000, "Recorded for the whole code: every holding")
        var record = Dividend(symbol: "0050", date: Date(), amount: 2000, status: .paid)
        record.holdingID = cash.id
        try store.saveDividend(record)
        let saved = try XCTUnwrap(PortfolioStore(url: dir.appendingPathComponent("p.json")).data.dividends.first)
        XCTAssertEqual(saved.holdingID, cash.id, "The holding a record belongs to is saved")
        let old = try JSONDecoder().decode(Dividend.self, from: Data(#"{"id":"6F1A3D9E-0000-4000-8000-000000000001","symbol":"0050","date":0,"amount":10,"status":"已入帳"}"#.utf8))
        XCTAssertNil(old.holdingID, "Older records have no holding")
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
    @MainActor func testScreenshotReimportFixesEarlierCosts() throws {
        let funds = Fund.starters + [Fund(id: "00991A", name: "主動測試", strategy: .unclassified)]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PortfolioStore(url: dir.appendingPathComponent("p.json"))
        try store.save(Holding(symbol: "2330", name: "台積電", shares: 10, unitCost: 100, broker: "", strategy: .unclassified))
        let wrong = try BrokerPreview.make(drafts: [ScreenshotImport.Draft(.init(symbol: "00991A", shares: 1000, cost: 17.35, basis: .total)),
                                                    ScreenshotImport.Draft(.init(symbol: "00991A", shares: 1000, cost: 18, kind: .margin, basis: .total)),
                                                    ScreenshotImport.Draft(.init(symbol: "0050", shares: 100, cost: 15000, basis: .total))], broker: "國泰證券", account: "主要", funds: funds)
        try store.importBroker(wrong, replaceAccount: true)
        XCTAssertEqual(try XCTUnwrap(store.data.holdings.first { $0.symbol == "00991A" && $0.broker == "國泰證券" }).unitCost, 0.01735, accuracy: 1e-9)
        let fixed = try BrokerPreview.make(drafts: [ScreenshotImport.Draft(.init(symbol: "00991A", shares: 1000, cost: 17.35, basis: .perShare)),
                                                    ScreenshotImport.Draft(.init(symbol: "00991A", shares: 1000, cost: 18, kind: .margin, basis: .perShare))], broker: "國泰證券", account: "主要", funds: funds)
        XCTAssertEqual(fixed.holdings.map(\.id), Array(wrong.holdings.prefix(2)).map(\.id), "The same lots of the same account keep their stable IDs")
        try store.importBroker(fixed, replaceAccount: true)
        let lots = store.data.holdings.filter { $0.symbol == "00991A" }
        XCTAssertEqual(lots.count, 2, "Re-importing overwrites the earlier 現股 and 融資 holdings instead of adding new ones")
        XCTAssertEqual(try XCTUnwrap(lots.first { $0.broker == "國泰證券" }).unitCost, 17.35, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(lots.first { $0.broker == "國泰證券（融資）" }).unitCost, 18, accuracy: 1e-9)
        XCTAssertFalse(store.data.holdings.contains { $0.symbol == "0050" }, "Replacing the account drops what the new screenshots no longer show")
        XCTAssertTrue(store.data.holdings.contains { $0.symbol == "2330" }, "Holdings entered by hand stay")
    }
}
