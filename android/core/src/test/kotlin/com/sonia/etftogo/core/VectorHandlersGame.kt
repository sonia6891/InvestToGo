package com.sonia.etftogo.core

import com.sonia.etftogo.core.game.Achievements
import com.sonia.etftogo.core.game.Dex
import com.sonia.etftogo.core.game.DexFacts
import com.sonia.etftogo.core.game.DexSeries
import com.sonia.etftogo.core.game.GameRules
import com.sonia.etftogo.core.game.GameState
import com.sonia.etftogo.core.game.Habit
import com.sonia.etftogo.core.game.LobbyReplay
import com.sonia.etftogo.core.game.LobbySnapshot
import com.sonia.etftogo.core.game.QuestTrigger
import com.sonia.etftogo.core.game.Quests
import com.sonia.etftogo.core.game.XPEvent
import com.sonia.etftogo.core.game.YearMonth
import com.sonia.etftogo.core.game.achievementsSinceCelebration
import com.sonia.etftogo.core.game.award
import com.sonia.etftogo.core.game.backfillDCA
import com.sonia.etftogo.core.game.celebrate
import com.sonia.etftogo.core.game.coinsSinceCelebration
import com.sonia.etftogo.core.game.collect
import com.sonia.etftogo.core.game.compareFees
import com.sonia.etftogo.core.game.complete
import com.sonia.etftogo.core.game.levelUpDue
import com.sonia.etftogo.core.game.logBuy
import com.sonia.etftogo.core.game.logDividend
import com.sonia.etftogo.core.game.migrate
import com.sonia.etftogo.core.game.reconcile
import com.sonia.etftogo.core.game.recordDCA
import com.sonia.etftogo.core.game.refreshAchievements
import com.sonia.etftogo.core.game.streak
import com.sonia.etftogo.core.game.visitFund
import com.sonia.etftogo.core.models.Fund
import com.sonia.etftogo.core.models.Portfolio
import com.sonia.etftogo.core.support.AppDataError
import com.sonia.etftogo.core.support.CoreJson
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** A saved game object with every set sorted, so Swift's unordered sets compare. */
fun normalizedGameJson(element: JsonElement): JsonElement {
    val game = element.jsonObject.toMutableMap()
    fun sortedStrings(e: JsonElement) = JsonArray(e.jsonArray.sortedBy { it.jsonPrimitive.content })
    for (key in listOf("celebratedAchievements", "rewardKeys")) game[key]?.let { game[key] = sortedStrings(it) }
    game["dcaMonths"]?.let { months ->
        game["dcaMonths"] = JsonArray(months.jsonArray.sortedBy { it.jsonObject.getValue("year").jsonPrimitive.int * 100 + it.jsonObject.getValue("month").jsonPrimitive.int })
    }
    game["questsDone"]?.let { done -> game["questsDone"] = JsonObject(done.jsonObject.mapValues { sortedStrings(it.value) }) }
    return JsonObject(game)
}

private fun normalizedGame(value: GameState): JsonElement = normalizedGameJson(encoded(GameState.serializer(), value))
private fun JsonElement.game(key: String = "state"): GameState = decode(key, GameState.serializer())
private fun JsonElement.portfolio(key: String = "portfolio"): Portfolio = decode(key, Portfolio.serializer())
private fun JsonElement.flag(key: String): Boolean = VectorIO.obj(this)[key]?.jsonPrimitive?.booleanOrNull ?: false
private fun events(list: List<XPEvent>): JsonElement = JsonArray(list.map { encoded(XPEvent.serializer(), it) })
private fun strings(list: List<String>): JsonElement = JsonArray(list.map(::JsonPrimitive))
private fun JsonElement.snapshot(key: String): LobbySnapshot? =
    VectorIO.obj(this)[key]?.let { CoreJson.json.decodeFromJsonElement(LobbySnapshot.serializer(), it) }

private fun lobbyOutput(s: LobbySnapshot): JsonElement = JsonObject(mapOf(
    "xp" to JsonPrimitive(s.xp), "coins" to JsonPrimitive(s.coins), "month" to JsonPrimitive(s.month), "quests" to strings(s.quests.sorted()),
))

