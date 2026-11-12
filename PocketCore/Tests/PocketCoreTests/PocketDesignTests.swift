import XCTest
@testable import PocketCore

final class PocketShapeTests: XCTestCase {
    private func mirrored(_ points: [SIMD2<Double>]) -> Bool {
        points.allSatisfy { p in points.contains { abs($0.x + p.x) < 0.03 && abs($0.y - p.y) < 0.03 } }
    }
    func testOutlinesAreSymmetricAndBackIsTaller() {
        let front = PocketShape.front(), back = PocketShape.back()
        XCTAssertGreaterThan(front.count, 40)
        XCTAssertTrue(mirrored(front)); XCTAssertTrue(mirrored(back))
        XCTAssertEqual(front.map(\.y).min()!, back.map(\.y).min()!, accuracy: 0.01, "Same rounded bottom")
        XCTAssertGreaterThan(back.map(\.y).max()!, front.map(\.y).max()! + 0.5, "The back panel stands above the front lip")
    }
    func testStitchesAreEvenAndInsideThePocket() {
        let stitches = PocketShape.stitches(), front = PocketShape.front()
        XCTAssertEqual(stitches.count, 36)
        let lengths = stitches.map(\.length)
        XCTAssertLessThan(lengths.max()! - lengths.min()!, 0.02, "Evenly spaced along the edge")
        XCTAssertTrue(stitches.allSatisfy { abs($0.center.x) < front.map(\.x).max()! && $0.center.y > front.map(\.y).min()! })
    }
}

