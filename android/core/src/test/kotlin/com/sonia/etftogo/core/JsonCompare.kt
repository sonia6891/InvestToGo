package com.sonia.etftogo.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlin.math.abs
import kotlin.math.max

/** Equality of JSON values as SharedFixtures/vectors/README.md defines it (the Swift side is `VectorJSON.equal`). */
object JsonCompare {
    fun equal(a: JsonElement, b: JsonElement): Boolean = when {
        a is JsonNull || b is JsonNull -> a is JsonNull && b is JsonNull
        a is JsonObject -> b is JsonObject && a.keys == b.keys && a.all { (key, value) -> equal(value, b.getValue(key)) }
        a is JsonArray -> b is JsonArray && a.size == b.size && a.indices.all { equal(a[it], b[it]) }
        a is JsonPrimitive && b is JsonPrimitive -> primitives(a, b)
        else -> false
    }

    private fun primitives(a: JsonPrimitive, b: JsonPrimitive): Boolean {
        if (a.isString || b.isString) return a.isString && b.isString && a.content == b.content
        val boolA = a.booleanOrNull
        val boolB = b.booleanOrNull
        if (boolA != null || boolB != null) return boolA == boolB
        val x = a.doubleOrNull ?: return false
        val y = b.doubleOrNull ?: return false
        return abs(x - y) <= max(1e-9, 1e-12 * max(abs(x), abs(y)))
    }
}
