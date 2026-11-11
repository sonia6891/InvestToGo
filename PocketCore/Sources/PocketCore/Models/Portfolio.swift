import Foundation

public enum Strategy: String, Codable, CaseIterable, Identifiable {
    case saving = "存錢筒", income = "印鈔機", risk = "老虎機", unclassified = "待分類"
    public var id: String { rawValue }
    /// SF Symbol name; kept as plain text so the core stays UI-free.
    public var symbol: String {
        switch self { case .saving: return "leaf"; case .income: return "banknote"; case .risk: return "bolt"; case .unclassified: return "tag" }
    }
    public var subtitle: String {
        switch self { case .saving: return "長期累積"; case .income: return "關注配息"; case .risk: return "高波動策略"; case .unclassified: return "自行選擇策略" }
    }
}

public struct Fund: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var strategy: Strategy
    public var market: String? = nil
    public var fullName: String? = nil
    public var fundType: String? = nil
    public var listingDate: String? = nil
    public init(id: String, name: String, strategy: Strategy, market: String? = nil, fullName: String? = nil, fundType: String? = nil, listingDate: String? = nil) {
        self.id = id; self.name = name; self.strategy = strategy; self.market = market; self.fullName = fullName; self.fundType = fundType; self.listingDate = listingDate
    }
    // Demo-only catalogue; the normal app uses the validated TWSE + TPEx catalogue.
    public static let starters: [Fund] = [
        .init(id: "0050", name: "元大台灣50", strategy: .saving),
        .init(id: "006208", name: "富邦台50", strategy: .saving),
        .init(id: "0056", name: "元大高股息", strategy: .income),
        .init(id: "00878", name: "國泰永續高股息", strategy: .income),
        .init(id: "00919", name: "群益台灣精選高息", strategy: .income),
        .init(id: "00631L", name: "元大台灣50正2", strategy: .risk)
    ]
}

public struct Holding: Identifiable, Codable {
    public var id = UUID()
    public var symbol: String
    public var name: String
    public var shares: Double
    public var unitCost: Double
    public var broker: String
    public var strategy: Strategy
    public var sourceAccount: String? = nil
    public init(id: UUID = UUID(), symbol: String, name: String, shares: Double, unitCost: Double, broker: String, strategy: Strategy, sourceAccount: String? = nil) {
        self.id = id; self.symbol = symbol; self.name = name; self.shares = shares; self.unitCost = unitCost; self.broker = broker; self.strategy = strategy; self.sourceAccount = sourceAccount
    }
    public var cost: Double { shares * unitCost }
    public func validate() throws {
        guard !symbol.isEmpty, !name.isEmpty, shares.isFinite, shares > 0,
              shares <= 1e10, unitCost.isFinite, unitCost >= 0, unitCost <= 1e9,
              cost.isFinite, !broker.isEmpty, broker.count <= 120, symbol.count <= 20, name.count <= 120 else { throw StoreError.invalidHolding }
    }
}

public enum DividendStatus: String, Codable, CaseIterable { case paid = "已入帳", announced = "已公告", estimated = "預估" }

public struct Dividend: Identifiable, Codable {
    public var id = UUID()
    public var symbol: String
    public var date: Date
    public var amount: Double
    public var status: DividendStatus
    public init(id: UUID = UUID(), symbol: String, date: Date, amount: Double, status: DividendStatus) {
        self.id = id; self.symbol = symbol; self.date = date; self.amount = amount; self.status = status
    }
}

public struct Quote: Codable {
    public var symbol: String
    public var price: Double
    public var changePercent: Double?
    public var date: String
    public var fetchedAt: Date
    public var currency: String? = nil
    public init(symbol: String, price: Double, changePercent: Double?, date: String, fetchedAt: Date, currency: String? = nil) {
        self.symbol = symbol; self.price = price; self.changePercent = changePercent; self.date = date; self.fetchedAt = fetchedAt; self.currency = currency
    }
    public var isTWD: Bool { currency == "TWD" || (currency == nil && Fund.starters.contains { $0.id == symbol }) }
}

public struct Portfolio: Codable {
    public var schema = 1
    public var holdings: [Holding] = []
    public var dividends: [Dividend] = []
    public var favorites: Set<String> = []
    public var quotes: [String: Quote] = [:]
    public var comparison: [String]? = nil
    public var legacyPlan: LegacyPlan? = nil
    public var legacyPrices: [String: LegacyPrice]? = nil
    public var legacyDividends: [String: BackupImport.OldDividend]? = nil
    public var components: [String: ComponentSnapshot]? = nil
    public var histories: [String: PriceHistory]? = nil
    public var fees: [String: FeeRecord]? = nil
    public init() {}
    public var cost: Double { holdings.reduce(0) { $0 + $1.cost } }
    public var marketValue: Double? {
        guard !holdings.isEmpty, holdings.allSatisfy({ quotes[$0.symbol]?.isTWD == true }) else { return nil }
        return holdings.reduce(0) { $0 + $1.shares * quotes[$1.symbol]!.price }
    }
    public static func decodeBackup(_ data: Data) throws -> Portfolio {
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
        for d in (value.legacyDividends ?? [:]).values { try d.validate() }
        for (code, snapshot) in value.components ?? [:] { guard code == snapshot.symbol else { throw StoreError.unsupportedBackup }; try snapshot.validate() }
        for (code, history) in value.histories ?? [:] { guard code == history.symbol else { throw StoreError.unsupportedBackup }; try history.validate() }
        for (code, fee) in value.fees ?? [:] { guard code == fee.symbol else { throw StoreError.unsupportedBackup }; try fee.validate() }
        guard (value.comparison?.count ?? 0) <= 3, (value.comparison ?? []).allSatisfy(DataChecks.code),
              (value.legacyPrices ?? [:]).values.allSatisfy({ DataChecks.code($0.symbol) && $0.price.isFinite && $0.price >= 0 && DataChecks.date($0.date) != nil }) else { throw StoreError.unsupportedBackup }
        return value
    }
    public static var demo: Portfolio {
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

public enum StoreError: LocalizedError {
    case invalidHolding, unsupportedBackup, missingKey, invalidQuote, keychain(Int32), http(Int)
    public var errorDescription: String? {
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