private fun replayOutput(r: LobbyReplay?): JsonElement = r?.let {
    JsonObject(mapOf(
        "newQuests" to strings(it.newQuests), "coinsFrom" to JsonPrimitive(it.coinsFrom), "coinsTo" to JsonPrimitive(it.coinsTo),
        "xpFrom" to JsonPrimitive(it.xpFrom), "xpTo" to JsonPrimitive(it.xpTo), "levelFrom" to JsonPrimitive(it.levelFrom),
        "levelTo" to JsonPrimitive(it.levelTo), "crossesLevel" to JsonPrimitive(it.crossesLevel),
    ))
} ?: JsonNull

private val numbers = MapSerializer(String.serializer(), Double.serializer())

private fun JsonElement.dexFacts(): DexFacts {
    val facts = field("facts")
    val o = VectorIO.obj(facts)
    fun map(key: String): Map<String, Double> = o[key]?.let { CoreJson.json.decodeFromJsonElement(numbers, it) } ?: emptyMap()
    val listed = o["listed"]?.let { CoreJson.json.decodeFromJsonElement(MapSerializer(String.serializer(), String.serializer()), it) } ?: emptyMap()
    return DexFacts(map("feeRate"), map("aum"), map("yield"), map("volatility"), listed.mapValues { VectorIO.date(it.value) })
}

private fun xpEvent(raw: String): XPEvent =
    XPEvent.entries.firstOrNull { encoded(XPEvent.serializer(), it).jsonPrimitive.content == raw } ?: throw AppDataError("unknown event")

/** Runs one scripted step on `game`; returns the new state and what the step gave back (Swift `runStep`). */
private fun runStep(step: JsonElement, game: GameState): Pair<GameState, JsonElement> {
    fun same(value: JsonElement) = game to value
    fun stepped(result: Pair<GameState, List<XPEvent>>) = result.first to events(result.second)
    return when (val action = step.str("do")) {
        "recordDCA" -> stepped(game.recordDCA(step.at("on"), VectorIO.obj(step)["now"]?.let { VectorIO.date(it.jsonPrimitive.content) }))
        "logBuy" -> stepped(game.logBuy(step.at("on"), step.at("now")))
        "visitFund" -> game.visitFund(step.str("symbol"), step.at("now")).let { (g, visit) ->
            g to JsonObject(mapOf("new" to JsonPrimitive(visit.new), "cardXP" to JsonPrimitive(visit.cardXP)))
        }
        "collect" -> stepped(game.collect(step.str("symbol"), step.at("now")))
        "logDividend" -> stepped(game.logDividend(step.str("symbol"), step.at("paid"), step.flag("held"), step.at("now")))
        "reconcile" -> stepped(game.reconcile(step.at("now")))
        "compareFees" -> game.compareFees(step.at("now")).let { (g, counted) -> g to JsonPrimitive(counted) }
        "complete" -> {
            val trigger = QuestTrigger.of(step.str("trigger")) ?: throw AppDataError("unknown trigger")
            stepped(game.complete(trigger, step.at("now")))
        }
        "refreshAchievements" -> game.refreshAchievements(step.portfolio(), step.at("now")).let { (g, ids) -> g to strings(ids) }
        "migrate" -> game.migrate(step.portfolio(), step.at("now")) to JsonNull
        "backfillDCA" -> game.backfillDCA(step.portfolio()) to JsonNull
        "award" -> game.award(xpEvent(step.str("event")), step.at("at")) to JsonNull
        "celebrate" -> game.celebrate(step.int("level")) to JsonNull
        "streak" -> same(JsonPrimitive(game.streak(step.at("now"))))
        "levelUpDue" -> same(game.levelUpDue?.let(::JsonPrimitive) ?: JsonNull)
        "coinsSinceCelebration" -> same(JsonPrimitive(game.coinsSinceCelebration))
        "achievementsSinceCelebration" -> same(strings(game.achievementsSinceCelebration))
        "lobby" -> same(lobbyOutput(LobbySnapshot.of(game, step.at("now"))))
        else -> throw AppDataError("unknown step $action")
    }
}

