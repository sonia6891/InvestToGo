package com.sonia.etftogo.core.support

import java.nio.ByteBuffer
import java.util.UUID

/** Port of PocketCore `StableID`: a name-based UUID identical to iPhone's, so imported records keep their IDs. */
object StableID {
    fun make(namespace: String, value: String): UUID {
        val bytes = SHA256Digest.hash((namespace + "\u0000" + value).toByteArray(Charsets.UTF_8)).copyOf(16)
        bytes[6] = ((bytes[6].toInt() and 0x0f) or 0x50).toByte()
        bytes[8] = ((bytes[8].toInt() and 0x3f) or 0x80).toByte()
        val buffer = ByteBuffer.wrap(bytes)
        return UUID(buffer.long, buffer.long)
    }
}

/** Swift's `UUID.uuidString`: uppercase. */
val UUID.uuidString: String get() = toString().uppercase()
