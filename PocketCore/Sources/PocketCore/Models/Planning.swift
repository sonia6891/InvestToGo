import Foundation

public enum Projection {
    public static func value(initial: Double, monthly: Double, years: Int, annualPercent: Double) -> Double {
        let rate = annualPercent / 100 / 12
        var total = initial
        for _ in 0..<(max(years, 0) * 12) { total = total * (1 + rate) + monthly }
        return total
    }
}

public struct LegacyPlan: Codable {
    public var principal: Double
    public var monthly: Double
    public var years: Int
    public var totalReturn: Double
    public var distributionRate: Double
    public var frequency: Int
    public var reinvest: Double
    public var deductionRate: Double
    public init(principal: Double, monthly: Double, years: Int, totalReturn: Double, distributionRate: Double, frequency: Int, reinvest: Double, deductionRate: Double) {
        self.principal = principal; self.monthly = monthly; self.years = years; self.totalReturn = totalReturn
        self.distributionRate = distributionRate; self.frequency = frequency; self.reinvest = reinvest; self.deductionRate = deductionRate
    }
    public func validate() throws {
        guard principal.isFinite, (0...1e12).contains(principal), monthly.isFinite, (0...1e9).contains(monthly), (1...50).contains(years), totalReturn.isFinite, (-0.9...0.5).contains(totalReturn), distributionRate.isFinite, (0...0.3).contains(distributionRate), [1,2,4,12].contains(frequency), reinvest.isFinite, (0...1).contains(reinvest), deductionRate.isFinite, (0...0.2).contains(deductionRate) else { throw StoreError.unsupportedBackup }
    }
}

public struct LegacyPrice: Codable {
    public var symbol: String
    public var price: Double
    public var date: String
    public init(symbol: String, price: Double, date: String) { self.symbol = symbol; self.price = price; self.date = date }
}

public struct PlanYear: Identifiable {
    public let year: Int
    public let invested: Double
    public let cash: Double
    public let contributed: Double
    public var id: Int { year }
    public var total: Double { invested + cash }
}

public enum PlanMath {
    public static func project(_ plan: LegacyPlan) throws -> [PlanYear] {
        try plan.validate()
        let monthlyRate = exp(log1p(plan.totalReturn) / 12) - 1
        var invested = plan.principal, cash = 0.0, contributed = plan.principal
        var rows = [PlanYear(year: 0, invested: invested, cash: cash, contributed: contributed)]
        for month in 1...(plan.years * 12) {
            invested *= 1 + monthlyRate
            if month % (12 / plan.frequency) == 0 {
                let gross = invested * plan.distributionRate / Double(plan.frequency)
                let net = gross * (1 - plan.deductionRate)
                invested -= gross
                invested += net * plan.reinvest
                cash += net * (1 - plan.reinvest)
            }
            invested += plan.monthly; contributed += plan.monthly
            if month % 12 == 0 { rows.append(PlanYear(year: month / 12, invested: invested, cash: cash, contributed: contributed)) }
        }
        return rows
    }
}
