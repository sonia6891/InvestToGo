import Foundation

extension DataChecks {
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
    // One session reuses TLS connections across chunked history and quote requests.
    private static let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
}
extension CatalogAPI {
    static func fetch(previous: CatalogSnapshot? = nil) async throws -> CatalogSnapshot {
        async let listed = PublicHTTP.get(URL(string: listedURL)!)
        async let twse = PublicHTTP.get(URL(string: twseURL)!)
        async let otc = PublicHTTP.get(URL(string: otcURL)!)
        return try await decode(listed: listed, twse: twse, otc: otc, previous: previous)
    }
}
