package com.sonia.etftogo.core

import com.sonia.etftogo.core.game.YearMonth
import com.sonia.etftogo.core.models.ComponentSnapshot
import com.sonia.etftogo.core.models.Fund
import com.sonia.etftogo.core.models.Quote
import com.sonia.etftogo.core.sources.AnnualExpense
import com.sonia.etftogo.core.sources.AnnualFeeCatalog
import com.sonia.etftogo.core.sources.CatalogAPI
import com.sonia.etftogo.core.sources.CatalogSnapshot
import com.sonia.etftogo.core.sources.DailyBar
import com.sonia.etftogo.core.sources.DividendEvent
import com.sonia.etftogo.core.sources.Fugle
import com.sonia.etftogo.core.sources.IssuerDirectory
import com.sonia.etftogo.core.sources.IssuerHoldings
import com.sonia.etftogo.core.sources.OfficialDistribution
import com.sonia.etftogo.core.sources.OfficialDividends
import com.sonia.etftogo.core.sources.OfficialHistory
import com.sonia.etftogo.core.sources.OpenData
import com.sonia.etftogo.core.sources.SplitEvent
import com.sonia.etftogo.core.sources.decodeComponents
import com.sonia.etftogo.core.sources.decodeHistory
import com.sonia.etftogo.core.support.epochSeconds
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonPrimitive

private fun quoteOutput(q: Quote, fetchedAt: Boolean): JsonElement {
    val out = linkedMapOf(
        "symbol" to JsonPrimitive(q.symbol), "price" to JsonPrimitive(q.price), "changePercent" to num(q.changePercent), "date" to JsonPrimitive(q.date),
        "currency" to orNull(q.currency), "change" to num(q.change), "open" to num(q.open), "high" to num(q.high), "low" to num(q.low),
        "volume" to num(q.volume), "source" to orNull(q.source), "trial" to (q.trial?.let(::JsonPrimitive) ?: JsonNull),
    )
    if (fetchedAt) out["fetchedAt"] = JsonPrimitive(q.fetchedAt.epochSeconds())
    return JsonObject(out)
}

private fun shortQuotes(quotes: Map<String, Quote>): JsonElement = JsonArray(quotes.values.sortedBy { it.symbol }.map {
    JsonObject(mapOf("symbol" to JsonPrimitive(it.symbol), "price" to JsonPrimitive(it.price), "date" to JsonPrimitive(it.date), "currency" to orNull(it.currency)))
})

private fun snapshotOutput(s: ComponentSnapshot): JsonElement = JsonObject(mapOf(
    "symbol" to JsonPrimitive(s.symbol), "date" to JsonPrimitive(s.date), "source" to orNull(s.source),
    "components" to JsonArray(s.components.map { JsonObject(mapOf("symbol" to JsonPrimitive(it.symbol), "name" to orNull(it.name), "weight" to JsonPrimitive(it.weight))) }),
))

private fun distributionOutput(d: OfficialDistribution): JsonElement =
    JsonObject(mapOf("ex" to JsonPrimitive(d.ex), "pay" to JsonPrimitive(d.pay), "amount" to num(d.amount)))

private fun distributions(map: Map<String, List<OfficialDistribution>>): JsonElement =
    JsonObject(map.mapValues { (_, list) -> JsonArray(list.map(::distributionOutput)) })

private fun strings(map: Map<String, String>): JsonElement = JsonObject(map.mapValues { JsonPrimitive(it.value) })

private fun dividendsOutput(r: OfficialDividends): JsonElement =
    JsonObject(mapOf("sources" to strings(r.sources), "events" to distributions(r.events), "freq" to strings(r.freq)))

private fun fundOutput(f: Fund): JsonElement = JsonObject(mapOf(
    "id" to JsonPrimitive(f.id), "name" to JsonPrimitive(f.name), "strategy" to JsonPrimitive(f.strategy.rawValue), "market" to orNull(f.market),
    "fullName" to orNull(f.fullName), "fundType" to orNull(f.fundType), "listingDate" to orNull(f.listingDate),
))

