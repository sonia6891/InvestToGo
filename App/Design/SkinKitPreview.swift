import SwiftUI

/// Opens the skin-kit sheet at launch when a UI test asks for it with `--ui-testing --open skinKit`
/// (debug builds only; release builds pass the content through).
struct SkinKitLaunch: ViewModifier {
    #if DEBUG
    @State private var open: Bool = {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--ui-testing"), let i = args.firstIndex(of: "--open"), args.indices.contains(i + 1) else { return false }
        return args[i + 1] == "skinKit"
    }()
    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $open) {
            NavigationStack { RouteView(route: .skinKitPreview) }
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
