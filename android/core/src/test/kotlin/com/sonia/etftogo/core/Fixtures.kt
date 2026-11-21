package com.sonia.etftogo.core

import java.io.File

/** Loads files from the repository's SharedFixtures directory, shared with the iPhone's PocketCore tests. */
object Fixtures {
    val root: File by lazy {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null) {
            val candidate = File(dir, "SharedFixtures")
            if (candidate.isDirectory) return@lazy candidate
            dir = dir.parentFile
        }
        error("SharedFixtures directory not found above ${System.getProperty("user.dir")}")
    }

    fun bytes(path: String): ByteArray = File(root, path).readBytes()
    fun text(path: String): String = bytes(path).decodeToString()
}
