import Foundation

/// The network behind `HoldingsClient`; tests inject a fake.
protocol HoldingsTransport: Sendable {
    func get(_ url: URL) async throws -> Data
    /// POST with a JSON body, or with no body at all (`json` nil).
    func post(_ url: URL, json: Data?) async throws -> Data
}

struct PublicHoldingsTransport: HoldingsTransport {
    func get(_ url: URL) async throws -> Data { try await PublicHTTP.get(url, accept: "*/*") }
    func post(_ url: URL, json: Data?) async throws -> Data { try await PublicHTTP.post(url, json: json) }
}

/// An ETF's holdings (成分股與權重). The fund company's own public page comes first (元大, 國泰, 富邦, 群益, 復華, 中信,
/// told apart by the fund's name); 富果 when a key is saved and the company is not one of the six or its page fails.
/// Requests carry only the ETF code, the company's own id for it and a date. One download per ETF per Taipei day:
/// after that the copy on the phone is returned.
actor HoldingsClient {
    static let shared = HoldingsClient()

    /// Thrown when the fund is not from one of the six companies and no 富果 key is saved.
    static let unsupported = "這家投信暫不支援"
    /// Thrown when the company's page could not be read (and 富果 could not step in).
    static let unavailable = "暫時取不到，稍後再試"

    /// What was downloaded, and on which Taipei day.
    private struct Kept: Codable { var day: String; var snapshot: ComponentSnapshot }

    private static let lookupLife: TimeInterval = 30 * 86_400

    private let transport: HoldingsTransport
    private let root: URL
    private let defaults: UserDefaults
    private let minInterval: TimeInterval
    private let clock: @Sendable () -> Date
    private let fugleKeySaved: @Sendable () -> Bool
    private let fugle: @Sendable (String) async throws -> ComponentSnapshot
    private let report: @Sendable (Error, Issuer) async -> Void
    /// Downloads under way, by ETF code: a second caller waits for the first one's answer.
    private var running: [String: Task<ComponentSnapshot, Error>] = [:]
    /// When the next request may start.
    private var nextSlot = Date.distantPast

    /// `report` gets a fund company's failure; the default sends it to the load-failure reporter under the company's
    /// name alone (never the ETF, never the holdings).
    init(transport: HoldingsTransport = PublicHoldingsTransport(), root: URL? = nil, defaults: UserDefaults = .standard,
         minInterval: TimeInterval = 0.5, clock: @escaping @Sendable () -> Date = { Date() },
         fugleKeySaved: @escaping @Sendable () -> Bool = { !((try? SecureKey.read()) ?? "").isEmpty },
         fugle: @escaping @Sendable (String) async throws -> ComponentSnapshot = { try await Fugle.components(symbol: $0) },
         report: @escaping @Sendable (Error, Issuer) async -> Void = { error, issuer in
             let offline = await MainActor.run { Connectivity.shared.offline }
             CrashReporting.capture(error, context: "holdings:\(issuer.rawValue)", offline: offline)
         }) {
        self.transport = transport
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("holdings", isDirectory: true)
        self.defaults = defaults
        self.minInterval = minInterval
        self.clock = clock
        self.fugleKeySaved = fugleKeySaved
        self.fugle = fugle
        self.report = report
    }

    /// The holdings of `symbol`. `fundName` is the fund's short name from the ETF list (「元大台灣50」,
    /// 「主動群益台灣強棒」): it tells which company to ask.
    func components(symbol: String, fundName: String) async throws -> ComponentSnapshot {
        guard DataChecks.code(symbol) else { throw AppDataError("ETF 代號格式不符。") }
        let today = DataChecks.day(clock())
        if let kept = kept(symbol), kept.day == today { return kept.snapshot }
        if let task = running[symbol] { return try await task.value }
        let task = Task { try await self.load(symbol: symbol, fundName: fundName, today: today) }
        running[symbol] = task
        defer { running[symbol] = nil }
        return try await task.value
    }

    private func load(symbol: String, fundName: String, today: String) async throws -> ComponentSnapshot {
        let issuer = IssuerDirectory.issuer(forFundName: fundName)
        let hasKey = fugleKeySaved()
        let snapshot: ComponentSnapshot
        if let issuer {
            do {
                snapshot = try await chain(issuer, symbol)
            } catch {
                if error is CancellationError { throw error }
                // The saved id may have gone stale; the next try asks the company for it again.
                defaults.removeObject(forKey: Self.lookupKey(issuer, symbol))
                await report(error, issuer)
                guard hasKey, let rescued = try? await fugle(symbol) else { throw AppDataError(Self.unavailable) }
                snapshot = rescued
            }
        } else if hasKey {
            // 富果's own messages (金鑰無效, 方案沒有權限…) say more than 暫時取不到, so they pass through.
            snapshot = try await fugle(symbol)
        } else {
            throw AppDataError(Self.unsupported)
        }
        guard snapshot.symbol == symbol else { throw AppDataError(Self.unavailable) }
        keep(Kept(day: today, snapshot: snapshot), symbol: symbol)
        return snapshot
    }

    // MARK: The six companies

    /// One company's requests, in the order its own site makes them.
    private func chain(_ issuer: Issuer, _ symbol: String) async throws -> ComponentSnapshot {
        switch issuer {
        case .yuanta:
            let body = try await get("https://etfapi.yuantaetfs.com/ectranslation/api/bridge?APIType=ETFAPI&FuncId=PCF/Daily&ticker=\(symbol)")
            return try IssuerHoldings.yuanta(body, symbol: symbol)

        case .cathay:
            let api = "https://cwapi.cathaysite.com.tw/api/ETF/"
            let code = try await lookup(issuer, symbol) {
                IssuerHoldings.cathayFundCode(try await self.get(api + "GetETFList?Keyword=\(symbol)"), symbol: symbol)
            }
            let fund = Self.escaped(code)
            // The holdings list has no date of its own: the fund's latest day is asked for first.
            guard let day = IssuerHoldings.cathayAssetsDate(try await get(api + "GetETFAssets?FundCode=\(fund)")) else {
                throw AppDataError("國泰投信持股資料格式不符（缺少資料日期）")
            }
            let body = try await get(api + "GetETFDetailStockList?FundCode=\(fund)&SearchDate=\(day)")
            return try IssuerHoldings.cathay(body, symbol: symbol, date: day)

        case .fubon:
            let body = try await get("https://websys.fsit.com.tw/FubonETF/Fund/Assets.aspx?stkId=\(symbol)")
            return try IssuerHoldings.fubon(Self.page(body), symbol: symbol)

        case .capital:
            let api = "https://www.capitalfund.com.tw/CFWeb/api/etf/"
            let fundNo = try await lookup(issuer, symbol) {
                IssuerHoldings.capitalFundNo(try await self.post(api + "items", nil), symbol: symbol)
            }
            let body = try await post(api + "buyback", ["fundId": fundNo, "date": NSNull()])
            return try IssuerHoldings.capital(body, symbol: symbol)

        case .fhtrust:
            let id = try await lookup(issuer, symbol) {
                IssuerHoldings.fhtrustFundID(Self.page(try await self.get("https://www.fhtrust.com.tw/ETF/etf_list")), symbol: symbol)
            }
            let fund = Self.escaped(id)
            // The date keeps its slashes: qDate=2026/11/13.
            return try await newestDay({ day in try await self.get("https://www.fhtrust.com.tw/api/assets?fundID=\(fund)&qDate=\(day)") },
                                       parse: { try IssuerHoldings.fhtrust($0, symbol: symbol) })

        case .ctbc:
            let api = "https://www.ctbcinvestments.com.tw/API/"
            let site = "www.ctbcinvestments.com"
            let hello = try await post(api + "home/AuthToken?token=" + Self.escaped(site), ["token": site])
            guard let token = IssuerHoldings.ctbcToken(hello) else { throw AppDataError("中國信託投信持股資料格式不符（缺少連線代碼）") }
            // In the address the token is percent-encoded (it can hold + / =); in the body it goes as it came.
            let query = "?token=" + Self.escaped(token)
            let fid = try await lookup(issuer, symbol) {
                IssuerHoldings.ctbcFID(try await self.post(api + "etf/ETFList" + query, ["token": token, "IsWithETF": "Y"]), symbol: symbol)
            }
            return try await newestDay({ day in
                try await self.post(api + "etf/ETFHoldingWeight" + query, ["token": token, "FID": fid, "StartDate": day])
            }, parse: { try IssuerHoldings.ctbc($0, symbol: symbol) })
        }
    }

    /// 復華 and 中信 answer for one day at a time and have nothing on a day without trading: today first, then up to
    /// five days back ("yyyy/MM/dd", Taipei). Only an answer that does not parse moves on to the day before; a
    /// request that fails ends the search.
    private func newestDay(_ fetch: (String) async throws -> Data,
                           parse: (Data) throws -> ComponentSnapshot) async throws -> ComponentSnapshot {
        let now = clock()
        var last: Error = AppDataError(Self.unavailable)
        for back in 0...5 {
            let date = GameRules.taipei.date(byAdding: .day, value: -back, to: now) ?? now
            let body = try await fetch(DataChecks.day(date).replacingOccurrences(of: "-", with: "/"))
            do { return try parse(body) } catch { last = error }
        }
        throw last
    }

    // MARK: Fund ids

    private static func lookupKey(_ issuer: Issuer, _ symbol: String) -> String { "holdings.lookup.\(issuer.rawValue).\(symbol)" }

    /// The company's own id for the ETF: the saved one while it is under 30 days old, else `find` asks for it.
    private func lookup(_ issuer: Issuer, _ symbol: String, find: () async throws -> String?) async throws -> String {
        let key = Self.lookupKey(issuer, symbol)
        let now = clock().timeIntervalSinceReferenceDate
        if let saved = defaults.dictionary(forKey: key), let id = saved["id"] as? String, !id.isEmpty,
           let at = saved["at"] as? Double, (0..<Self.lookupLife).contains(now - at) {
            return id
        }
        guard let id = try await find(), !id.isEmpty else { throw AppDataError("\(issuer.displayName)的 ETF 清單裡沒有這檔") }
        defaults.set(["id": id, "at": now] as [String: Any], forKey: key)
        return id
    }

    // MARK: Requests

    private func get(_ address: String) async throws -> Data {
        guard let url = URL(string: address) else { throw AppDataError(Self.unavailable) }
        try await pace()
        return try await transport.get(url)
    }

    private func post(_ address: String, _ body: [String: Any]?) async throws -> Data {
        guard let url = URL(string: address) else { throw AppDataError(Self.unavailable) }
        let json = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        try await pace()
        return try await transport.post(url, json: json)
    }

    /// At least `minInterval` between the starts of two requests, whichever company they go to.
    private func pace() async throws {
        let now = Date()
        let slot = max(now, nextSlot)
        nextSlot = slot.addingTimeInterval(minInterval)
        let wait = slot.timeIntervalSince(now)
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
    }

    /// A value for a query string: everything but letters, digits and - . _ ~ is percent-encoded.
    static func escaped(_ value: String) -> String {
        let plain = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: plain) ?? ""
    }

    /// A page's text: UTF-8, or Big5 when the bytes are not UTF-8 (older 投信 pages).
    static func page(_ bytes: Data) -> String {
        if let text = String(data: bytes, encoding: .utf8) { return text }
        let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        return String(data: bytes, encoding: big5) ?? String(decoding: bytes, as: UTF8.self)
    }

    // MARK: Today's copy

    private func file(_ symbol: String) -> URL { root.appendingPathComponent("\(symbol).json") }

    private func kept(_ symbol: String) -> Kept? {
        guard let bytes = try? Data(contentsOf: file(symbol)), let value = try? JSONDecoder().decode(Kept.self, from: bytes),
              value.snapshot.symbol == symbol, (try? value.snapshot.validate()) != nil else { return nil }
        return value
    }

    /// Best effort: a failed write only means the next call downloads again.
    private func keep(_ value: Kept, symbol: String) {
        guard let bytes = try? JSONEncoder().encode(value) else { return }
        let manager = FileManager.default
        if !manager.fileExists(atPath: root.path) {
            try? manager.createDirectory(at: root, withIntermediateDirectories: true)
            // It can be downloaded again, so it stays out of iCloud and device backups.
            var folder = root
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
        }
        try? bytes.write(to: file(symbol), options: .atomic)
    }
}

extension PortfolioStore {
    /// Downloads an ETF's holdings (`HoldingsClient`) and saves them with their history. A failure throws and leaves
    /// what is saved as it was.
    func refreshComponents(_ symbol: String, client: HoldingsClient = .shared) async throws {
        if Connectivity.forcedOffline { throw AppDataError("目前沒有網路，先顯示上次的成分股。") }
        try saveComponents(await client.components(symbol: symbol, fundName: name(for: symbol)))
    }
}
