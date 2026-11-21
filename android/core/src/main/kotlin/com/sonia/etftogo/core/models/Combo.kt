@file:OptIn(ExperimentalSerializationApi::class)

package com.sonia.etftogo.core.models

import com.sonia.etftogo.core.support.CoreJson
import com.sonia.etftogo.core.support.DataChecks
import com.sonia.etftogo.core.support.SwiftDateSerializer
import com.sonia.etftogo.core.support.swiftInstant
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.KeepGeneratedSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import kotlin.math.abs
import kotlin.math.pow

/*
 * ETF 組合試算 (the stock half is kept at zero so older files still open). Monthly compounding of an assumed annual
 * total return, new money at month end (or start), split by the chosen mix. Without reinvestment a cash yield is paid out
 * each month and kept as cash. 保守 −7 points, 樂觀 +3 points; the stress test applies −30% in the first year.
 */
@Serializable
enum class ComboScenario(val rawValue: String) {
    @SerialName("保守") CONSERVATIVE("保守"),
    @SerialName("基準") BASE("基準"),
    @SerialName("樂觀") OPTIMISTIC("樂觀"),
    @SerialName("壓力測試") STRESS("壓力測試");

    val id: String get() = rawValue

    fun rate(base: Double): Double = when (this) {
        CONSERVATIVE -> base - 7
        OPTIMISTIC -> base + 3
        BASE, STRESS -> base
    }

    companion object {
        fun of(rawValue: String): ComboScenario? = entries.firstOrNull { it.rawValue == rawValue }
    }
}

@Serializable
data class ComboItem(val symbol: String, val amount: Double) {
    val id: String get() = symbol
}

@Serializable(with = ComboSettingsSerializer::class)
@KeepGeneratedSerializer
data class ComboSettings(
    /** 0 = 我的持有, 1 = 模擬組合. */
    val source: Int = 0,
    val simulated: List<ComboItem> = emptyList(),
    val excluded: List<String> = emptyList(),
    /** ETF only: the stock share is never used. */
    val includeStocks: Boolean = false,
    val includeETFs: Boolean = true,
    @Serializable(with = SwiftDateSerializer::class) val snapshotAt: Instant? = null,
    val monthly: Double = 10000.0,
    /** Share of new money going to stocks; null follows the current mix. */
    val stockPercent: Double? = null,
    val startOfMonth: Boolean = false,
    val years: Int = 5,
    val stockReturn: Double = 5.0,
    val etfReturn: Double = 5.0,
    val reinvest: Boolean = true,
    val stockYield: Double? = null,
    val etfYield: Double? = null,
    val buyFee: Boolean = false,
    val scenario: ComboScenario = ComboScenario.BASE,
) {
    val isValid: Boolean get() {
        val numbers = listOf(monthly, stockReturn, etfReturn) + listOfNotNull(stockPercent, stockYield, etfYield) + simulated.map { it.amount }
        return numbers.all { it.isFinite() } && monthly >= 0 && monthly <= 1e9 && years in setOf(3, 5, 10) &&
            simulated.size <= 60 && simulated.all { DataChecks.code(it.symbol) && it.amount >= 0 && it.amount <= 1e12 } &&
            excluded.size <= 500 && abs(stockReturn) < 50 && abs(etfReturn) < 50
    }
}

/**
 * Every field is optional in stored data, so a file written by another version still opens; the stock group is always
 * off and the ETF group always on (ETF only), and an unknown scenario reads as 基準. Encoding is the plain one.
 */
object ComboSettingsSerializer : KSerializer<ComboSettings> {
    private val plain = ComboSettings.generatedSerializer()
    override val descriptor: SerialDescriptor = plain.descriptor
    override fun serialize(encoder: Encoder, value: ComboSettings) = plain.serialize(encoder, value)

    override fun deserialize(decoder: Decoder): ComboSettings {
        val obj = (decoder as JsonDecoder).decodeJsonElement() as? JsonObject ?: throw SerializationException("combo is not an object")
        val base = ComboSettings()
        fun <T> field(key: String, serializer: KSerializer<T>): T? {
            val element = obj[key] ?: return null
            if (element is JsonNull) return null
            return CoreJson.decode(serializer, element)
        }
        val scenario = try { field("scenario", ComboScenario.serializer()) } catch (_: Exception) { null }
        return ComboSettings(
            source = field("source", Int.serializer()) ?: base.source,
            simulated = field("simulated", ListSerializer(ComboItem.serializer())) ?: emptyList(),
            excluded = field("excluded", ListSerializer(String.serializer())) ?: emptyList(),
            includeStocks = false,
            includeETFs = true,
            snapshotAt = field("snapshotAt", Double.serializer())?.let(::swiftInstant),
            monthly = field("monthly", Double.serializer()) ?: base.monthly,
            stockPercent = field("stockPercent", Double.serializer()),
            startOfMonth = field("startOfMonth", Boolean.serializer()) ?: false,
            years = field("years", Int.serializer()) ?: base.years,
            stockReturn = field("stockReturn", Double.serializer()) ?: base.stockReturn,
            etfReturn = field("etfReturn", Double.serializer()) ?: base.etfReturn,
            reinvest = field("reinvest", Boolean.serializer()) ?: true,
            stockYield = field("stockYield", Double.serializer()),
            etfYield = field("etfYield", Double.serializer()),
            buyFee = field("buyFee", Boolean.serializer()) ?: false,
            scenario = scenario ?: ComboScenario.BASE,
        )
    }
}



object ComboMath {
    data class Part(val start: Double, val invested: Double, val value: Double, val cash: Double) {
        val end: Double get() = value + cash
    }

    data class Result(val stock: Part, val etf: Part, val invested: Double) {
        val end: Double get() = stock.end + etf.end
    }

    fun project(stockStart: Double, etfStart: Double, settings: ComboSettings, stockShare: Double, years: Int, scenario: ComboScenario): Result {
        val c = settings
        val fee = if (c.buyFee) 0.001425 else 0.0
        val shareStock = if (!c.includeETFs) 1.0 else if (!c.includeStocks) 0.0 else stockShare
        fun part(start: Double, share: Double, rate: Double, yield: Double): Part {
            var value = start
            var cash = 0.0
            for (month in 1..(years * 12)) {
                val annual = if (scenario == ComboScenario.STRESS && month <= 12) -0.3 else rate / 100
                val growth = (1 + annual).pow(1.0 / 12) - 1
                val put = c.monthly * share * (1 - fee)
                if (c.startOfMonth) value += put
                val paid = value * yield / 12
                value = value * (1 + growth) - paid
                cash += paid
                if (!c.startOfMonth) value += put
            }
            return Part(start, c.monthly * share * (years * 12).toDouble(), value, cash)
        }
        val stock = part(stockStart, shareStock, scenario.rate(c.stockReturn), if (c.reinvest) 0.0 else (c.stockYield ?: 0.0) / 100)
        val etf = part(etfStart, 1 - shareStock, scenario.rate(c.etfReturn), if (c.reinvest) 0.0 else (c.etfYield ?: 0.0) / 100)
        return Result(stock, etf, c.monthly * (years * 12).toDouble())
    }
}

data class ComboLine(val symbol: String, val amount: Double, val isStock: Boolean) {
    val id: String get() = symbol
}
