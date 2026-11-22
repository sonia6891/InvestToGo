import XCTest
import SwiftUI
import UIKit
@testable import ETFToGo

final class DexRevealTests: XCTestCase {
    func testStartPhase() {
        XCTAssertEqual(DexReveal.start(reduceMotion: false, uiTesting: true), .buttons)
        XCTAssertEqual(DexReveal.start(reduceMotion: true, uiTesting: false), .face)
        XCTAssertEqual(DexReveal.start(reduceMotion: true, uiTesting: true), .buttons)
        XCTAssertEqual(DexReveal.start(reduceMotion: false, uiTesting: false), .back)
    }

    func testRewardText() {
        XCTAssertEqual(DexReveal.rewardText(FundVisit(new: true, cardXP: 30)), "+30 經驗")
        XCTAssertEqual(DexReveal.rewardText(FundVisit(new: true, cardXP: 0)), "收進圖鑑")
    }

    func testSpokenSummary() {
        let fund = Fund(id: "0050", name: "元大台灣50", strategy: .saving)
        XCTAssertEqual(DexReveal.spoken(fund, visit: FundVisit(new: true, cardXP: 30)), "收進圖鑑：0050 元大台灣50，+30 經驗")
        XCTAssertEqual(DexReveal.spoken(fund, visit: FundVisit(new: true, cardXP: 0)), "收進圖鑑：0050 元大台灣50")
    }

    @MainActor func testRevealRendersInEverySkin() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = PortfolioStore(url: directory.appendingPathComponent("p.json"))
        for skin in Skins.all {
            let view = DexRevealView(item: DexRevealItem(symbol: "0050", visit: FundVisit(new: true, cardXP: 30)),
                                     onAccept: {}, onOpen: {})
                .frame(width: 390, height: 844)
                .environmentObject(store)
                .environment(\.skin, skin)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            XCTAssertNotNil(renderer.uiImage, "\(skin.id) reveal back did not render")
            // The end state (face, reward, buttons): ImageRenderer never runs .task, so a seam opens there.
            let end = DexRevealView(item: DexRevealItem(symbol: "0050", visit: FundVisit(new: true, cardXP: 30)),
                                    startPhase: .buttons, onAccept: {}, onOpen: {})
                .frame(width: 390, height: 844)
                .environmentObject(store)
                .environment(\.skin, skin)
            let endRenderer = ImageRenderer(content: end)
            endRenderer.scale = 1
            XCTAssertNotNil(endRenderer.uiImage, "\(skin.id) reveal end state did not render")
            if let a = renderer.uiImage?.pngData(), let b = endRenderer.uiImage?.pngData() {
                XCTAssertNotEqual(a, b, "\(skin.id) the end state differs from the back")
            }
        }
    }
}
