import XCTest
@testable import PocketCore

final class MemberFeatureTests: XCTestCase {
    func testEveryFeatureHasTitleAndPitch() {
        for feature in MemberFeature.allCases {
            XCTAssertFalse(feature.title.isEmpty, "\(feature) title")
            XCTAssertFalse(feature.pitch.isEmpty, "\(feature) pitch")
        }
        XCTAssertEqual(Set(MemberFeature.allCases.map(\.title)).count, MemberFeature.allCases.count, "titles are unique")
    }

    /// The lock card's title is the page's own title.
    func testReportTitleMatchesThePage() {
        XCTAssertEqual(MemberFeature.report.title, "口袋月報／年報")
    }

    /// The pitch names the scenarios the page offers, every one of them.
    func testScenariosPitchNamesEveryScenario() {
        XCTAssertEqual(MemberFeature.scenarios.pitch, "保守、基準、樂觀與壓力測試，四種情境一次試算")
        XCTAssertEqual(ComboScenario.allCases.count, 4)
        for scenario in ComboScenario.allCases {
            XCTAssertTrue(MemberFeature.scenarios.pitch.contains(scenario.rawValue), "\(scenario.rawValue) is in the pitch")
        }
    }

    /// The pitch says what the screen shows (holdings added, dropped, reweighted), not a daily list of trades.
    func testActiveTrackingPitch() {
        XCTAssertEqual(MemberFeature.activeTracking.pitch, "看主動式 ETF 新增、剔除了哪些持股，權重怎麼變")
    }
}