private fun expenseOutput(e: AnnualExpense): JsonElement = JsonObject(mapOf(
    "symbol" to JsonPrimitive(e.symbol), "fundID" to JsonPrimitive(e.fundID), "fundName" to JsonPrimitive(e.fundName), "year" to JsonPrimitive(e.year),
    "commission" to JsonPrimitive(e.commission), "tax" to JsonPrimitive(e.tax), "subscriptionOffset" to JsonPrimitive(e.subscriptionOffset),
    "management" to JsonPrimitive(e.management), "custody" to JsonPrimitive(e.custody), "guarantee" to JsonPrimitive(e.guarantee),
    "other" to JsonPrimitive(e.other), "total" to JsonPrimitive(e.total),
))

private fun bars(list: List<DailyBar>): JsonElement = JsonArray(list.map { JsonObject(mapOf("date" to JsonPrimitive(it.date), "close" to JsonPrimitive(it.close))) })

private fun events(list: List<DividendEvent>): JsonElement = JsonArray(list.map {
    JsonObject(mapOf("symbol" to JsonPrimitive(it.symbol), "exDate" to JsonPrimitive(it.exDate), "cash" to JsonPrimitive(it.cash)))
})

private fun JsonElement.record(): OfficialDividends = decode("record", OfficialDividends.serializer())
private fun JsonElement.html(): String = bytes().decodeToString()
private fun JsonElement.sub(key: String): JsonElement = field(key)
private val stringMap = MapSerializer(String.serializer(), String.serializer())

