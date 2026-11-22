package com.sonia.etftogo.core

import com.sonia.etftogo.core.models.Dividend
import com.sonia.etftogo.core.models.DividendStatus
import com.sonia.etftogo.core.models.Holding
import com.sonia.etftogo.core.models.Portfolio
import com.sonia.etftogo.core.models.Quote
import com.sonia.etftogo.core.models.Strategy
import com.sonia.etftogo.core.support.DataChecks
import java.time.Instant
import java.time.ZoneId

/** A small portfolio for unit tests (not part of the app); port of Samples.swift. */
object Samples {
    val portfolio: Portfolio get() {
        val holdings = listOf(
            Holding(symbol = "0050", name = "元大台灣50", shares = 2000.0, unitCost = 50.0, broker = "富邦證券", strategy = Strategy.SAVING),
            Holding(symbol = "00878", name = "國泰永續高股息", shares = 6000.0, unitCost = 20.0, broker = "富邦證券", strategy = Strategy.INCOME),
            Holding(symbol = "00919", name = "群益台灣精選高息", shares = 5000.0, unitCost = 22.0, broker = "國泰證券", strategy = Strategy.INCOME),
        )
        val prices = mapOf("0050" to 55.0, "00878" to 21.0, "00919" to 22.5)
        val quotes = prices.mapValues { (symbol, price) -> Quote(symbol = symbol, price = price, changePercent = 0.42, date = DataChecks.day(), fetchedAt = Instant.now()) }
        val start = java.time.LocalDate.now().withDayOfMonth(1).atStartOfDay(ZoneId.systemDefault())
        val dividends = listOf(
            Dividend(symbol = "00878", date = start.plusDays(7).toInstant(), amount = 2400.0, status = DividendStatus.PAID),
            Dividend(symbol = "00919", date = start.plusDays(19).toInstant(), amount = 3600.0, status = DividendStatus.ANNOUNCED),
        )
        return Portfolio(holdings = holdings, dividends = dividends, favorites = setOf("0050", "00878", "00919"), quotes = quotes)
    }
}
