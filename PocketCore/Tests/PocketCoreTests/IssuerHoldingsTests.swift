import XCTest
@testable import PocketCore

final class IssuerHoldingsTests: XCTestCase {
    private func fx(_ n: String) throws -> Data { try Fixtures.data("member/issuers/\(n)") }
    private func json(_ s: String) -> Data { Data(s.utf8) }

    private func assertSnapshot(_ s: ComponentSnapshot, _ issuer: Issuer, symbol: String, date: String, count: Int,
                                first: (String, String, Double), file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(s.symbol, symbol, file: file, line: line)
        XCTAssertEqual(s.date, date, file: file, line: line)
        XCTAssertEqual(s.source, issuer.displayName, file: file, line: line)
        XCTAssertEqual(s.components.count, count, file: file, line: line)
        XCTAssertEqual(s.components.first?.symbol, first.0, file: file, line: line)
        XCTAssertEqual(s.components.first?.name, first.1, file: file, line: line)
        XCTAssertEqual(s.components.first?.weight ?? -1, first.2, accuracy: 1e-9, file: file, line: line)
        XCTAssertNoThrow(try s.validate(), file: file, line: line)
    }

    // MARK: Issuers

    func testIssuerNames() {
        XCTAssertEqual(Issuer.allCases.map(\.displayName), ["元大投信", "國泰投信", "富邦投信", "群益投信", "復華投信", "中國信託投信"])
        XCTAssertEqual(Issuer(rawValue: "fhtrust"), .fhtrust)
    }

    func testIssuerByName() {
        XCTAssertEqual(IssuerDirectory.issuer(forFundName: "元大台灣50"), .yuanta)
        XCTAssertEqual(IssuerDirectory.issuer(forFundName: "國泰永續高股息"), .cathay)
        XCTAssertEqual(IssuerDirectory.issuer(forFundName: "富邦台50"), .fubon)
        XCTAssertEqual(IssuerDirectory.issuer(forFundName: "群益台灣精選高息"), .capital)
        XCTAssertEqual(IssuerDirectory.issuer(forFundName: "復華台灣科技優息"), .fhtrust)
        XCTAssertEqual(IssuerDirectory.issuer(forFundName: "中信關鍵半導體"), .ctbc)
        XCTAssertEqual(IssuerDirectory.issuer(forFundName: " 中國信託臺灣優選成長高股息"), .ctbc)
        XCTAssertNil(IssuerDirectory.issuer(forFundName: "統一台灣高息動能"))
        XCTAssertNil(IssuerDirectory.issuer(forFundName: ""))
    }

    /// Active ETFs carry 「主動」 in front of the company's name.
    func testIssuerOfActiveFunds() {
        XCTAssertEqual(IssuerDirectory.issuer(forFundName: "主動群益台灣強棒"), .capital)
        XCTAssertEqual(IssuerDirectory.issuer(forFundName: "主動元大台灣優息"), .yuanta)
        XCTAssertEqual(IssuerDirectory.issuer(forFundName: "主動國泰動能高息"), .cathay)
        XCTAssertEqual(IssuerDirectory.issuer(forFundName: "主動富邦動態入息"), .fubon)
        XCTAssertEqual(IssuerDirectory.issuer(forFundName: "主動復華未來50"), .fhtrust)
        XCTAssertEqual(IssuerDirectory.issuer(forFundName: "主動中信台灣收益"), .ctbc)
        XCTAssertEqual(IssuerDirectory.issuer(forFundName: " 主動 群益科技創新 "), .capital)
        XCTAssertNil(IssuerDirectory.issuer(forFundName: "主動統一升級50"))
        XCTAssertNil(IssuerDirectory.issuer(forFundName: "主動"))
        // 主動 only counts in front: a company is not read out of the middle of a name.
        XCTAssertNil(IssuerDirectory.issuer(forFundName: "統一主動元大"))
    }

    func testDay() {
        XCTAssertEqual(IssuerHoldings.day("20261111"), "2026-11-11")
        XCTAssertEqual(IssuerHoldings.day("2026/11/11"), "2026-11-11")
        XCTAssertEqual(IssuerHoldings.day("2026/1/5"), "2026-01-05")
        XCTAssertEqual(IssuerHoldings.day(" 2026-11-11 "), "2026-11-11")
        XCTAssertNil(IssuerHoldings.day("115/11/11"))
        XCTAssertNil(IssuerHoldings.day("2026/13/01"))
        XCTAssertNil(IssuerHoldings.day("abc"))
        XCTAssertNil(IssuerHoldings.day(nil))
    }

