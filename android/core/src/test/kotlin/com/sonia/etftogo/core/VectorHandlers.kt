package com.sonia.etftogo.core

import com.sonia.etftogo.core.support.DataChecks
import com.sonia.etftogo.core.support.SHA256Digest
import com.sonia.etftogo.core.support.StableID
import com.sonia.etftogo.core.support.TaiwanMarket
import com.sonia.etftogo.core.support.TrendRole
import com.sonia.etftogo.core.support.uuidString
import com.sonia.etftogo.core.support.decimal
import com.sonia.etftogo.core.support.money
import com.sonia.etftogo.core.support.percentText
import com.sonia.etftogo.core.support.priceText
import com.sonia.etftogo.core.support.wanText
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

fun JsonElement.str(key: String): String = VectorIO.obj(this)[key]?.jsonPrimitive?.content ?: error("vector input has no $key")
fun JsonElement.num(key: String): Double = VectorIO.obj(this)[key]?.jsonPrimitive?.double ?: error("vector input has no $key")
fun JsonElement.at(key: String = "at") = VectorIO.date(str(key))
fun orNull(value: String?): JsonElement = value?.let(::JsonPrimitive) ?: JsonNull

private val supportHandlers: Map<String, VectorHandler> = mapOf(
    "DataChecks.code" to { input -> JsonPrimitive(DataChecks.code(input.str("value"))) },
    "DataChecks.rocDay" to { input -> orNull(DataChecks.rocDay(input.str("text"))) },
    "DataChecks.date" to { input ->
        DataChecks.date(input.str("text"))?.let { JsonPrimitive(it.epochSecond + it.nano / 1e9) } ?: JsonNull
    },
    "DataChecks.day" to { input -> JsonPrimitive(DataChecks.day(input.at())) },
    "StableID.make" to { input -> JsonPrimitive(StableID.make(input.str("namespace"), input.str("value")).uuidString) },
    "SHA256Digest.hash" to { input ->
        JsonPrimitive(SHA256Digest.hash(input.str("utf8").toByteArray()).joinToString("") { "%02x".format(it) })
    },
    "TaiwanMarket.isOpen" to { input -> JsonPrimitive(TaiwanMarket.isOpen(input.at())) },
    "TrendRole.init" to { input ->
        val role = TrendRole.of(input.num("value"))
        buildJsonObject { put("role", role.name.lowercase()); put("colorName", role.colorName) }
    },
)

private val formatHandlers: Map<String, VectorHandler> = mapOf(
    "format.money" to { input -> JsonPrimitive(money(input.num("value"))) },
    "format.decimal" to { input -> JsonPrimitive(decimal(input.num("value"))) },
    "format.priceText" to { input -> JsonPrimitive(priceText(input.num("value"))) },
    "format.percentText" to { input -> JsonPrimitive(percentText(input.num("value"))) },
    "format.wanText" to { input -> JsonPrimitive(wanText(input.num("value"))) },
)

/** Every shared vector kind Kotlin answers, keyed by the vector's `kind` (the Swift side is `vectorHandlers`). */
val vectorHandlers: Map<String, VectorHandler> = buildMap {
    put("Vector.echo") { input -> VectorIO.obj(input)["value"] ?: JsonNull }
    putAll(supportHandlers)
    putAll(formatHandlers)
    putAll(modelHandlers)
    putAll(sourceHandlers)
    putAll(gameHandlers)
    putAll(analyticsHandlers)
    putAll(importHandlers)
}
