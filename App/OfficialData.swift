import Foundation

/// One official ETF distribution: ex-dividend date, payment date ("" when not announced) and amount per unit (nil until set).
struct OfficialDistribution: Codable, Hashable {
    var ex: String
    var pay: String
    var amount: Double?
}
/// Official distributions from the ex-rights and ex-dividend notices in the exchanges' open data, TWSE 上市股票除權除息
/// 預告表 and TPEx 上櫃股票除權除息預告表: upcoming ex-dividend days and cash amounts, without the payment day. Each
/// refresh adds to what is known, so the record builds up from the day in sources["since"]; figures over the past year
/// (frequency, trailing amount) wait until the record covers it. Bundled as official-dividends.json.
struct OfficialDividends: Codable {
    var sources: [String: String] = [:]
    var events: [String: [OfficialDistribution]] = [:]
    var freq: [String: String] = [:]

    static func bundled() -> OfficialDividends {
        guard let url = Bundle.main.url(forResource: "official-dividends", withExtension: "json"),
              let bytes = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(OfficialDividends.self, from: bytes) else { return OfficialDividends() }
        return value
    }
    func isNewer(than other: OfficialDividends) -> Bool { (sources["twse"] ?? "") > (other.sources["twse"] ?? "") || ((sources["twse"] ?? "") == (other.sources["twse"] ?? "") && (sources["tpex"] ?? "") > (other.sources["tpex"] ?? "")) }
    func list(_ symbol: String) -> [OfficialDistribution] { events[symbol] ?? [] }
    func frequency(_ symbol: String) -> String? { freq[symbol] }
    /// The day the record starts; nil for a record kept from before, which held data read from the TWSE website.
    var since: String? { sources["since"] }
    /// Whether the record covers the past year, so counts and sums over it are whole.
    var coversYear: Bool { (since ?? "9999") <= DataChecks.day(Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()) }
    /// Sum of announced amounts per unit with an ex-dividend date in the past year; nil until the record covers it.
    func trailingAmount(_ symbol: String) -> Double? {
        guard coversYear else { return nil }
        let from = DataChecks.day(Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()), today = DataChecks.day()
        let items = list(symbol).filter { $0.ex > from && $0.ex <= today && ($0.amount ?? 0) > 0 }
        return items.isEmpty ? nil : items.reduce(0) { $0 + ($1.amount ?? 0) }
    }
    /// Distribution frequency from the number of ex-dividend dates in the past year.
    static func frequency(of list: [OfficialDistribution]) -> String? {
        let from = DataChecks.day(Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()), today = DataChecks.day()
        let n = list.filter { $0.ex > from && $0.ex <= today }.count
        switch n {
        case 9...: return "月配"
        case 5...8: return "雙月配"
        case 3...4: return "季配"
        case 2: return "半年配"
        case 1: return "年配"
        default: return nil
        }
    }
    /// "115年10月22日" or "1151016" → "2026-10-22".
    static func rocDay(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespaces)
        let parts: [Int]
        if value.contains("年") {
            parts = value.replacingOccurrences(of: "年", with: "-").replacingOccurrences(of: "月", with: "-").replacingOccurrences(of: "日", with: "").split(separator: "-").compactMap { Int($0) }
        } else if value.count == 7, value.allSatisfy(\.isNumber) {
            parts = [Int(value.prefix(3)), Int(value.dropFirst(3).prefix(2)), Int(value.suffix(2))].compactMap { $0 }
        } else { return nil }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return String(format: "%04d-%02d-%02d", parts[0] + 1911, parts[1], parts[2])
    }
    static let twseURL = URL(string: "https://openapi.twse.com.tw/v1/exchangeReport/TWT48U_ALL")!
    static let tpexURL = URL(string: "https://www.tpex.org.tw/openapi/v1/tpex_exright_prepost")!
    /// The notice's ETFs among `markets` with a cash dividend (息, 權息): ex-dividend day and amount per unit, nil until
    /// set. TWSE names the fields Code, Date and Exdividend; TPEx SecuritiesCompanyCode, ExRrightsExDividendDate and
    /// ExRrightsExDividend. Both write dates in ROC years ("1151022").
    static func decode(_ bytes: Data, market: String, markets: [String: String]) throws -> [String: [OfficialDistribution]] {
        let keys = market == "TPEx" ? ("SecuritiesCompanyCode", "ExRrightsExDividendDate", "ExRrightsExDividend") : ("Code", "Date", "Exdividend")
        var data = bytes
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]], rows.first.map({ $0[keys.0] != nil && $0[keys.1] != nil }) ?? true
        else { throw AppDataError(market == "TPEx" ? "上櫃配息資料格式不符。" : "上市配息資料格式不符。") }
        var events: [String: [OfficialDistribution]] = [:]
        for row in rows {
            guard let symbol = (row[keys.0] as? String)?.trimmingCharacters(in: .whitespaces), market == "TPEx" ? markets[symbol] == "TPEx" : markets[symbol] != nil,
                  (row[keys.2] as? String ?? "").contains("息"), let ex = rocDay(row[keys.1] as? String ?? "") else { continue }
            let amount = Double((row["CashDividend"] as? String ?? "").replacingOccurrences(of: ",", with: "")).flatMap { $0 > 0 ? $0 : nil }
            events[symbol, default: []].append(OfficialDistribution(ex: ex, pay: "", amount: amount))
        }
        return events
    }
    /// Adds announcements to the known ones: a known ex-dividend day keeps its payment day, and its amount until the
    /// notice sets one. With `frequency`, once the record covers the past year, the label is worked out again from it.
    func merging(_ fresh: [String: [OfficialDistribution]], frequency: Bool) -> OfficialDividends {
        var next = self
        for (symbol, items) in fresh {
            var byDay = Dictionary(list(symbol).map { ($0.ex, $0) }, uniquingKeysWith: { first, _ in first })
            for item in items { byDay[item.ex] = OfficialDistribution(ex: item.ex, pay: byDay[item.ex]?.pay ?? "", amount: item.amount ?? byDay[item.ex]?.amount) }
            next.events[symbol] = byDay.values.sorted { $0.ex > $1.ex }
            if frequency, coversYear, let label = Self.frequency(of: next.events[symbol] ?? []) { next.freq[symbol] = label }
        }
        return next
    }
    /// Fetches both exchanges' notices; a source that fails keeps the previous data. Only listed ETFs have the earlier
    /// record (bundled from TWSE) to tell the frequency from.
    static func fetch(merging old: OfficialDividends, markets: [String: String]) async throws -> OfficialDividends {
        var next = old
        // A record without its start day holds data read from the TWSE website: start over from the notices.
        if next.since == nil { next = OfficialDividends(sources: ["since": DataChecks.day()]) }
        var errors: [String] = []
        for (market, url, label) in [("TWSE", twseURL, "上市"), ("TPEx", tpexURL, "上櫃")] {
            do {
                let bytes = try await PublicHTTP.get(url)
                let fresh = try decode(bytes, market: market, markets: markets)
                next = next.merging(fresh, frequency: market == "TWSE")
                next.sources[market.lowercased()] = DataChecks.day()
            } catch { errors.append("\(label)：\(error.localizedDescription)") }
        }
        if errors.count == 2 { throw AppDataError("無法更新官方配息資料，保留原本資料。\(errors.joined(separator: "；"))") }
        return next
    }
}
extension PortfolioStore {
    /// Official announcements for held ETFs (ex-dividend from a week ago onwards) not yet in the user's records, one per
    /// holding with its own shares: 現股 and 融資 (or two brokers) of the same code are separate holdings.
    func officialForHoldings() -> [(symbol: String, event: OfficialDistribution, shares: Double, holding: Holding)] {
        let from = DataChecks.day(Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date())
        var result: [(symbol: String, event: OfficialDistribution, shares: Double, holding: Holding)] = []
        for holding in data.holdings.sorted(by: { ($0.symbol, $0.broker) < ($1.symbol, $1.broker) }) {
            for event in official.list(holding.symbol) where event.ex >= from {
                let recorded = data.dividends.contains { $0.symbol == holding.symbol && ($0.holdingID == nil || $0.holdingID == holding.id)
                    && ($0.exDate.map(DataChecks.day) == event.ex || (!event.pay.isEmpty && DataChecks.day($0.date) == event.pay)) }
                if !recorded { result.append((holding.symbol, event, holding.shares, holding)) }
            }
        }
        return result.sorted { $0.event.ex < $1.event.ex }
    }
    /// The shares a dividend record is for: the holding it was recorded from, else every holding of the code.
    func dividendShares(_ symbol: String, holding: UUID?) -> Double {
        if let holding, let one = data.holdings.first(where: { $0.id == holding && $0.symbol == symbol }) { return one.shares }
        return data.holdings.filter { $0.symbol == symbol }.reduce(0) { $0 + $1.shares }
    }
}
