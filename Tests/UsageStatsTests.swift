import XCTest
import StoreKit
@testable import ETFToGo

/// 產品工作站 (docs/superpowers/specs/2026-11-22-workstation-metrics-design.md): the anonymous events, the once-a-day
/// rule, the queue and the server's answers, the switch and the UI-test gate, the install id and the purchase token.
/// The clock, the defaults and the transport are injected: nothing here touches the network.
final class UsageStatsTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private let taipei = TimeZone(identifier: "Asia/Taipei")!

    override func setUp() {
        super.setUp()
        suite = "ETFToGo.tests.usage.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    /// 2026-11-22 11:04:05.125 in Taipei.
    private let noon = Date(timeIntervalSince1970: 1_795_316_645.125)

    private func reporter(_ transport: FakeTransport, clock: TestClock, allowed: Bool = true, region: String = "TW") -> UsageReporter {
        UsageReporter(defaults: defaults, transport: transport, allowed: allowed, version: "1.0(7)",
                      now: { clock.date }, timeZone: { [taipei] in taipei }, region: { region })
    }

    // MARK: Events

    func testEventsCarryTheContractFields() {
        let iid = "0f8e2c1a-3b4d-4e5f-8a9b-0c1d2e3f4a5b"
        let first = UsageEvent.firstOpen(iid: iid, at: noon, region: "TW", version: "1.0(7)")
        XCTAssertEqual(first, UsageEvent(id: "\(iid):first_open", kind: "first_open", at: "2026-11-22T03:04:05.125Z",
                                         iid: iid, pf: "ios", m: "TW", v: "1.0(7)"))
        let daily = UsageEvent.dailyOpen(iid: iid, day: "2026-11-22", at: noon, region: "", version: "1.0(7)")
        XCTAssertEqual(daily.id, "\(iid):daily_open:2026-11-22")
        XCTAssertEqual(daily.kind, "daily_open")
        XCTAssertEqual(daily.m, "", "An unknown region is sent empty")
    }

    func testVersionIsShortVersionWithTheBuildInBrackets() {
        XCTAssertEqual(UsageVersion.string(info: ["CFBundleShortVersionString": "1.2", "CFBundleVersion": "34"]), "1.2(34)")
        XCTAssertEqual(UsageVersion.string(info: nil), "()")
        let app = UsageVersion.string(info: Bundle.main.infoDictionary)
        XCTAssertTrue(app.range(of: #"^[0-9.]+\([0-9]+\)$"#, options: .regularExpression) != nil, app)
    }

    func testTheDayIsGregorianWithPlainDigitsInLocalTime() {
        XCTAssertEqual(UsageClock.day(noon, timeZone: taipei), "2026-11-22")
        // 23:59:59 and 00:00:00 in Taipei.
        XCTAssertEqual(UsageClock.day(Date(timeIntervalSince1970: 1_795_363_199), timeZone: taipei), "2026-11-22")
        XCTAssertEqual(UsageClock.day(Date(timeIntervalSince1970: 1_795_363_200), timeZone: taipei), "2026-11-23")
        XCTAssertEqual(UsageClock.day(Date(timeIntervalSince1970: 1_795_363_200), timeZone: TimeZone(identifier: "UTC")!), "2026-11-22")
        for text in [UsageClock.day(noon, timeZone: taipei), UsageClock.iso(noon)] {
            XCTAssertTrue(text.unicodeScalars.allSatisfy(\.isASCII), "No Arabic, Persian or other digits: \(text)")
        }
    }

    // MARK: Once per install, once a day

    func testFirstOpenAndDailyOpenGoOutOnTheFirstLaunch() async throws {
        let transport = FakeTransport(), clock = TestClock(noon)
        await reporter(transport, clock: clock).appOpened()
        let events = transport.events
        XCTAssertEqual(events.map(\.kind), ["first_open", "daily_open"])
        let iid = UsageInstall.id(defaults: defaults)
        XCTAssertEqual(events.map(\.id), ["\(iid):first_open", "\(iid):daily_open:2026-11-22"])
        XCTAssertTrue(events.allSatisfy { $0.iid == iid && $0.pf == "ios" && $0.m == "TW" && $0.v == "1.0(7)" })
        let queue = await reporter(transport, clock: clock).queue
        XCTAssertTrue(queue.isEmpty, "Accepted events leave the queue")
    }

    func testDailyOpenAtMostOncePerLocalDay() async {
        let transport = FakeTransport(), clock = TestClock(noon)
        let usage = reporter(transport, clock: clock)
        await usage.appOpened()
        clock.date = noon.addingTimeInterval(3600)
        await usage.appOpened()
        // 23:59:59 the same day, after a relaunch.
        clock.date = Date(timeIntervalSince1970: 1_795_363_199)
        await reporter(transport, clock: clock).appOpened()
        XCTAssertEqual(transport.events.filter { $0.kind == "daily_open" }.count, 1, "One daily_open a local day")
        XCTAssertEqual(transport.bodies.count, 1, "Nothing new to send, nothing sent")
        // Midnight in Taipei: a new day.
        clock.date = Date(timeIntervalSince1970: 1_795_363_200)
        await usage.appOpened()
        XCTAssertEqual(transport.events.filter { $0.kind == "daily_open" }.map { String($0.id.suffix(10)) }, ["2026-11-22", "2026-11-23"])
    }

    func testFirstOpenOnlyOncePerInstall() async {
        let transport = FakeTransport(), clock = TestClock(noon)
        await reporter(transport, clock: clock).appOpened()
        for day in 1...3 {
            clock.date = noon.addingTimeInterval(Double(day) * 86_400)
            await reporter(transport, clock: clock).appOpened()
        }
        XCTAssertEqual(transport.events.filter { $0.kind == "first_open" }.count, 1)
        XCTAssertEqual(transport.events.filter { $0.kind == "daily_open" }.count, 4)
    }

    // MARK: Queue and answers

    func testTheQueueKeepsTheNewestFiftyAndOneOfEachID() {
        var queue: [UsageEvent] = []
        for n in 0..<60 { queue = UsageQueue.enqueue(queue, event("e\(n)")) }
        XCTAssertEqual(queue.count, 50)
        XCTAssertEqual(queue.first?.id, "e10")
        XCTAssertEqual(queue.last?.id, "e59")
        queue = UsageQueue.enqueue(queue, event("e30"))
        XCTAssertEqual(queue.count, 50)
        XCTAssertEqual(queue.filter { $0.id == "e30" }.count, 1, "A waiting id is not queued twice")
        XCTAssertEqual(queue.last?.id, "e30")
    }

    func testRefusedAnswersDropAndOthersKeep() {
        for status in [200, 201, 204, 400, 413, 422] { XCTAssertTrue(UsageQueue.leavesQueue(status: status), "\(status)") }
        for status in [nil, 401, 403, 404, 408, 429, 500, 502, 503] as [Int?] {
            XCTAssertFalse(UsageQueue.leavesQueue(status: status), "\(String(describing: status))")
        }
    }

    func testFailedSendsWaitAndGoOutNextTime() async {
        let transport = FakeTransport(), clock = TestClock(noon)
        transport.answers = [503, nil]
        let usage = reporter(transport, clock: clock)
        await usage.appOpened()
        var queue = await usage.queue
        XCTAssertEqual(queue.count, 2, "A 503 keeps the events")
        await usage.flush()
        queue = await usage.queue
        XCTAssertEqual(queue.count, 2, "No answer (offline) keeps them")
        await usage.flush()
        queue = await usage.queue
        XCTAssertTrue(queue.isEmpty, "Accepted on the third try")
        XCTAssertEqual(transport.bodies.count, 3)
    }

    func testRefusedEventsAreDropped() async {
        for status in [400, 413, 422] {
            let transport = FakeTransport(), clock = TestClock(noon)
            transport.answers = [status]
            defaults.removePersistentDomain(forName: suite)
            let usage = reporter(transport, clock: clock)
            await usage.appOpened()
            let queue = await usage.queue
            XCTAssertTrue(queue.isEmpty, "\(status) drops the batch")
        }
    }

    func testTheQueueNeverPassesFiftyWhileOffline() async {
        let transport = FakeTransport(), clock = TestClock(noon)
        transport.answers = Array(repeating: nil, count: 80)
        let usage = reporter(transport, clock: clock)
        for day in 0..<70 {
            clock.date = noon.addingTimeInterval(Double(day) * 86_400)
            await usage.appOpened()
        }
        let queue = await usage.queue
        XCTAssertEqual(queue.count, 50)
        XCTAssertEqual(queue.last?.id.hasSuffix(UsageClock.day(clock.date, timeZone: taipei)), true, "The newest are kept")
        XCTAssertLessThanOrEqual(transport.bodyEvents.map(\.count).max() ?? 0, 50)
    }

    func testThePayloadIsTheWorkstationContract() throws {
        let body = try UsageReporter.payload([event("a"), event("b")])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["p_product", "p_events"])
        XCTAssertEqual(json["p_product"] as? String, "94265929d4b69a431c5a")
        let events = try XCTUnwrap(json["p_events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(Set(events[0].keys), ["id", "kind", "at", "iid", "pf", "m", "v"], "Nothing else ever leaves the phone")
    }

    func testTheRequestCarriesTheAnonKey() {
        let request = WorkstationTransport.request(Data("{}".utf8))
        XCTAssertEqual(request.url?.absoluteString, "https://bpovoxjdqdwhhlfwgpep.supabase.co/rest/v1/rpc/ingest_app_events")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), WorkstationTransport.anonKey)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(WorkstationTransport.anonKey)")
        XCTAssertEqual(request.timeoutInterval, 10)
    }

    // MARK: The switch and the gate

    func testNothingIsQueuedOrSentWithTheSwitchOff() async {
        let transport = FakeTransport(), clock = TestClock(noon)
        transport.answers = [nil]
        let usage = reporter(transport, clock: clock)
        XCTAssertTrue(UsageReporter.isEnabled(defaults), "On by default")
        await usage.appOpened()
        var queue = await usage.queue
        XCTAssertEqual(queue.count, 2, "Waiting after an offline try")
        await usage.switched(on: false)
        XCTAssertFalse(UsageReporter.isEnabled(defaults))
        queue = await usage.queue
        XCTAssertTrue(queue.isEmpty, "Turning it off clears the queue")
        clock.date = noon.addingTimeInterval(86_400)
        await usage.appOpened()
        await usage.flush()
        queue = await usage.queue
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(transport.bodies.count, 1, "Nothing sent after it was turned off")
    }

    func testTurningItBackOnReportsToday() async {
        let transport = FakeTransport(), clock = TestClock(noon)
        defaults.set(false, forKey: UsageReporter.enabledKey)
        let usage = reporter(transport, clock: clock)
        await usage.appOpened()
        XCTAssertTrue(transport.bodies.isEmpty)
        await usage.switched(on: true)
        XCTAssertEqual(transport.events.map(\.kind), ["first_open", "daily_open"])
    }

    func testNeverUnderUITestsTheTestHostOrPreviews() async {
        XCTAssertTrue(UsageGate.allowed(arguments: ["ETFToGo"], environment: [:]))
        XCTAssertFalse(UsageGate.allowed(arguments: ["ETFToGo", "--ui-testing"], environment: [:]))
        XCTAssertFalse(UsageGate.allowed(arguments: [], environment: ["XCTestConfigurationFilePath": "/x.xctestconfiguration"]))
        XCTAssertFalse(UsageGate.allowed(arguments: [], environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"]))
        // This process is the unit-test host: the shared reporter is off.
        XCTAssertFalse(UsageGate.allowed(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment))
        let transport = FakeTransport(), clock = TestClock(noon)
        let usage = reporter(transport, clock: clock, allowed: false)
        await usage.appOpened()
        await usage.flush()
        let queue = await usage.queue
        XCTAssertTrue(queue.isEmpty)
        XCTAssertTrue(transport.bodies.isEmpty)
        XCTAssertNil(defaults.string(forKey: UsageInstall.key), "Not even an install id is made")
    }

    // MARK: Install id and purchase token

    func testTheInstallIDIsAStableLowercaseUUIDv4() {
        let iid = UsageInstall.id(defaults: defaults)
        XCTAssertTrue(UsageInstall.isValid(iid), iid)
        XCTAssertEqual(iid, iid.lowercased())
        XCTAssertEqual(UsageInstall.id(defaults: defaults), iid, "Made once, then kept")
        let other = UserDefaults(suiteName: suite + ".other")!
        defer { other.removePersistentDomain(forName: suite + ".other") }
        XCTAssertNotEqual(UsageInstall.id(defaults: other), iid, "Random per install")
        XCTAssertFalse(UsageInstall.isValid("0F8E2C1A-3B4D-4E5F-8A9B-0C1D2E3F4A5B"), "Uppercase is not the form sent")
        XCTAssertFalse(UsageInstall.isValid("0f8e2c1a-3b4d-1e5f-8a9b-0c1d2e3f4a5b"), "Version 1 is not v4")
        defaults.set("not-a-uuid", forKey: UsageInstall.key)
        XCTAssertTrue(UsageInstall.isValid(UsageInstall.id(defaults: defaults)), "A damaged id is made again")
    }

    func testTheInstallIDStaysOutOfTheAppBackup() throws {
        let iid = UsageInstall.id(defaults: .standard)
        let backup = String(decoding: try JSONEncoder().encode(Portfolio()), as: UTF8.self)
        XCTAssertFalse(backup.contains(iid))
        XCTAssertFalse(backup.contains("usageStats"))
    }

    func testTheAppAccountTokenIsTheInstallID() throws {
        let iid = UsageInstall.id(defaults: defaults)
        let token = try XCTUnwrap(UUID(uuidString: iid))
        XCTAssertEqual(UsageInstall.purchaseOptions(defaults: defaults), [Product.PurchaseOption.appAccountToken(token)])
        XCTAssertEqual(token.uuidString.lowercased(), iid)
        // Also with the switch off: it is only a random number Apple echoes back.
        defaults.set(false, forKey: UsageReporter.enabledKey)
        XCTAssertEqual(UsageInstall.purchaseOptions(defaults: defaults), [Product.PurchaseOption.appAccountToken(token)])
    }

    // MARK: Region

    func testTheRegionIsTwoLettersFromTheStorefrontElseThePhone() {
        XCTAssertEqual(UsageRegion.resolve(storefront: "TWN", phone: "JP"), "TW")
        XCTAssertEqual(UsageRegion.resolve(storefront: "usa", phone: nil), "US")
        XCTAssertEqual(UsageRegion.resolve(storefront: nil, phone: "jp"), "JP")
        XCTAssertEqual(UsageRegion.resolve(storefront: "???", phone: "HK"), "HK")
        XCTAssertEqual(UsageRegion.resolve(storefront: nil, phone: "419"), "", "A numeric region is not a country")
        XCTAssertEqual(UsageRegion.resolve(storefront: nil, phone: nil), "")
        for (three, two) in [("JPN", "JP"), ("HKG", "HK"), ("GBR", "GB"), ("KOR", "KR"), ("CHN", "CN"), ("SGP", "SG"), ("MYS", "MY"), ("MAC", "MO"), ("XKS", "XK")] {
            XCTAssertEqual(UsageRegion.alpha2(three), two, three)
        }
    }

    func testTheCountryTableIsWellFormed() {
        let table = UsageRegion.table
        XCTAssertGreaterThanOrEqual(table.count, 250)
        XCTAssertEqual(Set(table.values).count, table.count, "Every alpha-2 appears once")
        let iso = Set(Locale.Region.isoRegions.map(\.identifier))
        for (three, two) in table {
            XCTAssertTrue(three.count == 3 && three == three.uppercased(), three)
            if two != "XK" { XCTAssertTrue(iso.contains(two), "\(three) → \(two) is an ISO region") }
        }
    }

    private func event(_ id: String) -> UsageEvent {
        UsageEvent(id: id, kind: "daily_open", at: "2026-11-22T03:04:05.125Z", iid: "x", pf: "ios", m: "TW", v: "1.0(7)")
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ date: Date) { value = date }
    var date: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

/// Records each body; answers 200 unless told otherwise (`answers`, in order; nil is no answer).
final class FakeTransport: UsageTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [Data] = []
    private var queued: [Int?] = []

    var answers: [Int?] {
        get { lock.withLock { queued } }
        set { lock.withLock { queued = newValue } }
    }
    var bodies: [Data] { lock.withLock { sent } }

    func send(_ body: Data) async -> Int? {
        lock.withLock {
            sent.append(body)
            return queued.isEmpty ? 200 : queued.removeFirst()
        }
    }

    /// The events of each body, in order.
    var bodyEvents: [[UsageEvent]] {
        struct Body: Decodable { let p_events: [UsageEvent] }
        return bodies.compactMap { try? JSONDecoder().decode(Body.self, from: $0).p_events }
    }

    /// Every event that was sent, once per id (a retry sends the same event again).
    var events: [UsageEvent] {
        var seen = Set<String>(), out: [UsageEvent] = []
        for event in bodyEvents.joined() where seen.insert(event.id).inserted { out.append(event) }
        return out
    }
}
