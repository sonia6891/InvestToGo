import SwiftUI

/// The older button style, now drawn by the skin kit (`SkinButtonChrome`) so its existing callers take each skin's
/// own button. It stays the secondary (outlined) button it always was, filling in while pressed.
struct HexButtonStyle: ButtonStyle {
    var skin: Skin
    /// Side padding; smaller when two buttons share a row.
    var horizontal: CGFloat = 40
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        SkinButtonChrome(primary: primary, pressed: configuration.isPressed, horizontal: horizontal) { configuration.label }
            .environment(\.skin, skin)
    }
}

/// One line of a game-style status table: monospaced figures, a hairline below, the selected row in the accent colour.
struct HUDRow: View {
    var title: String
    var value: String
    var selected: Bool
    var skin: Skin
    var body: some View {
        HStack(spacing: 10) {
            Text("▶").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(rgb: skin.colors.accent)).opacity(selected ? 1 : 0).accessibilityHidden(true)
            Text(title).font(.system(size: 15, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
            Text(value).font(.system(size: 15, weight: .bold, design: .monospaced)).monospacedDigit()
        }
        .foregroundStyle(selected ? Color(rgb: skin.colors.accent) : Color(rgb: skin.colors.ink))
        .padding(.vertical, 11).padding(.horizontal, 4).frame(minHeight: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(rgb: skin.colors.line)).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

/// The skin pill: name and code, tapping moves on to the next skin of the carousel order.
struct SkinPicker: View {
    @ObservedObject var skins: SkinStore
    private static func following(_ skin: Skin) -> Skin {
        let order = Skins.carouselOrder
        return Skins.named(order[((order.firstIndex(of: skin.id) ?? -1) + 1) % order.count])
    }
    var body: some View {
        Button { skins.skin = Self.following(skins.skin); Haptics.tick(); SoundFX.tick(enabled: skins.soundOn) } label: {
            HStack(spacing: 6) {
                Text("皮膚 \(skins.skin.name)")
                Text(skins.skin.code).bold().foregroundStyle(Color(rgb: skins.skin.colors.accent == skins.skin.colors.ink ? skins.skin.colors.ink : skins.skin.colors.accent))
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Color(rgb: skins.skin.colors.ink))
            .padding(.horizontal, 12).frame(minHeight: 36)
            .overlay(Capsule().stroke(Color(rgb: skins.skin.colors.ink), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("skin-picker")
        .accessibilityLabel("換皮膚，目前\(skins.skin.name)")
    }
}
