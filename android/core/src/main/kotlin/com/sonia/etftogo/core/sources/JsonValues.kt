package com.sonia.etftogo.core.sources

import com.sonia.etftogo.core.support.CoreJson
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull

/*
 * Reading `JSONSerialization` values the way the Swift parsers cast them: `as? String` takes only JSON strings,
 * `as? Double` only JSON numbers, `as? [[String: Any]]` only an array whose every element is an object.
 */

/** `try? JSONSerialization.jsonObject(with:) as? [String: Any]`. */
internal fun parseObject(bytes: ByteArray): JsonObject? = parseJson(bytes) as? JsonObject

internal fun parseJson(bytes: ByteArray): JsonElement? =
    try { CoreJson.json.parseToJsonElement(bytes.decodeToString(throwOnInvalidSequence = true)) } catch (_: Exception) { null }

internal val JsonElement?.string: String? get() = (this as? JsonPrimitive)?.takeIf { it.isString }?.content

internal val JsonElement?.obj: JsonObject? get() = this as? JsonObject

internal val JsonElement?.objects: List<JsonObject>? get() {
    val array = this as? JsonArray ?: return null
    return array.map { it as? JsonObject ?: return null }
}

internal val JsonElement?.bool: Boolean? get() = (this as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull

internal val JsonElement?.double: Double? get() = (this as? JsonPrimitive)?.takeIf { !it.isString && it.booleanOrNull == null }?.doubleOrNull
