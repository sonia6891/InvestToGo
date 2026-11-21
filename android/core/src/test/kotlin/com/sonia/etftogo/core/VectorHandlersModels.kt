package com.sonia.etftogo.core

import com.sonia.etftogo.core.game.YearMonth
import com.sonia.etftogo.core.importing.BackupImport
import com.sonia.etftogo.core.importing.LegacyPlan
import com.sonia.etftogo.core.models.AlertEngine
import com.sonia.etftogo.core.models.ComboMath
import com.sonia.etftogo.core.models.ComboScenario
import com.sonia.etftogo.core.models.ComboSettings
import com.sonia.etftogo.core.models.ComponentSnapshot
import com.sonia.etftogo.core.models.FeeRecord
import com.sonia.etftogo.core.models.GoalPlanner
import com.sonia.etftogo.core.models.PerformanceStats
import com.sonia.etftogo.core.models.PlanMath
import com.sonia.etftogo.core.models.Portfolio
import com.sonia.etftogo.core.models.PriceAlert
import com.sonia.etftogo.core.models.PriceHistory
import com.sonia.etftogo.core.models.ResearchMath
import com.sonia.etftogo.core.support.CoreJson
import com.sonia.etftogo.core.support.uuidString
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** A portfolio as vector output: encoded the way the app saves it, with every set sorted (same as the Swift side). */
fun normalizedPortfolio(value: Portfolio): JsonElement {
    val root = CoreJson.json.parseToJsonElement(value.encode().decodeToString()).jsonObject.toMutableMap()
    fun sortedStrings(element: JsonElement) = JsonArray(element.jsonArray.sortedBy { it.jsonPrimitive.content })
    root["favorites"]?.let { root["favorites"] = sortedStrings(it) }
    root["game"]?.let { root["game"] = normalizedGameJson(it) }
    return JsonObject(root)
}

fun JsonElement.bytes(): ByteArray = if ("file" in VectorIO.obj(this)) VectorIO.file(this) else str("text").toByteArray()
fun JsonElement.int(key: String): Int = VectorIO.obj(this)[key]?.jsonPrimitive?.int ?: error("vector input has no $key")
fun JsonElement.field(key: String): JsonElement = VectorIO.obj(this)[key] ?: error("vector input has no $key")
fun <T> JsonElement.decode(key: String, serializer: KSerializer<T>): T = CoreJson.json.decodeFromJsonElement(serializer, field(key))
fun <T> encoded(serializer: KSerializer<T>, value: T): JsonElement = CoreJson.json.encodeToJsonElement(serializer, value)
fun num(value: Double?): JsonElement = value?.let(::JsonPrimitive) ?: JsonNull

private fun part(p: ComboMath.Part) = buildJsonObject {
    put("start", p.start); put("invested", p.invested); put("value", p.value); put("cash", p.cash); put("end", p.end)
}

val modelHandlers: Map<String, VectorHandler> = mapOf(
    "Portfolio.decodeBackup" to { input ->
        val limit = VectorIO.obj(input)["limit"]?.jsonPrimitive?.int ?: 5_000_000
        normalizedPortfolio(Portfolio.decodeBackup(input.bytes(), limit))
    },
    "BackupImport.decode" to { input -> normalizedPortfolio(BackupImport.decode(input.bytes())) },
    "GoalPlanner.monthlyContribution" to { input ->
        JsonPrimitive(GoalPlanner.monthlyContribution(input.num("target"), input.int("years"), input.num("current"), input.num("annualReturn")))
    },
    "GoalPlanner.scenarios" to { input ->
        buildJsonArray {
            for (s in GoalPlanner.scenarios(input.num("target"), input.int("years"), input.num("current"), input.num("annualReturn"))) {
                add(buildJsonObject { put("scenario", s.scenario.rawValue); put("annualReturn", s.annualReturn); put("monthly", s.monthly) })
            }
        }
    },
    "ComboMath.project" to { input ->
        val settings = input.decode("settings", ComboSettings.serializer())
        val scenario = ComboScenario.of(input.str("scenario")) ?: error("unknown scenario")
        val result = ComboMath.project(input.num("stockStart"), input.num("etfStart"), settings, input.num("stockShare"), input.int("years"), scenario)
        buildJsonObject { put("stock", part(result.stock)); put("etf", part(result.etf)); put("invested", result.invested); put("end", result.end) }
    },
    "PlanMath.project" to { input ->
        buildJsonArray {
            for (row in PlanMath.project(input.decode("plan", LegacyPlan.serializer()))) {
                add(buildJsonObject {
                    put("year", row.year); put("invested", row.invested); put("cash", row.cash); put("contributed", row.contributed)
                    put("dividends", row.dividends); put("total", row.total)
                })
            }
        }
    },
    "AlertEngine.due" to { input ->
        val alerts = input.decode("alerts", ListSerializer(PriceAlert.serializer()))
        val prices = input.decode("prices", MapSerializer(String.serializer(), Double.serializer()))
        val member = VectorIO.obj(input)["isMember"]?.jsonPrimitive?.boolean ?: false
        JsonArray(AlertEngine.due(alerts, prices, member).map { JsonPrimitive(it.uuidString) })
    },
    "AlertEngine.isCurrent" to { input -> JsonPrimitive(AlertEngine.isCurrent(input.str("day"), input.at("now"))) },
    "ResearchMath.exposures" to { input ->
        val portfolio = input.decode("portfolio", Portfolio.serializer())
        val stocks = input.decode("stocks", ListSerializer(String.serializer())).toSet()
        buildJsonArray {
            for (row in ResearchMath.exposures(portfolio, stocks)) {
                add(buildJsonObject {
                    put("symbol", row.symbol); put("name", row.name); put("value", row.value)
                    put("funds", JsonArray(row.funds.sorted().map(::JsonPrimitive)))
                })
            }
        }
    },
    "ResearchMath.overlap" to { input ->
        buildJsonArray {
            for (row in ResearchMath.overlap(input.decode("left", ComponentSnapshot.serializer()), input.decode("right", ComponentSnapshot.serializer()))) {
                add(buildJsonObject { put("symbol", row.symbol); put("name", row.name); put("left", row.left); put("right", row.right) })
            }
        }
    },
    "ComponentSnapshot.imported" to { input ->
        encoded(ComponentSnapshot.serializer(), ComponentSnapshot.imported(input.str("text").toByteArray(), input.str("symbol")))
    },
    "PriceHistory.validate" to { input -> input.decode("history", PriceHistory.serializer()).validate(); JsonPrimitive(true) },
    "PerformanceStats.init" to { input ->
        val stats = PerformanceStats(input.decode("history", PriceHistory.serializer()))
        buildJsonObject { put("change", stats.change); put("annualized", num(stats.annualized)); put("drawdown", stats.drawdown); put("volatility", num(stats.volatility)) }
    },
    "FeeRecord.validate" to { input -> input.decode("fee", FeeRecord.serializer()).validate(); JsonPrimitive(true) },
    "YearMonth.init" to { input ->
        val month = YearMonth.of(input.at())
        buildJsonObject { put("year", month.year); put("month", month.month); put("key", month.key) }
    },
    "YearMonth.fromKey" to { input ->
        YearMonth.fromKey(input.str("key"))?.let { buildJsonObject { put("year", it.year); put("month", it.month) } } ?: JsonNull
    },
)
