@file:OptIn(ExperimentalSerializationApi::class)

package com.sonia.etftogo.core.game

import com.sonia.etftogo.core.support.CoreJson
import java.util.Locale
import com.sonia.etftogo.core.support.SwiftDate
import com.sonia.etftogo.core.support.TAIPEI
import com.sonia.etftogo.core.support.swiftInstant
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.KeepGeneratedSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.SetSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import java.time.ZoneId

/** A calendar month in Taipei time; the unit the DCA streak counts in. JSON is `{"year":2026,"month":11}`, as on iPhone. */
@Serializable
data class YearMonth(val year: Int, val month: Int) : Comparable<YearMonth> {
    fun next(): YearMonth = if (month == 12) YearMonth(year + 1, 1) else YearMonth(year, month + 1)
    fun previous(): YearMonth = if (month == 1) YearMonth(year - 1, 12) else YearMonth(year, month - 1)

    /** "2026-11", the key used by `GameState.questsDone`. */
    val key: String get() = "%04d-%02d".format(Locale.ROOT, year, month)

    override fun compareTo(other: YearMonth): Int = compareValuesBy(this, other, { it.year }, { it.month })

    companion object {
        /** The Taipei month of `at` (or of `zone`, for callers that pass one). */
        fun of(at: Instant, zone: ZoneId = TAIPEI): YearMonth = at.atZone(zone).let { YearMonth(it.year, it.monthValue) }

        /** Reads a `key` back; null for anything else. */
        fun fromKey(key: String): YearMonth? {
            val parts = key.split("-")
            if (parts.size != 2 || parts[0].length != 4 || parts[1].length != 2) return null
            if (!key.all { it == '-' || it in '0'..'9' }) return null
            val year = parts[0].toIntOrNull() ?: return null
            val month = parts[1].toIntOrNull() ?: return null
            return if (month in 1..12) YearMonth(year, month) else null
        }
    }
}

@Serializable
enum class Habit {
    @SerialName("dca") DCA,
    @SerialName("dividends") DIVIDENDS,
    @SerialName("savingGoal") SAVING_GOAL,
}

@Serializable
enum class XPEvent {
    @SerialName("monthlyDCA") MONTHLY_DCA,
    @SerialName("questDone") QUEST_DONE,
    @SerialName("firstDexCard") FIRST_DEX_CARD,
    @SerialName("dividendLogged") DIVIDEND_LOGGED,
    @SerialName("reconciled") RECONCILED;

    /** The counter `award` increments. */
    val counterKey: CounterKey get() = when (this) {
        MONTHLY_DCA -> CounterKey.MONTHLY_DCA
        QUEST_DONE -> CounterKey.QUEST_DONE
        FIRST_DEX_CARD -> CounterKey.FIRST_DEX_CARD
        DIVIDEND_LOGGED -> CounterKey.DIVIDEND_LOGGED
        RECONCILED -> CounterKey.RECONCILED
    }
}

/** Keys of `GameState.counts`; shared by `award`, later feature code and the achievements. */
enum class CounterKey(val rawValue: String) {
    MONTHLY_DCA("monthlyDCA"), QUEST_DONE("questDone"), FIRST_DEX_CARD("firstDexCard"), DIVIDEND_LOGGED("dividendLogged"), RECONCILED("reconciled"),
    FEE_COMPARED("feeCompared"), CHECKUP("checkup"), EX_DIVIDEND_SEASON("exDividendSeason"), YEAR_REPORT("yearReport"),
}

object GameRules {
    /** Months are always counted in Taipei time so a debit near midnight lands in the month the user sees. */
    val taipei: ZoneId = TAIPEI
    val xp: Map<XPEvent, Int> = mapOf(XPEvent.MONTHLY_DCA to 100, XPEvent.QUEST_DONE to 40, XPEvent.FIRST_DEX_CARD to 30, XPEvent.DIVIDEND_LOGGED to 20, XPEvent.RECONCILED to 20)
    /** New dex cards that earn experience in one Taipei calendar month; later ones are collected for nothing (R34). */
    const val dexXPPerMonth = 3
    /** 記一筆配息 experience paid at most this many times in one Taipei month. */
    const val dividendXPPerMonth = 3

    /** Experience at which `level` starts: front-loaded 100, 250, 450, 700, then 300 per level. */
    fun xpToReach(level: Int): Int = when {
        level <= 1 -> 0
        level == 2 -> 100
        level == 3 -> 250
        level == 4 -> 450
        else -> 700 + (level - 5) * 300
    }

    /** Starts at 1, no cap. */
    fun level(xp: Int): Int {
        val x = maxOf(0, xp)
        return when {
            x >= 700 -> 5 + (x - 700) / 300
            x >= 450 -> 4
            x >= 250 -> 3
            x >= 100 -> 2
            else -> 1
        }
    }

    data class Progress(val into: Int, val needed: Int)

    fun progress(xp: Int): Progress {
        val x = maxOf(0, xp)
        val level = level(x)
        val start = xpToReach(level)
        return Progress(x - start, xpToReach(level + 1) - start)
    }
}

