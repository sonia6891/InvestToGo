import Foundation

/// A company listed on TWSE (上市) or TPEx (上櫃).
struct StockInfo: Identifiable, Hashable {
    let id: String
    let name: String
    /// "TWSE" or "TPEx".
    let market: String
    let industry: String
    let fullName: String
    let listingDate: String
    var marketName: String { market == "TPEx" ? "上櫃" : "上市" }
}

/// Taiwan stocks, last closes, both market indices and company figures, bundled from the exchanges' open data
/// by WebPreview/build_stocks.py (the same file the web app uses). Newer closes come from OpenData; live prices
/// only from the viewer's own Fugle key.
final class StockSnapshot {
    struct IndexDay { let date: String; let close: Double }
    struct MarketIndex {
        let name: String
        let date: String
        let close: Double?
        let change: Double?
        let percent: Double?
        let history: [IndexDay]
    }
    struct Revenue { let month: String; let amount: Double?; let monthChange: Double?; let yearChange: Double?; let cumulative: Double?; let cumulativeChange: Double? }
    struct Earnings { let year: Int; let quarter: Int; let value: Double }
    struct Policy: Identifiable { let year: String; let period: String; let cash: Double; let stock: Double; let meeting: String; let progress: String; var id: String { year + period } }
    struct ExRight: Identifiable { let date: String; let value: Double?; let kind: String; var id: String { date + kind } }

    let fetchedDay: String
    let closeDate: [String: String]
    let stocks: [StockInfo]
    let byID: [String: StockInfo]
    let industries: [String]
    let indices: [String: MarketIndex]
    let revenue: [String: Revenue]
    let earnings: [String: Earnings]
    let policies: [String: [Policy]]
    let exHistory: [String: [ExRight]]
    let exUpcoming: [String: [ExRight]]
    /// The day the ex-date history started from the exchanges' open data alone.
    let exHistorySince: String?
    private let closes: [String: [Double?]]

    static let bundled: StockSnapshot? = {
        guard let url = Bundle.main.url(forResource: "stock-data", withExtension: "json"), let bytes = try? Data(contentsOf: url) else { return nil }
        return StockSnapshot(bytes)
    }()

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber else { return nil }
        let double = value.doubleValue
        return double.isFinite ? double : nil
    }
    private static func text(_ value: Any?) -> String { (value as? String) ?? "" }

    init?(_ bytes: Data) {
        guard let root = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
              let rows = root["stocks"] as? [[Any]], let industryNames = root["industries"] as? [String] else { return nil }
        fetchedDay = Self.text(root["fetchedDay"])
        closeDate = (root["closeDate"] as? [String: String]) ?? [:]
        industries = industryNames
        var list: [StockInfo] = []
        for row in rows where row.count >= 6 {
            let index = Int(Self.number(row[3]) ?? -1)
            let industry = industryNames.indices.contains(index) ? industryNames[index] : "其他"
            list.append(StockInfo(id: Self.text(row[0]), name: Self.text(row[1]), market: Self.number(row[2]) == 2 ? "TPEx" : "TWSE", industry: industry, fullName: Self.text(row[4]), listingDate: Self.text(row[5])))
        }
        stocks = list
        byID = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var closeRows: [String: [Double?]] = [:]
        for (code, value) in (root["close"] as? [String: [Any]]) ?? [:] { closeRows[code] = value.map { Self.number($0) } }
        closes = closeRows
        var indexMap: [String: MarketIndex] = [:]
        for (key, value) in (root["index"] as? [String: [String: Any]]) ?? [:] {
            let days = ((value["hist"] as? [[Any]]) ?? []).compactMap { pair -> IndexDay? in
                guard pair.count == 2, let close = Self.number(pair[1]) else { return nil }
                return IndexDay(date: Self.text(pair[0]), close: close)
            }
            indexMap[key] = MarketIndex(name: Self.text(value["name"]), date: Self.text(value["date"]), close: Self.number(value["close"]), change: Self.number(value["change"]), percent: Self.number(value["pct"]), history: days)
        }
        indices = indexMap
        var revenueMap: [String: Revenue] = [:]
        for (code, value) in (root["revenue"] as? [String: [Any]]) ?? [:] where value.count >= 6 {
            revenueMap[code] = Revenue(month: Self.text(value[0]), amount: Self.number(value[1]), monthChange: Self.number(value[2]), yearChange: Self.number(value[3]), cumulative: Self.number(value[4]), cumulativeChange: Self.number(value[5]))
        }
        revenue = revenueMap
        var earningsMap: [String: Earnings] = [:]
        for (code, value) in (root["eps"] as? [String: [Any]]) ?? [:] where value.count >= 3 {
            if let year = Self.number(value[0]), let quarter = Self.number(value[1]), let eps = Self.number(value[2]) { earningsMap[code] = Earnings(year: Int(year), quarter: Int(quarter), value: eps) }
        }
        earnings = earningsMap
        var policyMap: [String: [Policy]] = [:]
        for (code, value) in (root["divPolicy"] as? [String: [[Any]]]) ?? [:] {
            policyMap[code] = value.filter { $0.count >= 6 }.map { Policy(year: Self.text($0[0]), period: Self.text($0[1]), cash: Self.number($0[2]) ?? 0, stock: Self.number($0[3]) ?? 0, meeting: Self.text($0[4]), progress: Self.text($0[5])) }
        }
        policies = policyMap
        func exRights(_ key: String) -> [String: [ExRight]] {
            var map: [String: [ExRight]] = [:]
            for (code, value) in (root[key] as? [String: [[Any]]]) ?? [:] {
                map[code] = value.filter { $0.count >= 3 }.map { ExRight(date: Self.text($0[0]), value: Self.number($0[1]), kind: Self.text($0[2])) }
            }
            return map
        }
        exHistory = exRights("exHist")
        exUpcoming = exRights("exNext")
        exHistorySince = (root["since"] as? [String: Any])?["exHist"] as? String
    }

    /// The exchange's last close as a quote, dated with the trading day.
    func close(_ symbol: String) -> Quote? {
        guard let row = closes[symbol], row.count >= 6, let price = row[0], price > 0 else { return nil }
        let market = byID[symbol]?.market ?? "TWSE"
        let day = closeDate[market == "TPEx" ? "tpex" : "twse"] ?? closeDate["twse"] ?? ""
        let change = row[1]
        let previous = change.map { price - $0 }
        let percent: Double? = (previous ?? 0) > 0 ? (change ?? 0) / previous! * 100 : nil
        let fetched = DataChecks.date(day).map { $0.addingTimeInterval(13.5 * 3600) } ?? Date.distantPast
        var quote = Quote(symbol: symbol, price: price, changePercent: percent, date: day, fetchedAt: fetched, currency: "TWD", change: change, open: row[2], high: row[3], low: row[4], volume: row[5].map { ($0 / 1000).rounded() }, source: OpenData.source)
        if !quote.isValid { quote.open = nil; quote.high = nil; quote.low = nil; quote.volume = nil }
        return quote.isValid ? quote : nil
    }
    /// Most traded on the last bundled day, by turnover.
    func mostTraded(_ symbols: [String], count: Int) -> [String] {
        let ranked = symbols.compactMap { symbol -> (String, Double)? in
            guard let row = closes[symbol], row.count >= 7, let value = row[6], value > 0 else { return nil }
            return (symbol, value)
        }
        return ranked.sorted { $0.1 > $1.1 }.prefix(count).map(\.0)
    }
    /// Whether the ex-date history covers the past year, so sums over it are whole.
    var exHistoryCoversYear: Bool { (exHistorySince ?? "9999") <= DataChecks.day(Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()) }
    /// Cash paid in pure ex-dividend events during the past year (per share); nil until the history covers it.
    func trailingCash(_ symbol: String) -> Double? {
        guard exHistoryCoversYear else { return nil }
        let start = DataChecks.day(Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date())
        return (exHistory[symbol] ?? []).filter { $0.date > start && $0.kind == "息" }.reduce(0) { $0 + ($1.value ?? 0) }
    }
}

