import XCTest
@testable import PocketCore

/// `Portfolio.componentHistory`: earlier holdings of each ETF, for 主動式 ETF 追蹤.
final class ComponentHistoryTests: XCTestCase {
    private func snapshot(_ symbol: String, _ date: String, weight: Double = 50) -> ComponentSnapshot {
        ComponentSnapshot(symbol: symbol, date: date, components: [FundComponent(symbol: "2330", name: "台積電", weight: weight)], source: "test")
    }

    func testRememberKeepsTwelveNewestOnePerDate() {
        var data = Portfolio()
        XCTAssertNil(data.componentHistory)
        for day in [5, 14, 1, 9, 2, 13, 3, 12, 4, 11, 6, 10, 7, 8] {
            data.remember(snapshot("00982A", String(format: "2026-09-%02d", day)))
        }
        data.remember(snapshot("0050", "2026-09-30"))
        let expected = (3...14).reversed().map { String(format: "2026-09-%02d", $0) }
        XCTAssertEqual(data.componentHistory?["00982A"]?.map(\.date), expected)
        XCTAssertEqual(data.componentHistory?["0050"]?.map(\.date), ["2026-09-30"])
        // The same date again replaces that day's holdings; nothing is added.
        data.remember(snapshot("00982A", "2026-09-10", weight: 61))
        XCTAssertEqual(data.componentHistory?["00982A"]?.map(\.date), expected)
        XCTAssertEqual(data.componentHistory?["00982A"]?.first(where: { $0.date == "2026-09-10" })?.components.first?.weight, 61)
        // Older than everything kept: it does not push a newer day out.
        data.remember(snapshot("00982A", "2026-08-01"))
        XCTAssertEqual(data.componentHistory?["00982A"]?.map(\.date), expected)
        XCTAssertEqual(Portfolio.historyLimit, 12)
    }

    func testFilesWithAndWithoutHistoryDecode() throws {
        // Written before the history existed: the key is simply missing.
        let old = Data(#"{"schema":1,"holdings":[],"dividends":[],"favorites":[],"quotes":{}}"#.utf8)
        XCTAssertNil(try Portfolio.decodeBackup(old).componentHistory)
        var data = Portfolio()
        data.remember(snapshot("0050", "2026-09-01"))
        data.remember(snapshot("0050", "2026-09-02"))
        let back = try Portfolio.decodeBackup(JSONEncoder().encode(data))
        XCTAssertEqual(back.componentHistory?["0050"]?.map(\.date), ["2026-09-02", "2026-09-01"])
        XCTAssertNil(back.components, "The history does not stand in for the current holdings")
    }

    func testBackupRejectsBadHistory() throws {
        func encoded(_ history: [String: [ComponentSnapshot]]) throws -> Data {
            var data = Portfolio()
            data.componentHistory = history
            return try JSONEncoder().encode(data)
        }
        XCTAssertNoThrow(try Portfolio.decodeBackup(encoded(["0050": [snapshot("0050", "2026-09-02"), snapshot("0050", "2026-09-01")]])))
        // Filed under another ETF's code.
        XCTAssertThrowsError(try Portfolio.decodeBackup(encoded(["0056": [snapshot("0050", "2026-09-01")]])))
        // The same date twice.
        XCTAssertThrowsError(try Portfolio.decodeBackup(encoded(["0050": [snapshot("0050", "2026-09-01"), snapshot("0050", "2026-09-01")]])))
        // More days than the app keeps.
        let many = (1...13).map { snapshot("0050", String(format: "2026-09-%02d", $0)) }
        XCTAssertThrowsError(try Portfolio.decodeBackup(encoded(["0050": many])))
        // Holdings that are not holdings (a weight over 100 %).
        XCTAssertThrowsError(try Portfolio.decodeBackup(encoded(["0050": [snapshot("0050", "2026-09-01", weight: 180)]])))
    }
}
