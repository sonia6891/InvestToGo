import XCTest
import SwiftUI
@testable import ETFToGo

/// 口袋月報／年報 in the app: the route, the periods it opens on, the picture that is shared and what UI tests reset.
final class PocketReportViewTests: XCTestCase {
    private let now = GameRules.taipei.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12))!
    private let card = ReportCard(title: "2026 年 10 月", dividends: 3_200, dcaMonths: 1, reconciles: 1, newDexCards: 2, level: 5, xpEarned: 180,
                                  notes: ["領息 2 筆，來自 2 檔。"])

    func testOpenRouteNeedsUITesting() {
        XCTAssertEqual(AppRoute.launchStack(["--ui-testing", "--open", "report"]), [.feature(.tools), .report])
        XCTAssertNil(AppRoute.launchStack(["--open", "report"]))
    }

    /// 月報 and 年報 are for periods that have ended: never the month or the year still running.
    @MainActor func testReportsOpenOnTheLastMonthAndYearThatEnded() {
        XCTAssertEqual(PocketReportView.lastMonth(now), YearMonth(year: 2026, month: 10))
        XCTAssertEqual(PocketReportView.lastYear(now), 2025)
        let newYear = GameRules.taipei.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 0))!
        XCTAssertEqual(PocketReportView.lastMonth(newYear), YearMonth(year: 2026, month: 12))
        XCTAssertEqual(PocketReportView.lastYear(newYear), 2026, "From January the year before has its 年報")
    }

    /// The picture has no screen behind it to take a skin from: it is drawn in the skin it is handed, at one size.
    @MainActor func testPictureIsDrawnInTheSkinItIsHanded() throws {
        XCTAssertEqual(Skins.all.count, 4)
        for skin in Skins.all {
            let image = try XCTUnwrap(PocketReportView.picture(of: card, heading: "口袋月報", isMonth: true, showDividends: true, skin: skin), skin.id)
            XCTAssertEqual(image.size.width, 360, skin.id)
            XCTAssertEqual(image.scale, 3, skin.id)
            XCTAssertGreaterThan(image.size.height, 200, skin.id)
            // The margin around the card is the skin's page colour.
            let corner = try XCTUnwrap(cornerColour(image), skin.id)
            XCTAssertTrue(close(corner, skin.colors.page), "\(skin.id): the margin is \(String(corner, radix: 16)), the page is \(String(skin.colors.page, radix: 16))")
        }
    }

    /// 顯示領息金額 off: the amount is left out of the picture altogether, so the card is shorter by that block.
    @MainActor func testPictureWithoutTheDividendAmountIsShorter() throws {
        let skin = Skins.named("blackgold")
        let with = try XCTUnwrap(PocketReportView.picture(of: card, heading: "口袋月報", isMonth: true, showDividends: true, skin: skin))
        let without = try XCTUnwrap(PocketReportView.picture(of: card, heading: "口袋月報", isMonth: true, showDividends: false, skin: skin))
        XCTAssertLessThan(without.size.height, with.size.height - 30)
        XCTAssertEqual(without.size.width, with.size.width)
    }

    /// A card with nothing in it is still a card.
    @MainActor func testEmptyCardIsDrawn() throws {
        let empty = PocketReport.make(.month(YearMonth(year: 2026, month: 10)), portfolio: Portfolio(), now: now)
        XCTAssertNotNil(PocketReportView.picture(of: empty, heading: "口袋月報", isMonth: true, showDividends: true, skin: Skins.named("voxel")))
    }

    /// What the store saves when a buy is logged carries the month the experience was earned in; the file reads
    /// back the same, and a backup of it still imports.
    @MainActor func testStoreKeepsExperienceByMonth() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("report-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("p.json")
        let store = PortfolioStore(url: file)
        var holding = Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "", strategy: .saving)
        holding.purchaseDate = now
        try store.save(holding, logBuy: true, now: now)
        let game = try XCTUnwrap(store.data.game)
        XCTAssertGreaterThan(game.xp, 0)
        XCTAssertEqual(game.xpByMonth, ["2026-11": game.xp])
        XCTAssertEqual(PortfolioStore(url: file).data.game?.xpByMonth, game.xpByMonth, "Saved with the records")
        let card = PocketReport.make(.yearToDate(2026), portfolio: store.data, now: now)
        XCTAssertEqual(card.xpEarned, game.xp)
        XCTAssertEqual(card.dcaMonths, 1)
        let other = PortfolioStore(url: directory.appendingPathComponent("other.json"))
        XCTAssertNoThrow(try other.importBackup(Data(contentsOf: store.export())))
        XCTAssertEqual(other.data.holdings.map(\.symbol), ["0050"])
    }

    func testResetNeedsUITesting() throws {
        let suite = "report-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: ReportSettings.showDividendsKey)
        defaults.set("2026-10", forKey: ReportSettings.seenMonthKey)
        ReportSettings.reset(["--reset"], defaults: defaults)
        XCTAssertEqual(defaults.object(forKey: ReportSettings.showDividendsKey) as? Bool, false, "A stray --reset changes nothing")
        XCTAssertEqual(defaults.string(forKey: ReportSettings.seenMonthKey), "2026-10")
        ReportSettings.reset(["--ui-testing", "--reset"], defaults: defaults)
        XCTAssertNil(defaults.object(forKey: ReportSettings.showDividendsKey))
        XCTAssertNil(defaults.object(forKey: ReportSettings.seenMonthKey))
    }

    // MARK: Pixels

    /// The colour of the picture's bottom-left pixel, as 0xRRGGBB.
    private func cornerColour(_ image: UIImage) -> UInt32? {
        guard let picture = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            // A one-pixel canvas at the picture's origin: only its bottom-left pixel lands on it.
            context.interpolationQuality = .none
            context.draw(picture, in: CGRect(x: 0, y: 0, width: picture.width, height: picture.height))
            return true
        }
        guard drawn else { return nil }
        let red = UInt32(bytes[0]), green = UInt32(bytes[1]), blue = UInt32(bytes[2])
        return (red << 16) | (green << 8) | blue
    }

    /// Within 8 on every channel.
    private func close(_ a: UInt32, _ b: UInt32) -> Bool {
        let shifts: [UInt32] = [16, 8, 0]
        for shift in shifts {
            let one = Int((a >> shift) & 0xFF)
            let other = Int((b >> shift) & 0xFF)
            if abs(one - other) > 8 { return false }
        }
        return true
    }
}
