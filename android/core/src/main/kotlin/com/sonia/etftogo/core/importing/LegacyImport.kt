package com.sonia.etftogo.core.importing

import com.sonia.etftogo.core.models.ComponentSnapshot
import com.sonia.etftogo.core.models.Dividend
import com.sonia.etftogo.core.models.DividendStatus
import com.sonia.etftogo.core.models.Holding
import com.sonia.etftogo.core.models.Portfolio
import com.sonia.etftogo.core.models.StoreError
import com.sonia.etftogo.core.models.Strategy
import com.sonia.etftogo.core.models.isPlainLink
import com.sonia.etftogo.core.support.CoreJson
import com.sonia.etftogo.core.support.DataChecks
import com.sonia.etftogo.core.support.StableID
import com.sonia.etftogo.core.support.charCount
import com.sonia.etftogo.core.support.parseUUID
import com.sonia.etftogo.core.support.swiftRounded
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

@Serializable
data class LegacyPlan(
    val principal: Double,
    val monthly: Double,
    val years: Int,
    val totalReturn: Double,
    val distributionRate: Double,
    val frequency: Int,
    val reinvest: Double,
    val deductionRate: Double,
) {
    fun validate() {
        val ok = principal.isFinite() && principal in 0.0..1e12 && monthly.isFinite() && monthly in 0.0..1e9 && years in 1..50 &&
            totalReturn.isFinite() && totalReturn in -0.9..0.5 && distributionRate.isFinite() && distributionRate in 0.0..0.3 &&
            frequency in setOf(1, 2, 4, 12) && reinvest.isFinite() && reinvest in 0.0..1.0 && deductionRate.isFinite() && deductionRate in 0.0..0.2
        if (!ok) throw StoreError.UnsupportedBackup
    }
}

@Serializable
data class LegacyPrice(val symbol: String, val price: Double, val date: String)

/** Backups written by the old web app (v3), the first native build (v1) and its planning file (v2). */
object BackupImport {
    @Serializable
    data class OldHolding(val id: String, val code: String, val name: String, val shares: Double, val cost: Double, val price: Double? = null, val priceDate: String? = null)

    @Serializable
    data class OldDividend(
        val id: String,
        val code: String,
        val name: String,
        val paymentDate: String,
        val exDate: String? = null,
        val eligibleShares: Double,
        val perShare: Double,
        val deductions: Double,
        val status: String,
        val actualReceived: Double? = null,
        val sourceUrl: String? = null,
    ) {
        val amount: Double get() = if (status == "received") actualReceived ?: 0.0 else eligibleShares * perShare - deductions

        fun validate() {
            val ok = eligibleShares.isFinite() && eligibleShares > 0 && eligibleShares <= 1e10 && swiftRounded(eligibleShares) == eligibleShares &&
                perShare.isFinite() && perShare in 0.0..1e5 && deductions.isFinite() && deductions in 0.0..(eligibleShares * perShare) &&
                (status != "received" || actualReceived != null) && (actualReceived?.let { it.isFinite() && it in 0.0..1e15 } ?: true) &&
                name.isNotEmpty() && name.charCount <= 120
            if (!ok) throw StoreError.UnsupportedBackup
            if (exDate != null && !(DataChecks.date(exDate) != null && exDate <= paymentDate)) throw StoreError.UnsupportedBackup
            if (!sourceUrl.isNullOrEmpty() && !(sourceUrl.charCount <= 2048 && isPlainLink(sourceUrl, setOf("http", "https")))) throw StoreError.UnsupportedBackup
        }
    }

    @Serializable
    data class Planning(val version: Int, val holdings: List<OldHolding>, val dividends: List<OldDividend>, val plan: LegacyPlan? = null)

    @Serializable
    data class Envelope(
        val app: String,
        val version: Int,
        val planning: Planning,
        val favorites: List<String>,
        val comparison: List<String>,
        val components: Map<String, ComponentSnapshot>? = null,
    )

