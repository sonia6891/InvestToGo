import XCTest
@testable import ETFToGo

/// Task 14: Sentry reports crashes and handled load failures only, and is off without a DSN, in UI tests and under
/// XCTest. Everything here is the pure seam; the SDK itself is never started by these tests.
final class CrashReportingTests: XCTestCase {
    /// The project's DSN, in full: `//` and `@` must survive from the build setting to the options.
    static let dsn = "https://879ab668f46097254e4b9af68234f109@o4512394043260928.ingest.us.sentry.io/4512422000197632"

    private func make(_ dsn: String?, arguments: [String] = [], environment: [String: String] = [:], debug: Bool = false) -> CrashReportingConfig? {
        CrashReportingConfig.make(dsn: dsn, arguments: arguments, environment: environment, debug: debug)
    }

    func testNoDSNGivesNoOptions() {
        for dsn in [nil, "", " ", "  \n\t "] as [String?] {
            XCTAssertNil(make(dsn), "DSN \(String(describing: dsn)) must leave Sentry off")
        }
    }

    func testUnexpandedBuildSettingGivesNoOptions() {
        // An Info.plist whose $(SENTRY_DSN) was never substituted is not a DSN.
        XCTAssertNil(make("$(SENTRY_DSN)"))
        XCTAssertNil(make("not a dsn"))
    }

    func testValidDSNGivesPrivateOptionsWithTheFullDSN() throws {
        let config = try XCTUnwrap(make(Self.dsn))
        XCTAssertEqual(config.dsn, Self.dsn, "the full DSN, // and @ included")
        XCTAssertFalse(config.sendDefaultPii)
        XCTAssertTrue(config.tracesSampleRate == nil || config.tracesSampleRate == 0, "tracing off")
        XCTAssertFalse(config.enableAutoPerformanceTracing)
        XCTAssertEqual(config.sessionReplaySampleRate, 0)
        XCTAssertEqual(config.sessionReplayOnErrorSampleRate, 0)
        XCTAssertTrue(config.enableAutoBreadcrumbTracking)
        XCTAssertFalse(config.enableUserInteractionTracing)
        XCTAssertFalse(config.enableNetworkBreadcrumbs)
        XCTAssertFalse(config.enableCaptureFailedRequests)
        XCTAssertFalse(config.attachScreenshot)
        XCTAssertFalse(config.attachViewHierarchy)
        XCTAssertTrue(config.enableAppHangTracking)
    }

    func testEnvironmentFollowsTheBuild() throws {
        XCTAssertEqual(try XCTUnwrap(make(Self.dsn, debug: false)).environment, "production")
        XCTAssertEqual(try XCTUnwrap(make(Self.dsn, debug: true)).environment, "debug")
    }

    func testUITestingGivesNoOptions() {
        XCTAssertNil(make(Self.dsn, arguments: ["ETFToGo", "--ui-testing", "--open", "lobby"]))
    }

    func testXCTestGivesNoOptions() {
        XCTAssertNil(make(Self.dsn, environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]))
    }

    func testScrubReplacesMoneyAndKeepsFundCodes() {
        XCTAssertEqual(CrashScrub.scrub("NT$ 255,277"), "NT$ <n>")
        XCTAssertEqual(CrashScrub.scrub("1,234.5"), "<n>")
        XCTAssertEqual(CrashScrub.scrub("123456"), "<n>")
        XCTAssertEqual(CrashScrub.scrub("0050"), "0050")
        XCTAssertEqual(CrashScrub.scrub("00878"), "00878")
        XCTAssertEqual(CrashScrub.scrub("0050 成本 NT$ 1,200,000 配息 12.5"), "0050 成本 NT$ <n> 配息 <n>")
    }

    func testOneEventPerContextPerLaunch() {
        var gate = CrashReportGate()
        let failure = AppDataError("名單數量異常減少，保留原有清單。")
        XCTAssertTrue(gate.admit(failure, context: "catalog"))
        XCTAssertFalse(gate.admit(failure, context: "catalog"), "a second capture of the same context is dropped")
        XCTAssertTrue(gate.admit(failure, context: "dividends"))
        XCTAssertTrue(gate.admit(failure, context: "market"))
    }

    func testOfflineTimeoutAndCancelAreNotReported() {
        var gate = CrashReportGate()
        for code in [URLError.Code.notConnectedToInternet, .timedOut, .cancelled] {
            XCTAssertFalse(CrashReportGate.isReportable(URLError(code)), "\(code)")
            XCTAssertFalse(gate.admit(URLError(code), context: "market"))
        }
        XCTAssertFalse(CrashReportGate.isReportable(CancellationError()))
        // Being offline does not use up the context's one event.
        XCTAssertTrue(gate.admit(URLError(.badServerResponse), context: "market"))
    }
}
