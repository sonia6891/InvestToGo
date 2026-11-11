import XCTest
@testable import PocketCore

/// Official open-data parsing against real 2026-11-10/11 responses kept in SharedFixtures (shared with Android).
final class OpenDataTests: XCTestCase {
    struct Expected: Decodable { let symbol: String; let price: Double; let date: String; let currency: String }

    private func quotes() throws -> [String: Quote] {
        try OpenData.decodeTWSE(Fixtures.data("official/twse-stock-day-all.json"))
            .merging(OpenData.decodeTPEx(Fixtures.data("official/tpex-daily-close.json"))) { first, _ in first }
    }

    func testETFClosesMatchSharedExpectation() throws {
        let all = try quotes()
        for e in try JSONDecoder().decode([Expected].self, from: Fixtures.data("official/expected-quotes.json")) {
            let q = try XCTUnwrap(all[e.symbol], e.symbol)
            XCTAssertEqual(q.price, e.price, e.symbol); XCTAssertEqual(q.date, e.date, e.symbol); XCTAssertEqual(q.currency, e.currency, e.symbol)
            XCTAssertEqual(q.source, OpenData.source)
        }
    }
    func testNoTradeRowsAreSkipped() throws {
        let all = try quotes()
        XCTAssertNil(all["00625K"], "Empty ClosingPrice must not become a price")
        XCTAssertNil(all["00986B"], "TPEx ' ---' close must be skipped")
    }
    func testOpenDataMarksCAndKAsForeign() throws {
        let all = try quotes()
        XCTAssertEqual(all["00636K"]?.isTWD, false)
        XCTAssertEqual(all["00687C"]?.isTWD, false)
        XCTAssertEqual(all["00635U"]?.isTWD, true, "U suffix is a TWD-traded futures ETF")
        XCTAssertEqual(all["0050"]?.isTWD, true)
    }
    func testCloseIsStampedAtTheEndOfItsTradingDay() throws {
        let q = try XCTUnwrap(try quotes()["0050"])
        XCTAssertEqual(q.fetchedAt, DataChecks.date("2026-11-10")!.addingTimeInterval(13.5 * 3600), "A later live quote must win over the close")
    }
}

final class OfficialDividendsDecodeTests: XCTestCase {
    func testCashAmountsAndBlankAmount() throws {
        let events = try OfficialDividends.decode(Fixtures.data("official/twse-twt48u.json"), market: "TWSE", markets: ["0051": "TWSE", "00690": "TWSE", "4562": "TWSE"])
        XCTAssertEqual(events["00690"], [OfficialDistribution(ex: "2026-11-17", pay: "", amount: 2.0)])
        XCTAssertEqual(events["0051"], [OfficialDistribution(ex: "2026-11-20", pay: "", amount: nil)], "A blank amount is unknown, not zero")
        XCTAssertNil(events["4562"], "A stock-dividend (權) notice is not a cash distribution")
        XCTAssertNil(events["01007T"], "Codes outside the catalogue are ignored")
    }
}
