@file:OptIn(ExperimentalSerializationApi::class)

package com.sonia.etftogo.core.models

import com.sonia.etftogo.core.game.GameState
import com.sonia.etftogo.core.importing.BackupImport
import com.sonia.etftogo.core.importing.LegacyPlan
import com.sonia.etftogo.core.importing.LegacyPrice
import com.sonia.etftogo.core.support.AppDataError
import com.sonia.etftogo.core.support.CoreJson
import com.sonia.etftogo.core.support.DataChecks
import com.sonia.etftogo.core.support.SwiftDate
import com.sonia.etftogo.core.support.SwiftUUID
import com.sonia.etftogo.core.support.charCount
import com.sonia.etftogo.core.support.nfc
import com.sonia.etftogo.core.support.swiftRounded
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KeepGeneratedSerializer
import kotlinx.serialization.Required
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonTransformingSerializer
import kotlinx.serialization.json.contentOrNull
import java.time.Instant
import java.util.UUID

@Serializable
enum class Strategy(val rawValue: String, val symbol: String, val subtitle: String) {
    @SerialName("存錢筒") SAVING("存錢筒", "leaf", "長期累積"),
    @SerialName("印鈔機") INCOME("印鈔機", "banknote", "關注配息"),
    @SerialName("老虎機") RISK("老虎機", "bolt", "高波動策略"),
    @SerialName("待分類") UNCLASSIFIED("待分類", "tag", "自行選擇策略");

    val id: String get() = rawValue
}

/** A fund as listed; names are read in NFC (official lists spell 金 來 益 as compatibility ideographs). */
@Serializable(with = FundSerializer::class)
@KeepGeneratedSerializer
data class Fund(
    val id: String,
    val name: String,
    val strategy: Strategy,
    val market: String? = null,
    val fullName: String? = null,
    val fundType: String? = null,
    val listingDate: String? = null,
) {
    companion object {
        /** Well-known NT$ ETFs: the currency and market fallback when the catalogue is missing. */
        val starters: List<Fund> = listOf(
            Fund("0050", "元大台灣50", Strategy.SAVING),
            Fund("006208", "富邦台50", Strategy.SAVING),
            Fund("0056", "元大高股息", Strategy.INCOME),
            Fund("00878", "國泰永續高股息", Strategy.INCOME),
            Fund("00919", "群益台灣精選高息", Strategy.INCOME),
            Fund("00631L", "元大台灣50正2", Strategy.RISK),
        )
    }
}

