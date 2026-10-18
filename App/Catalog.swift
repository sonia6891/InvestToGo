import Foundation

struct AppDataError: LocalizedError {
    let text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}
enum DataChecks {
    static func code(_ value: String) -> Bool { value.range(of: "^[0-9]{4,6}[A-Z]?$", options: .regularExpression) != nil }
    static func day(_ date: Date = Date()) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Taipei"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func date(_ text: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Taipei"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let value = formatter.date(from: text), formatter.string(from: value) == text else { return nil }
        return value
    }
    static func rocDay(_ text: String) -> String? {
        let raw = text.filter(\.isNumber)
        guard raw.count == 7 || raw.count == 8, let year = Int(raw.dropLast(4)) else { return nil }
        let value = String(year + (raw.count == 7 ? 1911 : 0)) + "-" + raw.dropLast(2).suffix(2) + "-" + raw.suffix(2)
        return date(value) == nil ? nil : value
    }
    static func readFile(_ url: URL, limit: Int = 5_000_000) throws -> Data {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? limit + 1) <= limit else { throw AppDataError("檔案太大，未讀取。") }
        return try Data(contentsOf: url)
    }
}
/// Spaces requests to one service across the whole app: at most `limit` per `window`, counted when a request is
/// actually sent, so a caller that gives up while waiting (a page closed) takes nothing. On the continuous clock,
/// which keeps time while the phone sleeps and does not move when the date and time are changed.
actor RequestPace {
    private let limit: Int
    private let window: Duration
    private var sent: [ContinuousClock.Instant] = []
    init(limit: Int, window: TimeInterval) { self.limit = limit; self.window = .milliseconds(Int64(window * 1000)) }
    /// 0: send now, and it is counted. Otherwise the seconds to wait before asking again.
    func take(now: ContinuousClock.Instant? = nil) -> TimeInterval {
        let now = now ?? ContinuousClock.now
        sent.removeAll { $0 + window <= now }
        if sent.count < limit { sent.append(now); return 0 }
        let wait = now.duration(to: sent[sent.count - limit] + window).components
        return max(0.05, Double(wait.seconds) + Double(wait.attoseconds) / 1e18)
    }
}
enum PublicHTTP {
    /// Fugle's free plan allows 60 requests a minute, shared by live polling and manual refreshes.
    static let fugle = RequestPace(limit: 55, window: 60)
    static func get(_ url: URL, key: String? = nil) async throws -> Data {
        guard url.scheme == "https" else { throw AppDataError("只接受安全的資料連線。") }
        if let pace = url.host == "api.fugle.tw" ? fugle : nil {
            while true {
                let wait = await pace.take()
                if wait == 0 { break }
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
        var request = URLRequest(url: url); request.timeoutInterval = 25; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key {
            guard url.host == "api.fugle.tw" else { throw AppDataError("金鑰只能傳給富果。") }
            request.setValue(key, forHTTPHeaderField: "X-API-KEY")
        }
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if key == nil, code == 401 || code == 403 { throw AppDataError("資料服務暫時拒絕連線（\(code)），保留上次成功資料。") }
            throw StoreError.http(code)
        }
        guard bytes.count <= 10_000_000 else { throw AppDataError("資料超過大小上限，保留原資料。") }
        return bytes
    }
    /// The exchanges' open data as rows: a JSON array of objects, sometimes behind a UTF-8 byte order mark.
    static func jsonRows(_ bytes: Data) -> [[String: Any]]? {
        var data = bytes
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
}
struct CatalogSnapshot: Codable {
    var funds: [Fund]
    var listedDate: String
    var fetchedDay: String
    var sources: [String]
    func validate() throws {
        guard !funds.isEmpty, funds.count <= 2000, Set(funds.map(\.id)).count == funds.count,
              DataChecks.date(listedDate) != nil, DataChecks.date(fetchedDay) != nil,
              listedDate <= DataChecks.day(), fetchedDay <= DataChecks.day(),
              funds.allSatisfy({ DataChecks.code($0.id) && !$0.name.isEmpty && $0.name.count <= 120 && ["TWSE", "TPEx"].contains($0.market ?? "") })
        else { throw AppDataError("ETF 名單未通過驗證，保留上次成功資料。") }
    }
    static func bundled() -> CatalogSnapshot? {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"), let bytes = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: bytes), (try? value.validate()) != nil else { return nil }
        return value
    }
}
enum CatalogAPI {
    static let listedURL = "https://openapi.twse.com.tw/v1/opendata/t187ap47_L"
    static let twseURL = "https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL"
    static let otcURL = "https://www.tpex.org.tw/openapi/v1/tpex_mainboard_quotes"
    static func strategy(_ name: String) -> Strategy {
        if name.contains("正2") || name.contains("反1") || name.contains("槓桿") || name.contains("反向") { return .risk }
        if name.contains("高股息") || name.contains("優息") || name.contains("高息") { return .income }
        if ["元大台灣50", "富邦台50", "元大富櫃50"].contains(name) { return .saving }
        return .unclassified
    }
    /// The ETFs are the codes starting with 00 in each exchange's daily trading list (TWSE 上市個股日成交資訊, TPEx 上櫃股票
    /// 收盤行情), so funds that left the market or are not listed yet drop out. TWSE 基金基本資料彙總表 adds the full name,
    /// fund type and listing day of listed ETFs; the open data has none of these for OTC ETFs, so they carry over from
    /// the previous list.
    static func decode(listed: Data, twse: Data, otc: Data, previous: CatalogSnapshot? = nil, today: String = DataChecks.day()) throws -> CatalogSnapshot {
        var details: [String: [String: Any]] = [:]; var dates: [String] = []
        for row in try rows(listed) {
            guard let code = text(row["基金代號"]), let day = DataChecks.rocDay(text(row["出表日期"]) ?? ""), day <= today, details[code] == nil else { throw AppDataError("上市基本資料欄位或日期改變，未覆寫。") }
            details[code] = row; dates.append(day)
        }
        let known = Dictionary((previous?.funds ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var funds: [Fund] = []
        for (market, bytes, codeKey, nameKey) in [("TWSE", twse, "Code", "Name"), ("TPEx", otc, "SecuritiesCompanyCode", "CompanyName")] {
            let records = try rows(bytes), before = funds.count
            guard records[0][codeKey] != nil, records[0][nameKey] != nil else { throw AppDataError("每日成交資料欄位改變，未覆寫。") }
            for row in records {
                guard let code = text(row[codeKey]), code.hasPrefix("00"), DataChecks.code(code), let name = text(row[nameKey]).map(unescape) else { continue }
                let detail = market == "TWSE" ? details[code] : nil, old = known[code]
                funds.append(Fund(id: code, name: name, strategy: strategy(name), market: market,
                                  fullName: text(detail?["基金中文名稱"]).map(unescape) ?? old?.fullName,
                                  fundType: text(detail?["基金類型"]) ?? old?.fundType,
                                  listingDate: DataChecks.rocDay(text(detail?["上市日期"]) ?? "") ?? old?.listingDate))
            }
            guard funds.count > before else { throw AppDataError("上市或上櫃資料不完整，保留原名單。") }
        }
        let value = CatalogSnapshot(funds: funds.sorted { $0.id < $1.id }, listedDate: dates.max() ?? today, fetchedDay: today, sources: [listedURL, twseURL, otcURL])
        try value.validate(); return value
    }
    private static func rows(_ bytes: Data) throws -> [[String: Any]] {
        guard let rows = PublicHTTP.jsonRows(bytes), !rows.isEmpty else { throw AppDataError("上市或上櫃資料不完整，保留原名單。") }
        return rows
    }
    private static func text(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        return text
    }
    /// The TWSE fund list writes some characters as HTML entities ("S&amp;P", "&#63754;").
    static func unescape(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        while let range = result.range(of: "&#[0-9]{1,7};", options: .regularExpression), let scalar = UInt32(result[range].dropFirst(2).dropLast()).flatMap({ Unicode.Scalar($0) }) {
            result.replaceSubrange(range, with: String(Character(scalar)))
        }
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] { result = result.replacingOccurrences(of: entity, with: character) }
        return result
    }
    static func fetch(previous: CatalogSnapshot? = nil) async throws -> CatalogSnapshot {
        async let listed = PublicHTTP.get(URL(string: listedURL)!)
        async let twse = PublicHTTP.get(URL(string: twseURL)!)
        async let otc = PublicHTTP.get(URL(string: otcURL)!)
        return try await decode(listed: listed, twse: twse, otc: otc, previous: previous)
    }
}
