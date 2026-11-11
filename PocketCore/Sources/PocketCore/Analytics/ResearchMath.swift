import Foundation

public struct ExposureRow: Identifiable {
    public var symbol: String
    public var name: String
    public var value: Double
    public var funds: Set<String>
    public var id: String { symbol }
}

public struct OverlapRow: Identifiable {
    public var symbol: String
    public var name: String
    public var left: Double
    public var right: Double
    public var id: String { symbol }
}

public enum ResearchMath {
    public static func exposures(_ portfolio: Portfolio) -> [ExposureRow] {
        var result: [String: ExposureRow] = [:]
        for h in portfolio.holdings {
            guard let quote = portfolio.quotes[h.symbol], quote.isTWD, let snapshot = portfolio.components?[h.symbol] else { continue }
            for c in snapshot.components {
                var row = result[c.symbol] ?? ExposureRow(symbol: c.symbol, name: c.name ?? c.symbol, value: 0, funds: [])
                row.value += h.shares * quote.price * c.weight / 100; row.funds.insert(h.symbol); result[c.symbol] = row
            }
        }
        return result.values.sorted { $0.value == $1.value ? $0.symbol < $1.symbol : $0.value > $1.value }
    }
    public static func overlap(_ left: ComponentSnapshot, _ right: ComponentSnapshot) -> [OverlapRow] {
        let other = Dictionary(uniqueKeysWithValues: right.components.map { ($0.symbol, $0) })
        return left.components.compactMap { x -> OverlapRow? in
            guard let y = other[x.symbol] else { return nil }
            return OverlapRow(symbol: x.symbol, name: x.name ?? y.name ?? x.symbol, left: x.weight, right: y.weight)
        }.sorted { min($0.left, $0.right) > min($1.left, $1.right) }
    }
}

public struct PerformanceStats {
    public let change: Double
    public let annualized: Double?
    public let drawdown: Double
    public let volatility: Double?
    public init(_ history: PriceHistory) throws {
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
