package com.sonia.etftogo.core

import com.sonia.etftogo.core.importing.Box
import com.sonia.etftogo.core.importing.BrokerMapping
import com.sonia.etftogo.core.importing.BrokerPreview
import com.sonia.etftogo.core.importing.CSVTable
import com.sonia.etftogo.core.importing.ScreenshotImport
import com.sonia.etftogo.core.importing.TextBox
import com.sonia.etftogo.core.models.Fund
import com.sonia.etftogo.core.models.Holding
import com.sonia.etftogo.core.support.AppDataError
import com.sonia.etftogo.core.support.CoreJson
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Broker CSV and screenshot import: the shapes both platforms read and write in SharedFixtures/vectors/importing.

private fun strings(list: List<String>): JsonElement = JsonArray(list.map(::JsonPrimitive))
private fun JsonElement.optNumber(key: String): Double? = (VectorIO.obj(this)[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.doubleOrNull
private fun JsonElement.optString(key: String): String? = (VectorIO.obj(this)[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull
private fun JsonElement.optBool(key: String): Boolean? = (VectorIO.obj(this)[key] as? JsonPrimitive)?.booleanOrNull

private fun JsonElement.funds(): List<Fund> =
    VectorIO.obj(this)["funds"]?.let { CoreJson.json.decodeFromJsonElement(ListSerializer(Fund.serializer()), it) } ?: Fund.starters

private fun JsonElement.mapping(table: CSVTable): BrokerMapping {
    val m = VectorIO.obj(this)["mapping"] ?: return BrokerMapping.guessing(table)
    return BrokerMapping(m.int("symbol"), m.int("name"), m.int("shares"), m.int("cost"), m.optBool("lots") ?: false, m.optBool("totalCost") ?: true)
}

private fun mappingOutput(m: BrokerMapping) = JsonObject(mapOf(
    "symbol" to JsonPrimitive(m.symbol), "name" to JsonPrimitive(m.name), "shares" to JsonPrimitive(m.shares), "cost" to JsonPrimitive(m.cost),
    "lots" to JsonPrimitive(m.lots), "totalCost" to JsonPrimitive(m.totalCost),
))

private fun previewOutput(p: BrokerPreview) = JsonObject(mapOf(
    "holdings" to JsonArray(p.holdings.map { encoded(Holding.serializer(), it) }), "sourceAccount" to JsonPrimitive(p.sourceAccount),
    "broker" to JsonPrimitive(p.broker), "skipped" to strings(p.skipped), "skippedCodes" to strings(p.skippedCodes.sorted()),
    "totalCost" to JsonPrimitive(p.totalCost),
))

private fun kind(raw: String): ScreenshotImport.Kind = ScreenshotImport.Kind.of(raw) ?: throw AppDataError("unknown kind")

private fun JsonElement.draft() = ScreenshotImport.Draft(
    symbol = str("symbol"), shares = str("shares"), cost = str("cost"), perShare = optBool("perShare") ?: false, kind = kind(optString("kind") ?: "現股"),
)

private fun basisName(basis: ScreenshotImport.Basis?): JsonElement = when (basis) {
    ScreenshotImport.Basis.TOTAL -> JsonPrimitive("total")
    ScreenshotImport.Basis.PER_SHARE -> JsonPrimitive("perShare")
    null -> JsonNull
}

private fun JsonElement.row() = ScreenshotImport.Row(
    symbol = str("symbol"), shares = optNumber("shares"), cost = optNumber("cost"), name = optString("name"),
    choices = VectorIO.obj(this)["choices"]?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList(), note = optString("note"),
    kind = kind(optString("kind") ?: "現股"),
    basis = when (optString("basis")) { "total" -> ScreenshotImport.Basis.TOTAL; "perShare" -> ScreenshotImport.Basis.PER_SHARE; else -> null },
)

private fun rowOutput(r: ScreenshotImport.Row) = JsonObject(mapOf(
    "symbol" to JsonPrimitive(r.symbol), "shares" to num(r.shares), "cost" to num(r.cost), "name" to orNull(r.name), "choices" to strings(r.choices),
    "note" to orNull(r.note), "kind" to JsonPrimitive(r.kind.rawValue), "basis" to basisName(r.basis),
))

private fun JsonElement.boxes(key: String): List<TextBox> = field(key).jsonArray.map { item ->
    val b = item.field("box").jsonArray.map { it.jsonPrimitive.doubleOrNull ?: error("box is not four numbers") }
    if (b.size != 4) error("box is not four numbers")
    TextBox(item.str("text"), Box(b[0], b[1], b[2], b[3]))
}

private fun listing(value: JsonElement) = ScreenshotImport.Listing(value.jsonArray.map { pair -> pair.jsonArray.let { it[0].jsonPrimitive.content to it[1].jsonPrimitive.content } })

private fun JsonElement.preview(): BrokerPreview {
    if ("drafts" in VectorIO.obj(this)) return BrokerPreview.make(field("drafts").jsonArray.map { it.draft() }, str("broker"), str("account"), funds())
    val table = CSVTable.parse(bytes())
    return BrokerPreview.make(table, mapping(table), str("broker"), str("account"), funds())
}

/** JSON has no NaN or infinity: they are written as text. */
private fun jsonNumber(value: Double?): JsonElement = when {
    value == null -> JsonNull
    value.isNaN() -> JsonPrimitive("nan")
    value.isInfinite() -> JsonPrimitive(if (value > 0) "inf" else "-inf")
    else -> JsonPrimitive(value)
}

private fun tableOutput(table: CSVTable) = JsonObject(mapOf("headers" to strings(table.headers), "rows" to JsonArray(table.rows.map(::strings))))

val importHandlers: Map<String, VectorHandler> = mapOf(
    "CSVTable.parse" to { input -> tableOutput(CSVTable.parse(input.bytes())) },
    "CSVTable.parseLegacyEncoding" to { input -> tableOutput(CSVTable.parse(input.bytes())) },
    "BrokerMapping.guessing" to { input -> mappingOutput(BrokerMapping.guessing(CSVTable.parse(input.bytes()))) },
    "BrokerPreview.makeTable" to { input -> previewOutput(input.preview()) },
    "BrokerPreview.makeDrafts" to { input -> previewOutput(input.preview()) },
    "BrokerPreview.warnings" to { input ->
        val prices = VectorIO.obj(input)["prices"]?.jsonObject?.mapValues { it.value.jsonPrimitive.doubleOrNull } ?: emptyMap()
        strings(input.preview().warnings { prices[it] })
    },
    "BrokerPreview.costWarning" to { input -> orNull(BrokerPreview.costWarning(input.num("average"), input.optNumber("price"))) },
    "BrokerPreview.shareCount" to { input -> jsonNumber(BrokerPreview.shareCount(input.str("text"))) },
    "BrokerPreview.number" to { input -> jsonNumber(BrokerPreview.number(input.str("text"))) },
    "ScreenshotImport.lines" to { input -> strings(ScreenshotImport.lines(input.boxes("boxes"))) },
    "ScreenshotImport.combine" to { input ->
        JsonArray(ScreenshotImport.combine(input.boxes("corrected"), input.boxes("raw")).map {
            JsonObject(mapOf("text" to JsonPrimitive(it.text), "box" to JsonArray(listOf(it.box.x, it.box.y, it.box.width, it.box.height).map(::JsonPrimitive))))
        })
    },
    "ScreenshotImport.parse" to { input ->
        JsonArray(ScreenshotImport.parse(input.field("lines").jsonArray.map { it.jsonPrimitive.content }, listing(input.field("listing"))).map(::rowOutput))
    },
    "ScreenshotImport.review" to { input ->
        val result = ScreenshotImport.review(input.field("pages").jsonArray.map { page -> page.jsonArray.map { it.row() } })
        JsonObject(mapOf("rows" to JsonArray(result.rows.map(::rowOutput)), "short" to JsonArray(result.short.map(::rowOutput))))
    },
    "ScreenshotImport.basis" to { input -> basisName(ScreenshotImport.basis(input.num("cost"), input.num("shares"), input.optNumber("price"))) },
    "ScreenshotImport.plausible" to { input -> JsonPrimitive(ScreenshotImport.plausible(input.num("average"), input.num("price"))) },
    "ScreenshotImport.Draft" to { input ->
        val d = ScreenshotImport.Draft.of(input.field("row").row(), input.optNumber("price"))
        JsonObject(mapOf(
            "symbol" to JsonPrimitive(d.symbol), "shares" to JsonPrimitive(d.shares), "cost" to JsonPrimitive(d.cost), "perShare" to JsonPrimitive(d.perShare),
            "kind" to JsonPrimitive(d.kind.rawValue), "seen" to JsonPrimitive(d.seen), "choices" to strings(d.choices), "note" to orNull(d.note),
            "costNote" to orNull(d.costNote), "totalCost" to num(d.totalCost), "averageCost" to num(d.averageCost),
        ))
    },
    "ScreenshotImport.Listing" to { input ->
        val l = listing(input.field("entries"))
        fun list(key: String) = VectorIO.obj(input)[key]?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList()
        JsonObject(mapOf(
            "exact" to JsonArray(list("exact").map { strings(l.exact(it)) }), "near" to JsonArray(list("near").map { strings(l.near(it)) }),
            "knows" to JsonArray(list("knows").map { JsonPrimitive(l.knows(it)) }),
        ))
    },
)
