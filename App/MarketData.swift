import Foundation

/// The last ETF closes and both market indices, bundled from the exchanges' open data by WebPreview/build_stocks.py.
/// The app is ETF only: nothing about companies is bundled. Newer closes come from OpenData; live prices only from
/// the viewer's own Fugle key.
final class MarketSnapshot {
    struct IndexDay { let date: String; let close: Double }
    struct MarketIndex {
        let name: String
        let date: String
        let close: Double?
        let change: Double?
        let percent: Double?
        let history: [IndexDay]
    }

    let fetchedDay: String
    let closeDate: [String: String]
    let indices: [String: MarketIndex]
    private let closes: [String: [Double?]]

    static let bundled: MarketSnapshot? = {
        guard let url = Bundle.main.url(forResource: "market-data", withExtension: "json"), let bytes = try? Data(contentsOf: url) else { return nil }
        return MarketSnapshot(bytes)
    }()

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber else { return nil }
        let double = value.doubleValue
        return double.isFinite ? double : nil
    }
    private static func text(_ value: Any?) -> String { (value as? String) ?? "" }

    init?(_ bytes: Data) {
        guard let root = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any], let rows = root["close"] as? [String: [Any]] else { return nil }
        fetchedDay = Self.text(root["fetchedDay"])
        closeDate = (root["closeDate"] as? [String: String]) ?? [:]
        closes = rows.mapValues { $0.map { Self.number($0) } }
        var indexMap: [String: MarketIndex] = [:]
        for (key, value) in (root["index"] as? [String: [String: Any]]) ?? [:] {
            let days = ((value["hist"] as? [[Any]]) ?? []).compactMap { pair -> IndexDay? in
                guard pair.count == 2, let close = Self.number(pair[1]) else { return nil }
                return IndexDay(date: Self.text(pair[0]), close: close)
            }
            indexMap[key] = MarketIndex(name: Self.text(value["name"]), date: Self.text(value["date"]), close: Self.number(value["close"]), change: Self.number(value["change"]), percent: Self.number(value["pct"]), history: days)
        }
        indices = indexMap
    }

    /// The exchange's last close as a quote, dated with the trading day of the fund's market.
    func close(_ symbol: String, market: String?) -> Quote? {
        guard let row = closes[symbol], row.count >= 6, let price = row[0], price > 0 else { return nil }
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
}

extension PortfolioStore {
    var marketSnapshot: MarketSnapshot? { MarketSnapshot.bundled }
    /// ETF codes start with 00 or are in the official list. Anything else is a record kept from an older version
    /// that also tracked company shares; it stays readable but is left out of ETF features.
    func isETF(_ symbol: String) -> Bool { symbol.hasPrefix("00") || funds.contains { $0.id == symbol } }
    /// The freshest price for a symbol: the user's own Fugle quote, else the bundled last close when it is newer.
    func quote(_ symbol: String) -> Quote? {
        var own = data.quotes[symbol]
        // A trial-match price only while its auction can still be running (each lasts at most half an hour).
        if let live = liveQuotes[symbol], live.trial != true || live.fetchedAt.timeIntervalSinceNow > -1800, live.fetchedAt > (own?.fetchedAt ?? .distantPast) { own = live }
        // The latest close: the open data fetched on the device, else the bundled snapshot.
        let market = funds.first { $0.id == symbol }?.market
        let closes = [daily?.quotes[symbol], MarketSnapshot.bundled?.close(symbol, market: market)].compactMap { $0 }
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