private fun JsonElement.habit(): Habit =
    Habit.entries.firstOrNull { encoded(Habit.serializer(), it).jsonPrimitive.content == str("habit") } ?: throw AppDataError("unknown habit")

val gameHandlers: Map<String, VectorHandler> = mapOf(
    "GameRules.xpToReach" to { input -> JsonPrimitive(GameRules.xpToReach(input.int("level"))) },
    "GameRules.level" to { input -> JsonPrimitive(GameRules.level(input.int("xp"))) },
    "GameRules.progress" to { input ->
        val p = GameRules.progress(input.int("xp"))
        JsonObject(mapOf("into" to JsonPrimitive(p.into), "needed" to JsonPrimitive(p.needed)))
    },
    "GameState.streak" to { input -> JsonPrimitive(input.game().streak(input.at("now"))) },
    "Quests.forMonth" to { input ->
        strings(Quests.forMonth(input.decode("month", YearMonth.serializer()), input.habit(), input.flag("isNewbie")).map { it.id })
    },
    "Achievements.longestDividendRun" to { input -> JsonPrimitive(Achievements.longestDividendRun(input.portfolio())) },
    "Achievements.hasAnniversary" to { input -> JsonPrimitive(Achievements.hasAnniversary(input.portfolio(), input.at("now"))) },
    "Achievements.steady" to { input -> JsonPrimitive(Achievements.steady(input.portfolio(), input.at("now"))) },
    "Achievements.progressAll" to { input ->
        val game = input.game()
        val p = input.portfolio()
        val now = input.at("now")
        JsonObject(Achievements.all.associate { it.id to JsonPrimitive(it.progress(game, p, now)) })
    },
    "Achievements.shown" to { input ->
        JsonArray(Achievements.shown(input.flag("upcoming")).map {
            JsonObject(mapOf("id" to JsonPrimitive(it.id), "title" to JsonPrimitive(it.title), "goal" to JsonPrimitive(it.goal), "comingSoon" to JsonPrimitive(it.comingSoon)))
        })
    },
    "DexSeries.of" to { input -> JsonPrimitive(DexSeries.of(input.decode("fund", Fund.serializer())).rawValue) },
    "Dex.stats" to { input ->
        val s = Dex.stats(input.decode("fund", Fund.serializer()), input.decode("among", ListSerializer(Fund.serializer())), input.dexFacts())
        JsonObject(mapOf(
            "fee" to JsonPrimitive(s.fee), "size" to JsonPrimitive(s.size), "yield" to JsonPrimitive(s.yield),
            "volatility" to JsonPrimitive(s.volatility), "history" to JsonPrimitive(s.history),
        ))
    },
    "LobbyReplay.between" to { input ->
        val now = input.snapshot("now") ?: throw AppDataError("no now")
        replayOutput(LobbyReplay.between(input.snapshot("shown"), now, input.decode("questOrder", ListSerializer(String.serializer()))))
    },
    "LobbyReplay.arrival" to { input ->
        val now = input.snapshot("now") ?: throw AppDataError("no now")
        val due = VectorIO.obj(input)["levelUpDue"]?.jsonPrimitive?.intOrNull
        replayOutput(LobbyReplay.arrival(input.snapshot("shown"), now, input.decode("questOrder", ListSerializer(String.serializer())), due, input.int("celebratedLevel")))
    },
    "LobbySnapshot.of" to { input -> lobbyOutput(LobbySnapshot.of(input.game(), input.at("now"))) },
    "GameState.script" to { input ->
        var game = input.game()
        val steps = VectorIO.obj(input)["steps"] as? JsonArray ?: throw AppDataError("no steps")
        val results = steps.map { step -> runStep(step, game).let { (next, out) -> game = next; out } }
        JsonObject(mapOf("steps" to JsonArray(results), "state" to normalizedGame(game)))
    },
)
