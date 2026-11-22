package com.sonia.etftogo.data

import com.sonia.etftogo.core.game.YearMonth
import com.sonia.etftogo.core.models.Holding
import com.sonia.etftogo.core.models.Strategy
import com.sonia.etftogo.core.models.TradeAction
import com.sonia.etftogo.core.support.AppDataError
import java.io.File
import java.nio.file.Files
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class PortfolioStoreTest {
    private val dir: File = Files.createTempDirectory("store").toFile()
    private val now: Instant = Instant.parse("2026-11-22T04:00:00Z")
    private fun holding() = Holding(symbol = "0050", name = "元大台灣50", shares = 10.0, unitCost = 180.0, broker = "", strategy = Strategy.SAVING, purchaseDate = now)

    @Test
    fun aNewPhoneStartsEmpty() {
        val store = PortfolioStore(dir)
        assertTrue(store.data.holdings.isEmpty())
        assertTrue(!store.readFailure)
    }

    @Test
    fun aNewHoldingIsSavedWithItsBuyAndTheMonthsDCA() {
        PortfolioStore(dir).save(holding(), logBuy = true, now = now)

        val again = PortfolioStore(dir)
        assertEquals(listOf("0050"), again.data.holdings.map { it.symbol })
        assertEquals(listOf(TradeAction.BUY), again.data.trades?.map { it.action })
        assertEquals(1800.0, again.data.trades?.single()?.total)
        assertTrue(YearMonth(2026, 11) in again.data.game!!.dcaMonths)
        assertEquals(File(dir, "ETFToGo/portfolio.json").exists(), true)
    }

    @Test
    fun aFileThatCannotBeReadIsNeverSavedOver() {
        val file = File(dir, "ETFToGo/portfolio.json").apply { parentFile.mkdirs(); writeText("{ broken") }
        val store = PortfolioStore(dir)
        assertTrue(store.readFailure)
        assertFailsWith<AppDataError> { store.save(holding(), logBuy = true, now = now) }
        assertContentEquals("{ broken".toByteArray(), file.readBytes())
    }

    @Test
    fun anInvalidHoldingIsRefused() {
        val store = PortfolioStore(dir)
        assertFailsWith<AppDataError> { store.save(holding().copy(shares = 0.0), logBuy = true, now = now) }
        assertTrue(!File(dir, "ETFToGo/portfolio.json").exists())
    }
}
