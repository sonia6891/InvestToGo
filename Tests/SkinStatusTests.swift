import XCTest
@testable import ETFToGo

final class SkinStatusTests: XCTestCase {
    func testHarvestStatus() {
        let h = Skins.named("harvest")
        XCTAssertEqual(SkinStatus(h, current: "blackgold", level: 40, member: false, achievements: []), .needsAchievement)
        XCTAssertEqual(SkinStatus.needsAchievement.tag(h, level: 40, member: false), "7–9 月記一筆配息解鎖")
        XCTAssertEqual(SkinStatus.needsAchievement.caption, "除息季")
        XCTAssertEqual(SkinStatus(h, current: "blackgold", level: 1, member: false, achievements: ["exDividendSkin"]), .unlocked)
        XCTAssertEqual(SkinStatus.unlocked.tag(h, level: 1, member: false, achievements: ["exDividendSkin"]), "除息季成就 · 已解鎖")
        XCTAssertEqual(SkinStatus.unlocked.tag(h, level: 1, member: true, achievements: []), "會員 · 已解鎖")
    }
}
