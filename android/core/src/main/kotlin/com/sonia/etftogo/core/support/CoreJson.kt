package com.sonia.etftogo.core.support

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.SerialKind
import kotlinx.serialization.descriptors.StructureKind
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import java.time.Instant
import java.util.UUID

/**
 * The JSON settings every backup and cache uses, matching what iPhone's `JSONEncoder` writes and `JSONDecoder` accepts:
 * unknown keys are skipped, absent optionals stay absent, and a wrong type or an unknown enum value is an error (no
 * coercion), as in Swift's synthesized decoding. Keys Swift requires carry `@Required` even when they have a default.
 */
object CoreJson {
    val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
    }

    /**
     * Decodes as iPhone's `JSONDecoder` would: kotlinx reads `"10"` as the number 10 and `"true"` as a boolean, Swift
     * refuses both, so the JSON is checked against the type's shape first ([StrictShape]).
     */
    fun <T> decode(serializer: KSerializer<T>, text: String): T = decode(serializer, json.parseToJsonElement(text))

    fun <T> decode(serializer: KSerializer<T>, element: JsonElement): T {
        StrictShape.check(element, serializer.descriptor, "$")
        return json.decodeFromJsonElement(serializer, element)
    }

    fun <T> decode(serializer: KSerializer<T>, bytes: ByteArray): T = decode(serializer, bytes.decodeToString(throwOnInvalidSequence = true))
}

/**
 * Swift's synthesized `Decodable` never converts between JSON types. Walks the JSON against a serial descriptor and
 * refuses a string where a number or boolean belongs, and a number or boolean where a string belongs. Fields Swift reads
 * with `try?` (an unknown value becomes nil) are named in [lenient] and not checked.
 */
object StrictShape {
    private val lenient = setOf("com.sonia.etftogo.core.game.GameState.lastAward", "com.sonia.etftogo.core.models.ComboSettings.scenario")

    fun check(element: JsonElement, descriptor: SerialDescriptor, path: String) {
        if (element is JsonNull) return
        when (val kind = descriptor.kind) {
            is PrimitiveKind -> {
                val primitive = element as? JsonPrimitive ?: fail(path)
                when (kind) {
                    PrimitiveKind.STRING, PrimitiveKind.CHAR -> if (!primitive.isString) fail(path)
                    PrimitiveKind.BOOLEAN -> if (primitive.isString || primitive.booleanOrNull == null) fail(path)
                    else -> if (primitive.isString) fail(path)
                }
            }
            SerialKind.ENUM -> if ((element as? JsonPrimitive)?.isString != true) fail(path)
            StructureKind.LIST -> {
                val array = element as? JsonArray ?: return
                val item = descriptor.getElementDescriptor(0)
                array.forEachIndexed { i, child -> check(child, item, "$path[$i]") }
            }
            StructureKind.MAP -> {
                val obj = element as? JsonObject ?: return
                val value = descriptor.getElementDescriptor(1)
                obj.forEach { (key, child) -> check(child, value, "$path.$key") }
            }
            StructureKind.CLASS, StructureKind.OBJECT -> {
                val obj = element as? JsonObject ?: return
                for (i in 0 until descriptor.elementsCount) {
                    val name = descriptor.getElementName(i)
                    if ("${descriptor.serialName.removeSuffix("?")}.$name" in lenient) continue
                    obj[name]?.let { check(it, descriptor.getElementDescriptor(i), "$path.$name") }
                }
            }
            else -> Unit
        }
    }

    private fun fail(path: String): Nothing = throw SerializationException("wrong JSON type at $path")
}

/** Seconds between 1970-01-01Z and 2001-01-01Z, Swift's `Date` reference. */
const val SWIFT_EPOCH_OFFSET = 978_307_200L

/** Swift `JSONEncoder`'s default date: a Double of seconds since 2001-01-01Z. */
object SwiftDateSerializer : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("SwiftDate", PrimitiveKind.DOUBLE)
    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeDouble(value.toSwiftSeconds())
    override fun deserialize(decoder: Decoder): Instant = swiftInstant(decoder.decodeDouble())
}

fun Instant.toSwiftSeconds(): Double = (epochSecond - SWIFT_EPOCH_OFFSET) + nano / 1e9

fun swiftInstant(seconds: Double): Instant {
    val whole = Math.floor(seconds)
    val nanos = Math.round((seconds - whole) * 1e9)
    return Instant.ofEpochSecond(whole.toLong() + SWIFT_EPOCH_OFFSET, nanos)
}

/** Seconds since 1970 as Swift's `timeIntervalSince1970` gives them. */
fun Instant.epochSeconds(): Double = epochSecond + nano / 1e9

/** Swift's `UUID` encodes as its uppercase `uuidString`; any case is read. */
object UppercaseUUIDSerializer : KSerializer<UUID> {
    override val descriptor = PrimitiveSerialDescriptor("SwiftUUID", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: UUID) = encoder.encodeString(value.uuidString)
    override fun deserialize(decoder: Decoder): UUID {
        val text = decoder.decodeString()
        return parseUUID(text) ?: throw SerializationException("not a UUID: $text")
    }
}

/** A date field as Swift's `JSONEncoder` writes it. */
typealias SwiftDate = @Serializable(with = SwiftDateSerializer::class) Instant

/** A UUID field as Swift writes it (uppercase) and reads it (strict 8-4-4-4-12). */
typealias SwiftUUID = @Serializable(with = UppercaseUUIDSerializer::class) UUID
