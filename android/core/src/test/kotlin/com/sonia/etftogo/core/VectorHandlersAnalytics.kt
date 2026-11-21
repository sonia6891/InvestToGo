package com.sonia.etftogo.core

import com.sonia.etftogo.core.analytics.Backtest
import com.sonia.etftogo.core.analytics.BacktestInput
import com.sonia.etftogo.core.analytics.BacktestLeg
import com.sonia.etftogo.core.analytics.CashFlow
import com.sonia.etftogo.core.analytics.FeeRate
import com.sonia.etftogo.core.analytics.Finance
import com.sonia.etftogo.core.analytics.PocketReport
import com.sonia.etftogo.core.analytics.ReportCard
import com.sonia.etftogo.core.analytics.ReportPeriod
import com.sonia.etftogo.core.analytics.SellCosts
import com.sonia.etftogo.core.analytics.SnapshotChange
import com.sonia.etftogo.core.analytics.SnapshotDiff
import com.sonia.etftogo.core.analytics.SymbolHistory
import com.sonia.etftogo.core.game.YearMonth
import com.sonia.etftogo.core.models.ComponentSnapshot
import com.sonia.etftogo.core.models.FundComponent
import com.sonia.etftogo.core.models.Portfolio
import com.sonia.etftogo.core.sources.DailyBar
import com.sonia.etftogo.core.sources.DividendEvent
import com.sonia.etftogo.core.sources.SplitEvent
import com.sonia.etftogo.core.support.AppDataError
import com.sonia.etftogo.core.support.CoreJson
import com.sonia.etftogo.core.support.KeyValueStore
import com.sonia.etftogo.core.support.MemoryKeyValueStore
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive

private fun JsonElement.flag(key: String, default: Boolean = false): Boolean = VectorIO.obj(this)[key]?.jsonPrimitive?.booleanOrNull ?: default
private fun <T> JsonElement.decodeOr(key: String, serializer: KSerializer<T>, default: T): T =
    VectorIO.obj(this)[key]?.let { CoreJson.json.decodeFromJsonElement(serializer, it) } ?: default
private fun strings(list: List<String>): JsonElement = JsonArray(list.map(::JsonPrimitive))

private fun JsonElement.period(): ReportPeriod {
    val p = field("period")
    return when (p.str("kind")) {
        "month" -> ReportPeriod.Month(p.decode("month", YearMonth.serializer()))
        "year" -> ReportPeriod.Year(p.int("year"))
        "yearToDate" -> ReportPeriod.YearToDate(p.int("year"))
        else -> throw AppDataError("unknown period")
    }
}

private fun history(element: JsonElement) = SymbolHistory(
    element.decodeOr("bars", ListSerializer(DailyBar.serializer()), emptyList()),
    element.decodeOr("dividends", ListSerializer(DividendEvent.serializer()), emptyList()),
    element.decodeOr("splits", ListSerializer(SplitEvent.serializer()), emptyList()),
    element.flag("suspect"),
    element.flag("fromFugle"),
)

private fun JsonElement.backtestInput() = BacktestInput(
    field("legs").jsonArray.map { BacktestLeg(it.str("symbol"), it.num("weight")) },
    num("monthly"), decode("start", YearMonth.serializer()), decode("end", YearMonth.serializer()), flag("reinvest"),
)

private fun cardOutput(c: ReportCard): JsonElement = JsonObject(mapOf(
    "title" to JsonPrimitive(c.title), "dividends" to JsonPrimitive(c.dividends), "dcaMonths" to JsonPrimitive(c.dcaMonths),
    "reconciles" to JsonPrimitive(c.reconciles), "newDexCards" to JsonPrimitive(c.newDexCards), "level" to JsonPrimitive(c.level),
    "xpEarned" to (c.xpEarned?.let(::JsonPrimitive) ?: JsonNull), "notes" to strings(c.notes),
))

private fun component(c: FundComponent, delta: Double? = null): JsonElement {
    val out = linkedMapOf<String, JsonElement>("symbol" to JsonPrimitive(c.symbol), "name" to orNull(c.name), "weight" to JsonPrimitive(c.weight))
    if (delta != null) out["delta"] = JsonPrimitive(delta)
    return JsonObject(out)
}

private fun changeOutput(c: SnapshotChange?): JsonElement = c?.let {
    JsonObject(mapOf(
        "from" to JsonPrimitive(it.from), "to" to JsonPrimitive(it.to), "added" to JsonArray(it.added.map { a -> component(a) }),
        "removed" to JsonArray(it.removed.map { r -> component(r) }), "changed" to JsonArray(it.changed.map { w -> component(w.component, w.delta) }),
        "changedCut" to JsonPrimitive(it.changedCut), "mixedSources" to JsonPrimitive(it.mixedSources), "isEmpty" to JsonPrimitive(it.isEmpty),
        "title" to JsonPrimitive(it.title),
    ))
} ?: JsonNull

