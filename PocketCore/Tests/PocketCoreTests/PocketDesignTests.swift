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
    func testThreeSkinsWithUniqueIDs() {
        XCTAssertEqual(Skins.all.map(\.name), ["黑金", "橘焰", "冰藍"])
        XCTAssertEqual(Set(Skins.all.map(\.id)).count, 3)
        XCTAssertEqual(Skins.default.id, "blackgold")
        XCTAssertEqual(Skins.named("ice")?.rarity, "普通"); XCTAssertNil(Skins.named("nope"))
    }
    func testSkinTextContrast() {
        for skin in Skins.all {
            XCTAssertGreaterThanOrEqual(contrastRatio(skin.foreground, skin.background), 4.5, skin.name)
            XCTAssertGreaterThanOrEqual(contrastRatio(skin.muted, skin.background), 4.5, "\(skin.name) small labels")
        }
        XCTAssertEqual(contrastRatio(0xFFFFFF, 0x000000), 21, accuracy: 0.01)
    }
}
