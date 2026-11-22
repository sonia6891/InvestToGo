package com.sonia.etftogo.core.support

import java.security.MessageDigest

/** Port of PocketCore `SHA256Digest`. */
object SHA256Digest {
    fun hash(data: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(data)
}
