import XCTest
import SwiftUI
import UIKit
@testable import ETFToGo

/// 收成 (the fifth 外觀主題) opens with the 除息季 achievement: a dividend paid in July to September, saved by any
/// flow, counts in the same write. A lapsed member keeps the theme once it is earned.
final class HarvestUnlockTests: XCTestCase {
    private lazy var directory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }()
    private var file: URL { directory.appendingPathComponent("p.json") }
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date { GameRules.taipei.date(from: DateComponents(year: year, month: month, day: day, hour: 12))! }
    private func dividend(_ symbol: String = "0056", on date: Date, status: DividendStatus = .paid) -> Dividend {
        Dividend(symbol: symbol, date: date, amount: 1200, status: status)
    }
    private let id = Achievements.exDividendSkinID

    @MainActor func testSavingASeasonDividendUnlocks() throws {
        let store = PortfolioStore(url: file)
        XCTAssertNil(store.data.game?.unlocked[id])
        try store.saveDividend(dividend(on: day(2026, 8, 10)), rewardNew: true, now: day(2026, 11, 20))
        XCTAssertNotNil(store.data.game?.unlocked[id], "A payment dated in August counts, whenever it was typed in")
        XCTAssertEqual(store.pendingReward, 0, "The season itself pays no experience")
        XCTAssertNotNil(PortfolioStore(url: file).data.game?.unlocked[id], "Saved with the record")
    }

    @MainActor func testAnOutOfSeasonDividendDoesNotUnlock() throws {
        let store = PortfolioStore(url: file)
        try store.saveDividend(dividend(on: day(2026, 6, 20)), rewardNew: true, now: day(2026, 11, 20))
        XCTAssertNil(store.data.game?.unlocked[id])
    }

    @MainActor func testRecordAndConfirmCount() throws {
        let store = PortfolioStore(url: file)
        try store.record(dividend(on: day(2026, 9, 1)))
        XCTAssertNotNil(store.data.game?.unlocked[id], "record counts")

        // Phones whose records already hold a September dividend, with nothing unlocked yet.
        var portfolio = Portfolio()
        let pending = dividend(on: day(2026, 9, 5), status: .announced)
        portfolio.dividends = [pending]
        let second = directory.appendingPathComponent("second.json")
        try JSONEncoder().encode(portfolio).write(to: second)
        let fresh = PortfolioStore(url: second)
        XCTAssertNil(fresh.data.game?.unlocked[id])
        try fresh.markPaid(pending)
        XCTAssertNotNil(fresh.data.game?.unlocked[id], "markPaid counts")

        let third = directory.appendingPathComponent("third.json")
        try JSONEncoder().encode(portfolio).write(to: third)
        let confirm = PortfolioStore(url: third)
        XCTAssertNil(confirm.data.game?.unlocked[id])
        try confirm.confirmPaid(pending)
        XCTAssertNotNil(confirm.data.game?.unlocked[id], "confirmPaid counts")
    }

    @MainActor func testImportedBackupUnlocks() throws {
        var backup = Portfolio()
        backup.dividends = [dividend(on: day(2025, 7, 20))]
        let bytes = try JSONEncoder().encode(backup)
        let store = PortfolioStore(url: file)
        try store.importBackup(bytes)
        XCTAssertNotNil(store.data.game?.unlocked[id], "A backup's July dividend counts at once")
        XCTAssertNotNil(PortfolioStore(url: file).data.game?.unlocked[id])
    }

    @MainActor func testLapsedMemberKeepsAnEarnedHarvest() {
        let wardrobe = SkinStore()
        wardrobe.select("harvest")
        XCTAssertFalse(wardrobe.takeOffLocked(level: 1, member: false, achievements: [id]))
        XCTAssertEqual(wardrobe.skin.id, "harvest")
        XCTAssertTrue(wardrobe.takeOffLocked(level: 1, member: false, achievements: []))
        XCTAssertEqual(wardrobe.skin.id, "blackgold")
    }

#if DEBUG
    @MainActor func testHarvestRendersEveryComponent() {
        let view = SkinKitPreview().frame(width: 390, height: 844).environment(\.skin, Skins.named("harvest"))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        XCTAssertNotNil(renderer.uiImage)
    }
#endif
}
