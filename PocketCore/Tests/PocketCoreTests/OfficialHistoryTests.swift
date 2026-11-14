import XCTest
@testable import PocketCore

final class OfficialHistoryTests: XCTestCase {
    private func fx(_ n: String) throws -> Data { try Fixtures.data("member/official/\(n)") }

    func testRocDates() {
        XCTAssertEqual(OfficialHistory.rocDate("114/06/18"), "2025-06-18")
        XCTAssertEqual(OfficialHistory.rocDate("114年01月17日"), "2025-01-17")
        XCTAssertNil(OfficialHistory.rocDate("abc"))
    }

    func testTwseMonth() throws {
        let bars = try OfficialHistory.twseMonth(fx("A_twse_STOCK_DAY_0050_202506.json"))
        XCTAssertEqual(bars.count, 4)
        XCTAssertEqual(bars.first, DailyBar(date: "2025-06-02", close: 175.90))
        XCTAssertTrue(bars.contains(DailyBar(date: "2025-06-10", close: 188.65)))
        let empty = Data("{\"stat\":\"很抱歉，沒有符合條件的資料!\"}".utf8)
        XCTAssertEqual(try OfficialHistory.twseMonth(empty), [])
    }

    func testTpexMonth() throws {
        let bars = try OfficialHistory.tpexMonth(fx("B_tpex_tradingStock_00679B_202506.json"))
        XCTAssertEqual(bars.count, 3)
        XCTAssertEqual(bars.first, DailyBar(date: "2025-06-02", close: 25.21))
        let empty = Data("{\"stat\":\"ok\",\"tables\":[{\"data\":[],\"fields\":[]}]}".utf8)
        XCTAssertEqual(try OfficialHistory.tpexMonth(empty), [])
    }

    func testTwseDividends() throws {
        let ev = try OfficialHistory.twseDividends(fx("C_twse_TWT49U_2025_sample.json"))
        XCTAssertTrue(ev.contains(DividendEvent(symbol: "0050", exDate: "2025-01-17", cash: 2.7)))
        XCTAssertTrue(ev.contains(DividendEvent(symbol: "00878", exDate: "2025-02-20", cash: 0.5)))
    }

    func testTpexDividends() throws {
        let ev = try OfficialHistory.tpexDividends(fx("C_tpex_exDailyQ_2025_sample.json"))
        XCTAssertEqual(ev.first, DividendEvent(symbol: "00937B", exDate: "2025-01-22", cash: 0.082))
    }

    func testSplits() throws {
        let ev = try OfficialHistory.splits(fx("D_twse_TWTCAU_2015_2026.json"))
        XCTAssertEqual(ev.count, 12)
        let s50 = try XCTUnwrap(ev.first { $0.symbol == "0050" })
        XCTAssertEqual(s50.resumeDate, "2025-06-18")
        XCTAssertEqual(s50.ratio, 4)
        let r = try XCTUnwrap(ev.first { $0.symbol == "00632R" })
        XCTAssertEqual(r.ratio, 1.0 / 7.0, accuracy: 1e-9)
    }

    func testSuspectedSplitFlagged() {
        let bars = [DailyBar(date: "2025-06-17", close: 100), DailyBar(date: "2025-06-18", close: 25)]
        XCTAssertEqual(OfficialHistory.suspectedSplits(bars, dividends: [], known: []), ["2025-06-18"])
        let known = [SplitEvent(symbol: "0050", resumeDate: "2025-06-18", ratio: 4)]
        XCTAssertEqual(OfficialHistory.suspectedSplits(bars, dividends: [], known: known), [])
    }

    func testURLs() {
        let m = YearMonth(year: 2025, month: 6)
        XCTAssertEqual(OfficialHistory.twseMonthURL(symbol: "0050", month: m).absoluteString,
                       "https://www.twse.com.tw/rwd/zh/afterTrading/STOCK_DAY?date=20250601&stockNo=0050&response=json")
        XCTAssertTrue(OfficialHistory.tpexMonthURL(symbol: "00679B", month: m).absoluteString.contains("date=2025/06/01"))
    }

    private func json(_ s: String) -> Data { Data(s.utf8) }

    func testMalformedResponsesThrow() {
        // stat error body
        XCTAssertThrowsError(try OfficialHistory.twseMonth(json("{\"stat\":\"查詢日期錯誤\"}")))
        XCTAssertThrowsError(try OfficialHistory.twseDividends(json("{\"stat\":\"error\"}")))
        XCTAssertThrowsError(try OfficialHistory.splits(json("{\"stat\":\"error\"}")))
        // TPEx body without tables / data
        XCTAssertThrowsError(try OfficialHistory.tpexMonth(json("{\"stat\":\"ok\"}")))
        XCTAssertThrowsError(try OfficialHistory.tpexDividends(json("{\"stat\":\"ok\"}")))
        XCTAssertThrowsError(try OfficialHistory.tpexMonth(json("{\"tables\":[{\"fields\":[]}]}")))
        // renamed fields
        XCTAssertThrowsError(try OfficialHistory.twseMonth(json(
            "{\"stat\":\"OK\",\"fields\":[\"Date\",\"Close\"],\"data\":[[\"114/06/02\",\"1\"]]}")))
        XCTAssertThrowsError(try OfficialHistory.tpexMonth(json(
            "{\"tables\":[{\"fields\":[\"d\",\"c\"],\"data\":[[\"114/06/02\",\"1\"]]}]}")))
        XCTAssertThrowsError(try OfficialHistory.twseDividends(json(
            "{\"stat\":\"OK\",\"fields\":[\"x\"],\"data\":[[\"1\"]]}")))
        XCTAssertThrowsError(try OfficialHistory.splits(json(
            "{\"stat\":\"OK\",\"fields\":[\"x\"],\"data\":[[\"1\"]]}")))
        // rows present but all unparsable
        XCTAssertThrowsError(try OfficialHistory.twseMonth(json(
            "{\"stat\":\"OK\",\"fields\":[\"日期\",\"收盤價\"],\"data\":[[\"bad\",\"--\"]]}")))
        XCTAssertThrowsError(try OfficialHistory.tpexMonth(json(
            "{\"tables\":[{\"fields\":[\"日 期\",\"收盤\"],\"data\":[[\"bad\",\"--\"]]}]}")))
        XCTAssertThrowsError(try OfficialHistory.tpexDividends(json(
            "{\"tables\":[{\"fields\":[\"除權息日期\",\"代號\",\"現金股利\"],\"data\":[[\"bad\",\"1\",\"x\"]]}]}")))
        XCTAssertThrowsError(try OfficialHistory.splits(json(
            "{\"stat\":\"OK\",\"fields\":[\"恢復買賣日期\",\"ETF代號\",\"停止買賣前收盤價格\",\"恢復買賣參考價\"],\"data\":[[\"bad\",\"0050\",\"x\",\"y\"]]}")))
    }

    func testGenuineEmptyResponsesAreEmpty() throws {
        XCTAssertEqual(try OfficialHistory.twseMonth(json("{\"stat\":\"很抱歉，沒有符合條件的資料!\"}")), [])
        XCTAssertEqual(try OfficialHistory.tpexMonth(json("{\"stat\":\"ok\",\"tables\":[{\"data\":[]}]}")), [])
    }
}
