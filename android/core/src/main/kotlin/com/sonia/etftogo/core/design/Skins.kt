package com.sonia.etftogo.core.design

import com.sonia.etftogo.core.support.CoreJson
import com.sonia.etftogo.core.support.CoreResources
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlin.math.pow

// Port of PocketCore Design/Skins.swift: the four 外觀主題 read from the shared skins.json.

/** A skins.json entry that does not read: the bundled file is broken, which iPhone treats as fatal. */
class SkinFileError(message: String) : IllegalStateException(message)

/** A 0xRRGGBB colour written in skins.json as "#RRGGBB". */
private fun hexColor(text: String): UInt {
    val digits = text.removePrefix("#")
    if (digits.length != 6) throw SkinFileError("Not a #RRGGBB colour: $text")
    return digits.toUIntOrNull(16) ?: throw SkinFileError("Not a #RRGGBB colour: $text")
}

private fun JsonElement.obj(): JsonObject = this as? JsonObject ?: throw SkinFileError("expected an object")
private fun JsonObject.need(key: String): JsonElement = this[key] ?: throw SkinFileError("missing $key")
private fun JsonObject.text(key: String): String =
    (need(key) as? JsonPrimitive)?.takeIf { it.isString }?.content ?: throw SkinFileError("$key is not text")
