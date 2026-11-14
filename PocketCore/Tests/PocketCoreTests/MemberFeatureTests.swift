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

    /// The pitch says what the screen shows (holdings added, dropped, reweighted), not a daily list of trades.
    func testActiveTrackingPitch() {
        XCTAssertEqual(MemberFeature.activeTracking.pitch, "看主動式 ETF 新增、剔除了哪些持股，權重怎麼變")
    }
}
