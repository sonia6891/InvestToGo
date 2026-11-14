import Foundation

/// 存錢目標反推: the monthly amount that grows to a target, under an assumed yearly return.
enum GoalPlanner {
    /// `annualReturn` is in percent (6 means 6%). Contributions land at the end of each month.
    static func monthlyContribution(target: Double, years: Int, current: Double, annualReturn: Double) -> Double {
        guard years > 0, target.isFinite, current.isFinite, annualReturn.isFinite else { return 0 }
        let n = Double(years * 12)
        let r = pow(1 + annualReturn / 100, 1.0 / 12) - 1
        guard r.isFinite else { return 0 }
        if r == 0 { return max(0, (target - current) / n) }
        let growth = pow(1 + r, n)
        let value = (target - current * growth) * r / (growth - 1)
        return value.isFinite ? max(0, value) : 0
    }

    static func scenarios(target: Double, years: Int, current: Double, annualReturn: Double) -> [(scenario: ComboScenario, annualReturn: Double, monthly: Double)] {
        [ComboScenario.optimistic, .base, .conservative].map { scenario in
            let rate = max(scenario.rate(annualReturn), -99)
            return (scenario, rate, monthlyContribution(target: target, years: years, current: current, annualReturn: rate))
        }
    }
}
