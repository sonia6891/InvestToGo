import Foundation

/// The four collection-book shelves. Raw values are the labels the dex screen shows.
enum DexSeries: String, CaseIterable {
    case marketCap = "市值型", highDividend = "高股息", bond = "債券", theme = "主題"

    /// Precedence: bond, then high dividend, then market cap; everything else (including leveraged / inverse /
    /// unclassified funds) is a theme.
    static func of(_ fund: Fund) -> DexSeries {
        if (fund.fundType ?? "").contains("債") || fund.name.contains("債") { return .bond }
        if fund.strategy == .income || ["高股息", "高息", "優息"].contains(where: { fund.name.contains($0) }) { return .highDividend }
        if fund.strategy == .saving { return .marketCap }
        return .theme
    }
}

/// Five 1-10 bars, 0 when the fact is missing (the screen shows "—"). Facts only: no total, no recommendation.
struct DexStats: Equatable {
    var fee: Int
    var size: Int
    var yield: Int
    var volatility: Int
    var history: Int
}

/// The raw facts per fund id. Any of them may be missing for a fund.
struct DexFacts {
    var feeRate: [String: Double] = [:]
    var aum: [String: Double] = [:]
    var yield: [String: Double] = [:]
    var volatility: [String: Double] = [:]
    var listed: [String: Date] = [:]
}

enum Dex {
    /// `band = ceil(rank / count * 10)` with `rank` = how many values are <= this fund's (so a tie shares the
    /// HIGHEST rank of its group: tied leaders all get 10 bars, and all-equal values all get 10).
    /// Non-finite values are treated as missing: 0 bars and left out of `count`.
    /// Fee is reversed (lower fee -> more bars) and history ranks by age (older -> more bars).
    /// Size and history rank across `among`; yield and volatility only within the fund's own series.
    static func stats(for fund: Fund, among: [Fund], facts: DexFacts) -> DexStats {
        var seen = Set<String>()
        let unique = (among + [fund]).filter { seen.insert($0.id).inserted }
        let all = unique
        let series = DexSeries.of(fund)
        let sameSeries = all.filter { DexSeries.of($0) == series }
        return DexStats(
            fee: band(of: fund, in: all, value: { facts.feeRate[$0.id].map { -$0 } }),
            size: band(of: fund, in: all, value: { facts.aum[$0.id] }),
            yield: band(of: fund, in: sameSeries, value: { facts.yield[$0.id] }),
            volatility: band(of: fund, in: sameSeries, value: { facts.volatility[$0.id] }),
            history: band(of: fund, in: all, value: { facts.listed[$0.id].map { -$0.timeIntervalSince1970 } }))
    }

    private static func band(of fund: Fund, in funds: [Fund], value: (Fund) -> Double?) -> Int {
        guard let mine = value(fund), mine.isFinite else { return 0 }
        let values = funds.compactMap(value).filter(\.isFinite)
        let rank = values.filter { $0 <= mine }.count
        return min(10, max(1, Int((Double(rank) / Double(values.count) * 10).rounded(.up))))
    }
}

extension GameState {
    /// Collects the card the first time it is viewed and returns the experience it earned: `[.firstDexCard]` for the
    /// first `GameRules.dexXPPerMonth` new cards of the Taipei calendar month, `[]` after that (the card is still
    /// collected) and for a card already held (ruling R34). Calls `award(.firstDexCard)` itself, so callers must not
    /// award again; whether the card was new is `collected[symbol] == nil` before the call.
    mutating func collect(_ symbol: String, now: Date) -> [XPEvent] {
        guard collected[symbol] == nil else { return [] }
        let month = YearMonth(now)
        let earlier = collected.values.filter { YearMonth($0) == month }.count
        collected[symbol] = now
        guard earlier < GameRules.dexXPPerMonth else { return [] }
        award(.firstDexCard)
        return [.firstDexCard]
    }

    /// Funds of series `s` in `funds` vs how many of them are collected.
    func seriesProgress(_ s: DexSeries, funds: [Fund]) -> (got: Int, total: Int) {
        let inSeries = funds.filter { DexSeries.of($0) == s }
        return (inSeries.filter { collected[$0.id] != nil }.count, inSeries.count)
    }
}
