import Foundation

/// A complete look: screen colours plus the 3D materials (matte body, a second matte for the back panel, polished
/// metal) and the burst colours. Colours are 0xRRGGBB.
struct Skin: Identifiable, Equatable {
    struct Metal: Equatable { var color: UInt32; var metalness: Double; var roughness: Double }
    var id: String
    var name: String
    var rarity: String
    var background: UInt32
    var foreground: UInt32
    var muted: UInt32
    var accent: UInt32
    var line: UInt32
    var matte: UInt32
    var matte2: UInt32
    var metal: Metal
    var burst: [UInt32]
}

/// The three skins of the concept page.
enum Skins {
    static let all: [Skin] = [
        Skin(id: "blackgold", name: "黑金", rarity: "傳奇", background: 0x0E0E10, foreground: 0xF4F1E8, muted: 0xA9A397, accent: 0xF2B632, line: 0x34343C,
             matte: 0x1D1D22, matte2: 0x2A2A31, metal: .init(color: 0xE9B949, metalness: 1, roughness: 0.2), burst: [0xFFFFFF, 0xF2B632, 0xFF6F91, 0x3D7BFF]),
        Skin(id: "ember", name: "橘焰", rarity: "稀有", background: 0xF2A93B, foreground: 0x17130E, muted: 0x5A3F12, accent: 0x17130E, line: 0xC98A2A,
             matte: 0x17130E, matte2: 0x2B2218, metal: .init(color: 0xF7F2E8, metalness: 0, roughness: 0.16), burst: [0xFFFFFF, 0x17130E, 0xE8573C]),
        Skin(id: "ice", name: "冰藍", rarity: "普通", background: 0x0B1530, foreground: 0xE8EEF8, muted: 0x9FB0D0, accent: 0x7FD3FF, line: 0x2A3D6B,
             matte: 0x15275A, matte2: 0x1E3570, metal: .init(color: 0xDCE6F2, metalness: 1, roughness: 0.12), burst: [0xFFFFFF, 0x7FD3FF, 0xFF6F91, 0x3D7BFF])
    ]
    static var `default`: Skin { all[0] }
    static func named(_ id: String) -> Skin? { all.first { $0.id == id } }
}

/// WCAG contrast ratio of two 0xRRGGBB colours (1…21).
func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
    func luminance(_ c: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double { let s = Double(v) / 255; return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel((c >> 16) & 0xFF) + 0.7152 * channel((c >> 8) & 0xFF) + 0.0722 * channel(c & 0xFF)
    }
    let (l1, l2) = (luminance(a), luminance(b))
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
}
