package com.sonia.etftogo.core.models

import com.sonia.etftogo.core.importing.LegacyPlan
import kotlin.math.exp
import kotlin.math.ln1p
import kotlin.math.max
import kotlin.math.pow

/** 存錢目標反推: the monthly amount that grows to a target, under an assumed yearly return. */
object GoalPlanner {
    data class Scenario(val scenario: ComboScenario, val annualReturn: Double, val monthly: Double)

    /** `annualReturn` is in percent (6 means 6%). Contributions land at the end of each month. */
    fun monthlyContribution(target: Double, years: Int, current: Double, annualReturn: Double): Double {
        if (years <= 0 || !target.isFinite() || !current.isFinite() || !annualReturn.isFinite()) return 0.0
        val n = (years * 12).toDouble()
        val r = (1 + annualReturn / 100).pow(1.0 / 12) - 1
        if (!r.isFinite()) return 0.0
        if (r == 0.0) return max(0.0, (target - current) / n)
        val growth = (1 + r).pow(n)
        val value = (target - current * growth) * r / (growth - 1)
        return if (value.isFinite()) max(0.0, value) else 0.0
    }

    fun scenarios(target: Double, years: Int, current: Double, annualReturn: Double): List<Scenario> =
        listOf(ComboScenario.OPTIMISTIC, ComboScenario.BASE, ComboScenario.CONSERVATIVE).map { scenario ->
            val rate = max(scenario.rate(annualReturn), -99.0)
            Scenario(scenario, rate, monthlyContribution(target, years, current, rate))
        }
}

data class PlanYear(val year: Int, val invested: Double, val cash: Double, val contributed: Double, val dividends: Double = 0.0) {
    val id: Int get() = year
    val total: Double get() = invested + cash
}

object PlanMath {
    fun project(plan: LegacyPlan): List<PlanYear> {
        plan.validate()
        val monthlyRate = exp(ln1p(plan.totalReturn) / 12) - 1
        var invested = plan.principal
        var cash = 0.0
        var contributed = plan.principal
        var dividends = 0.0
        val rows = mutableListOf(PlanYear(0, invested, cash, contributed))
        for (month in 1..(plan.years * 12)) {
            invested *= 1 + monthlyRate
            if (month % (12 / plan.frequency) == 0) {
                val gross = invested * plan.distributionRate / plan.frequency
                val net = gross * (1 - plan.deductionRate)
                dividends += net
                invested -= gross
                invested += net * plan.reinvest
                cash += net * (1 - plan.reinvest)
            }
            invested += plan.monthly
            contributed += plan.monthly
            if (month % 12 == 0) rows += PlanYear(month / 12, invested, cash, contributed, dividends)
        }
        return rows
    }
}