private fun JsonElement.rate(key: String = "rate"): FeeRate = decode(key, FeeRate.serializer())
private fun rateOutput(r: FeeRate): JsonElement = encoded(FeeRate.serializer(), r)
private val ratesSerializer = MapSerializer(String.serializer(), FeeRate.serializer())

private fun JsonElement.store(): KeyValueStore = MemoryKeyValueStore().also { SellCosts.save(decode("stored", ratesSerializer), it) }
private fun JsonElement.portfolio(): Portfolio = decode("portfolio", Portfolio.serializer())

val analyticsHandlers: Map<String, VectorHandler> = mapOf(
    "Finance.xirr" to { input ->
        num(Finance.xirr(input.field("flows").jsonArray.map { CashFlow(it.at("date"), it.num("amount")) }))
    },
    "Backtest.maxDrawdown" to { input -> JsonPrimitive(Backtest.maxDrawdown(input.decode("values", ListSerializer(Double.serializer())))) },
    "Backtest.run" to { input ->
        val raw = VectorIO.obj(input.field("history"))
        val r = Backtest.run(input.backtestInput(), raw.mapValues { history(it.value) })
        JsonObject(mapOf(
            "invested" to JsonPrimitive(r.invested), "endValue" to JsonPrimitive(r.endValue), "dividends" to JsonPrimitive(r.dividends),
            "xirr" to num(r.xirr), "maxDrawdown" to JsonPrimitive(r.maxDrawdown),
            "curve" to JsonArray(r.curve.map {
                JsonObject(mapOf("month" to JsonPrimitive(it.month.key), "invested" to JsonPrimitive(it.invested), "value" to JsonPrimitive(it.value)))
            }),
            "notes" to strings(r.notes),
        ))
    },
    "PocketReport.make" to { input ->
        cardOutput(PocketReport.make(input.period(), input.portfolio(), input.at("now"), input.flag("showDividends", default = true)))
    },
    "ReportPeriod.title" to { input -> JsonPrimitive(input.period().title(input.at("now"))) },
    "PocketReport.earliestMonth" to { input -> orNull(PocketReport.earliestMonth(input.portfolio(), input.at("now"))?.key) },
    "PocketReport.noticeDue" to { input ->
        JsonPrimitive(PocketReport.noticeDue(input.at("now"), input.str("seen"), input.flag("isMember"), input.portfolio()))
    },
    "SellCosts.fee" to { input -> JsonPrimitive(SellCosts.fee(input.num("gross"), input.rate())) },
    "SellCosts.net" to { input ->
        JsonPrimitive(SellCosts.net(input.num("gross"), input.flag("stock"), input.flag("bond"), input.rate(), input.at("on")))
    },
    "SellCosts.taxRate" to { input -> JsonPrimitive(SellCosts.taxRate(input.flag("stock"), input.flag("bond"), input.at("on"))) },
    "SellCosts.preset" to { input -> SellCosts.preset(input.str("broker"))?.let(::rateOutput) ?: JsonNull },
    "SellCosts.brokerKey" to { input -> JsonPrimitive(SellCosts.brokerKey(input.str("broker"))) },
    "SellCosts.rate" to { input ->
        val store = input.store()
        val broker = input.str("broker")
        JsonObject(mapOf(
            "rate" to rateOutput(SellCosts.rate(broker, store)), "isSet" to JsonPrimitive(SellCosts.isSet(broker, store)),
            "note" to JsonPrimitive(SellCosts.rateNote(broker, store)),
        ))
    },
    "SellCosts.remember" to { input ->
        val store = input.store()
        SellCosts.remember(input.rate(), input.str("broker"), store)
        encoded(ratesSerializer, SellCosts.rates(store))
    },
    "SnapshotDiff.compare" to { input ->
        changeOutput(SnapshotDiff.compare(input.decode("old", ComponentSnapshot.serializer()), input.decode("new", ComponentSnapshot.serializer())))
    },
    "SnapshotDiff.latest" to { input -> changeOutput(SnapshotDiff.latest(input.decode("history", ListSerializer(ComponentSnapshot.serializer())))) },
    "SnapshotDiff.shortDay" to { input -> JsonPrimitive(SnapshotDiff.shortDay(input.str("day"), input.flag("year"))) },
)
