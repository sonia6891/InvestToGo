import Foundation

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
    /// A trading day's close (the open data, or the bundled snapshot) rather than a live price.
    var isDailyClose: Bool { source == OpenData.source }
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
    /// `limit` is raised only for the device's own records file, which earlier versions let grow past a backup's
    /// size with price histories; the first save then moves those out.
    static func decodeBackup(_ data: Data, limit: Int = 5_000_000) throws -> Portfolio {
        guard data.count <= limit else { throw StoreError.unsupportedBackup }
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
enum Projection {
    static func value(initial: Double, monthly: Double, years: Int, annualPercent: Double) -> Double {
        let rate = annualPercent / 100 / 12
        var total = initial
        for _ in 0..<(max(years, 0) * 12) { total = total * (1 + rate) + monthly }
        return total
    }
}
