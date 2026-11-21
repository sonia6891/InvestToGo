package com.sonia.etftogo.core.models

import com.sonia.etftogo.core.support.CoreJson
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** MemberFeatureTests (feature part), NameNormalizationTests (Fund part) and ComponentHistoryTests. */
class ModelMiscTests {
    @Test fun everyFeatureHasTitleAndPitch() {
        for (feature in MemberFeature.entries) {
            assertTrue(feature.title.isNotEmpty())
            assertTrue(feature.pitch.isNotEmpty())
        }
        assertEquals(MemberFeature.entries.size, MemberFeature.entries.map { it.title }.toSet().size, "titles are unique")
        assertEquals("口袋月報／年報", MemberFeature.REPORT.title)
    }

    @Test fun scenariosPitchNamesEveryScenario() {
        assertEquals("保守、基準、樂觀與壓力測試，四種情境一次試算", MemberFeature.SCENARIOS.pitch)
        assertEquals(4, ComboScenario.entries.size)
        for (scenario in ComboScenario.entries) assertTrue(scenario.rawValue in MemberFeature.SCENARIOS.pitch)
    }

    @Test fun goalPlannerAndBacktestPitches() {
        assertEquals("設定目標金額與年數，算出每月要投多少", MemberFeature.GOAL_PLANNER.pitch)
        assertEquals("看看過去這樣每月買，會變成多少", MemberFeature.BACKTEST.pitch)
        for (feature in MemberFeature.entries) {
            assertFalse("我們" in feature.pitch)
            assertFalse("驗證" in feature.pitch)
        }
        assertEquals("看主動式 ETF 新增、剔除了哪些持股，權重怎麼變", MemberFeature.ACTIVE_TRACKING.pitch)
    }

    @Test fun fundNamesDecodeInNFC() {
        val json = "{\"id\":\"00400A\",\"name\":\"金來益\",\"strategy\":\"待分類\",\"market\":\"TWSE\",\"fullName\":\"主動式ETF證券投資信託基金\"}"
        val fund = CoreJson.json.decodeFromString(Fund.serializer(), json)
        assertEquals(listOf(0x91D1, 0x4F86, 0x76CA), fund.name.map { it.code })
        assertEquals(0x91D1, fund.fullName?.last()?.code)
        val again = CoreJson.json.decodeFromString(Fund.serializer(), CoreJson.json.encodeToString(Fund.serializer(), fund))
        assertEquals(fund, again)
        assertEquals("TWSE", again.market)
    }

    private fun snapshot(symbol: String, date: String, weight: Double = 50.0) =
        ComponentSnapshot(symbol, date, listOf(FundComponent("2330", "台積電", weight)), "test")

    @Test fun rememberKeepsTwelveNewestOnePerDate() {
        var data = Portfolio()
        assertNull(data.componentHistory)
        for (day in listOf(5, 14, 1, 9, 2, 13, 3, 12, 4, 11, 6, 10, 7, 8)) data = data.remember(snapshot("00982A", "2026-09-%02d".format(day)))
        data = data.remember(snapshot("0050", "2026-09-30"))
        val expected = (14 downTo 3).map { "2026-09-%02d".format(it) }
        assertEquals(expected, data.componentHistory?.get("00982A")?.map { it.date })
        assertEquals(listOf("2026-09-30"), data.componentHistory?.get("0050")?.map { it.date })
        data = data.remember(snapshot("00982A", "2026-09-10", weight = 61.0))
        assertEquals(expected, data.componentHistory?.get("00982A")?.map { it.date })
        assertEquals(61.0, data.componentHistory?.get("00982A")?.first { it.date == "2026-09-10" }?.components?.first()?.weight)
        data = data.remember(snapshot("00982A", "2026-08-01"))
        assertEquals(expected, data.componentHistory?.get("00982A")?.map { it.date })
        assertEquals(12, Portfolio.historyLimit)
    }

    @Test fun filesWithAndWithoutHistoryDecode() {
        assertNull(Portfolio.decodeBackup("""{"schema":1,"holdings":[],"dividends":[],"favorites":[],"quotes":{}}""".toByteArray()).componentHistory)
        val data = Portfolio().remember(snapshot("0050", "2026-09-01")).remember(snapshot("0050", "2026-09-02"))
        val back = Portfolio.decodeBackup(data.encode())
        assertEquals(listOf("2026-09-02", "2026-09-01"), back.componentHistory?.get("0050")?.map { it.date })
        assertNull(back.components)
    }
}