val sourceHandlers: Map<String, VectorHandler> = mapOf(
    // OpenData
    "OpenData.decodeTWSE" to { input -> shortQuotes(OpenData.decodeTWSE(input.bytes())) },
    "OpenData.decodeTPEx" to { input -> shortQuotes(OpenData.decodeTPEx(input.bytes())) },
    "OpenData.quotes" to { input ->
        val all = LinkedHashMap(OpenData.decodeTWSE(Fixtures.bytes(input.str("twse"))))
        for ((k, v) in OpenData.decodeTPEx(Fixtures.bytes(input.str("tpex")))) all.putIfAbsent(k, v)
        JsonObject(all.mapValues { quoteOutput(it.value, fetchedAt = true) })
    },
    "OpenData.decodeTAIEX" to { input -> OpenData.decodeTAIEX(input.bytes())?.let { quoteOutput(it, true) } ?: JsonNull },
    "OpenData.decodeTPExIndex" to { input -> OpenData.decodeTPExIndex(input.bytes())?.let { quoteOutput(it, true) } ?: JsonNull },
    "OpenData.expectedDay" to { input -> JsonPrimitive(OpenData.expectedDay(input.at())) },
    // OfficialDividends
    "OfficialDividends.decode" to { input ->
        distributions(OfficialDividends.decode(input.bytes(), input.str("market"), input.decode("markets", stringMap)))
    },
    "OfficialDividends.rocDay" to { input -> orNull(OfficialDividends.rocDay(input.str("text"))) },
    "OfficialDividends.frequency(of:)" to { input ->
        orNull(OfficialDividends.frequency(input.decode("list", ListSerializer(OfficialDistribution.serializer())), input.at("now")))
    },
    "OfficialDividends.merging" to { input ->
        val fresh = input.decode("fresh", MapSerializer(String.serializer(), ListSerializer(OfficialDistribution.serializer())))
        val flag = VectorIO.obj(input)["frequency"]?.jsonPrimitive?.booleanOrNull ?: false
        dividendsOutput(input.record().merging(fresh, flag, input.at("now")))
    },
    "OfficialDividends.trailingAmount" to { input -> num(input.record().trailingAmount(input.str("symbol"), input.at("now"))) },
    "OfficialDividends.isNewer" to { input ->
        JsonPrimitive(OfficialDividends(sources = input.decode("a", stringMap)).isNewer(OfficialDividends(sources = input.decode("b", stringMap))))
    },
    "OfficialDividends.bundled.summary" to { _ ->
        val r = OfficialDividends.bundled()
        JsonObject(mapOf(
            "sources" to strings(r.sources), "symbolCount" to JsonPrimitive(r.events.size),
            "firstSymbols" to JsonArray(r.events.keys.sorted().take(5).map(::JsonPrimitive)),
            "eventCount" to JsonPrimitive(r.events.values.sumOf { it.size }), "freqCount" to JsonPrimitive(r.freq.size),
        ))
    },
    // Catalog and fees
    "CatalogAPI.strategy" to { input -> JsonPrimitive(CatalogAPI.strategy(input.str("name")).rawValue) },
    "CatalogAPI.unescape" to { input -> JsonPrimitive(CatalogAPI.unescape(input.str("text"))) },
    "CatalogAPI.decode" to { input ->
        val previous = VectorIO.obj(input)["previous"]?.let { com.sonia.etftogo.core.support.CoreJson.decode(CatalogSnapshot.serializer(), it) }
        val s = CatalogAPI.decode(input.sub("listed").bytes(), input.sub("twse").bytes(), input.sub("otc").bytes(), previous, input.str("today"))
        JsonObject(mapOf(
            "funds" to JsonArray(s.funds.map(::fundOutput)), "listedDate" to JsonPrimitive(s.listedDate), "fetchedDay" to JsonPrimitive(s.fetchedDay),
            "sources" to JsonArray(s.sources.map(::JsonPrimitive)),
        ))
    },
    "CatalogSnapshot.bundled.summary" to { _ ->
        CatalogSnapshot.bundled()?.let {
            JsonObject(mapOf("count" to JsonPrimitive(it.funds.size), "listedDate" to JsonPrimitive(it.listedDate), "first" to JsonArray(it.funds.take(5).map { f -> JsonPrimitive(f.id) })))
        } ?: JsonNull
    },
    "AnnualFeeCatalog.bundled.summary" to { _ ->
        AnnualFeeCatalog.bundled?.let { c ->
            val first = c.records.keys.sorted().firstOrNull()?.let { c.records[it] }
            JsonObject(mapOf(
                "count" to JsonPrimitive(c.records.size), "fetchedDay" to JsonPrimitive(c.fetchedDay), "sourceURL" to JsonPrimitive(c.sourceURL),
                "first" to (first?.let(::expenseOutput) ?: JsonNull),
            ))
        } ?: JsonNull
    },
    // OfficialHistory
    "OfficialHistory.rocDate" to { input -> orNull(OfficialHistory.rocDate(input.str("text"))) },
    "OfficialHistory.twseMonth" to { input -> bars(OfficialHistory.twseMonth(input.bytes())) },
    "OfficialHistory.tpexMonth" to { input -> bars(OfficialHistory.tpexMonth(input.bytes())) },
    "OfficialHistory.twseDividends" to { input -> events(OfficialHistory.twseDividends(input.bytes())) },
    "OfficialHistory.tpexDividends" to { input -> events(OfficialHistory.tpexDividends(input.bytes())) },
    "OfficialHistory.splits" to { input ->
        JsonArray(OfficialHistory.splits(input.bytes()).map {
            JsonObject(mapOf("symbol" to JsonPrimitive(it.symbol), "resumeDate" to JsonPrimitive(it.resumeDate), "ratio" to JsonPrimitive(it.ratio)))
        })
    },
    "OfficialHistory.suspectedSplits" to { input ->
        JsonArray(OfficialHistory.suspectedSplits(
            input.decode("bars", ListSerializer(DailyBar.serializer())),
            input.decode("dividends", ListSerializer(DividendEvent.serializer())),
            input.decode("known", ListSerializer(SplitEvent.serializer())),
        ).map(::JsonPrimitive))
    },
    "OfficialHistory.urls" to { input ->
        val symbol = input.str("symbol")
        val month = input.decode("month", YearMonth.serializer())
        val from = input.at("from")
        val to = input.at("to")
        JsonObject(mapOf(
            "twseMonth" to JsonPrimitive(OfficialHistory.twseMonthURL(symbol, month).toString()),
            "tpexMonth" to JsonPrimitive(OfficialHistory.tpexMonthURL(symbol, month).toString()),
            "twseDividends" to JsonPrimitive(OfficialHistory.twseDividendsURL(from, to).toString()),
            "tpexDividends" to JsonPrimitive(OfficialHistory.tpexDividendsURL(from, to).toString()),
            "splits" to JsonPrimitive(OfficialHistory.splitsURL(from, to).toString()),
        ))
    },
    // Issuers
    "IssuerHoldings.yuanta" to { input -> snapshotOutput(IssuerHoldings.yuanta(input.bytes(), input.str("symbol"))) },
    "IssuerHoldings.cathay" to { input -> snapshotOutput(IssuerHoldings.cathay(input.bytes(), input.str("symbol"), input.str("date"))) },
    "IssuerHoldings.fubon" to { input -> snapshotOutput(IssuerHoldings.fubon(input.html(), input.str("symbol"))) },
    "IssuerHoldings.capital" to { input -> snapshotOutput(IssuerHoldings.capital(input.bytes(), input.str("symbol"))) },
    "IssuerHoldings.fhtrust" to { input -> snapshotOutput(IssuerHoldings.fhtrust(input.bytes(), input.str("symbol"))) },
    "IssuerHoldings.ctbc" to { input -> snapshotOutput(IssuerHoldings.ctbc(input.bytes(), input.str("symbol"))) },
    "IssuerHoldings.day" to { input -> orNull(IssuerHoldings.day(VectorIO.obj(input)["value"])) },
    "IssuerHoldings.cathayFundCode" to { input -> orNull(IssuerHoldings.cathayFundCode(input.bytes(), input.str("symbol"))) },
    "IssuerHoldings.cathayAssetsDate" to { input -> orNull(IssuerHoldings.cathayAssetsDate(input.bytes())) },
    "IssuerHoldings.capitalFundNo" to { input -> orNull(IssuerHoldings.capitalFundNo(input.bytes(), input.str("symbol"))) },
    "IssuerHoldings.fhtrustFundID" to { input -> orNull(IssuerHoldings.fhtrustFundID(input.html(), input.str("symbol"))) },
    "IssuerHoldings.ctbcFID" to { input -> orNull(IssuerHoldings.ctbcFID(input.bytes(), input.str("symbol"))) },
    "IssuerHoldings.ctbcToken" to { input -> orNull(IssuerHoldings.ctbcToken(input.bytes())) },
    "IssuerDirectory.issuer" to { input -> orNull(IssuerDirectory.issuer(input.str("name"))?.rawValue) },
    "IssuerDirectory.isBondFund" to { input ->
        JsonPrimitive(IssuerDirectory.isBondFund(input.str("symbol"), VectorIO.obj(input)["fundType"]?.jsonPrimitive?.content))
    },
    // Fugle
    "Fugle.decode" to { input -> quoteOutput(Fugle.decode(input.bytes(), input.str("expectedSymbol")), fetchedAt = false) },
    "Fugle.decodeComponents" to { input -> snapshotOutput(Fugle.decodeComponents(input.bytes(), input.str("symbol"))) },
    "Fugle.decodeHistory" to { input ->
        JsonArray(Fugle.decodeHistory(input.bytes(), input.str("symbol")).map { JsonObject(mapOf("date" to JsonPrimitive(it.date), "close" to JsonPrimitive(it.close))) })
    },
)
