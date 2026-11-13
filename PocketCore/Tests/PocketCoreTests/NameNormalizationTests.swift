import XCTest
@testable import PocketCore

/// Official lists spell 金 來 益 as CJK compatibility ideographs (U+F90A, U+F92D, U+FA17). The bundled skin fonts
/// only have the unified characters, so names are read in NFC. Swift's `==` treats the two spellings as equal, so
/// these tests compare Unicode scalars.
final class NameNormalizationTests: XCTestCase {
    private let compatibility: ClosedRange<UInt32> = 0xF900...0xFAFF
    private func hasCompatibility(_ text: String) -> Bool { text.unicodeScalars.contains { compatibility.contains($0.value) } }

    func testFundNamesDecodeInNFC() throws {
        let json = #"{"id":"00400A","name":"金來益","strategy":"待分類","market":"TWSE","fullName":"主動式ETF證券投資信託基金"}"#
        let fund = try JSONDecoder().decode(Fund.self, from: Data(json.utf8))
        XCTAssertEqual(fund.name.unicodeScalars.map(\.value), [0x91D1, 0x4F86, 0x76CA])
        XCTAssertEqual(fund.fullName?.unicodeScalars.last?.value, 0x91D1)
        // Encoding still round-trips every field.
        let again = try JSONDecoder().decode(Fund.self, from: JSONEncoder().encode(fund))
        XCTAssertEqual(again, fund)
        XCTAssertEqual(again.market, "TWSE")
    }

    func testAnnualFeeNamesDecodeInNFC() throws {
        let json = #"{"symbol":"00679B","fundID":"12345678","fundName":"債券ETF基金(收益平準金)","year":2025,"commission":0.01,"tax":0,"subscriptionOffset":0,"management":0.1,"custody":0.03,"guarantee":0,"other":0.01,"total":0.15}"#
        let record = try JSONDecoder().decode(AnnualExpense.self, from: Data(json.utf8))
        XCTAssertFalse(hasCompatibility(record.fundName))
        XCTAssertTrue(record.fundName.unicodeScalars.contains { $0.value == 0x76CA })
        XCTAssertEqual(record.total, 0.15)
    }

    func testTWSEEntitiesUnescapeInNFC() {
        XCTAssertEqual(CatalogAPI.unescape("基&#63754;").unicodeScalars.last?.value, 0x91D1)
        XCTAssertEqual(CatalogAPI.unescape("S&amp;P 500"), "S&P 500")
    }

    func testBundledDataHasNoCompatibilityIdeographs() throws {
        let catalog = try XCTUnwrap(CatalogSnapshot.bundled())
        for fund in catalog.funds {
            XCTAssertFalse(hasCompatibility(fund.name), fund.id)
            XCTAssertFalse(hasCompatibility(fund.fullName ?? ""), fund.id)
        }
        let fees = try XCTUnwrap(AnnualFeeCatalog.bundled)
        for record in fees.records.values { XCTAssertFalse(hasCompatibility(record.fundName), record.symbol) }
    }
}
