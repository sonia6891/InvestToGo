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
    // Well-known NT$ ETFs: the currency and market fallback when the catalogue is missing.
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
    var purchaseDate: Date? = nil
    var cost: Double { shares * unitCost }
    func validate() throws {
        guard !symbol.isEmpty, !name.isEmpty, shares.isFinite, shares > 0,
              shares <= 1e10, unitCost.isFinite, unitCost >= 0, unitCost <= 1e9,
              cost.isFinite, broker.count <= 120, symbol.count <= 20, name.count <= 120 else { throw StoreError.invalidHolding }
    }
}
enum TradeAction: String, Codable, CaseIterable { case buy = "買進", sell = "賣出", adjust = "調整", remove = "移除", brokerImport = "匯入" }
/// A change the user made to a holding in this app; not a broker fill report.
struct Trade: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var action: TradeAction
    var symbol: String
    var name: String
    var shares: Double
    var unitCost: Double
    var broker: String
    /// Money paid (buy, cost included) or received (sell, fees deducted); older entries derive it from shares × unit cost.
    var amount: Double? = nil
    /// Proceeds minus the average cost of the shares sold.
    var realized: Double? = nil
    var total: Double { amount ?? shares * unitCost }
    var isValid: Bool {
        guard !symbol.isEmpty, symbol.count <= 20, name.count <= 120, broker.count <= 120 else { return false }
        guard shares.isFinite, shares >= 0, shares <= 1e10, unitCost.isFinite, unitCost >= 0, unitCost <= 1e9 else { return false }
        if let amount, !(amount.isFinite && amount >= 0 && amount <= 1e12) { return false }
        if let realized, !realized.isFinite { return false }
        return true
    }
    init(id: UUID = UUID(), date: Date = Date(), action: TradeAction, holding: Holding, amount: Double? = nil) {
        self.id = id; self.date = date; self.action = action
        symbol = holding.symbol; name = holding.name; shares = holding.shares; unitCost = holding.unitCost; broker = holding.broker
        self.amount = amount
    }
    init(date: Date, action: TradeAction, symbol: String, name: String, shares: Double, amount: Double, broker: String, realized: Double? = nil) {
        self.date = date; self.action = action; self.symbol = symbol; self.name = name; self.shares = shares
        unitCost = shares > 0 ? amount / shares : 0; self.amount = amount; self.broker = broker; self.realized = realized
    }
}
enum DividendStatus: String, Codable, CaseIterable { case paid = "已入帳", announced = "已公告", estimated = "預估" }
struct Dividend: Identifiable, Codable {
    var id = UUID()
    var symbol: String
    /// Payment date (or expected payment date).
    var date: Date
    /// Amount received after deductions.
    var amount: Double
    var status: DividendStatus
    var exDate: Date? = nil
    var shares: Double? = nil
    var perShare: Double? = nil
    var deduction: Double? = nil
    var source: String? = nil
    var note: String? = nil
    /// The holding the record was made from. 現股 and 融資 (or two brokers) of one code are separate holdings, each
    /// paid on its own shares; nil for records of the whole code and older ones.
    var holdingID: UUID? = nil
    /// Shares × amount per unit, before deductions, when both are recorded.
    var gross: Double? {
        guard let shares, let perShare, shares > 0, perShare > 0 else { return nil }
        return (shares * perShare).rounded()
    }
    var detailsValid: Bool {
        [shares, perShare, deduction].allSatisfy { value in value.map { $0.isFinite && $0 >= 0 && $0 <= 1e10 } ?? true }
            && (source?.count ?? 0) <= 20 && (note?.count ?? 0) <= 80
    }
}
/// Where a dividend record came from; the source also sets its status.
enum DividendSource: String, CaseIterable, Identifiable {
    case broker = "證券帳務", announcement = "投信公告", estimate = "自行預估"
    var id: String { rawValue }
    var status: DividendStatus { switch self { case .broker: return .paid; case .announcement: return .announced; case .estimate: return .estimated } }
}
struct Quote: Codable {
    var symbol: String
    var price: Double
    var changePercent: Double?
    var date: String
    var fetchedAt: Date
    var currency: String? = nil
    var change: Double? = nil
    var open: Double? = nil
    var high: Double? = nil
    var low: Double? = nil
    /// Trading volume in lots (張), as reported by Fugle intraday quotes.
    var volume: Double? = nil
    /// `OpenData.source` for a trading day's close from the exchanges' open data; nil for Fugle and older saved quotes.
    var source: String? = nil
    /// True while the price is a trial match (before the open or in the closing call) rather than a trade; never saved.
    var trial: Bool? = nil
    /// A trading day's close (the open data, or the bundled snapshot stamped 13:30 that day) rather than a live price.
    var isDailyClose: Bool { source == OpenData.source || DataChecks.date(date).map { $0.addingTimeInterval(13.5 * 3600) == fetchedAt } ?? false }
    var isTWD: Bool { currency == "TWD" || (currency == nil && Fund.starters.contains { $0.id == symbol }) }
    var isValid: Bool {
        price.isFinite && price > 0 && [change, changePercent].allSatisfy { $0?.isFinite ?? true }
            && [open, high, low, volume].allSatisfy { value in value.map { $0.isFinite && $0 >= 0 } ?? true }
    }
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
    /// Absent in files written before the trade log existed.
    var trades: [Trade]? = nil
    /// 個股＋ETF 組合試算 settings and simulated mix; absent in older files.
    var combo: ComboSettings? = nil
    var cost: Double { holdings.reduce(0) { $0 + $1.cost } }
    /// Appends to the trade log, keeping the most recent 5,000 entries.
    mutating func log(_ action: TradeAction, _ holding: Holding, date: Date = Date(), amount: Double? = nil) {
        var list = trades ?? []
        list.append(Trade(date: date, action: action, holding: holding, amount: amount))
        if list.count > 5000 { list.removeFirst(list.count - 5000) }
        trades = list
    }
    mutating func log(_ trade: Trade) {
        var list = trades ?? []
        list.append(trade)
        if list.count > 5000 { list.removeFirst(list.count - 5000) }
        trades = list
    }
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
              value.dividends.allSatisfy({ !$0.symbol.isEmpty && $0.amount.isFinite && $0.amount >= 0 && $0.detailsValid }),
              value.quotes.allSatisfy({ $0.key == $0.value.symbol && $0.value.isValid }),
              (value.trades?.count ?? 0) <= 50000,
              Set((value.trades ?? []).map(\.id)).count == (value.trades?.count ?? 0),
              (value.trades ?? []).allSatisfy(\.isValid),
              value.combo?.isValid ?? true
        else { throw StoreError.unsupportedBackup }
        try value.legacyPlan?.validate()
        for d in (value.legacyDividends ?? [:]).values { try d.validate() }
        for (code, snapshot) in value.components ?? [:] { guard code == snapshot.symbol else { throw StoreError.unsupportedBackup }; try snapshot.validate() }
        for (code, history) in value.histories ?? [:] { guard code == history.symbol else { throw StoreError.unsupportedBackup }; try history.validate() }
        for (code, fee) in value.fees ?? [:] { guard code == fee.symbol else { throw StoreError.unsupportedBackup }; try fee.validate() }
        guard (value.comparison?.count ?? 0) <= 3, (value.comparison ?? []).allSatisfy(DataChecks.code),
              (value.legacyPrices ?? [:]).values.allSatisfy({ DataChecks.code($0.symbol) && $0.price.isFinite && $0.price >= 0 && DataChecks.date($0.date) != nil }) else { throw StoreError.unsupportedBackup }
        return value
    }
}
enum StoreError: LocalizedError {
    case invalidHolding, unsupportedBackup, missingKey, invalidQuote, keychain(OSStatus), http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidHolding: return "請填寫代碼與名稱，股數須大於 0，成本不可為負數。"
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
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded.write(to: url, options: [.atomic, .completeFileProtection])
        data = next
    }
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
        guard DataChecks.code(symbol) else { throw AppDataError("請輸入正確的股票或 ETF 代號。") }
        guard shares.isFinite, shares > 0, shares <= 1e10, amount.isFinite, amount >= 0, amount <= 1e12 else { throw AppDataError("請填寫股數與成交金額。") }
        var next = data
        let same = next.holdings.indices.filter { next.holdings[$0].symbol == symbol }
        let target = broker.isEmpty ? (same.count == 1 ? same.first : same.first(where: { next.holdings[$0].broker.isEmpty })) : same.first(where: { next.holdings[$0].broker == broker })
        let fundName = funds.first { $0.id == symbol }?.name ?? stock(symbol)?.name
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
    func refreshCatalog() async {
        guard !catalogRefreshing else { return }
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
enum Fugle {
    struct Total: Decodable { let tradeVolume: Double? }
    struct Response: Decodable { let symbol: String; let date: String; let closePrice: Double?; let lastPrice: Double?; let changePercent: Double?; let change: Double?; let openPrice: Double?; let highPrice: Double?; let lowPrice: Double?; let total: Total?; let isTrial: Bool? }
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
    static func decode(_ bytes: Data, expectedSymbol: String) throws -> Quote {
        let value = try JSONDecoder().decode(Response.self, from: bytes)
        // During a trial match only lastPrice moves (closePrice is the last real trade), as in the stream.
        let trial = value.isTrial == true
        guard value.symbol == expectedSymbol, let price = trial ? (value.lastPrice ?? value.closePrice) : (value.closePrice ?? value.lastPrice), price.isFinite, price > 0 else { throw StoreError.invalidQuote }
        let quote = Quote(symbol: value.symbol, price: price, changePercent: value.changePercent, date: value.date, fetchedAt: Date(), change: value.change, open: value.openPrice, high: value.highPrice, low: value.lowPrice, volume: value.total?.tradeVolume, trial: trial ? true : nil)
        guard quote.isValid else { throw StoreError.invalidQuote }
        return quote
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
