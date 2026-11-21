package com.sonia.etftogo.core.support

import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.time.Instant
import java.util.UUID

/** The JSON settings every backup and cache uses, matching what iPhone's `JSONEncoder` writes and `JSONDecoder` accepts. */
object CoreJson {
    val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
        coerceInputValues = true
    }
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
    override fun deserialize(decoder: Decoder): UUID = UUID.fromString(decoder.decodeString())
}
