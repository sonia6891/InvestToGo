import Foundation

struct FundComponent: Codable, Identifiable {
    var symbol: String
    var name: String?
    var weight: Double
    var id: String { symbol }
}
struct ComponentSnapshot: Codable {
    var symbol: String
    var date: String
    var components: [FundComponent]
    var source: String?
    var totalWeight: Double { components.reduce(0) { $0 + $1.weight } }
    func validate() throws {
        guard DataChecks.code(symbol), DataChecks.date(date) != nil, date <= DataChecks.day(), !components.isEmpty, components.count <= 1000,
              Set(components.map(\.symbol)).count == components.count, totalWeight > 0, totalWeight <= 101,
              components.allSatisfy({ !$0.symbol.isEmpty && $0.symbol.count <= 40 && ($0.name?.count ?? 0) <= 120 && $0.weight.isFinite && (0...100).contains($0.weight) }) else { throw AppDataError("成分資料日期、代碼或權重不正確。") }
    }
    static func imported(_ bytes: Data, symbol: String) throws -> Self {
        guard bytes.count <= 1_000_000 else { throw AppDataError("成分檔不可超過 1 MB。") }
        var value = try JSONDecoder().decode(Self.self, from: bytes)
        guard value.symbol == symbol else { throw AppDataError("成分檔與這檔 ETF 的代碼不同。") }
        value.source = "使用者匯入；原來源：" + (value.source ?? "未提供")
        try value.validate(); return value
    }
}
struct ExposureRow: Identifiable {
    var symbol: String
    var name: String
    var value: Double
    var funds: Set<String>
    var id: String { symbol }
}
struct OverlapRow: Identifiable {
    var symbol: String
    var name: String
    var left: Double
    var right: Double
    var id: String { symbol }
}
enum ResearchMath {
    static let direct = "直接持有"
    /// Holdings listed in `stocks` count as directly held and merge into the same row as that stock held through ETFs.
    /// `quote` defaults to the portfolio's own saved quotes.
    static func exposures(_ portfolio: Portfolio, stocks: Set<String> = [], quote: ((String) -> Quote?)? = nil) -> [ExposureRow] {
        let price: (String) -> Quote? = quote ?? { portfolio.quotes[$0] }
        var result: [String: ExposureRow] = [:]
        for h in portfolio.holdings {
            guard let quote = price(h.symbol), quote.isTWD else { continue }
            if let snapshot = portfolio.components?[h.symbol] {
                for c in snapshot.components {
                    var row = result[c.symbol] ?? ExposureRow(symbol: c.symbol, name: c.name ?? c.symbol, value: 0, funds: [])
                    row.value += h.shares * quote.price * c.weight / 100; row.funds.insert(h.symbol); result[c.symbol] = row
                }
            } else if stocks.contains(h.symbol) {
                var row = result[h.symbol] ?? ExposureRow(symbol: h.symbol, name: h.name, value: 0, funds: [])
                row.value += h.shares * quote.price; row.funds.insert(direct); result[h.symbol] = row
            }
        }
        return result.values.sorted { $0.value == $1.value ? $0.symbol < $1.symbol : $0.value > $1.value }
    }
    static func overlap(_ left: ComponentSnapshot, _ right: ComponentSnapshot) -> [OverlapRow] {
        let other = Dictionary(uniqueKeysWithValues: right.components.map { ($0.symbol, $0) })
        return left.components.compactMap { x -> OverlapRow? in
            guard let y = other[x.symbol] else { return nil }
            return OverlapRow(symbol: x.symbol, name: x.name ?? y.name ?? x.symbol, left: x.weight, right: y.weight)
        }.sorted { min($0.left, $0.right) > min($1.left, $1.right) }
    }
}
struct PricePoint: Codable, Identifiable { var date: String; var close: Double; var id: String { date } }
struct PriceHistory: Codable {
    var symbol: String
    var adjusted: Bool
    var points: [PricePoint]
    var fetchedDay: String
    var source: String
    func validate() throws {
        let today = DataChecks.day()
        guard DataChecks.code(symbol), adjusted, points.count >= 2, points.count <= 10000, DataChecks.date(fetchedDay) != nil,
              Set(points.map(\.date)).count == points.count,
              points.allSatisfy({ DataChecks.date($0.date) != nil && $0.date <= today && $0.close.isFinite && $0.close > 0 }),
              zip(points, points.dropFirst()).allSatisfy({ $0.date < $1.date }) else { throw AppDataError("歷史資料缺失、日期重複或沒有確認還原價格，未計算績效。") }
    }
}
struct PerformanceStats {
    let change: Double
    let annualized: Double?
    let drawdown: Double
    let volatility: Double?
    init(_ history: PriceHistory) throws {
        try history.validate()
        let p = history.points; let first = p[0]; let last = p[p.count - 1]
        let days = DataChecks.date(last.date)!.timeIntervalSince(DataChecks.date(first.date)!) / 86400
        change = last.close / first.close - 1
        annualized = days >= 365 ? pow(last.close / first.close, 365.25 / days) - 1 : nil
        var peak = first.close; var maxDrop = 0.0; var returns: [Double] = []
        for (index, point) in p.enumerated() {
            peak = max(peak, point.close); maxDrop = max(maxDrop, 1 - point.close / peak)
            if index > 0 { returns.append(log(point.close / p[index - 1].close)) }
        }
        drawdown = maxDrop
        if returns.count >= 20 {
            let average = returns.reduce(0, +) / Double(returns.count)
            volatility = sqrt(returns.reduce(0) { $0 + pow($1 - average, 2) } / Double(returns.count - 1) * 252)
        } else { volatility = nil }
    }
}
struct FeeRecord: Codable {
    var symbol: String
    var effectiveDate: String
    var management: String
    var custody: String
    var annualExpensePercent: Double?
    var expenseYear: Int?
    var sourceURL: String
    var note: String
    func validate() throws {
        guard DataChecks.code(symbol), DataChecks.date(effectiveDate) != nil, effectiveDate <= DataChecks.day(),
              !management.isEmpty, management.count <= 2000, !custody.isEmpty, custody.count <= 2000, note.count <= 2000 else { throw AppDataError("請填寫費率級距及有效日期。") }
        // A reference address is optional (older records have one); when present it must be a plain https link.
        if !sourceURL.isEmpty {
            guard let url = URL(string: sourceURL), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { throw AppDataError("參考網址須為 https 開頭。") }
        }
        if let rate = annualExpensePercent {
            guard rate.isFinite, (0...100).contains(rate), let year = expenseYear, (1990...Calendar.current.component(.year, from: Date())).contains(year) else { throw AppDataError("總費用率須附統計年度，且數值應為 0～100%。") }
        } else if expenseYear != nil { throw AppDataError("費用年度與總費用率須一起填寫。") }
    }
}
extension Fugle {
    static func data(path: String, symbol: String, query: [URLQueryItem] = []) async throws -> Data {
        guard DataChecks.code(symbol) else { throw StoreError.invalidQuote }
        let key = try SecureKey.read(); guard !key.isEmpty else { throw StoreError.missingKey }
        var url = URLComponents(string: "https://api.fugle.tw/marketdata/v1.0/stock/\(path)/\(symbol)")!; url.queryItems = query.isEmpty ? nil : query
        return try await PublicHTTP.get(url.url!, key: key)
    }
    static func components(symbol: String) async throws -> ComponentSnapshot {
        try decodeComponents(await data(path: "ownership/etf-holdings", symbol: symbol), symbol: symbol)
    }
    static func decodeComponents(_ bytes: Data, symbol: String) throws -> ComponentSnapshot {
        struct Day: Decodable { var date: String; var components: [FundComponent] }
        struct Response: Decodable { var symbol: String; var data: [Day] }
        let response = try JSONDecoder().decode(Response.self, from: bytes)
        guard response.symbol == symbol, let day = response.data.max(by: { $0.date < $1.date }), !day.components.isEmpty else { throw AppDataError("此區間沒有股票成分資料；債券、期貨或部分外幣級別可能沒有此資料，不能視為零重疊。") }
        let value = ComponentSnapshot(symbol: symbol, date: day.date, components: day.components, source: "富果／投信揭露資料")
        try value.validate(); return value
    }
    static func decodeHistory(_ bytes: Data, symbol: String) throws -> [PricePoint] {
        struct Response: Decodable { var symbol: String; var adjusted: Bool?; var timeframe: String; var data: [PricePoint] }
        let value = try JSONDecoder().decode(Response.self, from: bytes)
        guard value.symbol == symbol, value.adjusted == true, value.timeframe == "D" else { throw AppDataError("行情服務未確認還原價格，未計算績效。") }
        return value.data
    }
    static func history(symbol: String, years: Int) async throws -> PriceHistory {
        guard [1,3,5,10,16].contains(years) else { throw AppDataError("不支援此查詢區間。") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let end = DataChecks.date(DataChecks.day())!
        let earliest = DataChecks.date("2010-01-01")!
        var cursor = max(calendar.date(byAdding: .year, value: -years, to: end)!, earliest)
        var points: [PricePoint] = []
        while cursor <= end {
            try Task.checkCancellation()
            let chunkEnd = min(calendar.date(byAdding: .day, value: 359, to: cursor)!, end)
            do {
                let bytes = try await data(path: "historical/candles", symbol: symbol, query: [URLQueryItem(name: "from", value: DataChecks.day(cursor)), URLQueryItem(name: "to", value: DataChecks.day(chunkEnd)), URLQueryItem(name: "timeframe", value: "D"), URLQueryItem(name: "adjusted", value: "true"), URLQueryItem(name: "fields", value: "close"), URLQueryItem(name: "sort", value: "asc")])
                let chunk = try decodeHistory(bytes, symbol: symbol)
                guard chunk.allSatisfy({ $0.date >= DataChecks.day(cursor) && $0.date <= DataChecks.day(chunkEnd) }) else { throw AppDataError("歷史回傳日期超出查詢區間。") }
                points.append(contentsOf: chunk)
            } catch StoreError.http(404) { /* Pre-listing/non-trading intervals may legitimately contain no data. */ }
            cursor = calendar.date(byAdding: .day, value: 1, to: chunkEnd)!
            if cursor <= end { try await Task.sleep(nanoseconds: 1_100_000_000) }
        }
        let history = PriceHistory(symbol: symbol, adjusted: true, points: points.sorted { $0.date < $1.date }, fetchedDay: DataChecks.day(), source: "富果還原日收盤價")
        try history.validate(); return history
    }
}
