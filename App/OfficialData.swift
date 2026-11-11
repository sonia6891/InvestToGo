import Foundation

extension OfficialDividends {
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
