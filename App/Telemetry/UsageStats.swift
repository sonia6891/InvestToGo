import Foundation
import StoreKit

// 產品工作站 (docs/superpowers/specs/2026-11-22-workstation-metrics-design.md): the owner's dashboard counts
// downloads, version use and retention from a few anonymous events, as meow-work and 額度雷達 (quotaradar) do. The client
// mirrors 額度雷達's (quotaradar-app src/core/workstation.ts):
//   first_open  the app was opened for the first time on this phone (downloads), once per install
//   daily_open  the app was opened on this local calendar day (version use, retention), once a day
// Each event carries only a random install id (made here, never tied to the Apple ID or anything personal), the
// platform, the region (the App Store storefront's country, else the phone's region) and the app version. Never
// holdings, amounts, trades, ETF lists or any record. 設定 › 隱私與安全 › 「傳送匿名使用統計」 turns it off: then nothing
// is queued or sent and the waiting events are cleared. Events wait in UserDefaults until the workstation answers, at
// most `UsageQueue.limit` of them; the workstation ignores an id it already has.

/// One event, as the workstation's `ingest_app_events` takes it.
struct UsageEvent: Codable, Equatable {
    var id: String
    var kind: String
    /// ISO 8601 time in UTC, with milliseconds (as JavaScript's toISOString).
    var at: String
    var iid: String
    var pf: String
    /// Two-letter region (TW, JP…); '' when unknown.
    var m: String
    var v: String

    static let platform = "ios"

    /// Once per install: the id is fixed, so a resend is the same event.
    static func firstOpen(iid: String, at date: Date, region: String, version: String) -> UsageEvent {
        UsageEvent(id: "\(iid):first_open", kind: "first_open", at: UsageClock.iso(date), iid: iid, pf: platform, m: region, v: version)
    }

    /// Once per local calendar day (`day` is `UsageClock.day`).
    static func dailyOpen(iid: String, day: String, at date: Date, region: String, version: String) -> UsageEvent {
        UsageEvent(id: "\(iid):daily_open:\(day)", kind: "daily_open", at: UsageClock.iso(date), iid: iid, pf: platform, m: region, v: version)
    }
}

