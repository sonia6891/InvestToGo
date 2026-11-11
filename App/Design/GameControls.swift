import SwiftUI

/// The elongated hexagon used for the main action, outlined in the skin's foreground colour.
struct HexShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = min(16, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + inset, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath(); return p
    }
}

struct HexButtonStyle: ButtonStyle {
    var skin: Skin
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .black)).tracking(4)
            .foregroundStyle(configuration.isPressed ? Color(rgb: skin.background) : Color(rgb: skin.foreground))
            .padding(.horizontal, 40).frame(minHeight: 52)
            .background(HexShape().fill(configuration.isPressed ? Color(rgb: skin.foreground) : .clear))
            .overlay(HexShape().stroke(Color(rgb: skin.foreground), lineWidth: 2))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
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
            Text("▶").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(rgb: skin.accent)).opacity(selected ? 1 : 0).accessibilityHidden(true)
            Text(title).font(.system(size: 15, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
            Text(value).font(.system(size: 15, weight: .bold, design: .monospaced)).monospacedDigit()
        }
        .foregroundStyle(selected ? Color(rgb: skin.accent) : Color(rgb: skin.foreground))
        .padding(.vertical, 11).padding(.horizontal, 4).frame(minHeight: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(rgb: skin.line)).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

/// The skin pill: name and rarity, tapping cycles to the next skin.
struct SkinPicker: View {
    @ObservedObject var skins: SkinStore
    var body: some View {
        Button { skins.next(); Haptics.tick(); SoundFX.tick(enabled: skins.soundOn) } label: {
            HStack(spacing: 6) {
                Text("皮膚 \(skins.skin.name)")
                Text(skins.skin.rarity).bold().foregroundStyle(Color(rgb: skins.skin.accent == skins.skin.foreground ? skins.skin.foreground : skins.skin.accent))
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Color(rgb: skins.skin.foreground))
            .padding(.horizontal, 12).frame(minHeight: 36)
            .overlay(Capsule().stroke(Color(rgb: skins.skin.foreground), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("skin-picker")
        .accessibilityLabel("換皮膚，目前\(skins.skin.name)")
    }
}
