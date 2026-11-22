import UserNotifications
import XCTest
@testable import ETFToGo

final class NotificationRouterTests: XCTestCase {
    func testPresentation() {
        XCTAssertEqual(NotificationRouter.presentation(for: "price-alert-1"), [.banner, .list, .sound])
        XCTAssertEqual(NotificationRouter.presentation(for: "dca-reminder-2026-12"), [.banner, .list, .sound])
        XCTAssertEqual(NotificationRouter.presentation(for: "dca-reminder-eve-2026-12"), [.banner, .list, .sound])
        XCTAssertEqual(NotificationRouter.presentation(for: "dividend-ABC"), [])
    }

    func testRoute() {
        XCTAssertTrue(NotificationRouter.wantsQuickDCA(["route": "quickDCA"]))
        XCTAssertFalse(NotificationRouter.wantsQuickDCA(["route": "other"]))
        XCTAssertFalse(NotificationRouter.wantsQuickDCA([:]))
    }
}