/// Times and days, always Gregorian with ASCII digits whatever the phone's calendar and language.
enum UsageClock {
    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// The local calendar day, `yyyy-MM-dd`.
    static func day(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// The app version as the workstation shows it: `CFBundleShortVersionString(CFBundleVersion)`, e.g. `1.0(1)`.
enum UsageVersion {
    static func string(info: [String: Any]?) -> String {
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(short)(\(build))"
    }
}

/// The waiting events and what the workstation's answer does to them.
enum UsageQueue {
    static let limit = 50
    /// Answers that mean "these events will never be accepted": they are dropped so they do not block newer ones.
    static let refused: Set<Int> = [400, 413, 422]

    /// Adds an event unless one with its id is waiting already (the new one replaces it); keeps the newest `limit`.
    static func enqueue(_ queue: [UsageEvent], _ event: UsageEvent) -> [UsageEvent] {
        var next = queue.filter { $0.id != event.id }
        next.append(event)
        return Array(next.suffix(limit))
    }

    /// True when the sent events leave the queue: 2xx (stored, or already there) or refused. Anything else (no
    /// answer, offline, 401/403, 404 before the server side exists, 429, 5xx) keeps them for the next try.
    static func leavesQueue(status: Int?) -> Bool {
        guard let status else { return false }
        return (200..<300).contains(status) || refused.contains(status)
    }
}

/// The random install id: a lowercase UUID v4 made once and kept in this phone's UserDefaults. It is not part of the
/// app's own backup file (the records' JSON) and is never derived from anything about the phone or the person. It is
/// also the subscription's `appAccountToken` (only a random number Apple echoes back in its notifications), so it is
/// made even with the switch off.
enum UsageInstall {
    static let key = "usageStats.installID"
    private static let lock = NSLock()

    static func id(defaults: UserDefaults = .standard) -> String {
        lock.lock(); defer { lock.unlock() }
        if let saved = defaults.string(forKey: key), isValid(saved) { return saved }
        let made = UUID().uuidString.lowercased()
        defaults.set(made, forKey: key)
        return made
    }

    /// A lowercase UUID version 4 (RFC 4122 variant).
    static func isValid(_ text: String) -> Bool {
        text.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#, options: .regularExpression) != nil
    }

    /// What a subscription purchase passes to StoreKit: the install id as the app account token.
    static func purchaseOptions(defaults: UserDefaults = .standard) -> Set<Product.PurchaseOption> {
        guard let token = UUID(uuidString: id(defaults: defaults)) else { return [] }
        return [.appAccountToken(token)]
    }
}

/// Whether this process may report at all: never in UI tests, in the unit-test host or in Xcode previews.
enum UsageGate {
    static func allowed(arguments: [String], environment: [String: String]) -> Bool {
        !arguments.contains("--ui-testing")
            && environment["XCTestConfigurationFilePath"] == nil
            && environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1"
    }
}

/// The two-letter region: the App Store storefront's country (StoreKit gives ISO 3166-1 alpha-3), else the phone's
/// region, else ''.
enum UsageRegion {
    static func resolve(storefront: String?, phone: String?) -> String {
        if let storefront, let code = alpha2(storefront) { return code }
        if let phone, isAlpha2(phone.uppercased()) { return phone.uppercased() }
        return ""
    }

    /// An alpha-3 (TWN) or alpha-2 (TW) code as alpha-2; nil for anything else.
    static func alpha2(_ code: String) -> String? {
        let upper = code.uppercased()
        if isAlpha2(upper) { return upper }
        return table[upper]
    }

    private static func isAlpha2(_ text: String) -> Bool {
        text.utf8.count == 2 && text.utf8.allSatisfy { (0x41...0x5A).contains($0) }
    }

    /// ISO 3166-1 alpha-3 → alpha-2, with Kosovo (XKS, the App Store's code) as XK.
    static let table: [String: String] = {
        let pairs = """
        AFG AF ALA AX ALB AL DZA DZ ASM AS AND AD AGO AO AIA AI ATA AQ ATG AG ARG AR ARM AM ABW AW AUS AU AUT AT AZE AZ \
        BHS BS BHR BH BGD BD BRB BB BLR BY BEL BE BLZ BZ BEN BJ BMU BM BTN BT BOL BO BES BQ BIH BA BWA BW BVT BV BRA BR \
        IOT IO BRN BN BGR BG BFA BF BDI BI CPV CV KHM KH CMR CM CAN CA CYM KY CAF CF TCD TD CHL CL CHN CN CXR CX CCK CC \
        COL CO COM KM COG CG COD CD COK CK CRI CR CIV CI HRV HR CUB CU CUW CW CYP CY CZE CZ DNK DK DJI DJ DMA DM DOM DO \
        ECU EC EGY EG SLV SV GNQ GQ ERI ER EST EE SWZ SZ ETH ET FLK FK FRO FO FJI FJ FIN FI FRA FR GUF GF PYF PF ATF TF \
        GAB GA GMB GM GEO GE DEU DE GHA GH GIB GI GRC GR GRL GL GRD GD GLP GP GUM GU GTM GT GGY GG GIN GN GNB GW GUY GY \
        HTI HT HMD HM VAT VA HND HN HKG HK HUN HU ISL IS IND IN IDN ID IRN IR IRQ IQ IRL IE IMN IM ISR IL ITA IT JAM JM \
        JPN JP JEY JE JOR JO KAZ KZ KEN KE KIR KI PRK KP KOR KR KWT KW KGZ KG LAO LA LVA LV LBN LB LSO LS LBR LR LBY LY \
        LIE LI LTU LT LUX LU MAC MO MDG MG MWI MW MYS MY MDV MV MLI ML MLT MT MHL MH MTQ MQ MRT MR MUS MU MYT YT MEX MX \
        FSM FM MDA MD MCO MC MNG MN MNE ME MSR MS MAR MA MOZ MZ MMR MM NAM NA NRU NR NPL NP NLD NL NCL NC NZL NZ NIC NI \
        NER NE NGA NG NIU NU NFK NF MKD MK MNP MP NOR NO OMN OM PAK PK PLW PW PSE PS PAN PA PNG PG PRY PY PER PE PHL PH \
        PCN PN POL PL PRT PT PRI PR QAT QA REU RE ROU RO RUS RU RWA RW BLM BL SHN SH KNA KN LCA LC MAF MF SPM PM VCT VC \
        WSM WS SMR SM STP ST SAU SA SEN SN SRB RS SYC SC SLE SL SGP SG SXM SX SVK SK SVN SI SLB SB SOM SO ZAF ZA SGS GS \
        SSD SS ESP ES LKA LK SDN SD SUR SR SJM SJ SWE SE CHE CH SYR SY TWN TW TJK TJ TZA TZ THA TH TLS TL TGO TG TKL TK \
        TON TO TTO TT TUN TN TUR TR TKM TM TCA TC TUV TV UGA UG UKR UA ARE AE GBR GB USA US UMI UM URY UY UZB UZ VUT VU \
        VEN VE VNM VN VGB VG VIR VI WLF WF ESH EH YEM YE ZMB ZM ZWE ZW XKS XK
        """
        let words = pairs.split(separator: " ").map(String.init)
        var table: [String: String] = [:]
        for index in stride(from: 0, to: words.count - 1, by: 2) { table[words[index]] = words[index + 1] }
        return table
    }()

    /// The storefront's country, waiting at most two seconds for StoreKit.
    static func storefront() async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await Storefront.current?.countryCode }
            group.addTask { try? await Task.sleep(for: .seconds(2)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    static func current() async -> String {
        resolve(storefront: await storefront(), phone: Locale.current.region?.identifier)
    }
}

/// Sends a batch; returns the HTTP status, or nil when there was no answer.
protocol UsageTransport: Sendable {
    func send(_ body: Data) async -> Int?
}

/// The workstation's ingest function, over an ephemeral URLSession (no cookies, no cache).
struct WorkstationTransport: UsageTransport {
    static let url = URL(string: "https://bpovoxjdqdwhhlfwgpep.supabase.co/rest/v1/rpc/ingest_app_events")!
    /// The workstation's public (anon) key: it can only call the ingest functions, never read anything.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJwb3ZveGpkcWR3aGhsZndncGVwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQzNjE1NTQsImV4cCI6MjEwOTkzNzU1NH0.gM51zQ_K3O-N4SsnP_B1JKNXSM3WSimLiyzXV-pcsxs"
    private static let session = URLSession(configuration: .ephemeral)

    static func request(_ body: Data) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        return request
    }

    func send(_ body: Data) async -> Int? {
        do {
            let (_, response) = try await Self.session.data(for: Self.request(body))
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }
}

/// Queues and sends the events. Every dependency is injected, so tests never touch the network, the real defaults or
/// the clock.
actor UsageReporter {
    /// 投資袋著走's product id in the workstation.
    static let productID = "94265929d4b69a431c5a"
    static let enabledKey = "usageStats.on"
    static let firstOpenKey = "usageStats.firstOpenQueued"
    static let dailyKey = "usageStats.lastDailyDay"
    static let queueKey = "usageStats.queue"

    static let shared = UsageReporter(
        defaults: .standard, transport: WorkstationTransport(),
        allowed: UsageGate.allowed(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment),
        version: UsageVersion.string(info: Bundle.main.infoDictionary),
        now: { Date() }, timeZone: { TimeZone.current }, region: { await UsageRegion.current() })

    private let defaults: UserDefaults
    private let transport: UsageTransport
    private let allowed: Bool
    private let version: String
    private let now: @Sendable () -> Date
    private let timeZone: @Sendable () -> TimeZone
    private let region: @Sendable () async -> String
    private var flushing = false

    init(defaults: UserDefaults, transport: UsageTransport, allowed: Bool, version: String,
         now: @escaping @Sendable () -> Date, timeZone: @escaping @Sendable () -> TimeZone,
         region: @escaping @Sendable () async -> String) {
        self.defaults = defaults
        self.transport = transport
        self.allowed = allowed
        self.version = version
        self.now = now
        self.timeZone = timeZone
        self.region = region
    }

    /// 「傳送匿名使用統計」: on unless turned off.
    static func isEnabled(_ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    /// The events waiting to be sent, oldest first.
    var queue: [UsageEvent] {
        defaults.data(forKey: Self.queueKey).flatMap { try? JSONDecoder().decode([UsageEvent].self, from: $0) } ?? []
    }

    private func save(_ queue: [UsageEvent]) {
        if queue.isEmpty { defaults.removeObject(forKey: Self.queueKey) } else { defaults.set(try? JSONEncoder().encode(queue), forKey: Self.queueKey) }
    }

    /// The app is open (launch, or back to the front): first_open once per install, daily_open once a local day, then
    /// what is waiting is sent. With the switch off, the waiting events are cleared and nothing is sent.
    func appOpened() async {
        guard allowed else { return }
        guard Self.isEnabled(defaults) else { save([]); return }
        let date = now()
        let day = UsageClock.day(date, timeZone: timeZone())
        let needFirst = !defaults.bool(forKey: Self.firstOpenKey)
        let needDaily = defaults.string(forKey: Self.dailyKey) != day
        if needFirst || needDaily {
            let iid = UsageInstall.id(defaults: defaults)
            let m = await region()
            // The switch may have been turned off while the region was read.
            guard Self.isEnabled(defaults) else { save([]); return }
            var next = queue
            if needFirst { next = UsageQueue.enqueue(next, .firstOpen(iid: iid, at: date, region: m, version: version)) }
            if needDaily { next = UsageQueue.enqueue(next, .dailyOpen(iid: iid, day: day, at: date, region: m, version: version)) }
            save(next)
            if needFirst { defaults.set(true, forKey: Self.firstOpenKey) }
            if needDaily { defaults.set(day, forKey: Self.dailyKey) }
        }
        await flush()
    }

    /// The switch was turned off: the waiting events are cleared. Turned on: today's open is reported.
    func switched(on: Bool) async {
        defaults.set(on, forKey: Self.enabledKey)
        if on { await appOpened() } else { save([]) }
    }

    /// Sends what is waiting; the events the workstation accepted (or refused for good) leave the queue.
    func flush() async {
        guard allowed, Self.isEnabled(defaults), !flushing else { return }
        let batch = queue
        guard !batch.isEmpty, let body = try? Self.payload(batch) else { return }
        flushing = true
        defer { flushing = false }
        let status = await transport.send(body)
        if UsageQueue.leavesQueue(status: status) {
            let sent = Set(batch.map(\.id))
            save(queue.filter { !sent.contains($0.id) })
        }
    }

    static func payload(_ events: [UsageEvent]) throws -> Data {
        struct Body: Encodable { let p_product: String; let p_events: [UsageEvent] }
        return try JSONEncoder().encode(Body(p_product: productID, p_events: events))
    }
}

/// The app's one entry point: called when the app is in front past the opening and the lock. Never on the main
/// actor's time: the work runs in the background and never blocks the screen.
enum UsageStats {
    static func appOpened() {
        Task.detached(priority: .utility) { await UsageReporter.shared.appOpened() }
    }

    static func switched(on: Bool) {
        Task.detached(priority: .utility) { await UsageReporter.shared.switched(on: on) }
    }
}
