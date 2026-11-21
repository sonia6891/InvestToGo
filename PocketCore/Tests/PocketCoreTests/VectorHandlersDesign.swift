import Foundation
@testable import PocketCore

// 外觀主題資料、方塊字形與口袋形狀: the shapes both platforms read and write in SharedFixtures/vectors/design.

private func skinOutput(_ s: Skin) -> [String: Any] {
    let c = s.colors, f = s.fonts, st = s.style
    let unlock: [String: Any]
    switch s.unlock {
    case .free: unlock = ["kind": "free"]
    case .member: unlock = ["kind": "member"]
    case .level(let level): unlock = ["kind": "level", "level": level]
    }
    return [
        "id": s.id, "name": s.name, "code": s.code,
        "colors": ["page": c.page, "ink": c.ink, "sub": c.sub, "dim": c.dim, "card": c.card, "line": c.line, "accent": c.accent,
                   "up": c.up, "down": c.down, "extra": c.extra] as [String: Any],
        "fonts": ["big": f.big, "title": f.title, "body": f.body, "mono": f.mono, "bigBold": f.bigBold, "bigOverhang": f.bigOverhang] as [String: Any],
        "style": ["tag": st.tag.rawValue, "button": st.button.rawValue, "stage": st.stage.rawValue, "check": st.check.rawValue,
                  "quick": st.quick.rawValue, "chart": st.chart.rawValue, "decor": st.decor.rawValue],
        "art": ["kind": s.art.kind.rawValue, "folder": s.art.folder],
        "feedback": ["sound": s.feedback.sound, "haptic": s.feedback.haptic.rawValue],
        "unlock": unlock,
        "metal": orNull(s.metal.map { ["color": $0.color, "metalness": $0.metalness, "roughness": $0.roughness] as [String: Any] }),
        "burst": s.burst,
    ]
}

private func blockOutput(_ b: GlyphBlock) -> [String: Any] {
    let shape: String
    switch b.shape { case .box: shape = "box"; case .ring: shape = "ring"; case .slash: shape = "slash" }
    return ["shape": shape, "x": b.x, "y": b.y, "width": b.width, "height": b.height, "depth": b.depth, "rotation": b.rotation, "gold": b.gold]
}

private func points(_ list: [SIMD2<Double>]) -> [[Double]] { list.map { [$0.x, $0.y] } }

let designHandlers: [String: VectorHandler] = [
    "Skins.all.summary": { _ in Skins.all.map(skinOutput) },
    "Skins.named": { input in Skins.named(try string(input, "id")).id },
    "Skins.isUnlocked": { input in
        let level = try int(input, "level")
        let member = (try VectorIO.object(input)["member"] as? Bool) ?? false
        return Skins.all.filter { Skins.isUnlocked($0, level: level, member: member) }.map(\.id)
    },
    "contrastRatio": { input in contrastRatio(UInt32(try int(input, "a")), UInt32(try int(input, "b"))) },
    "BlockGlyphs.layout": { input in
        let result = BlockGlyphs.layout(try string(input, "text"))
        return ["blocks": result.blocks.map(blockOutput), "width": result.width] as [String: Any]
    },
    "BlockGlyphs.voxelize": { input in
        BlockGlyphs.voxelize(BlockGlyphs.layout(try string(input, "text")).blocks, cell: try number(input, "cell")).map(blockOutput)
    },
    "PocketShape.front": { _ in points(PocketShape.front()) },
    "PocketShape.back": { _ in points(PocketShape.back()) },
    "PocketShape.stitches": { _ in
        PocketShape.stitches().map { ["center": [$0.center.x, $0.center.y], "angle": $0.angle, "length": $0.length] as [String: Any] }
    },
]
