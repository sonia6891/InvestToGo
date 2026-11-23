import XCTest
@testable import ETFToGo

/// The 外觀主題 count shown on 工具 and the 會員 page comes from `Skins.all`, so a new theme cannot leave 「四套」 behind.
final class ThemeCountTests: XCTestCase {
    func testPhraseNamesTheNumberOfThemes() {
        XCTAssertEqual(ThemeCount.count, Skins.all.count)
        XCTAssertEqual(ThemeCount.phrase, "\(ThemeCount.chinese(Skins.all.count))套世界任你換")
    }

    func testFiveThemesToday() {
        XCTAssertEqual(Skins.all.count, 5)
        XCTAssertEqual(ThemeCount.phrase, "五套世界任你換")
    }

    func testNumeralsOneToTen() {
        XCTAssertEqual((1...10).map(ThemeCount.chinese), ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"])
        XCTAssertEqual(ThemeCount.chinese(11), "11")
    }
}
