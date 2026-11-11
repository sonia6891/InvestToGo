import XCTest
@testable import PocketCore

final class TrendRoleTests: XCTestCase {
    func testPaletteFollowsTaiwanConvention() {
        XCTAssertEqual(TrendRole(0.01), .up)
        XCTAssertEqual(TrendRole(-0.01), .down)
        XCTAssertEqual(TrendRole(0), .flat)
        XCTAssertEqual(TrendRole.up.colorName, "red", "Taiwan shows gains in red")
        XCTAssertEqual(TrendRole.down.colorName, "green", "and losses in green")
    }
}
