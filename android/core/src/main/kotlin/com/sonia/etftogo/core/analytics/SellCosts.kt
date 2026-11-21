package com.sonia.etftogo.core.analytics

import com.sonia.etftogo.core.support.CoreJson
import com.sonia.etftogo.core.support.DataChecks
import com.sonia.etftogo.core.support.KeyValueStore
import com.sonia.etftogo.core.support.swiftTrim
import kotlinx.serialization.Required
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.time.Instant
import kotlin.math.floor

/** A broker's selling fee: the discount in 折 (2.8 means 28% of the list 0.1425%) and the smallest fee charged. */
@Serializable
data class FeeRate(@Required val discount: Double, @Required val minimum: Double) {
    val valid: FeeRate get() = FeeRate(minOf(maxOf(discount, 0.0), 10.0), minOf(maxOf(minimum, 0.0), 1000.0))
}

/**
 * 市值 the way brokers show it: what selling today would bring in, the price × shares less the estimated selling fee
 * (0.1425% × the broker's discount, rounded down, at least its minimum) and the securities transaction tax (stocks
 * 0.3%, ETFs 0.1%, bond ETFs exempt through 2026), also rounded down. Each broker's rate is the viewer's to set in 設定;
 * a broker without one is charged the list price. The settings live in a [KeyValueStore] under the iPhone key names.
 */
object SellCosts {
    const val netKey = "netMarketValue"
    const val ratesKey = "brokerFeeRates"
    /** The list price: no discount, at least NT$20 (most brokers' minimum on a board-lot trade). */
    val standard = FeeRate(10.0, 20.0)
    /** Bond ETFs are exempt from the transaction tax until the end of 2026. */
    val bondExemptionEnd: Instant = DataChecks.date("2027-01-01")!!
    private val ratesSerializer = MapSerializer(String.serializer(), FeeRate.serializer())

    /** Deduct the estimated selling costs from 市值 (on unless turned off). */
    fun enabled(store: KeyValueStore): Boolean = store.getString(netKey)?.let { it == "true" } ?: true

    /** The broker a fee belongs to: 融資 holdings sell through the same broker as cash ones. */
    fun brokerKey(broker: String): String = broker.replace("（融資）", "").replace("(融資)", "").swiftTrim()

    /** The rates the viewer set, by broker; the key "" holds a default for every other broker. */
    fun rates(store: KeyValueStore): Map<String, FeeRate> =
        store.getString(ratesKey)?.let { runCatching { CoreJson.decode(ratesSerializer, it) }.getOrNull() } ?: emptyMap()

    fun save(rates: Map<String, FeeRate>, store: KeyValueStore) {
        store.putString(ratesKey, CoreJson.json.encodeToString(ratesSerializer, rates))
    }

    /** The viewer's own rate for the broker, else its common online rate, else the viewer's default, else the list price. */
    fun rate(broker: String, store: KeyValueStore): FeeRate {
        val set = rates(store)
        val key = brokerKey(broker)
        return (set[key] ?: preset(key) ?: set[""] ?: standard).valid
    }

    /** Whether this broker's fee is known (the viewer's own, or a common rate) rather than the list price. */
    fun isSet(broker: String, store: KeyValueStore): Boolean {
        val set = rates(store)
        val key = brokerKey(broker)
        return key in set || preset(key) != null || "" in set
    }

    /**
     * Keeps the rate the viewer confirmed for a broker; a rate equal to what the broker would get anyway is not stored,
     * so a common rate stays a common rate.
     */
    fun remember(rate: FeeRate, broker: String, store: KeyValueStore) {
        val key = brokerKey(broker)
        if (key.isEmpty()) return
        val set = rates(store)
        if (key !in set && rate.valid == (preset(key) ?: set[""] ?: standard).valid) return
        save(set + (key to rate.valid), store)
    }

    /** Where a broker's rate comes from, in a sentence for the screen. */
    fun rateNote(broker: String, store: KeyValueStore): String {
        val set = rates(store)
        val key = brokerKey(broker)
        if (key in set) return "你為${key}設定的折扣，用來估算市值。"
        if (preset(key) != null) return "${key}常見的電子下單優惠，實際以你的帳戶為準，可直接修改。"
        if ("" in set) return "用你在設定裡的預設折扣；這家的優惠不同可直接修改。"
        return "沒有這家的常見優惠，先用原價（不打折、最低 20 元）；請改成你的折扣。"
    }

    data class Preset(val name: String, val core: String, val rate: FeeRate)

    /** Common online-order (電子下單) rates as reported in 2026; only where a broker starts, the viewer's own rate wins. */
    val presets: List<Preset> = listOf(
        Preset("國泰證券", "國泰", FeeRate(2.8, 1.0)),
        Preset("永豐金證券", "永豐", FeeRate(2.0, 1.0)),
        Preset("元大證券", "元大", FeeRate(6.0, 20.0)),
        Preset("富邦證券", "富邦", FeeRate(6.0, 20.0)),
        Preset("凱基證券", "凱基", FeeRate(6.0, 20.0)),
        Preset("群益證券", "群益", FeeRate(6.0, 20.0)),
    )

    /** Other brokers offered for picking; they start at the list price. */
    val otherBrokers = listOf("元富證券", "統一證券", "兆豐證券", "第一金證券", "華南永昌證券", "台新證券", "玉山證券", "中國信託證券", "康和證券", "國票證券", "新光證券")

    /** 「國泰」, 「國泰證券」 and 「國泰綜合證券」 are the same broker. */
    fun preset(broker: String): FeeRate? {
        val key = brokerKey(broker)
        if (key.isEmpty()) return null
        return presets.firstOrNull { key.contains(it.core) }?.rate
    }

    fun taxRate(stock: Boolean, bond: Boolean, day: Instant = Instant.now()): Double {
        if (stock) return 0.003
        return if (bond && day < bondExemptionEnd) 0.0 else 0.001
    }

    fun fee(gross: Double, rate: FeeRate): Double {
        if (!(gross > 0)) return 0.0
        return maxOf(rate.minimum, down(gross * 0.001425 * rate.discount / 10))
    }

    /** The price × shares after the estimated fee and tax of selling them. */
    fun net(gross: Double, stock: Boolean, bond: Boolean, rate: FeeRate, day: Instant = Instant.now()): Double {
        if (!(gross > 0)) return gross
        val tax = down(gross * taxRate(stock, bond, day))
        return gross - fee(gross, rate.valid) - tax
    }

    /** Rounded down to whole dollars; a hair is added so 300.0 that comes out as 299.9999… stays 300. */
    private fun down(value: Double): Double = floor(value + 1e-6)
}
