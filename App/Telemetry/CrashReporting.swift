import Foundation
import Sentry

/// Crash and handled-error reporting (Task 14). Sentry sees crashes, app hangs and the load failures a page already
/// shows as LoadFailed — nothing else: no tracing, profiling, session replay, screenshots, view hierarchy, user,
/// IP, sessions, network or tap breadcrumbs. Off without a DSN (Debug builds and CI), in UI tests and under XCTest.
enum CrashReporting {
    private static let lock = NSLock()
    private static var started = false
    private static var gate = CrashReportGate()

    /// Called once from `ETFToGoApp.init`. The DSN comes from Info.plist `SentryDSN` (build setting `SENTRY_DSN`,
    /// set for Release only in project.yml).
    static func start(bundle: Bundle = .main, process: ProcessInfo = .processInfo) {
        #if DEBUG
        let debug = true
        #else
        let debug = false
        #endif
        guard let config = CrashReportingConfig.make(dsn: bundle.object(forInfoDictionaryKey: "SentryDSN") as? String,
                                                     arguments: process.arguments, environment: process.environment, debug: debug) else { return }
        lock.lock(); defer { lock.unlock() }
        guard !started else { return }
        SentrySDK.start(options: config.options())
        started = true
    }

    /// A load failure the user was shown (`context`: "catalog", "dividends", "market"). At most one event per context
    /// per launch. Nothing is sent while `offline` (the phone has no network, and errors then are often URLErrors
    /// wrapped in AppDataError text), nor for offline, timed-out and cancelled requests. Does nothing when Sentry is off.
    static func capture(_ error: Error, context: String, offline: Bool) {
        lock.lock()
        let send = started && gate.admit(error, context: context, offline: offline)
        lock.unlock()
        guard send else { return }
        SentrySDK.capture(error: error) { scope in scope.setTag(value: context, key: "load") }
    }
}

/// The options Sentry starts with, as plain values so tests read them without the SDK.
struct CrashReportingConfig: Equatable {
    var dsn: String
    var environment: String
    var sendDefaultPii = false
    var tracesSampleRate: Double? = nil
    var enableAutoPerformanceTracing = false
    var sessionReplaySampleRate: Float = 0
    var sessionReplayOnErrorSampleRate: Float = 0
    var enableAutoBreadcrumbTracking = true
    var enableUserInteractionTracing = false
    var enableNetworkBreadcrumbs = false
    var enableCaptureFailedRequests = false
    var attachScreenshot = false
    var attachViewHierarchy = false
    var enableAppHangTracking = true
    /// Release-health sessions and client reports are extra traffic beyond crashes and errors.
    var enableAutoSessionTracking = false
    var sendClientReports = false

    /// nil (Sentry stays off) when the DSN is missing, blank or not a DSN, with `--ui-testing`, or under XCTest.
    static func make(dsn: String?, arguments: [String], environment: [String: String], debug: Bool) -> CrashReportingConfig? {
        guard let dsn = dsn?.trimmingCharacters(in: .whitespacesAndNewlines), isDSN(dsn),
              !arguments.contains("--ui-testing"),
              environment["XCTestConfigurationFilePath"] == nil else { return nil }
        return CrashReportingConfig(dsn: dsn, environment: debug ? "debug" : "production")
    }

    /// `https://<key>@<host>/<project>`: an unexpanded `$(SENTRY_DSN)` or any other text is refused.
    static func isDSN(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme, ["https", "http"].contains(scheme),
              let user = url.user, !user.isEmpty, let host = url.host, !host.isEmpty else { return false }
        return url.path.count > 1
    }

    func options() -> Options {
        let options = Options()
        options.dsn = dsn
        options.environment = environment
        // Release stays the SDK default, <bundle id>@CFBundleShortVersionString+CFBundleVersion.
        options.sendDefaultPii = sendDefaultPii
        options.tracesSampleRate = tracesSampleRate.map { NSNumber(value: $0) }
        options.enableAutoPerformanceTracing = enableAutoPerformanceTracing
        options.sessionReplay.sessionSampleRate = sessionReplaySampleRate
        options.sessionReplay.onErrorSampleRate = sessionReplayOnErrorSampleRate
        options.enableAutoBreadcrumbTracking = enableAutoBreadcrumbTracking
        options.enableUserInteractionTracing = enableUserInteractionTracing
        options.enableNetworkBreadcrumbs = enableNetworkBreadcrumbs
        options.enableCaptureFailedRequests = enableCaptureFailedRequests
        options.attachScreenshot = attachScreenshot
        options.attachViewHierarchy = attachViewHierarchy
        options.enableAppHangTracking = enableAppHangTracking
        options.enableAutoSessionTracking = enableAutoSessionTracking
        options.sendClientReports = sendClientReports
        options.beforeSend = { event in CrashScrub.scrub(event) }
        return options
    }
}

/// Money never leaves the phone: every number with a comma or decimal point, and every plain number of six or
/// more digits, becomes `<n>`; the full-width comma counts. Four- and five-digit codes (0050, 00878) stay.
enum CrashScrub {
    private static let pattern = try! NSRegularExpression(pattern: #"\d+(?:[.,，]\d+)+|\d{6,}"#)

    static func scrub(_ text: String) -> String {
        pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "<n>")
    }

    /// The event message, exception values, mechanism descriptions and breadcrumb messages. The NSError user info
    /// (context "user info", mechanism data) is dropped whole: it can hold any text.
    static func scrub(_ event: Event) -> Event {
        // No user at all: the SDK fills user.userId with its installation UUID in prepareEvent, before beforeSend runs,
        // so sendDefaultPii = false alone does not keep it off the event.
        event.user = nil
        if let message = event.message { event.message = SentryMessage(formatted: scrub(message.formatted)) }
        event.exceptions?.forEach { exception in
            exception.value = scrub(exception.value)
            if let mechanism = exception.mechanism {
                if let desc = mechanism.desc { mechanism.desc = scrub(desc) }
                mechanism.data = nil
            }
        }
        event.context?.removeValue(forKey: "user info")
        event.breadcrumbs?.forEach { crumb in if let message = crumb.message { crumb.message = scrub(message) } }
        return event
    }
}

/// One event per context per launch; requests that failed for want of a connection are not errors worth sending.
struct CrashReportGate {
    private var sent: Set<String> = []

    /// True when this failure should be sent; a sent context is closed for the rest of the launch.
    /// `offline`: the phone has no network, so the failure is the connection whatever error carries it; it does not
    /// use up the context's event.
    mutating func admit(_ error: Error, context: String, offline: Bool = false) -> Bool {
        guard !offline, Self.isReportable(error), !sent.contains(context) else { return false }
        sent.insert(context)
        return true
    }

    static func isReportable(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let url = error as? URLError, [URLError.Code.notConnectedToInternet, .timedOut, .cancelled].contains(url.code) { return false }
        return true
    }
}
