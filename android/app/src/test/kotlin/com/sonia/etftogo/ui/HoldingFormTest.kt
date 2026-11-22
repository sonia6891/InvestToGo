package com.sonia.etftogo.ui

import com.sonia.etftogo.core.models.Fund
import com.sonia.etftogo.core.models.Strategy
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals

/** iPhone `HoldingEditor.save()`'s checks and the holding it builds for 新增持有. */
class HoldingFormTest {
    private val funds = Fund.starters
    private val date = Instant.parse("2026-11-22T04:00:00Z")
    private fun build(symbol: String, shares: String, total: String, name: String = "", broker: String = "") =
        HoldingForm(symbol, name, shares, total, broker).build(funds, date)

    @Test
    fun aListedFundBuildsAHoldingAtTheAverageCost() {
        val holding = (build(" 0050 ", "1,000", "180,500", broker = " 元大 ") as HoldingForm.Result.Ok).holding
        assertEquals("0050", holding.symbol)
        assertEquals("元大台灣50", holding.name)
        assertEquals(1000.0, holding.shares)
        assertEquals(180.5, holding.unitCost)
        assertEquals("元大", holding.broker)
        assertEquals(Strategy.SAVING, holding.strategy)
        assertEquals(date, holding.purchaseDate)
    }

    @Test
    fun aNameTypedInIsKept() {
        assertEquals("我的 0056", (build("0056", "10", "400", name = " 我的 0056 ") as HoldingForm.Result.Ok).holding.name)
    }

    @Test
    fun eachMistakeSaysWhatToFix() {
        assertEquals(HoldingForm.Result.Error("請輸入正確的 ETF 代號，例如 0050、00878。"), build("", "10", "100"))
        assertEquals(HoldingForm.Result.Error("目前只支援 ETF，請輸入 ETF 名單中的代號。"), build("2330", "10", "100"))
        assertEquals(HoldingForm.Result.Error("持有股數須大於 0。"), build("0050", "0", "100"))
        assertEquals(HoldingForm.Result.Error("請填寫總成本（含手續費）。"), build("0050", "10", ""))
    }

    @Test
    fun theAverageCostLineAppearsOnlyWithBothNumbers() {
        assertEquals("平均成本 18.05 元／股", HoldingForm("0050", "", "10", "180.5", "").averageText)
        assertEquals(null, HoldingForm("0050", "", "10", "", "").averageText)
    }
}
