package com.sonia.etftogo.core.models

import com.sonia.etftogo.core.importing.BackupImport
import kotlinx.serialization.SerializationException
import kotlin.test.Test
import kotlin.test.assertFailsWith

/**
 * The backup screen tells "this file is not a backup" apart from a crash by catching two types only: AppDataError
 * (StoreError and friends) and SerializationException. Bytes that are not UTF-8 must land in one of them.
 */
class BackupDecodeErrorTests {
    private val notUtf8 = byteArrayOf('{'.code.toByte(), 0xFF.toByte(), '}'.code.toByte())

    @Test fun portfolioBackupThatIsNotUtf8() {
        assertFailsWith<SerializationException> { Portfolio.decodeBackup(notUtf8) }
    }

    @Test fun legacyBackupThatIsNotUtf8() {
        assertFailsWith<SerializationException> { BackupImport.decode(notUtf8) }
    }
}
