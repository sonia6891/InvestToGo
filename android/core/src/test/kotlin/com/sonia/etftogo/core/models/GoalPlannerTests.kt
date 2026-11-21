package com.sonia.etftogo.core.models

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class GoalPlannerTests {
    @Test fun tenYearsThreeMillionAtSixPercent() = assertEquals(18464.56, GoalPlanner.monthlyContribution(3_000_000.0, 10, 0.0, 6.0), 0.01)
    @Test fun existingMoneyReducesContribution() = assertEquals(12953.35, GoalPlanner.monthlyContribution(3_000_000.0, 10, 500_000.0, 6.0), 0.01)
    @Test fun zeroReturnIsStraightDivision() = assertEquals(25000.0, GoalPlanner.monthlyContribution(3_000_000.0, 10, 0.0, 0.0), 0.0001)
    @Test fun alreadyThereIsZero() = assertEquals(0.0, GoalPlanner.monthlyContribution(3_000_000.0, 10, 4_000_000.0, 6.0))

    @Test fun badInputIsZero() {
        assertEquals(0.0, GoalPlanner.monthlyContribution(3_000_000.0, 0, 0.0, 6.0))
        assertEquals(0.0, GoalPlanner.monthlyContribution(Double.NaN, 10, 0.0, 6.0))
    }

    @Test fun scenariosUseComboRates() {
        val s = GoalPlanner.scenarios(3_000_000.0, 10, 0.0, 6.0)
        assertEquals(listOf(ComboScenario.OPTIMISTIC, ComboScenario.BASE, ComboScenario.CONSERVATIVE), s.map { it.scenario })
        assertEquals(listOf(9.0, 6.0, -1.0), s.map { it.annualReturn })
        assertTrue(s[0].monthly < s[1].monthly && s[1].monthly < s[2].monthly)
    }
}
