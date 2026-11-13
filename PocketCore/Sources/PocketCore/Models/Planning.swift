import Foundation

struct PlanYear: Identifiable {
    let year: Int
    let invested: Double
    let cash: Double
    let contributed: Double
    var dividends: Double = 0
    var id: Int { year }
    var total: Double { invested + cash }
}
enum PlanMath {
    static func project(_ plan: LegacyPlan) throws -> [PlanYear] {
        try plan.validate()
        let monthlyRate = exp(log1p(plan.totalReturn) / 12) - 1
        var invested = plan.principal, cash = 0.0, contributed = plan.principal, dividends = 0.0
        var rows = [PlanYear(year: 0, invested: invested, cash: cash, contributed: contributed)]
        for month in 1...(plan.years * 12) {
            invested *= 1 + monthlyRate
            if month % (12 / plan.frequency) == 0 {
                let gross = invested * plan.distributionRate / Double(plan.frequency)
                let net = gross * (1 - plan.deductionRate)
                dividends += net
                invested -= gross
                invested += net * plan.reinvest
                cash += net * (1 - plan.reinvest)
            }
            invested += plan.monthly; contributed += plan.monthly
            if month % 12 == 0 { rows.append(PlanYear(year: month / 12, invested: invested, cash: cash, contributed: contributed, dividends: dividends)) }
        }
        return rows
    }
}
