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
    /// Card and inset surfaces of the ordinary screens.
    var surface: UInt32 = 0x1A1A1F
    var surface2: UInt32 = 0x26262C
    /// Gains and losses (Taiwan: up red, down green), tuned to stay readable on this skin's background.
    var up: UInt32 = 0xFF4D5E
    var down: UInt32 = 0x2FD08A
}

/// The three skins; the first is the default.
enum Skins {
    static let all: [Skin] = [
        // The default look: saturated orange-yellow with black and cream objects, the strongest contrast of the set.
        Skin(id: "ember", name: "橘焰", rarity: "稀有", background: 0xFFA41B, foreground: 0x111111, muted: 0x4A2E05, accent: 0x111111, line: 0x111111,
             matte: 0x141414, matte2: 0x262626, metal: .init(color: 0xFFF6E5, metalness: 0, roughness: 0.16), burst: [0xFFFFFF, 0x111111, 0xE8253C],
             surface: 0xFFBA45, surface2: 0xF29A10, up: 0xA3001B, down: 0x00653A),
        Skin(id: "blackgold", name: "黑金", rarity: "傳奇", background: 0x0E0E10, foreground: 0xF4F1E8, muted: 0xA9A397, accent: 0xF2B632, line: 0x34343C,
             matte: 0x22222A, matte2: 0x2E2E36, metal: .init(color: 0xF4C24E, metalness: 1, roughness: 0.1), burst: [0xFFFFFF, 0xF2B632, 0xFF6F91, 0x3D7BFF]),
        Skin(id: "ice", name: "冰藍", rarity: "普通", background: 0x0B1530, foreground: 0xE8EEF8, muted: 0x9FB0D0, accent: 0x7FD3FF, line: 0x2A3D6B,
             matte: 0x15275A, matte2: 0x1E3570, metal: .init(color: 0xDCE6F2, metalness: 1, roughness: 0.12), burst: [0xFFFFFF, 0x7FD3FF, 0xFF6F91, 0x3D7BFF],
             surface: 0x14234A, surface2: 0x1C2F5E)
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
