import Foundation

/// The fund, amount and broker the quick-DCA sheet starts from.
struct QuickDCAPreset: Codable, Equatable {
    var symbol: String
    var amount: Int
    var broker: String
    var isValid: Bool { DataChecks.code(symbol) && (1...1_000_000_000_000).contains(amount) && broker.count <= 120 }
}

struct QuickDCADefaults: Equatable {
    var symbol: String?
    var amount: Int?
    var broker: String
}

enum QuickDCAProblem: Equatable {
    case unknownFund, invalidAmount, invalidShares
    var message: String? { self == .unknownFund ? "找不到這檔 ETF" : nil }
}

enum QuickDCA {
    static func defaults(preset: QuickDCAPreset?, onboardingSymbol: String?, onboardingMonthly: Int?, portfolio: Portfolio) -> QuickDCADefaults {
        let held = Set(portfolio.holdings.map(\.symbol))
        let latestHeldBuy = (portfolio.trades ?? []).filter { $0.action == .buy && held.contains($0.symbol) }.max { $0.date < $1.date }?.symbol
        let amount: Int? = preset?.amount ?? ((onboardingMonthly ?? 0) > 0 ? onboardingMonthly : nil)
        return QuickDCADefaults(symbol: preset?.symbol ?? onboardingSymbol ?? latestHeldBuy, amount: amount, broker: preset?.broker ?? "")
    }

    static func estimatedShares(amount: Int?, close: Double?) -> Int? {
        guard let amount, let close, close.isFinite, close > 0 else { return nil }
        let shares = (Double(amount) / close).rounded(.down)
        guard shares.isFinite, shares >= 1, shares <= 1e10 else { return nil }
        return Int(shares)
    }

    static func closeNote(day: String) -> String? {
        guard DataChecks.date(day) != nil else { return nil }
        let parts = day.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        return "以 \(month)/\(d) 收盤價估算，可改成實際成交股數"
    }

    static func problem(known: Bool, shares: Int?, amount: Int?) -> QuickDCAProblem? {
        if !known { return .unknownFund }
        guard let amount, (1...1_000_000_000_000).contains(amount) else { return .invalidAmount }
        guard let shares, (1...10_000_000_000).contains(shares) else { return .invalidShares }
        return nil
    }

    static func amountText(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: amount)) ?? String(amount)
    }
}

extension Portfolio {
    func hasBuy(in month: YearMonth) -> Bool {
        (trades ?? []).contains { $0.action == .buy && YearMonth($0.date) == month }
    }
    /// 本月已記到定投, derived from the records: the streak month is set and a buy still stands.
    func dcaLogged(in month: YearMonth) -> Bool {
        (game?.dcaMonths.contains(month) ?? false) && hasBuy(in: month)
    }
}

extension GameState {
    func isDone(_ quest: Quest, in month: YearMonth, records: Portfolio) -> Bool {
        guard isDone(quest, in: month) else { return false }
        return quest.trigger == .dcaLogged ? records.hasBuy(in: month) : true
    }
}
