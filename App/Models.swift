import Foundation
import Security
import SwiftUI
import PocketCore

@MainActor final class PortfolioStore: ObservableObject {
    @Published private(set) var data = Portfolio()
    @Published var message: String?
    @Published var refreshing = false
    @Published private(set) var catalog = CatalogSnapshot.bundled()
    @Published var catalogMessage: String?
    @Published var catalogRefreshing = false
    var funds: [Fund] { isDemo ? Fund.starters : (catalog?.funds ?? []) }
    let isDemo: Bool
    private let url: URL
    init(url: URL? = nil, demo: Bool = false, reset: Bool = false) {
        isDemo = demo
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.url = url ?? base.appendingPathComponent("ETFToGo/portfolio.json")
        if let bytes = try? Data(contentsOf: self.url.appendingPathExtension("catalog")), let cached = try? JSONDecoder().decode(CatalogSnapshot.self, from: bytes), (try? cached.validate()) != nil { catalog = cached }
        if demo { data = .demo; return }
        if reset { try? FileManager.default.removeItem(at: self.url) }
        if FileManager.default.fileExists(atPath: self.url.path) {
            do { data = try Portfolio.decodeBackup(Data(contentsOf: self.url)) }
            catch { message = "無法讀取既有資料，原始檔已保留。請先匯出或檢查備份。"; readFailure = true }
        }
    }
    private var readFailure = false
    func commit(_ next: Portfolio) throws {
        guard !readFailure else { throw StoreError.unsupportedBackup }
        let encoded = try JSONEncoder().encode(next)
        _ = try Portfolio.decodeBackup(encoded)
        if !isDemo {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: url, options: [.atomic, .completeFileProtection])
        }
        data = next
    }
    func save(_ holding: Holding) throws {
        try holding.validate()
        var next = data
        if let i = next.holdings.firstIndex(where: { $0.id == holding.id }) { next.holdings[i] = holding }
        else { next.holdings.append(holding) }
        try commit(next)
    }
    func remove(_ holding: Holding) throws { var next = data; next.holdings.removeAll { $0.id == holding.id }; try commit(next) }
    func favorite(_ symbol: String) {
        var next = data
        if next.favorites.contains(symbol) { next.favorites.remove(symbol) } else { next.favorites.insert(symbol) }
        do { try commit(next) } catch { message = error.localizedDescription }
    }
    func record(_ dividend: Dividend) throws { var next = data; next.dividends.append(dividend); try commit(next) }
    func removeDividend(_ dividend: Dividend) throws { var next = data; next.dividends.removeAll { $0.id == dividend.id }; try commit(next) }
    func export() throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ETFToGo-backup-\(UUID().uuidString.prefix(8)).json")
        // Preserve recoverable bytes when decoding failed; never export an empty replacement.
        let bytes = readFailure ? try Data(contentsOf: url) : try JSONEncoder().encode(data)
        try bytes.write(to: file, options: .atomic)
        return file
    }
    func importBackup(_ bytes: Data) throws {
        let incoming = try BackupImport.decode(bytes)
        // Merge by stable IDs; incoming records update matches, existing unmatched records are retained.
        var next = data
        for item in incoming.holdings {
            if let i = next.holdings.firstIndex(where: { $0.id == item.id }) { next.holdings[i] = item } else { next.holdings.append(item) }
        }
        for item in incoming.dividends {
            if let i = next.dividends.firstIndex(where: { $0.id == item.id }) { next.dividends[i] = item } else { next.dividends.append(item) }
        }
        next.favorites.formUnion(incoming.favorites)
        next.comparison = incoming.comparison ?? next.comparison
        next.legacyPlan = incoming.legacyPlan ?? next.legacyPlan
        next.legacyPrices = (next.legacyPrices ?? [:]).merging(incoming.legacyPrices ?? [:]) { _, new in new }
        next.legacyDividends = (next.legacyDividends ?? [:]).merging(incoming.legacyDividends ?? [:]) { _, new in new }
        next.components = (next.components ?? [:]).merging(incoming.components ?? [:]) { _, new in new }
        next.histories = (next.histories ?? [:]).merging(incoming.histories ?? [:]) { _, new in new }
        next.fees = (next.fees ?? [:]).merging(incoming.fees ?? [:]) { _, new in new }
        // Restore missing cached quotes; retain quotes already on this device.
        for (symbol, quote) in incoming.quotes where next.quotes[symbol] == nil { next.quotes[symbol] = quote }
        try saveRecovery()
        try commit(next)
    }
    func saveRecovery() throws {
        guard !readFailure else { throw StoreError.unsupportedBackup }
        if !isDemo, FileManager.default.fileExists(atPath: url.path) {
            let directory = url.deletingLastPathComponent().appendingPathComponent("Recovery")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(contentsOf: url).write(to: directory.appendingPathComponent("before-import-\(UUID().uuidString).json"), options: [.atomic, .completeFileProtection])
        }
    }
    func refreshCatalog() async {
        guard !isDemo, !catalogRefreshing else { return }
        catalogRefreshing = true; defer { catalogRefreshing = false }
        do {
            let next = try await CatalogAPI.fetch()
            if let old = catalog {
                guard next.listedDate >= old.listedDate else { throw AppDataError("來源日期比目前資料舊，未覆寫。") }
                for market in ["TWSE", "TPEx"] {
                    guard Double(next.funds.filter { $0.market == market }.count) >= Double(old.funds.filter { $0.market == market }.count) * 0.8 else { throw AppDataError("名單數量異常減少，保留原有清單。") }
                }
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url.appendingPathExtension("catalog"), options: .atomic)
            catalog = next; catalogMessage = "已更新上市與上櫃 ETF 名單。"
        } catch { catalogMessage = error.localizedDescription }
    }
    func saveComponents(_ value: ComponentSnapshot) throws { try value.validate(); var next = data; if next.components == nil { next.components = [:] }; next.components?[value.symbol] = value; try commit(next) }
    func saveHistory(_ value: PriceHistory) throws { try value.validate(); var next = data; if next.histories == nil { next.histories = [:] }; next.histories?[value.symbol] = value; try commit(next) }
    func saveFee(_ value: FeeRecord) throws { try value.validate(); var next = data; if next.fees == nil { next.fees = [:] }; next.fees?[value.symbol] = value; try commit(next) }
    func refresh(symbols: [String]? = nil) async {
        if isDemo { message = "這是介面示範資料，沒有連線取得市場價格。"; return }
        guard !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        message = nil
        do {
            let key = try SecureKey.read()
            guard !key.isEmpty else { throw StoreError.missingKey }
            let targets = Array(Set(symbols ?? data.holdings.map(\.symbol))).sorted()
            guard !targets.isEmpty else { message = "請先新增持有，或到單檔 ETF 頁面更新報價。"; return }
            var fetched: [String: Quote] = [:]
            for symbol in targets {
                let quote = try await Fugle.quote(symbol: symbol, key: key)
                fetched[symbol] = quote
                if symbol != targets.last { try await Task.sleep(nanoseconds: 2_100_000_000) }
            }
            // The user may have edited holdings while the requests were running.
            var next = data
            next.quotes.merge(fetched) { _, refreshed in refreshed }
            try commit(next)
        } catch { message = error.localizedDescription }
    }
}
enum SecureKey {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ETFToGo.Fugle", kSecAttrAccount as String: "personal-api-key"]
    static func save(_ key: String) throws {
        let bytes = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        if bytes.isEmpty { try remove(); return }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = bytes; add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let result = SecItemAdd(add as CFDictionary, nil); guard result == errSecSuccess else { throw StoreError.keychain(result) }
        } else if status != errSecSuccess { throw StoreError.keychain(status) }
    }
    static func read() throws -> String {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let bytes = item as? Data else { throw StoreError.keychain(status) }
        return String(data: bytes, encoding: .utf8) ?? ""
    }
    static func remove() throws { let result = SecItemDelete(query as CFDictionary); guard result == errSecSuccess || result == errSecItemNotFound else { throw StoreError.keychain(result) } }
}
enum Fugle {
    static func quote(symbol: String, key: String) async throws -> Quote {
        guard symbol.range(of: "^[0-9A-Z]{4,8}$", options: .regularExpression) != nil else { throw StoreError.invalidQuote }
        let url = URL(string: "https://api.fugle.tw/marketdata/v1.0/stock/intraday/quote/\(symbol)")!
        let bytes = try await PublicHTTP.get(url, key: key)
        struct Ticker: Decodable { let symbol: String; let tradingCurrency: String? }
        let ticker = try JSONDecoder().decode(Ticker.self, from: await PublicHTTP.get(URL(string: "https://api.fugle.tw/marketdata/v1.0/stock/intraday/ticker/\(symbol)")!, key: key))
        guard ticker.symbol == symbol else { throw StoreError.invalidQuote }
        var quote = try FugleDecode.quote(bytes, expectedSymbol: symbol)
        quote.currency = ticker.tradingCurrency ?? "UNKNOWN"
        return quote
    }
}
