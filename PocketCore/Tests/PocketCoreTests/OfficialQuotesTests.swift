import XCTest
@testable import PocketCore

final class OfficialQuotesTests: XCTestCase {
    struct Expected: Decodable, Equatable { let symbol: String; let price: Double; let date: String; let currency: String }
    let now = Date(timeIntervalSince1970: 1_794_400_000)

    private func decodedAll() throws -> [Quote] {
        try OfficialQuotes.decodeTWSE(Fixtures.data("official/twse-stock-day-all.json"), fetchedAt: now)
            + OfficialQuotes.decodeTPEx(Fixtures.data("official/tpex-daily-close.json"), fetchedAt: now)
    }

    func testDecodeMatchesSharedExpectation() throws {
        let expected = try JSONDecoder().decode([Expected].self, from: Fixtures.data("official/expected-quotes.json"))
        let actual = try decodedAll().map { Expected(symbol: $0.symbol, price: $0.price, date: $0.date, currency: $0.currency ?? "") }.sorted { $0.symbol < $1.symbol }
        XCTAssertEqual(actual, expected)
        XCTAssertTrue(try decodedAll().allSatisfy { $0.changePercent == nil && $0.fetchedAt == now })
    }

    func testNoTradeRowsAreSkipped() throws {
        let symbols = Set(try decodedAll().map(\.symbol))
        XCTAssertFalse(symbols.contains("00625K"), "Empty ClosingPrice must not become a zero price")
        XCTAssertFalse(symbols.contains("00986B"), "TPEx ' ---' close must be skipped")
        XCTAssertFalse(symbols.contains("2330"), "Non-ETF codes are ignored")
    }

    func testForeignClassIsNotTWD() throws {
        let quotes = Dictionary(uniqueKeysWithValues: try decodedAll().map { ($0.symbol, $0) })
        XCTAssertEqual(quotes["00636K"]?.isTWD, false)
        XCTAssertEqual(quotes["00687C"]?.isTWD, false)
        XCTAssertEqual(quotes["00635U"]?.isTWD, true, "U suffix is a TWD-traded futures ETF")
        XCTAssertEqual(quotes["0050"]?.isTWD, true)
    }

    func testMergeKeepsNewerQuote() {
        func q(_ date: String, _ price: Double) -> Quote { Quote(symbol: "0050", price: price, changePercent: nil, date: date, fetchedAt: now, currency: "TWD") }
        XCTAssertEqual(OfficialQuotes.merge([q("2026-11-10", 1)], into: ["0050": q("2026-11-11", 2)])["0050"]?.price, 2)
        XCTAssertEqual(OfficialQuotes.merge([q("2026-11-10", 1)], into: ["0050": q("2026-11-07", 2)])["0050"]?.price, 1)
        XCTAssertEqual(OfficialQuotes.merge([q("2026-11-10", 1)], into: ["0050": q("2026-11-10", 2)])["0050"]?.price, 2)
        XCTAssertEqual(OfficialQuotes.merge([q("2026-11-10", 1)], into: [:])["0050"]?.price, 1)
    }

    func testChangedDateFormatThrows() {
        let bytes = Data(#"[{"Date":"2026/11/10","Code":"0050","Name":"元大台灣50","ClosingPrice":"99.70"}]"#.utf8)
        XCTAssertThrowsError(try OfficialQuotes.decodeTWSE(bytes, fetchedAt: now)) { error in
            XCTAssertEqual(error.localizedDescription, "官方收盤價日期格式改變，保留原有報價。")
        }
    }
}
