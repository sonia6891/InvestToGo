package com.sonia.etftogo.core.sources

import com.sonia.etftogo.core.models.Quote
import com.sonia.etftogo.core.models.StoreError
import com.sonia.etftogo.core.support.CoreJson
import kotlinx.serialization.Serializable
import java.time.Instant

object Fugle {
    @Serializable
    data class Total(val tradeVolume: Double? = null)

    @Serializable
    data class Response(
        val symbol: String,
        val date: String,
        val closePrice: Double? = null,
        val lastPrice: Double? = null,
        val changePercent: Double? = null,
        val change: Double? = null,
        val openPrice: Double? = null,
        val highPrice: Double? = null,
        val lowPrice: Double? = null,
        val total: Total? = null,
        val isTrial: Boolean? = null,
    )

    fun decode(bytes: ByteArray, expectedSymbol: String, now: Instant = Instant.now()): Quote {
        val value = CoreJson.decode(Response.serializer(), bytes)
        // During a trial match only lastPrice moves (closePrice is the last real trade), as in the stream.
        val trial = value.isTrial == true
        val price = if (trial) value.lastPrice ?: value.closePrice else value.closePrice ?: value.lastPrice
        if (value.symbol != expectedSymbol || price == null || !price.isFinite() || price <= 0) throw StoreError.InvalidQuote
        val quote = Quote(
            symbol = value.symbol, price = price, changePercent = value.changePercent, date = value.date, fetchedAt = now,
            change = value.change, open = value.openPrice, high = value.highPrice, low = value.lowPrice, volume = value.total?.tradeVolume,
            trial = if (trial) true else null,
        )
        if (!quote.isValid) throw StoreError.InvalidQuote
        return quote
    }
}