    // MARK: Holdings from the captured responses

    func testYuanta() throws {
        let s = try IssuerHoldings.yuanta(fx("E_yuanta_PCF_Daily_0050.json"), symbol: "0050")
        // Three stock rows; the two FutureWeights rows are not holdings.
        assertSnapshot(s, .yuanta, symbol: "0050", date: "2026-11-11", count: 3, first: ("2330", "台積電", 58.7))
        XCTAssertFalse(s.components.contains { $0.symbol == "TX" })
    }

    func testCathay() throws {
        let s = try IssuerHoldings.cathay(fx("E_cathay_GetETFDetailStockList_00878.json"), symbol: "00878", date: "2026-11-13")
        assertSnapshot(s, .cathay, symbol: "00878", date: "2026-11-13", count: 3, first: ("2891", "中信金", 11.26))
        let slashed = try IssuerHoldings.cathay(fx("E_cathay_GetETFDetailStockList_00878.json"), symbol: "00878", date: "2026/11/13")
        XCTAssertEqual(slashed.date, "2026-11-13")
    }

    func testCapital() throws {
        let s = try IssuerHoldings.capital(fx("E_capital_buyback_00919.json"), symbol: "00919")
        assertSnapshot(s, .capital, symbol: "00919", date: "2026-11-13", count: 3, first: ("2881", "富邦金", 16.1341))
    }

    func testFhtrust() throws {
        let s = try IssuerHoldings.fhtrust(fx("E_fhtrust_assets_00929.json"), symbol: "00929")
        // The 期貨 row (WTX202611) is dropped.
        assertSnapshot(s, .fhtrust, symbol: "00929", date: "2026-11-11", count: 3, first: ("2357", "華碩電腦", 4.123))
        XCTAssertFalse(s.components.contains { $0.symbol.hasPrefix("WTX") })
    }

    func testCtbc() throws {
        let s = try IssuerHoldings.ctbc(fx("E_ctbc_ETFHoldingWeight_00934.json"), symbol: "00934")
        // Only the STOCK group; the 保證金 and 現金 groups are dropped.
        assertSnapshot(s, .ctbc, symbol: "00934", date: "2026-11-13", count: 3, first: ("3293", "鈊象電子", 8.10))
    }

    func testFubon() throws {
        let html = try String(decoding: fx("E_fubon_Assets_006208_excerpt.html"), as: UTF8.self)
        let s = try IssuerHoldings.fubon(html, symbol: "006208")
        assertSnapshot(s, .fubon, symbol: "006208", date: "2026-11-13", count: 2, first: ("2330", "台積電", 58.4473))
        XCTAssertTrue(s.components.allSatisfy { $0.weight > 0 && $0.weight <= 100 })
        // A later table (futures) is not read as stock rows, and a 合計 line is not a holding.
        let more = html.replacingOccurrences(of: "</tbody></table>", with: "<tr><td colspan=\"4\">合計</td><td>64.6076</td></tr></tbody></table>")
            + "<table><tr><td>期貨代碼</td><td>期貨名稱</td><td>口數</td><td>金額</td><td>權重(%)</td></tr>"
            + "<tr><td>TX</td><td>臺股期貨</td><td>10</td><td>1,000</td><td>0.5</td></tr></table>"
        XCTAssertEqual(try IssuerHoldings.fubon(more, symbol: "006208").components.map(\.symbol), ["2330", "2454"])
    }

    /// A footer row with as many cells as the header (合計 where the code belongs) is not a holding either.
    func testFubonSkipsRowsWithoutACode() throws {
        let head = "資料日期：2026/11/13<table><tr><td>股票代碼</td><td>股票名稱</td><td>股數</td><td>金額</td><td>權重(%)</td></tr>"
        let rows = "<tr><td>2330</td><td>台積電</td><td>1</td><td>2</td><td>58.4473</td></tr>"
            + "<tr><td>00679B</td><td>元大美債20年</td><td>1</td><td>2</td><td>1.5</td></tr>"
            + "<tr><td>AAPL US</td><td>Apple</td><td>1</td><td>2</td><td>3.25</td></tr>"
            + "<tr><td>BRK.B</td><td>Berkshire</td><td>1</td><td>2</td><td>1.25</td></tr>"
        let footer = "<tr><td>合計</td><td></td><td>4</td><td>8</td><td>64.4473</td></tr>"
            + "<tr><td>－</td><td>現金</td><td></td><td>9</td><td>0.5</td></tr></table>"
        let s = try IssuerHoldings.fubon(head + rows + footer, symbol: "006208")
        XCTAssertEqual(s.components.map(\.symbol), ["2330", "00679B", "AAPL US", "BRK.B"])
        XCTAssertEqual(s.totalWeight, 64.4473, accuracy: 1e-9)
        // Nothing but a footer: no holdings, so it throws rather than returning the total as a stock.
        XCTAssertThrowsError(try IssuerHoldings.fubon(head + footer, symbol: "006208"))
    }

