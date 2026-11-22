package com.sonia.etftogo.core.models

import com.sonia.etftogo.core.support.AppDataError
import com.sonia.etftogo.core.support.DataChecks
import com.sonia.etftogo.core.support.SwiftDate
import com.sonia.etftogo.core.support.SwiftUUID
import com.sonia.etftogo.core.support.TAIPEI
import com.sonia.etftogo.core.support.decimal
import kotlinx.serialization.Required
import kotlinx.serialization.Serializable
import java.time.Instant
import java.util.UUID

/**
 * 到價提醒 (口袋會員): one price to watch for one code. It fires once, is then switched off with the time it fired, and can
 * be switched on again by hand.
 */
@Serializable
data class PriceAlert(
    @Required val id: SwiftUUID = UUID.randomUUID(),
    val symbol: String,
    /** True: the price is at or over `price`. False: at or under it. */
    val above: Boolean,
    val price: Double,
    @Required val enabled: Boolean = true,
    /** When it last fired; null until it has. */
    val firedAt: SwiftDate? = null,
) {
    val isValid: Boolean get() = DataChecks.code(symbol) && price.isFinite() && price > 0 && price <= AlertEngine.maxPrice

    /** 「高於 200」 or 「低於 18.5」. */
    val condition: String get() = "${if (above) "高於" else "低於"} ${decimal(price)}"
}

object AlertEngine {
    /** How many alerts may be kept, switched on or off. */
    const val limit = 20
    const val maxPrice = 1_000_000.0
    /** A price whose trading day is further back than this is not judged. */
    const val freshDays = 7L

    /**
     * The alerts to fire now: the enabled ones whose code has a price at or past the target. A code without a price is
     * skipped, and nothing is due for someone who is not a member.
     */
    fun due(alerts: List<PriceAlert>, prices: Map<String, Double>, isMember: Boolean): List<UUID> {
        if (!isMember) return emptyList()
        return alerts.filter { alert ->
            val price = prices[alert.symbol]
            if (!alert.enabled || price == null || !price.isFinite() || !(price > 0)) false
            else if (alert.above) price >= alert.price else price <= alert.price
        }.map { it.id }
    }

    /** Whether there is anything to check in the background: an enabled alert, and a member to tell. */
    fun watching(alerts: List<PriceAlert>, isMember: Boolean): Boolean = isMember && alerts.any { it.enabled }

    /** Whether a price of trading day `day` ("yyyy-MM-dd") is recent enough to judge an alert on. */
    fun isCurrent(day: String, now: Instant): Boolean {
        if (DataChecks.date(day) == null) return false
        val oldest = now.atZone(TAIPEI).minusDays(freshDays).toInstant()
        return day >= DataChecks.day(oldest)
    }

    /** The notification's words: the code, the price it reached and what was set. A fact, never advice. */
    fun message(alert: PriceAlert, price: Double): String =
        "${alert.symbol} 已到 ${decimal(price)}，你設定的是${if (alert.above) "高於" else "低於"} ${decimal(alert.price)}。"
}

/**
 * Adds an alert, switched on, and returns the new portfolio with it. Throws, in the form's own words, when the list is
 * full, the same alert is there already or the values cannot be an alert.
 */
fun Portfolio.addAlert(symbol: String, above: Boolean, price: Double): Pair<Portfolio, PriceAlert> {
    val alert = PriceAlert(symbol = symbol, above = above, price = price)
    if (!alert.isValid) throw AppDataError("請輸入正確的代號與大於 0 的價格。")
    val list = alerts ?: emptyList()
    if (list.size >= AlertEngine.limit) throw AppDataError("最多 ${AlertEngine.limit} 個提醒，請先刪除不用的。")
    if (list.any { it.symbol == symbol && it.above == above && it.price == price }) throw AppDataError("已經有一樣的提醒。")
    return copy(alerts = list + alert) to alert
}

/** Marks these alerts as fired at `now` and switches them off; returns the portfolio and the alerts as they are now. */
fun Portfolio.fireAlerts(ids: List<UUID>, now: Instant): Pair<Portfolio, List<PriceAlert>> {
    val fired = mutableListOf<PriceAlert>()
    val list = (alerts ?: emptyList()).map { alert ->
        if (alert.id in ids) alert.copy(enabled = false, firedAt = now).also { fired += it } else alert
    }
    return (if (fired.isEmpty()) this else copy(alerts = list)) to fired
}

/** A backup's alerts: one with a known id replaces it, a new one is added while there is room. */
fun Portfolio.mergeAlerts(incoming: List<PriceAlert>): Portfolio {
    if (incoming.isEmpty()) return this
    val list = (alerts ?: emptyList()).toMutableList()
    for (item in incoming) {
        val i = list.indexOfFirst { it.id == item.id }
        if (i >= 0) list[i] = item else if (list.size < AlertEngine.limit) list += item
    }
    return copy(alerts = list)
}
