import Foundation
import Security
import SwiftUI

enum Strategy: String, Codable, CaseIterable, Identifiable {
    case saving = "存錢筒", income = "印鈔機", risk = "老虎機", unclassified = "待分類"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .saving: return "leaf"; case .income: return "banknote"; case .risk: return "bolt"; case .unclassified: return "tag" }
    }
    var subtitle: String {
        switch self { case .saving: return "長期累積"; case .income: return "關注配息"; case .risk: return "高波動策略"; case .unclassified: return "自行選擇策略" }
    }
}
struct Fund: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var strategy: Strategy
    var market: String? = nil
    var fullName: String? = nil
    var fundType: String? = nil
    var listingDate: String? = nil
    // Demo-only catalogue; the normal app uses the validated TWSE + TPEx catalogue.
    static let starters: [Fund] = [
        .init(id: "0050", name: "元大台灣50", strategy: .saving),
        .init(id: "006208", name: "富邦台50", strategy: .saving),
        .init(id: "0056", name: "元大高股息", strategy: .income),
        .init(id: "00878", name: "國泰永續高股息", strategy: .income),
        .init(id: "00919", name: "群益台灣精選高息", strategy: .income),
        .init(id: "00631L", name: "元大台灣50正2", strategy: .risk)
    ]
}
struct Holding: Identifiable, Codable {
    var id = UUID()
    var symbol: String
    var name: String
    var shares: Double
    var unitCost: Double
    var broker: String
    var strategy: Strategy
    var sourceAccount: String? = nil
    var cost: Double { shares * unitCost }
    func validate() throws {
        guard !symbol.isEmpty, !name.isEmpty, shares.isFinite, shares > 0,
              shares <= 1e10, unitCost.isFinite, unitCost >= 0, unitCost <= 1e9,
              cost.isFinite, !broker.isEmpty, broker.count <= 120, symbol.count <= 20, name.count <= 120 else { throw StoreError.invalidHolding }
    }
}
enum DividendStatus: String, Codable, CaseIterable { case paid = "已入帳", announced = "已公告", estimated = "預估" }
struct Dividend: Identifiable, Codable {
    var id = UUID()
    var symbol: String
    var date: Date
    var amount: Double
    var status: DividendStatus
}
struct Quote: Codable {
    var symbol: String
    var price: Double
    var changePercent: Double?
    var date: String
    var fetchedAt: Date
    var currency: String? = nil
    var isTWD: Bool { currency == "TWD" || (currency == nil && Fund.starters.contains { $0.id == symbol }) }
}
struct Portfolio: Codable {
    var schema = 1
    var holdings: [Holding] = []
    var dividends: [Dividend] = []
    var favorites: Set<String> = []
    var quotes: [String: Quote] = [:]
    var comparison: [String]? = nil
    var legacyPlan: LegacyPlan? = nil
    var legacyPrices: [String: LegacyPrice]? = nil
    var legacyDividends: [String: BackupImport.OldDividend]? = nil
    var components: [String: ComponentSnapshot]? = nil
    var histories: [String: PriceHistory]? = nil
    var fees: [String: FeeRecord]? = nil
    var scenarioPlan: ScenarioPlan? = nil
    var cost: Double { holdings.reduce(0) { $0 + $1.cost } }
    var marketValue: Double? {
        guard !holdings.isEmpty, holdings.allSatisfy({ quotes[$0.symbol]?.isTWD == true }) else { return nil }
        return holdings.reduce(0) { $0 + $1.shares * quotes[$1.symbol]!.price }
    }
    static func decodeBackup(_ data: Data) throws -> Portfolio {
        guard data.count <= 5_000_000 else { throw StoreError.unsupportedBackup }
        let value = try JSONDecoder().decode(Portfolio.self, from: data)
        guard value.schema == 1, value.holdings.count <= 10000, value.dividends.count <= 50000, value.favorites.count <= 2000 else { throw StoreError.unsupportedBackup }
        for holding in value.holdings { try holding.validate() }
        guard Set(value.holdings.map(\.id)).count == value.holdings.count,
              Set(value.dividends.map(\.id)).count == value.dividends.count,
              value.dividends.allSatisfy({ !$0.symbol.isEmpty && $0.amount.isFinite && $0.amount >= 0 }),
              value.quotes.allSatisfy({ $0.key == $0.value.symbol && $0.value.price.isFinite && $0.value.price > 0 })
        else { throw StoreError.unsupportedBackup }
        try value.legacyPlan?.validate()
        if let plan = value.scenarioPlan { guard (try? plan.validate()) != nil else { throw StoreError.unsupportedBackup } }
        for d in (value.legacyDividends ?? [:]).values { try d.validate() }
        for (code, snapshot) in value.components ?? [:] { guard code == snapshot.symbol else { throw StoreError.unsupportedBackup }; try snapshot.validate() }
        for (code, history) in value.histories ?? [:] { guard code == history.symbol else { throw StoreError.unsupportedBackup }; try history.validate() }
        for (code, fee) in value.fees ?? [:] { guard code == fee.symbol else { throw StoreError.unsupportedBackup }; try fee.validate() }
        guard (value.comparison?.count ?? 0) <= 3, (value.comparison ?? []).allSatisfy(DataChecks.code),
              (value.legacyPrices ?? [:]).values.allSatisfy({ DataChecks.code($0.symbol) && $0.price.isFinite && $0.price >= 0 && DataChecks.date($0.date) != nil }) else { throw StoreError.unsupportedBackup }
        return value
    }
    static var demo: Portfolio {
        var value = Portfolio()
        value.holdings = [
            .init(symbol: "0050", name: "元大台灣50", shares: 2000, unitCost: 50, broker: "富邦證券", strategy: .saving),
            .init(symbol: "00878", name: "國泰永續高股息", shares: 6000, unitCost: 20, broker: "富邦證券", strategy: .income),
            .init(symbol: "00919", name: "群益台灣精選高息", shares: 5000, unitCost: 22, broker: "國泰證券", strategy: .income)
        ]
        let prices: [String: Double] = ["0050": 55, "00878": 21, "00919": 22.5]
        for (symbol, price) in prices { value.quotes[symbol] = Quote(symbol: symbol, price: price, changePercent: 0.42, date: "示範資料", fetchedAt: Date()) }
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
        value.dividends = [
            Dividend(symbol: "00878", date: Calendar.current.date(byAdding: .day, value: 7, to: start)!, amount: 2400, status: .paid),
            Dividend(symbol: "00919", date: Calendar.current.date(byAdding: .day, value: 19, to: start)!, amount: 3600, status: .announced)
        ]
        value.favorites = ["0050", "00878", "00919"]
        return value
    }
}
enum StoreError: LocalizedError {
    case invalidHolding, unsupportedBackup, missingKey, invalidQuote, keychain(OSStatus), http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidHolding: return "請填寫代碼、名稱與券商，股數須大於 0，每股成本不可為負數。"
        case .unsupportedBackup: return "備份格式不支援或資料不完整；現有資料未變更。"
        case .missingKey: return "請先在行情連線儲存你的富果 API Key。"
        case .invalidQuote: return "行情沒有有效成交價，請稍後再試。"
        case .keychain: return "無法安全儲存金鑰，請重試。"
        case .http(let code):
            if code == 401 { return "金鑰無效或已失效，請重新確認行情金鑰。" }
            if code == 403 { return "目前方案沒有這項資料權限；成分股需要富果開發者或進階方案。已有報價會保留。" }
            if code == 429 { return "已達資料請求額度，請稍後重試；已有資料會保留。" }
            return "資料服務暫時無法使用（\(code)），保留上次成功資料。"
        }
    }
}
@MainActor final class PortfolioStore: ObservableObject {
    @Published private(set) var data = Portfolio()
    @Published var message: String?
    @Published var refreshing = false
    @Published private(set) var catalog = CatalogSnapshot.bundled()
    @Published var catalogMessage: String?
    @Published var catalogRefreshing = false
    var funds: [Fund] { isDemo ? Fund.starters : (catalog?.funds ?? []) }
    // Codes outside the ETF catalogue are treated as individual stocks.
    func isETF(_ symbol: String) -> Bool { funds.contains { $0.id == symbol } }
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
        next.scenarioPlan = incoming.scenarioPlan ?? next.scenarioPlan
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
    struct Response: Decodable { let symbol: String; let date: String; let closePrice: Double?; let lastPrice: Double?; let changePercent: Double? }
    static func quote(symbol: String, key: String) async throws -> Quote {
        guard symbol.range(of: "^[0-9A-Z]{4,8}$", options: .regularExpression) != nil else { throw StoreError.invalidQuote }
        let url = URL(string: "https://api.fugle.tw/marketdata/v1.0/stock/intraday/quote/\(symbol)")!
        let bytes = try await PublicHTTP.get(url, key: key)
        struct Ticker: Decodable { let symbol: String; let tradingCurrency: String? }
        let ticker = try JSONDecoder().decode(Ticker.self, from: await PublicHTTP.get(URL(string: "https://api.fugle.tw/marketdata/v1.0/stock/intraday/ticker/\(symbol)")!, key: key))
        guard ticker.symbol == symbol else { throw StoreError.invalidQuote }
        var quote = try decode(bytes, expectedSymbol: symbol)
        quote.currency = ticker.tradingCurrency ?? "UNKNOWN"
        return quote
    }
    static func decode(_ bytes: Data, expectedSymbol: String) throws -> Quote {
        let value = try JSONDecoder().decode(Response.self, from: bytes)
        guard value.symbol == expectedSymbol, let price = value.closePrice ?? value.lastPrice, price.isFinite, price > 0 else { throw StoreError.invalidQuote }
        return Quote(symbol: value.symbol, price: price, changePercent: value.changePercent, date: value.date, fetchedAt: Date())
    }
}
enum Projection {
    static func value(initial: Double, monthly: Double, years: Int, annualPercent: Double) -> Double {
        let rate = annualPercent / 100 / 12
        var total = initial
        for _ in 0..<(max(years, 0) * 12) { total = total * (1 + rate) + monthly }
        return total
    }
}
