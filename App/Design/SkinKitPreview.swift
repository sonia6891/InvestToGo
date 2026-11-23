import SwiftUI

/// Opens the skin-kit sheet at launch when a UI test asks for it with `--ui-testing --open skinKit`
/// (debug builds only; release builds pass the content through).
struct SkinKitLaunch: ViewModifier {
    #if DEBUG
    /// `--open skinKit` or `--open widgetPreview`.
    @State private var route: AppRoute? = {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--ui-testing"), let i = args.firstIndex(of: "--open"), args.indices.contains(i + 1) else { return nil }
        switch args[i + 1] {
        case "skinKit": return .skinKitPreview
        case "widgetPreview": return .widgetPreview
        default: return nil
        }
    }()
    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: Binding(get: { route != nil }, set: { if !$0 { route = nil } })) {
            NavigationStack { if let route { RouteView(route: route) } }
                .environment(\.skin, SkinStore.shared.skin)
        }
    }
    #else
    func body(content: Content) -> some View { content }
    #endif
}

#if DEBUG
/// 元件總表: every skin-kit component drawn in the current skin, to set beside the four-skin canvas.
struct SkinKitPreview: View {
    @Environment(\.skin) private var skin
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var chip = 0
    private let chips = ["全部", "市值型", "高股息", "債券", "主題"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(skin.code) · \(skin.name)").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
                    Text("元件總表").skinFont(.title(30)).skinForeground(\.ink)
                }
                // The hero zone: the stage with the skin's decoration around it. Decoration lives only here, never
                // under text or controls.
                ZStack {
                    SkinDecor(page: .lobby)
                    SkinStage(size: 240) { SkinImage(.find).frame(width: 170, height: 170) }
                }
                .frame(height: 320)
                .padding(.horizontal, -20)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("12").skinFont(.big(48))
                    Text("個月").skinFont(.title(24))
                    Spacer()
                    SkinCheck(done: true); SkinCheck(done: false)
                }
                .skinForeground(\.ink)
                HStack(spacing: 12) { SkinTag("連續定期定額"); SkinTag("找 ETF"); SkinTag("市值型") }
                VStack(spacing: 14) {
                    SkinButton("加入口袋") {}
                    SkinButton("＋ 加一檔", primary: false) {}
                }
                .frame(maxWidth: .infinity)
                SkinSearchField(text: $query, prompt: "輸入代號或名稱")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(chips.indices, id: \.self) { i in SkinChip(chips[i], selected: chip == i) { chip = i } }
                    }
                    .padding(.trailing, 8).padding(.bottom, 4)
                }
                SkinCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("本月任務 2/3"); Spacer(); Text("+120 XP").foregroundStyle(skin.color(skin.lightText ? \.accent : \.ink)) }
                            .skinFont(.mono(11)).skinForeground(\.sub)
                        HStack(spacing: 14) {
                            quest(true, "定投一次"); quest(true, "看配息"); quest(false, "研究新 ETF")
                        }
                    }
                }
                HStack {
                    ForEach([SkinArtName.pocketIcon, .dividends, .tools, .achievements], id: \.self) { name in
                        VStack(spacing: 6) { SkinImage(name).frame(width: 64, height: 64); SkinTag(name.rawValue) }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
        }
        .accessibilityIdentifier("skinkit-root")
        .background(skin.color(\.page).ignoresSafeArea())
        .navigationTitle("元件總表").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("關閉") { dismiss() } } }
    }

    private func quest(_ done: Bool, _ title: String) -> some View {
        HStack(spacing: 7) { SkinCheck(done: done, size: 18); Text(title).skinFont(.body(12)) }
    }
}
#endif

#if DEBUG
/// 連續定投 widget: its small and medium tiles drawn in the current skin, at the home screen's sizes, for three states
/// (running, broken, newbie). The unsigned simulator build has no App Group, so this is how tests and screenshots see
/// the widget. `--open widgetPreview`.
struct WidgetPreview: View {
    @Environment(\.skin) private var skin
    @Environment(\.dismiss) private var dismiss
    private let now = Date()

    var body: some View {
        let running = WidgetSnapshot.sample(streak: 12, done: 2, skinID: skin.id, now: now)
        let broken = WidgetSnapshot.sample(streak: 0, longest: 5, done: 0, skinID: skin.id, now: now)
        let newbie = WidgetSnapshot.newbie(now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(skin.code) · \(skin.name)").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
                tile("widget-preview-small-running", running, medium: false)
                tile("widget-preview-medium-running", running, medium: true)
                tile("widget-preview-small-broken", broken, medium: false)
                tile("widget-preview-small-newbie", newbie, medium: false)
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
        }
        .accessibilityIdentifier("widget-preview-root")
        .background(skin.color(\.page).ignoresSafeArea())
        .navigationTitle("連續定投小工具").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("關閉") { dismiss() } } }
    }

    private func tile(_ id: String, _ snapshot: WidgetSnapshot, medium: Bool) -> some View {
        Group {
            if medium { StreakMediumView(snapshot: snapshot, skin: skin) } else { StreakSmallView(snapshot: snapshot, skin: skin) }
        }
        .padding(16)
        .frame(width: medium ? 338 : 158, height: 158)
        .background { StreakWidgetBackground(skin: skin) }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(skin.color(\.line), lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}
#endif
