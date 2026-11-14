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

    /// B5. The lock cards say what the screen does. Nothing is "told to us" (no figure leaves the phone), and 回測
    /// shows what a monthly buy would have become, it does not "verify" a way of buying.
    func testGoalPlannerAndBacktestPitches() {
        XCTAssertEqual(MemberFeature.goalPlanner.pitch, "設定目標金額與年數，算出每月要投多少")
        XCTAssertEqual(MemberFeature.backtest.pitch, "看看過去這樣每月買，會變成多少")
        for feature in MemberFeature.allCases {
            XCTAssertFalse(feature.pitch.contains("我們"), "\(feature): nothing is sent to anybody")
            XCTAssertFalse(feature.pitch.contains("驗證"), "\(feature)")
        }
    }

    /// C. Nothing that is only planned is shown: the flag is off, and with it the achievements no feature counts
    /// toward are off the wall (and out of its 已解鎖 N / M).
    func testUpcomingContentIsHidden() {
        XCTAssertFalse(Upcoming.visible)
        let wall = Achievements.shown()
        XCTAssertFalse(wall.contains { $0.comingSoon })
        XCTAssertEqual(wall.map(\.id), ["dividendStreak", "holdingAnniversary", "dcaPunchCard", "steadyYear", "reconcileMaster", "feeSaver", "dexCollector", "dividendMilestone"])
        XCTAssertEqual(Achievements.shown(upcoming: true).count, Achievements.all.count, "Nothing was deleted")
        XCTAssertEqual(Achievements.shown(upcoming: false).count, Achievements.all.count - 3)
    }

    /// The pitch says what the screen shows (holdings added, dropped, reweighted), not a daily list of trades.
    func testActiveTrackingPitch() {
        XCTAssertEqual(MemberFeature.activeTracking.pitch, "看主動式 ETF 新增、剔除了哪些持股，權重怎麼變")
    }
}
