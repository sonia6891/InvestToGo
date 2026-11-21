package com.sonia.etftogo.core.sources

import com.sonia.etftogo.core.models.ComponentSnapshot
import com.sonia.etftogo.core.models.FundComponent
import com.sonia.etftogo.core.models.PricePoint
import com.sonia.etftogo.core.support.AppDataError
import com.sonia.etftogo.core.support.CoreJson
import kotlinx.serialization.Serializable

@Serializable
private data class FugleComponentDay(val date: String, val components: List<FundComponent>)

@Serializable
private data class FugleComponents(val symbol: String, val data: List<FugleComponentDay>)

@Serializable
private data class FugleHistory(val symbol: String, val adjusted: Boolean? = null, val timeframe: String, val data: List<PricePoint>)

/** Research.swift's `extension Fugle`: an ETF's holdings and its adjusted daily closes. */
fun Fugle.decodeComponents(bytes: ByteArray, symbol: String): ComponentSnapshot {
    val response = CoreJson.decode(FugleComponents.serializer(), bytes)
    val day = response.data.maxByOrNull { it.date }
    if (response.symbol != symbol || day == null || day.components.isEmpty()) {
        throw AppDataError("此區間沒有股票成分資料；債券、期貨或部分外幣級別可能沒有此資料，不能視為零重疊。")
    }
    val value = ComponentSnapshot(symbol, day.date, day.components, "富果／投信揭露資料")
    value.validate()
    return value
}

fun Fugle.decodeHistory(bytes: ByteArray, symbol: String): List<PricePoint> {
    val value = CoreJson.decode(FugleHistory.serializer(), bytes)
    if (value.symbol != symbol || value.adjusted != true || value.timeframe != "D") throw AppDataError("行情服務未確認還原價格，未計算績效。")
    return value.data
}
