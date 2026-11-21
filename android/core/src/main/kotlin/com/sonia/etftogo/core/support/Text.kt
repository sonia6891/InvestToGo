package com.sonia.etftogo.core.support

import java.text.BreakIterator
import java.text.Normalizer
import java.util.UUID

/** Unicode NFC, Swift's `precomposedStringWithCanonicalMapping`: compatibility ideographs become the unified characters. */
val String.nfc: String get() = Normalizer.normalize(this, Normalizer.Form.NFC)

/** Swift's `String.count`: user-perceived characters, not UTF-16 units, so length limits match iPhone's. */
val String.charCount: Int get() {
    if (all { it.code < 0x300 }) return length
    val iterator = BreakIterator.getCharacterInstance().also { it.setText(this) }
    var count = 0
    while (iterator.next() != BreakIterator.DONE) count++
    return count
}

private val uuidPattern = Regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")

/** Swift's `UUID(uuidString:)`: only the 8-4-4-4-12 hex form, in either case; null for anything else. */
fun parseUUID(text: String): UUID? = if (uuidPattern.matches(text)) UUID.fromString(text) else null
