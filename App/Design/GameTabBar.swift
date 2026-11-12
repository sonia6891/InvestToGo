import SwiftUI

/// The bottom navigation in the game style: a flat bar in the current skin's colours, monochrome icons, small
/// monospaced labels, and the selected tab in the accent colour with a thick marker above it. Taps tick.
struct GameTabBar: View {
    @Binding var selection: Int
    var reselect: (Int) -> Void
    @ObservedObject private var skins = SkinStore.shared

    var body: some View {
        let skin = skins.skin
        HStack(spacing: 0) {
            ForEach(AppTabs.items.indices, id: \.self) { index in
                let item = AppTabs.items[index], selected = index == selection
                Button {
                    if selected { reselect(index) } else { selection = index }
                    Haptics.tick(); SoundFX.tick(enabled: skins.soundOn)
                } label: {
                    VStack(spacing: 4) {
                        Rectangle().fill(selected ? Color(rgb: skin.colors.accent) : .clear).frame(width: 26, height: 4)
                        Image(systemName: item.icon).font(.system(size: 19, weight: selected ? .black : .regular))
                        Text(item.title).font(.system(size: 10, weight: selected ? .bold : .regular, design: .monospaced))
                    }
                    .foregroundStyle(Color(rgb: selected ? skin.colors.accent : skin.colors.sub))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityIdentifier("tab-\(item.title)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.top, 2)
        .background(alignment: .top) {
            Color(rgb: skin.colors.page)
                .overlay(alignment: .top) { Rectangle().fill(Color(rgb: skin.colors.line)).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
