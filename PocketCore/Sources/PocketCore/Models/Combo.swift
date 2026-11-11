import Foundation

/* ---------- 個股＋ETF 組合試算 ----------
   Monthly compounding of an assumed annual total return (dividends included, never added twice), new money at month
   end (or start), split between stocks and ETFs by the chosen mix. Without reinvestment a cash yield is paid out each
   month and kept as cash. Scenarios shift both assumptions: 保守 −7 points, 樂觀 +3 points; the stress test applies
   −30% in the first year, then the base assumptions. Same method as the web app. */
enum ComboScenario: String, Codable, CaseIterable, Identifiable {
    case conservative = "保守", base = "基準", optimistic = "樂觀", stress = "壓力測試"
    var id: String { rawValue }
    func rate(_ base: Double) -> Double {
        switch self { case .conservative: return base - 7; case .optimistic: return base + 3; case .base, .stress: return base }
    }
}
struct ComboItem: Codable, Hashable, Identifiable {
    var symbol: String
    var amount: Double
    var id: String { symbol }
}
struct ComboSettings: Codable, Equatable {
    /// 0 = 我的持有, 1 = 模擬組合.
    var source = 0
    var simulated: [ComboItem] = []
    var excluded: [String] = []
    var includeStocks = true
    var includeETFs = true
    var snapshotAt: Date? = nil
    var monthly: Double = 10000
    /// Share of new money going to stocks; nil follows the current mix.
    var stockPercent: Double? = nil
    var startOfMonth = false
    var years = 5
    var stockReturn: Double = 5
    var etfReturn: Double = 5
    var reinvest = true
    var stockYield: Double? = nil
    var etfYield: Double? = nil
    var buyFee = false
    var scenario = ComboScenario.base
    init() {}
    /// Every field is optional in stored data, so a file written by another version still opens.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = ComboSettings()
        source = try c.decodeIfPresent(Int.self, forKey: .source) ?? base.source
        simulated = try c.decodeIfPresent([ComboItem].self, forKey: .simulated) ?? []
        excluded = try c.decodeIfPresent([String].self, forKey: .excluded) ?? []
        includeStocks = try c.decodeIfPresent(Bool.self, forKey: .includeStocks) ?? true
        includeETFs = try c.decodeIfPresent(Bool.self, forKey: .includeETFs) ?? true
        snapshotAt = try c.decodeIfPresent(Date.self, forKey: .snapshotAt)
        monthly = try c.decodeIfPresent(Double.self, forKey: .monthly) ?? base.monthly
        stockPercent = try c.decodeIfPresent(Double.self, forKey: .stockPercent)
        startOfMonth = try c.decodeIfPresent(Bool.self, forKey: .startOfMonth) ?? false
        years = try c.decodeIfPresent(Int.self, forKey: .years) ?? base.years
        stockReturn = try c.decodeIfPresent(Double.self, forKey: .stockReturn) ?? base.stockReturn
        etfReturn = try c.decodeIfPresent(Double.self, forKey: .etfReturn) ?? base.etfReturn
        reinvest = try c.decodeIfPresent(Bool.self, forKey: .reinvest) ?? true
        stockYield = try c.decodeIfPresent(Double.self, forKey: .stockYield)
        etfYield = try c.decodeIfPresent(Double.self, forKey: .etfYield)
        buyFee = try c.decodeIfPresent(Bool.self, forKey: .buyFee) ?? false
        scenario = (try? c.decodeIfPresent(ComboScenario.self, forKey: .scenario)) ?? .base
    }
    var isValid: Bool {
        let numbers = [monthly, stockReturn, etfReturn] + [stockPercent, stockYield, etfYield].compactMap { $0 } + simulated.map(\.amount)
        return numbers.allSatisfy { $0.isFinite } && monthly >= 0 && monthly <= 1e9 && [3, 5, 10].contains(years)
            && simulated.count <= 60 && simulated.allSatisfy { DataChecks.code($0.symbol) && $0.amount >= 0 && $0.amount <= 1e12 }
            && excluded.count <= 500 && abs(stockReturn) < 50 && abs(etfReturn) < 50
    }
}
enum ComboMath {
    struct Part { let start: Double; let invested: Double; let value: Double; let cash: Double; var end: Double { value + cash } }
    struct Result { let stock: Part; let etf: Part; let invested: Double; var end: Double { stock.end + etf.end } }
    static func project(stockStart: Double, etfStart: Double, settings c: ComboSettings, stockShare: Double, years: Int, scenario: ComboScenario) -> Result {
        let fee = c.buyFee ? 0.001425 : 0
        let shareStock = !c.includeETFs ? 1 : (!c.includeStocks ? 0 : stockShare)
        func part(_ start: Double, share: Double, rate: Double, yield: Double) -> Part {
            var value = start, cash = 0.0
            for month in 1...(years * 12) {
                let annual = scenario == .stress && month <= 12 ? -0.3 : rate / 100
                let growth = pow(1 + annual, 1.0 / 12) - 1
                let put = c.monthly * share * (1 - fee)
                if c.startOfMonth { value += put }
                let paid = value * yield / 12
                value = value * (1 + growth) - paid
                cash += paid
                if !c.startOfMonth { value += put }
            }
            return Part(start: start, invested: c.monthly * share * Double(years * 12), value: value, cash: cash)
        }
        let stock = part(stockStart, share: shareStock, rate: scenario.rate(c.stockReturn), yield: c.reinvest ? 0 : (c.stockYield ?? 0) / 100)
        let etf = part(etfStart, share: 1 - shareStock, rate: scenario.rate(c.etfReturn), yield: c.reinvest ? 0 : (c.etfYield ?? 0) / 100)
        return Result(stock: stock, etf: etf, invested: c.monthly * Double(years * 12))
    }
}
struct ComboLine: Identifiable {
    let symbol: String
    let amount: Double
    let isStock: Bool
    var id: String { symbol }
}
