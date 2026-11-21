package com.sonia.etftogo.core

import com.sonia.etftogo.core.design.BlockGlyphs
import com.sonia.etftogo.core.design.GlyphBlock
import com.sonia.etftogo.core.design.PocketShape
import com.sonia.etftogo.core.design.Skin
import com.sonia.etftogo.core.design.SkinUnlock
import com.sonia.etftogo.core.design.Skins
import com.sonia.etftogo.core.design.Vec2
import com.sonia.etftogo.core.design.contrastRatio
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

// 外觀主題資料、方塊字形與口袋形狀: the shapes both platforms read and write in SharedFixtures/vectors/design.

private fun colors(list: List<UInt>): JsonElement = JsonArray(list.map { JsonPrimitive(it.toLong()) })
private fun color(value: UInt) = JsonPrimitive(value.toLong())

private fun skinOutput(s: Skin): JsonElement {
    val c = s.colors
    val f = s.fonts
    val st = s.style
    val unlock = when (val u = s.unlock) {
        SkinUnlock.Free -> mapOf("kind" to JsonPrimitive("free"))
        SkinUnlock.Member -> mapOf("kind" to JsonPrimitive("member"))
        is SkinUnlock.Level -> mapOf("kind" to JsonPrimitive("level"), "level" to JsonPrimitive(u.level))
    }
    return JsonObject(mapOf(
        "id" to JsonPrimitive(s.id), "name" to JsonPrimitive(s.name), "code" to JsonPrimitive(s.code),
        "colors" to JsonObject(mapOf(
            "page" to color(c.page), "ink" to color(c.ink), "sub" to color(c.sub), "dim" to color(c.dim), "card" to color(c.card), "line" to color(c.line),
            "accent" to color(c.accent), "up" to color(c.up), "down" to color(c.down), "extra" to colors(c.extra),
        )),
        "fonts" to JsonObject(mapOf(
            "big" to JsonPrimitive(f.big), "title" to JsonPrimitive(f.title), "body" to JsonPrimitive(f.body), "mono" to JsonPrimitive(f.mono),
            "bigBold" to JsonPrimitive(f.bigBold), "bigOverhang" to JsonPrimitive(f.bigOverhang),
        )),
        "style" to JsonObject(mapOf(
            "tag" to JsonPrimitive(st.tag.rawValue), "button" to JsonPrimitive(st.button.rawValue), "stage" to JsonPrimitive(st.stage.rawValue),
            "check" to JsonPrimitive(st.check.rawValue), "quick" to JsonPrimitive(st.quick.rawValue), "chart" to JsonPrimitive(st.chart.rawValue),
            "decor" to JsonPrimitive(st.decor.rawValue),
        )),
        "art" to JsonObject(mapOf("kind" to JsonPrimitive(s.art.kind.rawValue), "folder" to JsonPrimitive(s.art.folder))),
        "feedback" to JsonObject(mapOf("sound" to JsonPrimitive(s.feedback.sound), "haptic" to JsonPrimitive(s.feedback.haptic.rawValue))),
        "unlock" to JsonObject(unlock),
        "metal" to (s.metal?.let { JsonObject(mapOf("color" to color(it.color), "metalness" to JsonPrimitive(it.metalness), "roughness" to JsonPrimitive(it.roughness))) } ?: JsonNull),
        "burst" to colors(s.burst),
    ))
}

private fun blockOutput(b: GlyphBlock) = JsonObject(mapOf(
    "shape" to JsonPrimitive(b.shape.name.lowercase()), "x" to JsonPrimitive(b.x), "y" to JsonPrimitive(b.y), "width" to JsonPrimitive(b.width),
    "height" to JsonPrimitive(b.height), "depth" to JsonPrimitive(b.depth), "rotation" to JsonPrimitive(b.rotation), "gold" to JsonPrimitive(b.gold),
))

private fun point(p: Vec2) = JsonArray(listOf(JsonPrimitive(p.x), JsonPrimitive(p.y)))
private fun points(list: List<Vec2>) = JsonArray(list.map(::point))

val designHandlers: Map<String, VectorHandler> = mapOf(
    "Skins.all.summary" to { _ -> JsonArray(Skins.all.map(::skinOutput)) },
    "Skins.named" to { input -> JsonPrimitive(Skins.named(input.str("id")).id) },
    "Skins.isUnlocked" to { input ->
        val member = VectorIO.obj(input)["member"]?.jsonPrimitive?.booleanOrNull ?: false
        JsonArray(Skins.all.filter { Skins.isUnlocked(it, input.int("level"), member) }.map { JsonPrimitive(it.id) })
    },
    "contrastRatio" to { input ->
        JsonPrimitive(contrastRatio(VectorIO.obj(input).getValue("a").jsonPrimitive.long.toUInt(), VectorIO.obj(input).getValue("b").jsonPrimitive.long.toUInt()))
    },
    "BlockGlyphs.layout" to { input ->
        val result = BlockGlyphs.layout(input.str("text"))
        JsonObject(mapOf("blocks" to JsonArray(result.blocks.map(::blockOutput)), "width" to JsonPrimitive(result.width)))
    },
    "BlockGlyphs.voxelize" to { input -> JsonArray(BlockGlyphs.voxelize(BlockGlyphs.layout(input.str("text")).blocks, input.num("cell")).map(::blockOutput)) },
    "PocketShape.front" to { _ -> points(PocketShape.front()) },
    "PocketShape.back" to { _ -> points(PocketShape.back()) },
    "PocketShape.stitches" to { _ ->
        JsonArray(PocketShape.stitches().map { JsonObject(mapOf("center" to point(it.center), "angle" to JsonPrimitive(it.angle), "length" to JsonPrimitive(it.length))) })
    },
)