private fun JsonObject.number(key: String): Double = (need(key) as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull ?: throw SkinFileError("$key is not a number")
private fun JsonObject.texts(key: String): List<String> =
    (need(key) as? JsonArray)?.map { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content ?: throw SkinFileError("$key holds a non-text") }
        ?: throw SkinFileError("$key is not a list")
private fun JsonObject.color(key: String): UInt = hexColor(text(key))
private fun <E> raw(values: Array<E>, text: String, name: (E) -> String): E = values.firstOrNull { name(it) == text } ?: throw SkinFileError("Unknown value $text")

/** The named colours of one skin. Screens ask for colours by name, never by code. */
data class SkinColors(
    val page: UInt, val ink: UInt, val sub: UInt, val dim: UInt, val card: UInt, val line: UInt, val accent: UInt, val up: UInt, val down: UInt,
    /** Flat-shard and paper accents (e.g. stitch navy, mustard, cream); may be empty. */
    val extra: List<UInt>,
) {
    internal companion object {
        fun read(o: JsonObject) = SkinColors(
            o.color("page"), o.color("ink"), o.color("sub"), o.color("dim"), o.color("card"), o.color("line"), o.color("accent"),
            o.color("up"), o.color("down"), o.texts("extra").map(::hexColor),
        )
    }
}

/** PostScript font names, plus how the big face is drawn. */
data class SkinFonts(
    val big: String,
    val title: String,
    val body: String,
    val mono: String,
    /** The big face is a variable font registered under its Regular instance, drawn bold as on the canvas (sketch's Caveat). */
    val bigBold: Boolean = false,
    /** How far, in em, the big face's ink reaches past its last glyph's advance; the kit adds that much trailing room. */
    val bigOverhang: Double = 0.0,
) {
    internal companion object {
        fun read(o: JsonObject) = SkinFonts(
            o.text("big"), o.text("title"), o.text("body"), o.text("mono"),
            o["bigBold"]?.let { (it as? JsonPrimitive)?.booleanOrNull ?: throw SkinFileError("bigBold is not true or false") } ?: false,
            o["bigOverhang"]?.let { o.number("bigOverhang") } ?: 0.0,
        )
    }
}

data class SkinStyle(
    val tag: TagKind,
    val button: ButtonKind,
    val stage: StageKind,
    val check: CheckKind,
    val quick: QuickKind,
    val chart: ChartKind,
    val decor: DecorKind,
) {
    enum class TagKind(val rawValue: String) { HEX_OUTLINE("hexOutline"), PIXEL_BLOCK("pixelBlock"), PAPER_STRIP("paperStrip"), HIGHLIGHTER("highlighter") }
    enum class ButtonKind(val rawValue: String) { HEX("hex"), PIXEL_BLOCK("pixelBlock"), PAPER_STITCH("paperStitch"), SKETCH_BOX("sketchBox") }
    enum class StageKind(val rawValue: String) { DISC_RING("discRing"), PIXEL_FRAME("pixelFrame"), PAPER_DISC("paperDisc"), NONE("none") }
    enum class CheckKind(val rawValue: String) { DISC("disc"), SQUARE("square"), STITCH_DISC("stitchDisc"), SKETCH_CIRCLE("sketchCircle") }
    enum class QuickKind(val rawValue: String) { GOLD_HEX("goldHex"), PINK_BLOCK("pinkBlock"), STITCH_DISC("stitchDisc"), SKETCH_DOT("sketchDot") }
    enum class ChartKind(val rawValue: String) { SMOOTH("smooth"), STEPPED("stepped"), PLAIN("plain"), PENCIL("pencil") }
    enum class DecorKind(val rawValue: String) { RAYS("rays"), PIXEL_STARS("pixelStars"), SEAMS("seams"), DOODLES("doodles") }

    internal companion object {
        fun read(o: JsonObject) = SkinStyle(
            raw(TagKind.entries.toTypedArray(), o.text("tag")) { it.rawValue },
            raw(ButtonKind.entries.toTypedArray(), o.text("button")) { it.rawValue },
            raw(StageKind.entries.toTypedArray(), o.text("stage")) { it.rawValue },
            raw(CheckKind.entries.toTypedArray(), o.text("check")) { it.rawValue },
            raw(QuickKind.entries.toTypedArray(), o.text("quick")) { it.rawValue },
            raw(ChartKind.entries.toTypedArray(), o.text("chart")) { it.rawValue },
            raw(DecorKind.entries.toTypedArray(), o.text("decor")) { it.rawValue },
        )
    }
}

/**
 * The images every skin provides, each drawn in that skin's own style (spec 8.2). Vector skins also carry numerals
 * "digit_0"…"digit_9"; stitch adds a mustard set "digit_N_b" and the cloth "patch", sketch adds tally marks "tally_1"…"tally_5".
 */
enum class SkinArtName(val rawValue: String) {
    HERO_DOLLAR("hero_dollar"), POCKET("pocket"), POCKET_ICON("pocket_icon"), FIND("find"), DIVIDENDS("dividends"), TOOLS("tools"),
    ACHIEVEMENTS("achievements"), CROWN("crown"), CALC("calc"), FEES("fees"), REMINDER("reminder"), GOAL("goal"), BADGE("badge"),
}

data class SkinArt(val kind: ArtKind, /** Asset folder, e.g. "Skins/stitch". */ val folder: String) {
    enum class ArtKind(val rawValue: String) { RENDER_3D("render3D"), VOXEL_3D("voxel3D"), VECTOR("vector") }

    /** The asset name of one of this skin's images, e.g. "Skins/stitch/find". */
    fun image(name: SkinArtName): String = image(name.rawValue)

    /** Names outside [SkinArtName], such as the vector skins' "digit_0"…"digit_9". */
    fun image(named: String): String = "$folder/$named"

    internal companion object {
        fun read(o: JsonObject) = SkinArt(raw(ArtKind.entries.toTypedArray(), o.text("kind")) { it.rawValue }, o.text("folder"))
    }
}

data class SkinFeedback(val sound: String, val haptic: HapticKind) {
    enum class HapticKind(val rawValue: String) { HEAVY("heavy"), TRIPLE("triple"), TAP("tap"), FAINT("faint") }

    internal companion object {
        fun read(o: JsonObject) = SkinFeedback(o.text("sound"), raw(HapticKind.entries.toTypedArray(), o.text("haptic")) { it.rawValue })
    }
}

sealed interface SkinUnlock {
    data object Free : SkinUnlock
    data class Level(val level: Int) : SkinUnlock
    data object Member : SkinUnlock

    companion object {
        internal fun read(o: JsonObject): SkinUnlock = when (val kind = o.text("kind")) {
            "free" -> Free
            "member" -> Member
            "level" -> Level((o.need("level") as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull ?: throw SkinFileError("level is not a whole number"))
            else -> throw SkinFileError("Unknown unlock $kind")
        }
    }
}

/** A complete look: colours, fonts, shape kinds, art, feedback and how it unlocks. The 3D skins also carry a metal material and burst colours. */
data class Skin(
    val id: String,
    val name: String,
    /** "SKN 001" */
    val code: String,
    val colors: SkinColors,
    val fonts: SkinFonts,
    val style: SkinStyle,
    val art: SkinArt,
    val feedback: SkinFeedback,
    val unlock: SkinUnlock,
    val metal: Metal?,
    val burst: List<UInt>,
) {
    data class Metal(val color: UInt, val metalness: Double, val roughness: Double)

    internal companion object {
        fun read(o: JsonObject) = Skin(
            o.text("id"), o.text("name"), o.text("code"), SkinColors.read(o.need("colors").obj()), SkinFonts.read(o.need("fonts").obj()),
            SkinStyle.read(o.need("style").obj()), SkinArt.read(o.need("art").obj()), SkinFeedback.read(o.need("feedback").obj()),
            SkinUnlock.read(o.need("unlock").obj()),
            o["metal"]?.takeIf { it !is kotlinx.serialization.json.JsonNull }?.obj()?.let { Metal(it.color("color"), it.number("metalness"), it.number("roughness")) },
            o.texts("burst").map(::hexColor),
        )
    }
}

/** The four skins, loaded once from the shared skins.json. */
object Skins {
    val all: List<Skin> by lazy {
        val root = CoreJson.json.parseToJsonElement(CoreResources.read("skins.json").decodeToString()) as? JsonArray ?: throw SkinFileError("skins.json is not a list")
        root.map { Skin.read(it.obj()) }
    }

    /** The free skin, black-gold. */
    val default: Skin get() = named("blackgold")

    /** Unknown or retired ids fall back to black-gold. */
    fun named(id: String): Skin = all.firstOrNull { it.id == id } ?: all.firstOrNull { it.id == "blackgold" } ?: all[0]

    val carouselOrder: List<String> = listOf("voxel", "blackgold", "stitch", "sketch")

    /** Whether a skin can be worn: black-gold always, a level skin from its level on (G3, G6), and every skin for members. */
    fun isUnlocked(skin: Skin, level: Int, member: Boolean): Boolean = when (val unlock = skin.unlock) {
        SkinUnlock.Free -> true
        is SkinUnlock.Level -> member || level >= unlock.level
        SkinUnlock.Member -> member
    }
}

/** WCAG contrast ratio of two 0xRRGGBB colours (1…21). */
fun contrastRatio(a: UInt, b: UInt): Double {
    fun channel(v: UInt): Double {
        val s = v.toDouble() / 255
        return if (s <= 0.03928) s / 12.92 else ((s + 0.055) / 1.055).pow(2.4)
    }
    fun luminance(c: UInt): Double = 0.2126 * channel((c shr 16) and 0xFFu) + 0.7152 * channel((c shr 8) and 0xFFu) + 0.0722 * channel(c and 0xFFu)
    val l1 = luminance(a)
    val l2 = luminance(b)
    return (maxOf(l1, l2) + 0.05) / (minOf(l1, l2) + 0.05)
}
