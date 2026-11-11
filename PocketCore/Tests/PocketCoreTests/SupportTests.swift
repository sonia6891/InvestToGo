import XCTest
@testable import PocketCore

final class SupportTests: XCTestCase {
    private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    func testSHA256KnownVectors() {
        XCTAssertEqual(hex(SHA256Digest.hash(Data("abc".utf8))), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(hex(SHA256Digest.hash(Data())), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(hex(SHA256Digest.hash(Data("代碼".utf8))), "e4cf7624ee98d7a86f74171a55fa5f7afebd727c9986b7b23c05b5edcfe36e8b")
        XCTAssertEqual(hex(SHA256Digest.hash(Data(repeating: 0x61, count: 1_000))), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }

    func testStableIDMatchesLegacyValues() {
        XCTAssertEqual(StableID.make("legacy-holding", "pwa-001").uuidString, "5FEF0885-6A6B-555C-8BEC-451862548983")
        XCTAssertEqual(StableID.make("broker-account", "富邦證券\u{0}主帳戶").uuidString, "BC7184A2-8615-5B96-BBEF-6ACB785C7D4E")
    }

    func testDataChecksDatesAndCodes() {
        XCTAssertEqual(DataChecks.rocDay("1151110"), "2026-11-10")
        XCTAssertNil(DataChecks.date("2026-02-30"))
        XCTAssertTrue(DataChecks.code("00679B"))
        XCTAssertFalse(DataChecks.code("AAPL"))
    }
}
