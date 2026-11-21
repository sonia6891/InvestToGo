package com.sonia.etftogo.core.support

/** The JSON files PocketCore bundles (catalog, annual fees, official dividends, skins), read from the classpath. */
object CoreResources {
    fun read(name: String): ByteArray =
        CoreResources::class.java.classLoader.getResourceAsStream(name)?.use { it.readBytes() }
            ?: throw AppDataError("找不到內建資料 $name")
}
