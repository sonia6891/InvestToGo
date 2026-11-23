import XCTest
@testable import ETFToGo

final class MotionTests: XCTestCase {
    func testAmbientAllowedOnlyWhenEverythingPermits() {
        XCTAssertTrue(AmbientMotion.allowed(reduceMotion: false, lowPower: false, uiTesting: false, onScreen: true, active: true))
        XCTAssertFalse(AmbientMotion.allowed(reduceMotion: true, lowPower: false, uiTesting: false, onScreen: true, active: true))
        XCTAssertFalse(AmbientMotion.allowed(reduceMotion: false, lowPower: true, uiTesting: false, onScreen: true, active: true))
        XCTAssertFalse(AmbientMotion.allowed(reduceMotion: false, lowPower: false, uiTesting: true, onScreen: true, active: true))
        XCTAssertFalse(AmbientMotion.allowed(reduceMotion: false, lowPower: false, uiTesting: false, onScreen: false, active: true))
        XCTAssertFalse(AmbientMotion.allowed(reduceMotion: false, lowPower: false, uiTesting: false, onScreen: true, active: false))
    }

    func testSkinMotionPerSkin() {
        let voxel = SkinMotion.of(Skins.named("voxel")), sketch = SkinMotion.of(Skins.named("sketch"))
        let gold = SkinMotion.of(Skins.named("blackgold")), stitch = SkinMotion.of(Skins.named("stitch"))
        XCTAssertTrue(voxel.stepped)
        XCTAssertEqual(voxel.stepsPerSecond, 8)
        XCTAssertTrue(sketch.jitter)
        XCTAssertFalse(gold.stepped)
        XCTAssertGreaterThan(stitch.bounce, gold.bounce)
        XCTAssertEqual(SkinMotion.of(Skins.named("nope")), gold)
    }

    func testHarvestSwaysAndDropsGrain() {
        let harvest = SkinMotion.of(Skins.named("harvest"))
        XCTAssertEqual(harvest.particle, .grain); XCTAssertGreaterThan(harvest.sway, 0); XCTAssertFalse(harvest.stepped); XCTAssertFalse(harvest.jitter)
        XCTAssertLessThan(harvest.bobAmplitude, SkinMotion.of(Skins.named("stitch")).bobAmplitude)
        XCTAssertEqual(SkinMotion.of(Skins.named("stitch")).sway, 0)
    }
}
