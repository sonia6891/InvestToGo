import Foundation
import PocketCore

enum FileAccess {
    static func read(_ url: URL, limit: Int = 5_000_000) throws -> Data {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? limit + 1) <= limit else { throw AppDataError("檔案太大，未讀取。") }
        return try Data(contentsOf: url)
    }
}
enum PublicHTTP {
    static func get(_ url: URL, key: String? = nil) async throws -> Data {
        guard url.scheme == "https" else { throw AppDataError("只接受安全的資料連線。") }
        var request = URLRequest(url: url); request.timeoutInterval = 25; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key {
            guard url.host == "api.fugle.tw" else { throw AppDataError("金鑰只能傳給富果。") }
            request.setValue(key, forHTTPHeaderField: "X-API-KEY")
        }
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw StoreError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
        guard bytes.count <= 10_000_000 else { throw AppDataError("資料超過大小上限，保留原資料。") }
        return bytes
    }
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
}
extension CatalogAPI {
    static func fetch() async throws -> CatalogSnapshot {
        async let listed = PublicHTTP.get(URL(string: listedURL)!)
        async let otc = PublicHTTP.get(URL(string: otcURL)!)
        async let active = PublicHTTP.get(URL(string: activeURL)!)
        return try await decode(listed: listed, otc: otc, active: active)
    }
}