object FundSerializer : JsonTransformingSerializer<Fund>(Fund.generatedSerializer()) {
    override fun transformDeserialize(element: JsonElement): JsonElement {
        val obj = element as? JsonObject ?: return element
        return JsonObject(obj.mapValues { (key, value) ->
            val text = (value as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
            if ((key == "name" || key == "fullName") && text != null) JsonPrimitive(text.nfc) else value
        })
    }
}

@Serializable
data class Holding(
    @Required val id: SwiftUUID = UUID.randomUUID(),
    val symbol: String,
    val name: String,
    val shares: Double,
    val unitCost: Double,
    val broker: String,
    val strategy: Strategy,
    val sourceAccount: String? = null,
    val purchaseDate: SwiftDate? = null,
) {
    val cost: Double get() = shares * unitCost

    fun validate() {
        if (!(symbol.isNotEmpty() && name.isNotEmpty() && shares.isFinite() && shares > 0 && shares <= 1e10 &&
                unitCost.isFinite() && unitCost >= 0 && unitCost <= 1e9 && cost.isFinite() &&
                broker.charCount <= 120 && symbol.charCount <= 20 && name.charCount <= 120)) throw StoreError.InvalidHolding
    }
}

@Serializable
enum class TradeAction(val rawValue: String) {
    @SerialName("買進") BUY("買進"),
    @SerialName("賣出") SELL("賣出"),
    @SerialName("調整") ADJUST("調整"),
    @SerialName("移除") REMOVE("移除"),
    @SerialName("匯入") BROKER_IMPORT("匯入"),
}

/** A change the user made to a holding in this app; not a broker fill report. */
@Serializable
data class Trade(
    @Required val id: SwiftUUID = UUID.randomUUID(),
    val date: SwiftDate,
    val action: TradeAction,
    val symbol: String,
    val name: String,
    val shares: Double,
    val unitCost: Double,
    val broker: String,
    /** Money paid (buy, cost included) or received (sell, fees deducted); older entries derive it from shares × unit cost. */
    val amount: Double? = null,
    /** Proceeds minus the average cost of the shares sold. */
    val realized: Double? = null,
) {
    val total: Double get() = amount ?: (shares * unitCost)

    val isValid: Boolean get() {
        if (symbol.isEmpty() || symbol.charCount > 20 || name.charCount > 120 || broker.charCount > 120) return false
        if (!(shares.isFinite() && shares >= 0 && shares <= 1e10 && unitCost.isFinite() && unitCost >= 0 && unitCost <= 1e9)) return false
        if (amount != null && !(amount.isFinite() && amount >= 0 && amount <= 1e12)) return false
        if (realized != null && !realized.isFinite()) return false
        return true
    }

    companion object {
        /** Swift `Trade(id:date:action:holding:amount:)`. */
        fun of(action: TradeAction, holding: Holding, date: Instant = Instant.now(), amount: Double? = null, id: UUID = UUID.randomUUID()) =
            Trade(id, date, action, holding.symbol, holding.name, holding.shares, holding.unitCost, holding.broker, amount)

        /** Swift `Trade(date:action:symbol:name:shares:amount:broker:realized:)`: the unit cost is the amount per share. */
        fun amount(date: Instant, action: TradeAction, symbol: String, name: String, shares: Double, amount: Double, broker: String, realized: Double? = null) =
            Trade(UUID.randomUUID(), date, action, symbol, name, shares, if (shares > 0) amount / shares else 0.0, broker, amount, realized)
    }
}

@Serializable
enum class DividendStatus(val rawValue: String) {
    @SerialName("已入帳") PAID("已入帳"),
    @SerialName("已公告") ANNOUNCED("已公告"),
    @SerialName("預估") ESTIMATED("預估"),
}

@Serializable
data class Dividend(
    @Required val id: SwiftUUID = UUID.randomUUID(),
    val symbol: String,
    /** Payment date (or expected payment date). */
    val date: SwiftDate,
    /** Amount received after deductions. */
    val amount: Double,
    val status: DividendStatus,
    val exDate: SwiftDate? = null,
    val shares: Double? = null,
    val perShare: Double? = null,
    val deduction: Double? = null,
    val source: String? = null,
    val note: String? = null,
    /** The holding the record was made from; null for records of the whole code and older ones. */
    val holdingID: SwiftUUID? = null,
) {
    /** Shares × amount per unit, before deductions, when both are recorded. */
    val gross: Double? get() {
        if (shares == null || perShare == null || !(shares > 0) || !(perShare > 0)) return null
        return swiftRounded(shares * perShare)
    }

    val detailsValid: Boolean get() =
        listOf(shares, perShare, deduction).all { value -> value?.let { it.isFinite() && it >= 0 && it <= 1e10 } ?: true } &&
            (source?.charCount ?: 0) <= 20 && (note?.charCount ?: 0) <= 80
}

/** Where a dividend record came from; the source also sets its status. */
enum class DividendSource(val rawValue: String) {
    BROKER("證券帳務"), ANNOUNCEMENT("投信公告"), ESTIMATE("自行預估");

