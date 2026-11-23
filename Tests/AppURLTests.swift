import XCTest
@testable import ETFToGo

final class AppURLTests: XCTestCase {
    func testOnlyTheLobbyURLOpensTheLobby() {
        XCTAssertTrue(AppURL.opensLobby(URL(string: "etftogo://lobby")!))
        XCTAssertTrue(AppURL.opensLobby(AppURL.lobby))
        XCTAssertFalse(AppURL.opensLobby(URL(string: "etftogo://dividends")!))
        XCTAssertFalse(AppURL.opensLobby(URL(string: "https://lobby")!))
        XCTAssertFalse(AppURL.opensLobby(URL(string: "etftogo:///lobby")!))
    }
}
