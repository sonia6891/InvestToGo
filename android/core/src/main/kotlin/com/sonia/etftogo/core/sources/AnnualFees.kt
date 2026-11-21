@file:OptIn(ExperimentalSerializationApi::class)

package com.sonia.etftogo.core.sources

import com.sonia.etftogo.core.support.AppDataError
import com.sonia.etftogo.core.support.CoreJson
import com.sonia.etftogo.core.support.CoreResources
import com.sonia.etftogo.core.support.DataChecks
import com.sonia.etftogo.core.support.nfc
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KeepGeneratedSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonTransformingSerializer
import java.time.ZonedDateTime

@Serializable(with = AnnualExpenseSerializer::class)
@KeepGeneratedSerializer
data class AnnualExpense(
    val symbol: String,
    val fundID: String,
    val fundName: String,
    val year: Int,
    val commission: Double,
    val tax: Double,
    val subscriptionOffset: Double,
    val management: Double,
    val custody: Double,
    val guarantee: Double,
    val other: Double,
    val total: Double,
) {
    fun validate() {
        // Calendar.current: the year on the device.
        val ok = DataChecks.code(symbol) && fundIDPattern.matches(fundID) && fundName.isNotEmpty() && year >= 1990 && year < ZonedDateTime.now().year &&
            listOf(commission, tax, subscriptionOffset, management, custody, guarantee, other, total).all { it.isFinite() && it in 0.0..100.0 }
        if (!ok) throw AppDataError("年度費用資料格式不正確。")
    }
}

private val fundIDPattern = Regex("^[0-9]{8}$")

/** The fund name in NFC (see `FundSerializer`): SITCA writes 金 and 益 as compatibility ideographs. */
object AnnualExpenseSerializer : JsonTransformingSerializer<AnnualExpense>(AnnualExpense.generatedSerializer()) {
    override fun transformDeserialize(element: JsonElement): JsonElement {
        val obj = element as? JsonObject ?: return element
        val name = (obj["fundName"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return element
        return JsonObject(obj + ("fundName" to JsonPrimitive(name.nfc)))
    }
}

@Serializable
data class AnnualFeeCatalog(val fetchedDay: String, val sourceURL: String, val records: Map<String, AnnualExpense>) {
    companion object {
        const val SOURCE_URL = "https://www.sitca.org.tw/ROC/Industry/IN2211.aspx?pid=IN2222_01"

        val bundled: AnnualFeeCatalog? by lazy {
            val result = try { CoreJson.decode(serializer(), CoreResources.read("annual-fees.json")) } catch (_: Exception) { return@lazy null }
            val ok = DataChecks.date(result.fetchedDay) != null && result.sourceURL == SOURCE_URL &&
                result.records.all { (key, value) -> key == value.symbol && runCatching { value.validate() }.isSuccess }
            if (ok) result else null
        }
    }
}
