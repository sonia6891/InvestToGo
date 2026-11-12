import Foundation
import Security
import SwiftUI

@MainActor final class PortfolioStore: ObservableObject {
    @Published private(set) var data = Portfolio()
    @Published var message: String?
    @Published var refreshing = false
    @Published private(set) var catalog = CatalogSnapshot.bundled()
    @Published var catalogMessage: String?
    @Published var catalogRefreshing = false
    @Published private(set) var official = OfficialDividends.bundled()
    @Published var officialRefreshing = false
    @Published var officialMessage: String?
    /// 加權 / 櫃買 index quotes, keyed "taiex" and "tpex": live with the viewer's Fugle key, else the latest close.
    @Published var indices: [String: Quote] = [:]
    /// Prices pushed or polled during the trading session; kept in memory and saved for holdings and watchlist when the app leaves.
    @Published var liveQuotes: [String: Quote] = [:]
    @Published var liveStatus = LiveStatus()
    /// The stock or ETF page on screen, streamed first.
    @Published var liveFocus: String?
    /// Set by the home page: open 探索 on stocks or ETFs, optionally with the search field focused.
    @Published var discoverRequest: DiscoverRequest?
    /// The latest trading day's prices from the exchanges' open data (OpenData), cached on the device.
    @Published var daily: OpenData.Day?
    var dailyAttemptAt: Date?
    lazy var live = LiveFeed(store: self)
    var funds: [Fund] { catalog?.funds ?? [] }
    private let url: URL
    init(url: URL? = nil, reset: Bool = false) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.url = url ?? base.appendingPathComponent("ETFToGo/portfolio.json")
        if let bytes = try? Data(contentsOf: self.url.appendingPathExtension("catalog")), let cached = try? JSONDecoder().decode(CatalogSnapshot.self, from: bytes), (try? cached.validate()) != nil { catalog = cached }
        if let bytes = try? Data(contentsOf: self.url.appendingPathExtension("official")), let cached = try? JSONDecoder().decode(OfficialDividends.self, from: bytes), cached.since != nil, cached.isNewer(than: official) { official = cached }
        if let bytes = try? Data(contentsOf: self.url.appendingPathExtension("daily")), let cached = try? JSONDecoder().decode(OpenData.Day.self, from: bytes),
           cached.quotes.allSatisfy({ $0.key == $0.value.symbol && $0.value.isValid }), cached.indices.values.allSatisfy(\.isValid) { daily = cached; indices = cached.indices }
        if reset { try? FileManager.default.removeItem(at: self.url); try? FileManager.default.removeItem(at: historiesURL) }
        if FileManager.default.fileExists(atPath: self.url.path) {
            do { data = try Portfolio.decodeBackup(Data(contentsOf: self.url), limit: 100_000_000) }
            catch { message = "無法讀取既有資料，原始檔已保留。請先匯出或檢查備份。"; readFailure = true }
        }
        historiesSaved = (data.histories ?? [:]).isEmpty
        // Earlier versions kept histories in the records file; the next save moves them out. A history that does not
        // validate is dropped, since it can be fetched again.
        if let bytes = try? Data(contentsOf: historiesURL), let cached = try? JSONDecoder().decode([String: PriceHistory].self, from: bytes) {
            let valid = cached.filter { $0.key == $0.value.symbol && (try? $0.value.validate()) != nil }
            if !valid.isEmpty { data.histories = (data.histories ?? [:]).merging(valid) { _, cached in cached } }
        }
    }
    private var readFailure = false
    /// Price histories are large and can be fetched again, so they are saved apart from the records: a save of the
    /// records stays small and fast, and many histories never push the records past the backup size limit.
    private var historiesURL: URL { url.appendingPathExtension("histories") }
    func commit(_ next: Portfolio) throws {
        guard !readFailure else { throw StoreError.unsupportedBackup }
        var records = next; records.histories = nil
        let encoded = try JSONEncoder().encode(records)
        guard encoded.count <= 5_000_000 else { throw AppDataError("紀錄超過 5 MB 上限，這次變更未儲存；現有資料未變更。") }
        _ = try Portfolio.decodeBackup(encoded)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if next.histories != data.histories || !historiesSaved {
            try JSONEncoder().encode(next.histories ?? [:]).write(to: historiesURL, options: [.atomic, .completeFileProtection])
            historiesSaved = true
        }
        try encoded.write(to: url, options: [.atomic, .completeFileProtection])
        data = next
    }
    /// Changes the game progress and saves it with the records; nothing is written when it does not change.
    func updateGame(_ change: (inout GameState) -> Void) throws {
        var game = data.game ?? GameState()
        change(&game)
        guard game != (data.game ?? GameState()) else { return }
        var next = data; next.game = game
        try commit(next)
    }
    /// False while the records file still holds histories from an earlier version, so the next save moves them out.
    private var historiesSaved = false
    func save(_ holding: Holding) throws {
        try holding.validate()
        var next = data
        if let i = next.holdings.firstIndex(where: { $0.id == holding.id }) {
            let old = next.holdings[i]
            next.holdings[i] = holding
            if old.symbol != holding.symbol || old.shares != holding.shares || old.unitCost != holding.unitCost || old.broker != holding.broker { next.log(.adjust, holding) }
        } else {
            next.holdings.append(holding)
            next.log(.buy, holding, date: holding.purchaseDate ?? Date(), amount: holding.cost)
        }
        try commit(next)
    }
    func remove(_ holding: Holding) throws {
        var next = data
        guard let stored = next.holdings.first(where: { $0.id == holding.id }) else { return }
        next.holdings.removeAll { $0.id == holding.id }
        next.log(.remove, stored)
        try commit(next)
    }
    func favorite(_ symbol: String) {
        var next = data
        if next.favorites.contains(symbol) { next.favorites.remove(symbol) } else { next.favorites.insert(symbol) }
        do { try commit(next) } catch { message = error.localizedDescription }
    }
    func record(_ dividend: Dividend) throws { var next = data; next.dividends.append(dividend); try commit(next) }
    func markPaid(_ dividend: Dividend) throws {
        var next = data
        guard let i = next.dividends.firstIndex(where: { $0.id == dividend.id }) else { return }
        next.dividends[i].status = .paid
        try commit(next)
    }
    func addToComparison(_ symbol: String) {
        var list = data.comparison ?? []
        if list.contains(symbol) { message = "\(symbol) 已在比較清單，可到「工具 › 三檔比較」查看。"; return }
        if list.count >= 3 { list.removeFirst() }
        list.append(symbol)
        var next = data; next.comparison = list
        do { try commit(next); message = "已加入比較：\(list.joined(separator: "、"))。可到「工具 › 三檔比較」查看。" } catch { message = error.localizedDescription }
    }
    func removeDividend(_ dividend: Dividend) throws { var next = data; next.dividends.removeAll { $0.id == dividend.id }; try commit(next) }
    func saveDividend(_ dividend: Dividend) throws {
        guard !dividend.symbol.isEmpty, dividend.amount.isFinite, dividend.amount > 0, dividend.detailsValid else { throw AppDataError("請填寫代碼、股數與每股配息；扣繳後的入帳金額必須大於 0。") }
        var next = data
        if let i = next.dividends.firstIndex(where: { $0.id == dividend.id }) { next.dividends[i] = dividend } else { next.dividends.append(dividend) }
        try commit(next)
    }
    /// Marks a record as received; a payment date still in the future becomes today.
    @discardableResult func confirmPaid(_ dividend: Dividend) throws -> Dividend {
        var next = data
        guard let i = next.dividends.firstIndex(where: { $0.id == dividend.id }) else { return dividend }
        next.dividends[i].status = .paid
        next.dividends[i].source = DividendSource.broker.rawValue
        if next.dividends[i].date > Date() { next.dividends[i].date = Calendar.current.startOfDay(for: Date()) }
        try commit(next)
        return next.dividends[i]
    }
    /// A buy adds to the holding of the same ETF and broker (re-averaging its cost) or creates one;
    /// a sell reduces it at its average cost, records the realised result and removes it at zero.
    func applyTrade(_ action: TradeAction, symbol: String, date: Date, shares: Double, amount: Double, broker: String) throws {
        guard action == .buy || action == .sell else { return }
        guard DataChecks.code(symbol) else { throw AppDataError("請輸入正確的 ETF 代號。") }
        guard shares.isFinite, shares > 0, shares <= 1e10, amount.isFinite, amount >= 0, amount <= 1e12 else { throw AppDataError("請填寫股數與成交金額。") }
        var next = data
        let same = next.holdings.indices.filter { next.holdings[$0].symbol == symbol }
        let target = broker.isEmpty ? (same.count == 1 ? same.first : same.first(where: { next.holdings[$0].broker.isEmpty })) : same.first(where: { next.holdings[$0].broker == broker })
        let fundName = funds.first { $0.id == symbol }?.name
        var realized: Double? = nil
        if action == .buy {
            if let i = target {
                let total = next.holdings[i].cost + amount
                next.holdings[i].shares += shares
                next.holdings[i].unitCost = total / next.holdings[i].shares
            } else {
                guard let fundName else { throw AppDataError("清單沒有這檔，請先用「新增持有」填寫名稱。") }
                let strategy = funds.first(where: { $0.id == symbol })?.strategy ?? .unclassified
                next.holdings.append(Holding(symbol: symbol, name: fundName, shares: shares, unitCost: amount / shares, broker: broker, strategy: strategy, purchaseDate: date))
            }
        } else {
            guard let i = target else { throw AppDataError(same.count > 1 ? "這檔在多個券商都有持有，請填寫券商。" : "找不到這檔的持有，無法賣出。") }
            guard shares <= next.holdings[i].shares + 1e-9 else { throw AppDataError("賣出股數超過持有（\(decimal(next.holdings[i].shares)) 股）。") }
            realized = ((amount - shares * next.holdings[i].unitCost) * 100).rounded() / 100
            next.holdings[i].shares -= shares
            if next.holdings[i].shares <= 1e-9 { next.holdings.remove(at: i) }
        }
        let holdingName = target.map { data.holdings[$0].name }
        next.log(Trade(date: date, action: action, symbol: symbol, name: fundName ?? holdingName ?? symbol, shares: shares, amount: amount, broker: broker.isEmpty ? (target.map { data.holdings[$0].broker } ?? "") : broker, realized: realized))
        try commit(next)
    }
    func removeTrade(_ trade: Trade) throws { var next = data; next.trades?.removeAll { $0.id == trade.id }; try commit(next) }
    func refreshOfficial() async {
        guard !officialRefreshing else { return }
        officialRefreshing = true; defer { officialRefreshing = false }
        do {
            let markets = Dictionary(uniqueKeysWithValues: (catalog?.funds ?? Fund.starters).map { ($0.id, $0.market ?? "") })
            let fresh = try await OfficialDividends.fetch(merging: official, markets: markets)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(fresh).write(to: url.appendingPathExtension("official"), options: .atomic)
            official = fresh; officialMessage = "已更新官方配息資料。"
        } catch { officialMessage = error.localizedDescription }
    }
    func saveDaily() {
        guard let daily else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(daily).write(to: url.appendingPathExtension("daily"), options: .atomic)
    }
    func export() throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ETFToGo-backup-\(UUID().uuidString.prefix(8)).json")
        // Preserve recoverable bytes when decoding failed; never export an empty replacement.
        // Price histories are left out: they can be fetched again and would make the backup too large to import.
        var records = data; records.histories = nil
        let bytes = readFailure ? try Data(contentsOf: url) : try JSONEncoder().encode(records)
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
        for item in incoming.trades ?? [] {
            if next.trades == nil { next.trades = [] }
            if let i = next.trades?.firstIndex(where: { $0.id == item.id }) { next.trades?[i] = item } else { next.trades?.append(item) }
        }
        next.favorites.formUnion(incoming.favorites)
        next.combo = incoming.combo ?? next.combo
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
        if FileManager.default.fileExists(atPath: url.path) {
            let directory = url.deletingLastPathComponent().appendingPathComponent("Recovery")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(contentsOf: url).write(to: directory.appendingPathComponent("before-import-\(UUID().uuidString).json"), options: [.atomic, .completeFileProtection])
        }
    }
    /// `automatic` (at launch) skips the three requests when today's list is already on the device; the 立即更新 buttons always fetch.
    func refreshCatalog(automatic: Bool = false) async {
        guard !catalogRefreshing, !(automatic && catalog?.fetchedDay == DataChecks.day()) else { return }
        catalogRefreshing = true; defer { catalogRefreshing = false }
        do {
            let next = try await CatalogAPI.fetch(previous: catalog)
            if let old = catalog {
                guard next.listedDate >= old.listedDate else { throw AppDataError("新取得的資料日期比目前舊，未覆寫。") }
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
        guard !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        message = nil
        let started = Date()
        do {
            let key = try SecureKey.read()
            let targets = Array(Set(symbols ?? data.holdings.map(\.symbol))).sorted()
            guard !targets.isEmpty else { message = "請先新增持有，或到單檔 ETF 頁面更新報價。"; return }
            var fetched: [String: Quote] = [:]
            if key.isEmpty {
                // No Fugle key: the latest trading day's closes from the exchanges' open data, saved where newer.
                guard await refreshDaily(manual: true), let closes = daily?.quotes else { throw AppDataError("暫時取不到收盤資料，保留上次報價。") }
                let wanted = Set(targets)
                guard wanted.contains(where: { closes[$0] != nil }) else { throw AppDataError("目前沒有這些代號的收盤資料，保留上次報價。") }
                fetched = closes.filter { wanted.contains($0.key) && $0.value.fetchedAt > (data.quotes[$0.key]?.fetchedAt ?? .distantPast) }
                guard !fetched.isEmpty else { message = "收盤資料已是最新（\((daily?.day ?? "").replacingOccurrences(of: "-", with: "/"))）。"; return }
            } else {
                // In a list, prices streamed in the last minute are already current. PublicHTTP spaces the requests so
                // they stay within the plan together with live polling; what arrived before an error is still kept.
                let stale = targets.count == 1 ? targets : targets.filter { (liveQuotes[$0]?.fetchedAt.timeIntervalSinceNow ?? -.infinity) < -60 }
                do {
                    for symbol in stale { fetched[symbol] = try await Fugle.quote(symbol: symbol, key: key, currency: data.quotes[symbol]?.currency) }
                } catch {
                    if !fetched.isEmpty { try? keepFetched(fetched, since: started) }
                    throw error
                }
            }
            try keepFetched(fetched, since: started)
        } catch { message = error.localizedDescription }
    }
    /// Saves refreshed quotes, merged into the current data since the user may have edited holdings meanwhile.
    /// Trial-match prices only show (through liveQuotes) and are never saved as the day's price.
    private func keepFetched(_ fetched: [String: Quote], since started: Date) throws {
        let trial = fetched.filter { $0.value.trial == true }
        // A real trade streamed in while the requests were running, or anything newer, is kept.
        if !trial.isEmpty { liveQuotes.merge(trial) { old, new in (old.trial != true && old.date == new.date && old.fetchedAt >= started) || old.fetchedAt > new.fetchedAt ? old : new } }
        var next = data
        next.quotes.merge(fetched.filter { $0.value.trial != true }) { _, refreshed in refreshed }
        try commit(next)
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
extension Fugle {
    /// The ticker request for the trading currency is skipped when it is already known.
    static func quote(symbol: String, key: String, currency known: String? = nil) async throws -> Quote {
        guard symbol.range(of: "^[0-9A-Z]{4,8}$", options: .regularExpression) != nil else { throw StoreError.invalidQuote }
        let url = URL(string: "https://api.fugle.tw/marketdata/v1.0/stock/intraday/quote/\(symbol)")!
        let bytes = try await PublicHTTP.get(url, key: key)
        if let known, known != "UNKNOWN" { var quote = try decode(bytes, expectedSymbol: symbol); quote.currency = known; return quote }
        struct Ticker: Decodable { let symbol: String; let tradingCurrency: String? }
        let ticker = try JSONDecoder().decode(Ticker.self, from: await PublicHTTP.get(URL(string: "https://api.fugle.tw/marketdata/v1.0/stock/intraday/ticker/\(symbol)")!, key: key))
        guard ticker.symbol == symbol else { throw StoreError.invalidQuote }
        var quote = try decode(bytes, expectedSymbol: symbol)
        quote.currency = ticker.tradingCurrency ?? "UNKNOWN"
        return quote
    }
}
