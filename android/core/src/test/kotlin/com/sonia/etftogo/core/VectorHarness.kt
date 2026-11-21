package com.sonia.etftogo.core

import com.sonia.etftogo.core.support.AppDataError
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.time.Instant
import java.time.OffsetDateTime

/** A case's `input` in, its output out. Throwing `AppDataError` yields `{"error": text}`; any other throw `{"error": "*"}`. */
typealias VectorHandler = (JsonElement) -> JsonElement

/** One vector file: its kind, the platforms it runs on, and its cases. */
data class VectorFile(val file: File, val kind: String, val platforms: List<String>?, val cases: List<JsonObject>) {
    val runsOnKotlin: Boolean get() = platforms == null || "kotlin" in platforms
}

object VectorHarness {
    private val lenient = Json { isLenient = false }

    /** Every JSON file under vectors/ whose top level has a `kind`. */
    fun files(): List<VectorFile> = Fixtures.root.resolve("vectors").walkTopDown()
        .filter { it.isFile && it.extension == "json" }
        .mapNotNull { file ->
            val body = lenient.parseToJsonElement(file.readText()) as? JsonObject ?: return@mapNotNull null
            val kind = (body["kind"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return@mapNotNull null
            VectorFile(
                file = file,
                kind = kind,
                platforms = body["platforms"]?.jsonArray?.map { it.jsonPrimitive.content },
                cases = body["cases"]?.jsonArray?.map { it.jsonObject } ?: emptyList(),
            )
        }
        .sortedBy { it.file.path }
        .toList()

    fun output(handler: VectorHandler, input: JsonElement): JsonElement = try {
        handler(input)
    } catch (error: AppDataError) {
        JsonObject(mapOf("error" to JsonPrimitive(error.text)))
    } catch (error: Exception) {
        JsonObject(mapOf("error" to JsonPrimitive("*")))
    }
}

/** Helpers for handlers: reading inputs. */
object VectorIO {
    fun obj(input: JsonElement): JsonObject = input as? JsonObject ?: throw AppDataError("vector input is not an object")
    fun date(text: String): Instant = OffsetDateTime.parse(text).toInstant()

    /** The bytes of a `{"file": path}` input, relative to SharedFixtures. */
    fun file(input: JsonElement): ByteArray =
        Fixtures.bytes(obj(input)["file"]?.jsonPrimitive?.content ?: throw AppDataError("vector input has no file"))

    val nothing: JsonElement = JsonNull
}
