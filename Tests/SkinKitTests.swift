import XCTest
import SwiftUI
import UIKit
@testable import ETFToGo

/// Every skin must draw every kit component: a missing `switch` case, font or image shows up as a failed render.
@MainActor final class SkinKitTests: XCTestCase {
    private func render<V: View>(_ view: V, _ skin: Skin, width: CGFloat? = nil, height: CGFloat? = nil) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height).environment(\.skin, skin))
        renderer.scale = 1
        return renderer.uiImage
    }

    private func assertDrawn<V: View>(_ name: String, _ view: V, _ skin: Skin, width: CGFloat? = nil, height: CGFloat? = nil,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let image = render(view, skin, width: width, height: height)
        XCTAssertNotNil(image, "\(skin.id) \(name) did not render", file: file, line: line)
        if let image {
            XCTAssertGreaterThan(image.size.width, 0, "\(skin.id) \(name) has no width", file: file, line: line)
            XCTAssertGreaterThan(image.size.height, 0, "\(skin.id) \(name) has no height", file: file, line: line)
        }
    }

    func testEveryStyleKindHasARendering() {
        XCTAssertEqual(Skins.all.count, 4)
        for skin in Skins.all {
            // A missing font or image would still "render" (as a fallback), so check the resources themselves.
            for name in [skin.fonts.big, skin.fonts.title, skin.fonts.body, skin.fonts.mono] {
                XCTAssertNotNil(UIFont(name: name, size: 17), "\(skin.id) font \(name) is not registered")
            }
            for name in SkinArtName.allCases {
                XCTAssertNotNil(UIImage(named: skin.art.image(name)), "\(skin.id) has no \(name.rawValue) art")
            }
            assertDrawn("tag", SkinTag("連續定期定額"), skin)
            assertDrawn("primary button", SkinButton("加入口袋") {}, skin)
            assertDrawn("secondary button", SkinButton("＋ 加一檔", primary: false) {}, skin)
            assertDrawn("chip on", SkinChip("全部", selected: true) {}, skin)
            assertDrawn("chip off", SkinChip("市值型", selected: false) {}, skin)
            assertDrawn("search field", SkinSearchField(text: .constant(""), prompt: "輸入代號或名稱"), skin, width: 340)
            assertDrawn("check done", SkinCheck(done: true), skin)
            assertDrawn("check undone", SkinCheck(done: false), skin)
            assertDrawn("stage", SkinStage(size: 220) { SkinImage(.find).frame(width: 150, height: 150) }, skin)
            for page in [DecorPage.lobby, .splash, .other] {
                assertDrawn("decor \(page)", SkinDecor(page: page), skin, width: 390, height: 844)
            }
            for name in SkinArtName.allCases {
                assertDrawn("image \(name.rawValue)", SkinImage(name), skin, width: 80, height: 80)
            }
            assertDrawn("card", SkinCard { Text("本月任務 2/3").skinFont(.mono(11)) }, skin, width: 340)
            for font in [SkinFont.big(42), .title(20), .body(15), .mono(11)] {
                assertDrawn("font \(font)", Text("12 個月").skinFont(font), skin)
            }
        }
    }

    func testButtonsMeetMinimumHitSize() {
        for skin in Skins.all {
            for primary in [true, false] {
                let height = render(SkinButton("收下", primary: primary) {}, skin)?.size.height ?? 0
                XCTAssertGreaterThanOrEqual(height, 44, "\(skin.id) \(primary ? "primary" : "secondary") button is \(height)pt tall")
            }
            for selected in [true, false] {
                let size = render(SkinChip("債券", selected: selected) {}, skin)?.size ?? .zero
                XCTAssertGreaterThanOrEqual(size.height, 44, "\(skin.id) chip is \(size.height)pt tall")
                XCTAssertGreaterThanOrEqual(size.width, 44, "\(skin.id) chip is \(size.width)pt wide")
            }
            let field = render(SkinSearchField(text: .constant(""), prompt: "搜尋"), skin, width: 300)?.size.height ?? 0
            XCTAssertGreaterThanOrEqual(field, 44, "\(skin.id) search field is \(field)pt tall")
        }
    }

    /// The hand-drawn outlines use a fixed seed: the same component looks the same on every draw.
    func testSketchOutlinesAreStable() {
        let rect = CGRect(x: 0, y: 0, width: 160, height: 48)
        XCTAssertEqual(SketchBoxShape(seed: 3).path(in: rect).description, SketchBoxShape(seed: 3).path(in: rect).description)
        XCTAssertNotEqual(SketchBoxShape(seed: 3).path(in: rect).description, SketchBoxShape(seed: 4).path(in: rect).description)
        XCTAssertEqual(SketchCircleShape(seed: 9).path(in: rect).description, SketchCircleShape(seed: 9).path(in: rect).description)
        XCTAssertEqual(SkinSeed.of("加入口袋"), SkinSeed.of("加入口袋"))
    }

    func testHexagonCutIsAFractionOfTheHeight() {
        let path = HexagonShape().path(in: CGRect(x: 0, y: 0, width: 200, height: 50))
        // The top edge starts 0.28 × height in from the left.
        XCTAssertTrue(path.contains(CGPoint(x: 15, y: 2)))
        XCTAssertFalse(path.contains(CGPoint(x: 12, y: 2)))
        XCTAssertTrue(path.contains(CGPoint(x: 1, y: 25)))
    }
}
