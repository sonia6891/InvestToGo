package com.sonia.etftogo.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.fail

/** Runs every shared vector against :core; the Swift side is PocketCore's VectorTests. */
class VectorTests {
    @Test fun allVectors() = runAll()

    /**
     * A phone set to Arabic, Persian, Marathi or Burmese formats numbers with its own digits; every key, day and request
     * address must still be written in ASCII digits, as iPhone writes them, or months and rewards stop matching.
     */
    @Test fun allVectorsUnderNonAsciiDigitLocales() {
        val saved = java.util.Locale.getDefault()
        try {
            for (tag in listOf("ar-EG", "fa-IR", "mr-IN", "my-MM")) {
                java.util.Locale.setDefault(java.util.Locale.forLanguageTag(tag))
                runAll(tag)
            }
        } finally {
            java.util.Locale.setDefault(saved)
        }
    }

    private fun runAll(locale: String? = null) {
        val failures = mutableListOf<String>()
        for (vector in VectorHarness.files().filter { it.runsOnKotlin }) {
            val handler = vectorHandlers[vector.kind] ?: continue
            vector.cases.forEachIndexed { index, case ->
                val name = (case["name"] as? kotlinx.serialization.json.JsonPrimitive)?.content ?: "#$index"
                val expected = case["expected"]
                if (expected == null) {
                    failures += "${vector.kind} / $name: no expected value; record it"
                    return@forEachIndexed
                }
                val actual = VectorHarness.output(handler, case["input"] ?: JsonNull)
                if (!JsonCompare.equal(expected, actual)) failures += "${vector.kind} / $name: expected $expected, got $actual"
            }
        }
        if (failures.isNotEmpty()) fail((if (locale != null) "[$locale] " else "") + failures.take(20).joinToString("\n"))
    }

    @Test fun everyKindHasKotlinHandler() {
        val missing = VectorHarness.files().filter { it.runsOnKotlin }.map { it.kind }.filter { it !in vectorHandlers }
        assertTrue(missing.isEmpty(), "No Kotlin handler for: ${missing.joinToString()}")
    }

    @Test fun noOrphanKotlinHandler() {
        val kinds = VectorHarness.files().map { it.kind }.toSet()
        val orphans = vectorHandlers.keys.filter { it !in kinds }.sorted()
        assertTrue(orphans.isEmpty(), "Handlers without a vector file: ${orphans.joinToString()}")
    }

    @Test fun jsonCompareRules() {
        fun j(text: String) = Json.parseToJsonElement(text)
        assertTrue(JsonCompare.equal(j("1.0"), j("1")))
        assertTrue(JsonCompare.equal(j("${0.1 + 0.2}"), j("0.3")))
        assertFalse(JsonCompare.equal(j("[1,2]"), j("[2,1]")))
        assertFalse(JsonCompare.equal(j("""{"a":1}"""), j("""{"a":1,"b":2}""")))
        assertFalse(JsonCompare.equal(j("true"), j("1")))
        assertFalse(JsonCompare.equal(j("\"1\""), j("1")))
    }
}