/** Everything the game layer remembers; lives in `Portfolio.game` (null in files written before it existed). */
@Serializable(with = GameStateSerializer::class)
@KeepGeneratedSerializer
data class GameState(
    val xp: Int = 0,
    val coins: Int = 0,
    val dcaMonths: Set<YearMonth> = emptySet(),
    val longestStreak: Int = 0,
    /** Dex card id -> when it was collected. */
    val collected: Map<String, SwiftDate> = emptyMap(),
    /** Achievement id -> when it was unlocked. */
    val unlocked: Map<String, SwiftDate> = emptyMap(),
    /** "2026-11" -> ids of that month's finished quests. */
    val questsDone: Map<String, Set<String>> = emptyMap(),
    /** The habit picked in onboarding; null until then (callers use `habit ?: Habit.DCA`). */
    val habit: Habit? = null,
    /** Event counters for achievements whose data source has no record of its own. */
    val counts: Map<String, Int> = emptyMap(),
    /** The highest level whose LEVEL×UP has been shown. Saved, so each level is celebrated once. */
    val celebratedLevel: Int = 1,
    /** The experience event that came last; the LEVEL×UP screen names it as the reason. */
    val lastAward: XPEvent? = null,
    /** Coins held when the last LEVEL×UP was accepted. */
    val celebratedCoins: Int = 0,
    /** Achievements already shown, or held, at the last LEVEL×UP. */
    val celebratedAchievements: Set<String> = emptySet(),
    /** Rewards already paid, by key, so repeating an action earns nothing (ruling R34). */
    val rewardKeys: Set<String> = emptySet(),
    /** Experience earned in each Taipei month, "2026-11" -> points, from the day this was first recorded. */
    val xpByMonth: Map<String, Int> = emptyMap(),
    /** The one-time migrations already run on this progress; 0 in saves made before them. */
    val migration: Int = 0,
    /** When the migrations first ran on this phone. */
    val migratedAt: SwiftDate? = null,
) {
    fun counter(key: CounterKey): Int = counts[key.rawValue] ?: 0
    fun count(key: CounterKey): GameState = copy(counts = counts + (key.rawValue to counter(key) + 1))

    /** A newbie is someone who has not started a DCA yet. */
    val isNewbie: Boolean get() = dcaMonths.isEmpty()

    /** Nothing has been earned yet: no experience, no 定期定額 month, no card collected, no reward paid. */
    val isFresh: Boolean get() = xp == 0 && dcaMonths.isEmpty() && collected.isEmpty() && rewardKeys.isEmpty()

    /** A backup's progress as it is taken over: totals never negative, months never more than the total. */
    fun checkedForAdoption(): GameState {
        var game = copy(xp = maxOf(0, xp), coins = maxOf(0, coins))
        val months = game.xpByMonth.values
        if (months.any { it < 0 } || months.fold(0.0) { a, b -> a + b } > game.xp.toDouble()) game = game.copy(xpByMonth = emptyMap())
        return game
    }

    data class Adoption(val game: GameState?, val skipped: Boolean)

    companion object {
        /**
         * The progress to keep when a backup is imported, and whether the backup's was left out. A fresh game (or none)
         * takes the backup's whole; a game that already has progress stays exactly as it is. The two are never merged.
         */
        fun afterImport(local: GameState?, incoming: GameState?): Adoption {
            if (incoming == null) return Adoption(local, false)
            if (local == null || local.isFresh) return Adoption(incoming.checkedForAdoption(), false)
            return Adoption(local, incoming != local && !incoming.isFresh)
        }
    }
}

/**
 * Every field falls back to its default so progress saved by an older build never fails to decode; an event a later
 * build added reads as unknown. Encoding is the plain one.
 */
object GameStateSerializer : KSerializer<GameState> {
    private val plain = GameState.generatedSerializer()
    override val descriptor: SerialDescriptor = plain.descriptor
    override fun serialize(encoder: Encoder, value: GameState) = plain.serialize(encoder, value)

    override fun deserialize(decoder: Decoder): GameState {
        val obj = (decoder as JsonDecoder).decodeJsonElement() as? JsonObject ?: throw SerializationException("game is not an object")
        fun <T> field(key: String, serializer: KSerializer<T>): T? {
            val element = obj[key] ?: return null
            if (element is JsonNull) return null
            return CoreJson.decode(serializer, element)
        }
        val dates = MapSerializer(String.serializer(), Double.serializer())
        val strings = SetSerializer(String.serializer())
        val xp = field("xp", Int.serializer()) ?: 0
        val coins = field("coins", Int.serializer()) ?: 0
        val unlocked = field("unlocked", dates)?.mapValues { swiftInstant(it.value) } ?: emptyMap()
        return GameState(
            xp = xp,
            coins = coins,
            dcaMonths = field("dcaMonths", SetSerializer(YearMonth.serializer())) ?: emptySet(),
            longestStreak = field("longestStreak", Int.serializer()) ?: 0,
            collected = field("collected", dates)?.mapValues { swiftInstant(it.value) } ?: emptyMap(),
            unlocked = unlocked,
            questsDone = field("questsDone", MapSerializer(String.serializer(), strings)) ?: emptyMap(),
            habit = field("habit", Habit.serializer()),
            counts = field("counts", MapSerializer(String.serializer(), Int.serializer())) ?: emptyMap(),
            // Progress saved before celebrations were recorded: the levels already held are not new.
            celebratedLevel = field("celebratedLevel", Int.serializer()) ?: GameRules.level(xp),
            lastAward = try { field("lastAward", XPEvent.serializer()) } catch (_: Exception) { null },
            celebratedCoins = field("celebratedCoins", Int.serializer()) ?: coins,
            celebratedAchievements = field("celebratedAchievements", strings) ?: unlocked.keys,
            rewardKeys = field("rewardKeys", strings) ?: emptySet(),
            xpByMonth = field("xpByMonth", MapSerializer(String.serializer(), Int.serializer())) ?: emptyMap(),
            migration = field("migration", Int.serializer()) ?: 0,
            migratedAt = field("migratedAt", Double.serializer())?.let(::swiftInstant),
        )
    }
}