    // MARK: Hardening

    func testEmptyHoldingsThrow() throws {
        let empty = json(#"{"PCF":{"markcd":"0050","trandate":"20261111"},"FundWeights":{"StockWeights":[]}}"#)
        XCTAssertThrowsError(try IssuerHoldings.yuanta(empty, symbol: "0050"))
        for body in ["{}", "[]", "<html>維護中</html>", ""] {
            let data = json(body)
            XCTAssertThrowsError(try IssuerHoldings.yuanta(data, symbol: "0050"), body)
            XCTAssertThrowsError(try IssuerHoldings.cathay(data, symbol: "00878", date: "2026-11-13"), body)
            XCTAssertThrowsError(try IssuerHoldings.fubon(body, symbol: "006208"), body)
            XCTAssertThrowsError(try IssuerHoldings.capital(data, symbol: "00919"), body)
            XCTAssertThrowsError(try IssuerHoldings.fhtrust(data, symbol: "00929"), body)
            XCTAssertThrowsError(try IssuerHoldings.ctbc(data, symbol: "00934"), body)
        }
    }

    func testErrorBodiesThrow() {
        let cathay = json(#"{"result":null,"returnCode":"9999","success":false,"returnMessage":"查無資料"}"#)
        XCTAssertThrowsError(try IssuerHoldings.cathay(cathay, symbol: "00878", date: "2026-11-13"))
        let capital = json(#"{"code":500,"data":null,"message":"系統忙碌"}"#)
        XCTAssertThrowsError(try IssuerHoldings.capital(capital, symbol: "00919"))
        let ctbc = json(#"{"ResultCode":1,"ResultMsg":"查無資料","Data":null}"#)
        XCTAssertThrowsError(try IssuerHoldings.ctbc(ctbc, symbol: "00934"))
        let fhtrust = json(#"{"result":[],"status":0}"#)
        XCTAssertThrowsError(try IssuerHoldings.fhtrust(fhtrust, symbol: "00929"))
    }

    func testReshapedRowsThrow() {
        // Rows are there but the keys changed: nothing parses, so nothing is returned.
        let renamed = json(#"{"result":[{"code":"2891","title":"中信金","ratio":"11.26"}],"success":true}"#)
        XCTAssertThrowsError(try IssuerHoldings.cathay(renamed, symbol: "00878", date: "2026-11-13"))
        // A stock row whose weight cannot be read fails the whole snapshot instead of dropping the row.
        let badWeight = json(#"{"result":[{"stockCode":"2891","stockName":"中信金","weights":"11.26"},{"stockCode":"2382","stockName":"廣達","weights":"--"}],"success":true}"#)
        XCTAssertThrowsError(try IssuerHoldings.cathay(badWeight, symbol: "00878", date: "2026-11-13"))
        // No date, or a date that is not a date.
        let ok = #"{"result":[{"stockCode":"2891","stockName":"中信金","weights":"11.26"}],"success":true}"#
        XCTAssertThrowsError(try IssuerHoldings.cathay(json(ok), symbol: "00878", date: ""))
        XCTAssertThrowsError(try IssuerHoldings.cathay(json(ok), symbol: "00878", date: "2999-01-01"))
        let noDate = json(#"{"PCF":{"markcd":"0050"},"FundWeights":{"StockWeights":[{"code":"2330","name":"台積電","weights":58.7}]}}"#)
        XCTAssertThrowsError(try IssuerHoldings.yuanta(noDate, symbol: "0050"))
        // Weights that cannot be a fund (over 100 % in total).
        let tooMuch = json(#"{"result":[{"stockCode":"2891","stockName":"中信金","weights":"80"},{"stockCode":"2382","stockName":"廣達","weights":"80"}],"success":true}"#)
        XCTAssertThrowsError(try IssuerHoldings.cathay(tooMuch, symbol: "00878", date: "2026-11-13"))
        // 富邦: a date but no stock table, and a stock table but no date.
        XCTAssertThrowsError(try IssuerHoldings.fubon("<p>資料日期：2026/11/13</p><table><tr><td>項目</td><td>金額</td></tr></table>", symbol: "006208"))
        let table = "<table><tr><td>股票代碼</td><td>股票名稱</td><td>股數</td><td>金額</td><td>權重(%)</td></tr>"
            + "<tr><td>2330</td><td>台積電</td><td>1</td><td>2</td><td>58.4473</td></tr></table>"
        XCTAssertThrowsError(try IssuerHoldings.fubon(table, symbol: "006208"))
        XCTAssertEqual(try IssuerHoldings.fubon("資料日期：2026/11/13" + table, symbol: "006208").components.count, 1)
    }

    func testWrongFundThrows() throws {
        XCTAssertThrowsError(try IssuerHoldings.yuanta(fx("E_yuanta_PCF_Daily_0050.json"), symbol: "0056"))
        XCTAssertThrowsError(try IssuerHoldings.fhtrust(fx("E_fhtrust_assets_00929.json"), symbol: "00927"))
        XCTAssertThrowsError(try IssuerHoldings.ctbc(fx("E_ctbc_ETFHoldingWeight_00934.json"), symbol: "00882"))
    }

    func testRowsAreCleaned() throws {
        // Names are trimmed, a repeated code is summed, a line without a code (cash) is skipped,
        // and numbers may carry commas or a percent sign.
        let body = json(#"""
        {"result":[
          {"stockCode":" 2891 ","stockName":" 中信金 ","weights":"1.5"},
          {"stockCode":"2382","stockName":"廣達","weights":"8.01%"},
          {"stockCode":"2891","stockName":"中信金","weights":"2.25"},
          {"stockCode":"","stockName":"現金","weights":"3.34"},
          {"stockCode":"2882","stockName":"","weights":7}
        ],"success":true}
        """#)
        let s = try IssuerHoldings.cathay(body, symbol: "00878", date: "2026-11-13")
        XCTAssertEqual(s.components.map(\.symbol), ["2891", "2382", "2882"])
        XCTAssertEqual(s.components[0].name, "中信金")
        XCTAssertEqual(s.components[0].weight, 3.75, accuracy: 1e-9)
        XCTAssertEqual(s.components[1].weight, 8.01, accuracy: 1e-9)
        XCTAssertNil(s.components[2].name)
        XCTAssertEqual(s.components[2].weight, 7, accuracy: 1e-9)
    }

    // MARK: Fund-code lookups

    func testCapitalFundNo() throws {
        let data = try fx("E_capital_items_sample.json")
        XCTAssertEqual(IssuerHoldings.capitalFundNo(data, symbol: "00919"), "195")
        XCTAssertEqual(IssuerHoldings.capitalFundNo(data, symbol: "00982A"), "399")
        XCTAssertNil(IssuerHoldings.capitalFundNo(data, symbol: "0050"))
        XCTAssertNil(IssuerHoldings.capitalFundNo(json("{}"), symbol: "00919"))
        XCTAssertNil(IssuerHoldings.capitalFundNo(json("oops"), symbol: "00919"))
    }

    func testCtbcFID() throws {
        let data = try fx("E_ctbc_ETFList_sample.json")
        XCTAssertEqual(IssuerHoldings.ctbcFID(data, symbol: "00934"), "E0024")
        XCTAssertEqual(IssuerHoldings.ctbcFID(data, symbol: "00882"), "E0014")
        XCTAssertNil(IssuerHoldings.ctbcFID(data, symbol: "0050"))
        XCTAssertNil(IssuerHoldings.ctbcFID(json("{}"), symbol: "00934"))
    }

    /// The real GetETFList?Keyword=00878 answer (captured 2026-11-14): `result[] {stockCode, fundCode}`.
    func testCathayFundCode() throws {
        let data = try fx("E_cathay_GetETFList_00878.json")
        XCTAssertEqual(IssuerHoldings.cathayFundCode(data, symbol: "00878"), "CN")
        XCTAssertNil(IssuerHoldings.cathayFundCode(data, symbol: "0050"))
        // A keyword can match several funds; only the one with that exact code counts, and a blank code is none.
        let many = json(#"{"totalCount":3,"result":[{"fundCode":"EA","stockCode":"00400A"},{"fundCode":"CN","stockCode":"00878"},{"fundCode":" ","stockCode":"00881"}],"returnCode":"2000","success":true}"#)
        XCTAssertEqual(IssuerHoldings.cathayFundCode(many, symbol: "00878"), "CN")
        XCTAssertEqual(IssuerHoldings.cathayFundCode(many, symbol: "00400a"), "EA")
        XCTAssertNil(IssuerHoldings.cathayFundCode(many, symbol: "00881"))
        XCTAssertNil(IssuerHoldings.cathayFundCode(many, symbol: "0087"))
        let none = json(#"{"totalCount":0,"totalPage":0,"result":[],"returnCode":"2000","success":true}"#)
        XCTAssertNil(IssuerHoldings.cathayFundCode(none, symbol: "00878"))
        XCTAssertNil(IssuerHoldings.cathayFundCode(json("{}"), symbol: "00878"))
        XCTAssertNil(IssuerHoldings.cathayFundCode(json("oops"), symbol: "00878"))
    }

    /// GetETFAssets as it answered on 2026-11-14 (FundCode=CN): the day comes with slashes.
    func testCathayAssetsDate() {
        let real = json(#"{"result":{"preDate":"2026/11/13","fundNav":"664,848,873,726","fundOutstandingShares":"19,840,290,000","fundPerNav":"33.51"},"returnCode":"2000","success":true,"returnMessage":"成功"}"#)
        XCTAssertEqual(IssuerHoldings.cathayAssetsDate(real), "2026-11-13")
        XCTAssertEqual(IssuerHoldings.cathayAssetsDate(json(#"{"result":{"preDate":"2026-11-13T00:00:00"}}"#)), "2026-11-13")
        XCTAssertNil(IssuerHoldings.cathayAssetsDate(json(#"{"result":{"preDate":""}}"#)))
        XCTAssertNil(IssuerHoldings.cathayAssetsDate(json(#"{"result":null,"returnCode":"9999","success":false}"#)))
        XCTAssertNil(IssuerHoldings.cathayAssetsDate(json("oops")))
    }

    /// Three rows of the real etf_list page (captured 2026-11-13): the code has a cell of its own, the id is in the
    /// row's link.
    func testFhtrustFundID() throws {
        let html = try String(decoding: fx("E_fhtrust_etf_list_excerpt.html"), as: UTF8.self)
        XCTAssertEqual(IssuerHoldings.fhtrustFundID(html, symbol: "00929"), "ETF21")
        // The rows before and after it keep their own ids.
        XCTAssertEqual(IssuerHoldings.fhtrustFundID(html, symbol: "00991A"), "ETF23")
        XCTAssertEqual(IssuerHoldings.fhtrustFundID(html, symbol: "00731"), "ETF08")
        XCTAssertNil(IssuerHoldings.fhtrustFundID(html, symbol: "0092"))
        XCTAssertNil(IssuerHoldings.fhtrustFundID(html, symbol: "0050"))
        // A date or a price in another cell is not a code.
        XCTAssertNil(IssuerHoldings.fhtrustFundID(html, symbol: "2026"))
        let row = "<tr><td>00929</td><td><a href=\"/ETF/etf_detail/ETF21\">復華台灣科技優息</a></td></tr>"
        XCTAssertEqual(IssuerHoldings.fhtrustFundID(row, symbol: "00929"), "ETF21")
        // A row with the code but no link gives nothing, and the next row's id is not borrowed.
        let bare = "<table><tr><td>00929</td><td>復華台灣科技優息</td></tr>"
            + "<tr><td>00731</td><td><a href=\"/ETF/etf_detail/ETF08\">復華富時高息低波</a></td></tr></table>"
        XCTAssertNil(IssuerHoldings.fhtrustFundID(bare, symbol: "00929"))
        XCTAssertEqual(IssuerHoldings.fhtrustFundID(bare, symbol: "00731"), "ETF08")
        XCTAssertNil(IssuerHoldings.fhtrustFundID("", symbol: "00929"))
    }

    func testCtbcToken() {
        XCTAssertEqual(IssuerHoldings.ctbcToken(json(#"{"ResultCode":0,"ResultMsg":"","Data":{"token":" aB+/c9== "}}"#)), "aB+/c9==")
        XCTAssertNil(IssuerHoldings.ctbcToken(json(#"{"ResultCode":0,"Data":{"token":""}}"#)))
        XCTAssertNil(IssuerHoldings.ctbcToken(json(#"{"ResultCode":1,"Data":null}"#)))
        XCTAssertNil(IssuerHoldings.ctbcToken(json("<html>")))
    }
}