extension PortfolioStore {
    var stockSnapshot: StockSnapshot? { StockSnapshot.bundled }
    func stock(_ symbol: String) -> StockInfo? { StockSnapshot.bundled?.byID[symbol] }
    /// Company shares have four-digit codes (optionally a letter); ETF codes start with 00.
    func isStock(_ symbol: String) -> Bool {
        if symbol.hasPrefix("00") || funds.contains(where: { $0.id == symbol }) { return false }
        return stock(symbol) != nil || symbol.range(of: "^[1-9][0-9]{3}[A-Z]?$", options: .regularExpression) != nil
    }
    /// The freshest price for a symbol: the user's own Fugle quote, else the bundled last close when it is newer.
    func quote(_ symbol: String) -> Quote? {
        var own = data.quotes[symbol]
        // A trial-match price only while its auction can still be running (each lasts at most half an hour).
        if let live = liveQuotes[symbol], live.trial != true || live.fetchedAt.timeIntervalSinceNow > -1800, live.fetchedAt > (own?.fetchedAt ?? .distantPast) { own = live }
        // The latest close: the open data fetched on the device, else the bundled snapshot.
        let closes = [daily?.quotes[symbol], StockSnapshot.bundled?.close(symbol)].compactMap { $0 }
        guard let close = closes.max(by: { $0.fetchedAt < $1.fetchedAt }) else { return own }
        guard let own else { return close }
        return own.fetchedAt.addingTimeInterval(3600) < close.fetchedAt ? close : own
    }
    /// The portfolio with every holding priced by `quote(_:)`, for totals and charts.
    var effectiveData: Portfolio {
        var value = data
        for symbol in Set(value.holdings.map(\.symbol)) { if let quote = quote(symbol) { value.quotes[symbol] = quote } }
        return value
    }
    /// Totals with 市值 as the holdings list shows it (after the estimated selling costs), when every holding is priced.
    var summary: PortfolioSummary {
        let data = effectiveData
        let values = data.holdings.map { marketValue(of: $0) }
        return PortfolioSummary(data, marketValue: data.holdings.isEmpty || values.contains { $0 == nil } ? nil : values.reduce(0) { $0 + ($1 ?? 0) })
    }
    /// Live index quotes with the viewer's key: IX0001 (加權) and IX0043 (櫃買); without one, the latest closes.
    func refreshIndices() async {
        guard let key = try? SecureKey.read(), !key.isEmpty else { await refreshDaily(manual: true); return }
        for (name, symbol) in [("taiex", "IX0001"), ("tpex", "IX0043")] {
            do {
                let bytes = try await PublicHTTP.get(URL(string: "https://api.fugle.tw/marketdata/v1.0/stock/intraday/quote/\(symbol)")!, key: key)
                indices[name] = try Fugle.decode(bytes, expectedSymbol: symbol)
            } catch {
                if let failure = error as? StoreError, case .http(let code) = failure, code == 401 || code == 429 { message = failure.localizedDescription; return }
            }
        }
    }
}
