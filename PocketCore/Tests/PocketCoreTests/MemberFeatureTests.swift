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
}
