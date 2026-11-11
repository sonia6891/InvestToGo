import XCTest
import PocketCore
@testable import ETFToGo

// Store-level tests that need the iOS app target. Pure logic tests live in PocketCore/Tests.
final class PortfolioTests: XCTestCase {
    @MainActor func testPersistenceAndImportIdempotence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PortfolioStore(url: url)
        let holding = Portfolio.demo.holdings[0]
        try store.save(holding)
        let reopened = PortfolioStore(url: url)
        XCTAssertEqual(reopened.data.holdings.first?.shares, holding.shares)
        let bytes = try JSONEncoder().encode(Portfolio.demo)
        try reopened.importBackup(bytes)
        let count = reopened.data.holdings.count
        try reopened.importBackup(bytes)
        XCTAssertEqual(reopened.data.holdings.count, count)
        XCTAssertTrue(reopened.data.holdings.contains { $0.id == holding.id })
    }
    @MainActor func testMalformedFileIsNotOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original = Data("invalid data".utf8)
        try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PortfolioStore(url: url)
        XCTAssertThrowsError(try store.save(Portfolio.demo.holdings[0]))
        XCTAssertEqual(try Data(contentsOf: url), original)
        let exported = try store.export()
        defer { try? FileManager.default.removeItem(at: exported) }
        XCTAssertEqual(try Data(contentsOf: exported), original)
    }
}