    val id: String get() = rawValue
    val status: DividendStatus get() = when (this) {
        BROKER -> DividendStatus.PAID; ANNOUNCEMENT -> DividendStatus.ANNOUNCED; ESTIMATE -> DividendStatus.ESTIMATED
    }
}

/** `OpenData.source`: the close of a trading day from the exchanges' open data. */
const val OPEN_DATA_SOURCE = "收盤"

@Serializable
data class Quote(
    val symbol: String,
    val price: Double,
    val changePercent: Double? = null,
    val date: String,
    val fetchedAt: SwiftDate,
    val currency: String? = null,
    val change: Double? = null,
    val open: Double? = null,
    val high: Double? = null,
    val low: Double? = null,
    /** Trading volume in lots (張). */
    val volume: Double? = null,
    /** `OPEN_DATA_SOURCE` for a trading day's close; null for live and older saved quotes. */
    val source: String? = null,
    /** True while the price is a trial match rather than a trade; never saved. */
    val trial: Boolean? = null,
) {
    val isDailyClose: Boolean get() = source == OPEN_DATA_SOURCE
    val isTWD: Boolean get() = currency == "TWD" || (currency == null && Fund.starters.any { it.id == symbol })
    val isValid: Boolean get() =
        price.isFinite() && price > 0 && listOf(change, changePercent).all { it?.isFinite() ?: true } &&
            listOf(open, high, low, volume).all { value -> value?.let { it.isFinite() && it >= 0 } ?: true }
}

@Serializable
data class Portfolio(
    @Required val schema: Int = 1,
    @Required val holdings: List<Holding> = emptyList(),
    @Required val dividends: List<Dividend> = emptyList(),
    @Required val favorites: Set<String> = emptySet(),
    @Required val quotes: Map<String, Quote> = emptyMap(),
    val comparison: List<String>? = null,
    val legacyPlan: LegacyPlan? = null,
    val legacyPrices: Map<String, LegacyPrice>? = null,
    val legacyDividends: Map<String, BackupImport.OldDividend>? = null,
    val components: Map<String, ComponentSnapshot>? = null,
    /** Earlier holdings of each ETF, newest first, at most `historyLimit` days apiece; absent in older files. */
    val componentHistory: Map<String, List<ComponentSnapshot>>? = null,
    val histories: Map<String, PriceHistory>? = null,
    val fees: Map<String, FeeRecord>? = null,
    /** Absent in files written before the trade log existed. */
    val trades: List<Trade>? = null,
    /** Absent in files written before the game layer; start from `game ?: GameState()`. */
    val game: GameState? = null,
    /** 組合試算 settings and simulated mix; absent in older files. */
    val combo: ComboSettings? = null,
    /** 到價提醒, at most `AlertEngine.limit`; absent in older files. */
    val alerts: List<PriceAlert>? = null,
) {
    val cost: Double get() = holdings.sumOf { it.cost }

    val marketValue: Double? get() {
        if (holdings.isEmpty() || !holdings.all { quotes[it.symbol]?.isTWD == true }) return null
        return holdings.fold(0.0) { total, h -> total + h.shares * quotes.getValue(h.symbol).price }
    }

    /** Files `snapshot` under its ETF: a snapshot of the same date is replaced, the newest `historyLimit` dates stay. */
    fun remember(snapshot: ComponentSnapshot): Portfolio {
        val list = ((componentHistory?.get(snapshot.symbol) ?: emptyList()).filter { it.date != snapshot.date } + snapshot)
            .sortedByDescending { it.date }.take(historyLimit)
        return copy(componentHistory = (componentHistory ?: emptyMap()) + (snapshot.symbol to list))
    }

    /** Appends to the trade log, keeping the most recent 5,000 entries. */
    fun log(action: TradeAction, holding: Holding, date: Instant = Instant.now(), amount: Double? = null): Portfolio =
        log(Trade.of(action, holding, date, amount))

    fun log(trade: Trade): Portfolio = copy(trades = ((trades ?: emptyList()) + trade).takeLast(5000))

    /** The bytes the app saves and backs up. */
    fun encode(): ByteArray = CoreJson.json.encodeToString(serializer(), this).toByteArray()

    companion object {
        /** Days of holdings kept for one ETF. */
        const val historyLimit = 12

        /** One ETF's history as it may be saved: its own snapshots, one per date, no more than `historyLimit`, each valid. */
        fun validate(history: List<ComponentSnapshot>, of: String) {
            if (history.size > historyLimit || history.map { it.date }.toSet().size != history.size) throw StoreError.UnsupportedBackup
            for (snapshot in history) {
                if (of != snapshot.symbol) throw StoreError.UnsupportedBackup
                snapshot.validate()
            }
        }

        /**
         * `limit` is raised only for the device's own records file, which earlier versions let grow past a backup's size
         * with price histories; the first save then moves those out.
         */
        fun decodeBackup(data: ByteArray, limit: Int = 5_000_000): Portfolio {
            if (data.size > limit) throw StoreError.UnsupportedBackup
            val value = CoreJson.decode(serializer(), data)
            if (!(value.schema == 1 && value.holdings.size <= 10000 && value.dividends.size <= 50000 && value.favorites.size <= 2000)) throw StoreError.UnsupportedBackup
            for (holding in value.holdings) holding.validate()
            val trades = value.trades ?: emptyList()
            val alerts = value.alerts ?: emptyList()
            val ok = value.holdings.map { it.id }.toSet().size == value.holdings.size &&
                value.dividends.map { it.id }.toSet().size == value.dividends.size &&
                value.dividends.all { it.symbol.isNotEmpty() && it.amount.isFinite() && it.amount >= 0 && it.detailsValid } &&
                value.quotes.all { (key, quote) -> key == quote.symbol && quote.isValid } &&
                trades.size <= 50000 && trades.map { it.id }.toSet().size == trades.size && trades.all { it.isValid } &&
                (value.combo?.isValid ?: true) &&
                alerts.size <= AlertEngine.limit && alerts.map { it.id }.toSet().size == alerts.size && alerts.all { it.isValid }
            if (!ok) throw StoreError.UnsupportedBackup
            value.legacyPlan?.validate()
            for (d in (value.legacyDividends ?: emptyMap()).values) d.validate()
            for ((code, snapshot) in value.components ?: emptyMap()) {
                if (code != snapshot.symbol) throw StoreError.UnsupportedBackup
                snapshot.validate()
            }
            for ((code, list) in value.componentHistory ?: emptyMap()) validate(list, code)
            for ((code, history) in value.histories ?: emptyMap()) {
                if (code != history.symbol) throw StoreError.UnsupportedBackup
                history.validate()
            }
            for ((code, fee) in value.fees ?: emptyMap()) {
                if (code != fee.symbol) throw StoreError.UnsupportedBackup
                fee.validate()
            }
            val comparison = value.comparison ?: emptyList()
            val prices = (value.legacyPrices ?: emptyMap()).values
            if (!(comparison.size <= 3 && comparison.all(DataChecks::code) &&
                    prices.all { DataChecks.code(it.symbol) && it.price.isFinite() && it.price >= 0 && DataChecks.date(it.date) != null })) throw StoreError.UnsupportedBackup
            return value
        }
    }
}

/** PocketCore `StoreError`: each case's text is what the person reads. */
sealed class StoreError(text: String) : AppDataError(text) {
    data object InvalidHolding : StoreError("請填寫代碼與名稱，股數須大於 0，成本不可為負數。")
    data object UnsupportedBackup : StoreError("備份格式不支援或資料不完整；現有資料未變更。")
    data object MissingKey : StoreError("請先在行情連線儲存你的富果 API Key。")
    data object InvalidQuote : StoreError("行情沒有有效成交價，請稍後再試。")
    class Keychain(val status: Int) : StoreError("無法安全儲存金鑰，請重試。")
    class Http(val code: Int) : StoreError(httpText(code))

    companion object {
        fun httpText(code: Int): String = when (code) {
            401 -> "金鑰無效或已失效，請重新確認行情金鑰。"
            403 -> "目前方案沒有這項資料權限；成分股需要富果開發者或進階方案。已有報價會保留。"
            429 -> "已達資料請求額度，請稍後重試；已有資料會保留。"
            else -> "資料服務暫時無法使用（$code），保留上次成功資料。"
        }
    }
}

object Projection {
    fun value(initial: Double, monthly: Double, years: Int, annualPercent: Double): Double {
        val rate = annualPercent / 100 / 12
        var total = initial
        repeat(maxOf(years, 0) * 12) { total = total * (1 + rate) + monthly }
        return total
    }
}
