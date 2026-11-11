import XCTest
@testable import PocketCore

final class OfficialDividendsTests: XCTestCase {
    struct Expected: Decodable { let etfCodes: [String]; let notices: [ExDividendNotice] }

    func testDecodeMatchesSharedExpectation() throws {
        let expected = try JSONDecoder().decode(Expected.self, from: Fixtures.data("official/expected-ex-dividends.json"))
        let actual = try OfficialDividends.decodeTWT48U(Fixtures.data("official/twse-twt48u.json"), etfCodes: Set(expected.etfCodes))
        XCTAssertEqual(actual, expected.notices)
    }

    func testMissingCashDividendIsNil() throws {
        let notices = try OfficialDividends.decodeTWT48U(Fixtures.data("official/twse-twt48u.json"), etfCodes: ["0051"])
        XCTAssertEqual(notices.count, 1)
        XCTAssertNil(notices[0].cashPerShare, "A blank CashDividend means not yet announced, not zero")
    }

    func testOnlyCatalogueETFsAreKept() throws {
        let bytes = try Fixtures.data("official/twse-twt48u.json")
        XCTAssertEqual(try OfficialDividends.decodeTWT48U(bytes, etfCodes: ["00690"]).map(\.symbol), ["00690"])
        XCTAssertTrue(try OfficialDividends.decodeTWT48U(bytes, etfCodes: []).isEmpty)
        XCTAssertEqual(try OfficialDividends.decodeTWT48U(bytes, etfCodes: ["4562"]).first?.kind, .stock)
    }

    func testUnknownKindThrows() {
        let bytes = Data(#"[{"Date":"1151117","Code":"00690","Name":"兆豐藍籌30","Exdividend":"減","CashDividend":"2.000000"}]"#.utf8)
        XCTAssertThrowsError(try OfficialDividends.decodeTWT48U(bytes, etfCodes: ["00690"])) { error in
            XCTAssertEqual(error.localizedDescription, "除權息資料欄位改變，未更新。")
        }
    }
}