    private val statuses = mapOf("received" to DividendStatus.PAID, "announced" to DividendStatus.ANNOUNCED, "planned" to DividendStatus.ESTIMATED)

    fun decode(bytes: ByteArray): Portfolio {
        if (bytes.size > 5_000_000) throw StoreError.UnsupportedBackup
        val text = CoreJson.utf8(bytes)
        val root = CoreJson.json.parseToJsonElement(text) as? JsonObject ?: throw StoreError.UnsupportedBackup
        if ("schema" in root) return Portfolio.decodeBackup(bytes)
        var result = Portfolio()
        val planning: Planning
        if ("app" in root) {
            val old = CoreJson.decode(Envelope.serializer(), root)
            val known = (old.app == "ETF_CLASSIFIER" && old.version == 3) || (old.app == "ETF_TOGO_NATIVE" && old.version == 1)
            if (!(known && old.favorites.size <= 1000 && old.comparison.size <= 3 && old.favorites.all(DataChecks::code) && old.comparison.all(DataChecks::code))) {
                throw StoreError.UnsupportedBackup
            }
            planning = old.planning
            result = result.copy(favorites = old.favorites.toSet(), comparison = old.comparison, components = old.components)
        } else {
            planning = CoreJson.decode(Planning.serializer(), root)
        }
        if (!(planning.version == 2 && planning.holdings.size <= 10000 && planning.dividends.size <= 50000 &&
                planning.holdings.map { it.id }.toSet().size == planning.holdings.size &&
                planning.dividends.map { it.id }.toSet().size == planning.dividends.size)) throw StoreError.UnsupportedBackup
        result = result.copy(legacyPlan = planning.plan)
        val holdings = mutableListOf<Holding>()
        var legacyPrices: MutableMap<String, LegacyPrice>? = null
        for (h in planning.holdings) {
            val ok = h.id.isNotEmpty() && h.id.charCount <= 80 && DataChecks.code(h.code) && h.name.isNotEmpty() && h.name.charCount <= 120 &&
                h.shares.isFinite() && h.shares > 0 && h.shares <= 1e10 && h.cost.isFinite() && h.cost in 0.0..1e13
            if (!ok) throw StoreError.UnsupportedBackup
            val id = parseUUID(h.id) ?: StableID.make("legacy-holding", h.id)
            holdings += Holding(id, h.code, h.name, h.shares, h.cost / h.shares, "舊版匯入（券商未記錄）", Strategy.UNCLASSIFIED)
            // User-entered reference prices are preserved separately, never promoted to a verified live quote.
            val price = h.price
            if (price != null) {
                val day = h.priceDate
                if (!(price.isFinite() && price >= 0 && day != null && DataChecks.date(day) != null)) throw StoreError.UnsupportedBackup
                legacyPrices = (legacyPrices ?: linkedMapOf()).also { it[h.id] = LegacyPrice(h.code, price, day) }
            }
        }
        val dividends = mutableListOf<Dividend>()
        var legacyDividends: MutableMap<String, OldDividend>? = null
        for (d in planning.dividends) {
            d.validate()
            val date = DataChecks.date(d.paymentDate)
            val status = statuses[d.status]
            if (!(d.id.isNotEmpty() && d.id.charCount <= 80 && DataChecks.code(d.code) && date != null && status != null && d.amount.isFinite() && d.amount >= 0)) {
                throw StoreError.UnsupportedBackup
            }
            dividends += Dividend(parseUUID(d.id) ?: StableID.make("legacy-dividend", d.id), d.code, date, d.amount, status)
            legacyDividends = (legacyDividends ?: linkedMapOf()).also { it[d.id] = d }
        }
        result = result.copy(holdings = holdings, dividends = dividends, legacyPrices = legacyPrices, legacyDividends = legacyDividends)
        Portfolio.decodeBackup(result.encode())
        return result
    }
}