final class SkinsTests: XCTestCase {
    func testFourSkinsInOrder() {
        XCTAssertEqual(Skins.all.map(\.id), ["blackgold", "voxel", "stitch", "sketch"])
        XCTAssertEqual(Skins.all.map(\.name), ["黑金", "像素", "縫線", "手繪"])
        XCTAssertEqual(Skins.default.id, "blackgold")
        XCTAssertEqual(Skins.carouselOrder, ["voxel", "blackgold", "stitch", "sketch"])
    }
    func testColorsMatchSpec() {
        let gold = Skins.named("blackgold").colors
        XCTAssertEqual(gold.page, 0x1A1A1D); XCTAssertEqual(gold.ink, 0xF4F1E8); XCTAssertEqual(gold.accent, 0xF2B632)
        XCTAssertEqual(gold.up, 0xF25C54); XCTAssertEqual(gold.down, 0x3BB273)
        XCTAssertEqual(Skins.named("voxel").colors.page, 0x1B1F4B); XCTAssertEqual(Skins.named("voxel").colors.accent, 0xFF3D8B)
        let stitch = Skins.named("stitch").colors
        XCTAssertEqual(stitch.page, 0xE9DCC3); XCTAssertEqual(stitch.ink, 0x3B2A1A); XCTAssertEqual(stitch.accent, 0xC9573F)
        XCTAssertEqual(stitch.extra, [0x2F4A6D, 0xE3A82B, 0xF7F0E1])
        let sketch = Skins.named("sketch").colors
        XCTAssertEqual(sketch.page, 0xFAF8F3); XCTAssertEqual(sketch.ink, 0x1F1F1F); XCTAssertEqual(sketch.accent, 0xF2D16B)
    }
    func testSkinTextContrast() {
        for skin in Skins.all {
            XCTAssertGreaterThanOrEqual(contrastRatio(skin.colors.ink, skin.colors.page), 4.5, "\(skin.id) ink")
            XCTAssertGreaterThanOrEqual(contrastRatio(skin.colors.sub, skin.colors.page), 4.5, "\(skin.id) sub")
            XCTAssertGreaterThanOrEqual(contrastRatio(skin.colors.up, skin.colors.page), 3, "\(skin.id) up")
            XCTAssertGreaterThanOrEqual(contrastRatio(skin.colors.down, skin.colors.page), 3, "\(skin.id) down")
        }
        XCTAssertEqual(contrastRatio(0xFFFFFF, 0x000000), 21, accuracy: 0.01)
    }
    func testUnknownOrRetiredSkinFallsBackToBlackGold() {
        for id in ["ember", "ice", "", "nope"] { XCTAssertEqual(Skins.named(id).id, "blackgold", id) }
        XCTAssertEqual(Skins.named("stitch").id, "stitch")
    }
    func testUnlockRules() {
        XCTAssertEqual(Skins.named("blackgold").unlock, .free)
        XCTAssertEqual(Skins.named("sketch").unlock, .level(5))
        XCTAssertEqual(Skins.named("voxel").unlock, .level(10))
        XCTAssertEqual(Skins.named("stitch").unlock, .member)
    }
    /// Black-gold is free, sketch opens at LV.5, pixel at LV.10, stitch only for members; members get all four.
    func testIsUnlocked() {
        func open(_ level: Int, member: Bool) -> [String] { Skins.all.filter { Skins.isUnlocked($0, level: level, member: member) }.map(\.id) }
        XCTAssertEqual(open(1, member: false), ["blackgold"])
        XCTAssertEqual(open(4, member: false), ["blackgold"])
        XCTAssertEqual(open(5, member: false), ["blackgold", "sketch"])
        XCTAssertEqual(open(9, member: false), ["blackgold", "sketch"])
        XCTAssertEqual(open(10, member: false), ["blackgold", "voxel", "sketch"])
        XCTAssertEqual(open(40, member: false), ["blackgold", "voxel", "sketch"], "Stitch never opens by level")
        XCTAssertEqual(open(1, member: true), ["blackgold", "voxel", "stitch", "sketch"])
    }
    func testOnlyVectorSkinsHaveNoMetal() {
        for id in ["stitch", "sketch"] {
            XCTAssertEqual(Skins.named(id).art.kind, .vector, id); XCTAssertNil(Skins.named(id).metal, id)
        }
        for id in ["blackgold", "voxel"] { XCTAssertNotNil(Skins.named(id).metal, id) }
        XCTAssertEqual(Skins.named("blackgold").art.kind, .render3D); XCTAssertEqual(Skins.named("voxel").art.kind, .voxel3D)
    }
    func testFontsAndFeedback() {
        XCTAssertEqual(Skins.named("blackgold").fonts, SkinFonts(big: "Anton-Regular", title: "NotoSansTC-Bold", body: "NotoSansTC-Medium", mono: "JetBrainsMono-Regular"))
        XCTAssertEqual(Skins.named("voxel").fonts, SkinFonts(big: "PressStart2P-Regular", title: "DotGothic16-Regular", body: "DotGothic16-Regular", mono: "PressStart2P-Regular"))
        XCTAssertEqual(Skins.named("stitch").fonts, SkinFonts(big: "BreeSerif-Regular", title: "NotoSerifTC-Bold", body: "NotoSerifTC-Medium", mono: "BreeSerif-Regular"))
        XCTAssertEqual(Skins.named("sketch").fonts, SkinFonts(big: "Caveat-Regular", title: "LXGWWenKaiTC-Medium", body: "LXGWWenKaiTC-Medium", mono: "LXGWWenKaiTC-Medium",
                                                                 bigBold: true, bigOverhang: 0.12))
        // Only the sketch skin's big face is drawn bold and needs room for its overhang; the others keep the defaults.
        for id in ["blackgold", "voxel", "stitch"] {
            XCTAssertFalse(Skins.named(id).fonts.bigBold, id); XCTAssertEqual(Skins.named(id).fonts.bigOverhang, 0, id)
        }
        XCTAssertEqual(Skins.all.map(\.feedback.sound), ["thud", "chip", "snip", "scribble"])
        XCTAssertEqual(Skins.named("sketch").feedback.haptic, .faint)
        XCTAssertEqual(Skins.named("stitch").art.folder, "Skins/stitch")
    }
    func testArtNamesAndFolders() {
        XCTAssertEqual(SkinArtName.allCases.map(\.rawValue), ["hero_dollar", "pocket", "pocket_icon", "find", "dividends", "tools", "achievements",
                                                             "crown", "calc", "fees", "reminder", "goal", "badge"])
        XCTAssertEqual(Skins.all.map(\.art.folder), ["Skins/blackgold", "Skins/voxel", "Skins/stitch", "Skins/sketch"])
        XCTAssertEqual(Skins.named("stitch").art.image(.find), "Skins/stitch/find")
        XCTAssertEqual(Skins.named("sketch").art.image(named: "tally_5"), "Skins/sketch/tally_5")
    }
}
