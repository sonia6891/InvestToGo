package com.sonia.etftogo.core.support

/** The small settings store PocketCore reads through `UserDefaults`; the app backs it with SharedPreferences. */
interface KeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String)
    fun remove(key: String)
    fun getBool(key: String): Boolean = getString(key) == "true"
    fun putBool(key: String, value: Boolean) = putString(key, value.toString())
    fun getDouble(key: String): Double? = getString(key)?.toDoubleOrNull()
    fun putDouble(key: String, value: Double) = putString(key, value.toString())
}

/** In-memory store for tests and previews. */
class MemoryKeyValueStore : KeyValueStore {
    private val values = mutableMapOf<String, String>()
    override fun getString(key: String): String? = synchronized(values) { values[key] }
    override fun putString(key: String, value: String) { synchronized(values) { values[key] = value } }
    override fun remove(key: String) { synchronized(values) { values.remove(key) } }
}
