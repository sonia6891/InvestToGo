import SwiftUI

/// Where a skin stands for this player: worn now, free to put on, or locked behind a level or membership.
enum SkinStatus: Equatable {
    case wearing, unlocked, needsLevel(Int), needsMember

    init(_ skin: Skin, current: String, level: Int, member: Bool) {
        if skin.id == current { self = .wearing }
        else if Skins.isUnlocked(skin, level: level, member: member) { self = .unlocked }
        else if case .level(let needed) = skin.unlock { self = .needsLevel(needed) }
        else { self = .needsMember }
    }

    /// The tag under the name, e.g. 「LV.5 已解鎖 · 你是 LV.7」.
    func tag(_ skin: Skin, level: Int, member: Bool) -> String {
        switch self {
        case .wearing: return skin.unlock == .free ? "預設皮膚 · 使用中" : "使用中"
        case .unlocked:
            switch skin.unlock {
            case .free: return "預設皮膚 · 已解鎖"
            case .level(let needed): return member && level < needed ? "會員 · 已解鎖" : "LV.\(needed) 已解鎖 · 你是 LV.\(level)"
            case .member: return "會員 · 已解鎖"
            }
        case .needsLevel(let needed): return "LV.\(needed) 解鎖 · 你是 LV.\(level)"
        case .needsMember: return "會員專屬"
        }
    }

    /// The short caption under a style badge.
    var caption: String {
        switch self {
        case .wearing: return "使用中"
        case .unlocked: return "已解鎖"
        case .needsLevel(let needed): return "LV.\(needed)"
        case .needsMember: return "會員"
        }
    }
}

extension Skin {
    /// One sentence about the look, under the name on the skin page.
    var pitch: String {
        switch id {
        case "voxel": return "方塊疊出來的世界，硬陰影配 8-bit 的「叮」。"
        case "stitch": return "牛皮紙剪貼，一圈縫線，硬幣被縫進口袋。"
        case "sketch": return "白紙上的鉛筆塗鴉，最安靜的一套。"
        default: return "啞光黑黏土配漆金，金幣掉進錢袋。"
        }
    }
}

/// 換膚 (spec 5.13): the four skins as cards, then the focused one's name, status, a sentence, the style badges and
/// one button. Holding a card tries the skin on full screen until the finger lifts; only 「換上這套」 changes the app.
struct SkinsView: View {
    @EnvironmentObject var store: PortfolioStore
    @ObservedObject private var skins = SkinStore.shared
    @ObservedObject private var membership = MembershipStore.shared
    @Environment(\.skin) private var skin
    @Environment(\.lobbyNavigation) private var navigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The card in the middle; starts on the skin being worn.
    @State private var focus: String? = SkinStore.current.id

    var body: some View {
        let level = GameRules.level(xp: (store.data.game ?? GameState()).xp), member = membership.isMember
        let focused = Skins.named(focus ?? skins.skin.id)
        let status = SkinStatus(focused, current: skins.skin.id, level: level, member: member)
        Page {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("換膚").skinFont(.title(30)).skinForeground(\.ink)
                Text("SKINS").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
            }
            SkinCarousel(focus: $focus, tryOn: $skins.tryOn)
            VStack(spacing: 10) {
                pageDots(focused.id)
                Text(focused.name).skinFont(.title(28)).skinForeground(\.ink)
                    .accessibilityIdentifier("skin-name")
                SkinTag(status.tag(focused, level: level, member: member))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(status.tag(focused, level: level, member: member))
                    .accessibilityIdentifier("skin-status")
                Text(focused.pitch).skinFont(.body(13)).skinForeground(\.sub)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                badges(level: level, member: member)
                applyButton(focused, status: status)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear { skins.tryOn = nil }
        .task { await membership.start() }
    }

    /// One dot per skin, the focused one long, and 「n / 4」.
    private func pageDots(_ id: String) -> some View {
        let order = Skins.carouselOrder, index = order.firstIndex(of: id) ?? 0
        return HStack(spacing: 7) {
            ForEach(order, id: \.self) { item in
                Capsule().fill(item == id ? skin.color(\.accent) : skin.color(\.line))
                    .frame(width: item == id ? 18 : 7, height: 7)
            }
            Text("\(index + 1) / \(order.count)").skinFont(.mono(11)).skinForeground(\.sub).padding(.leading, 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(index + 1) 套，共 \(order.count) 套")
    }

    /// The four style badges, each in its own skin's drawing on its own page colour; tapping one turns to its card.
    private func badges(level: Int, member: Bool) -> some View {
        HStack(spacing: 18) {
            ForEach(Skins.carouselOrder, id: \.self) { id in
                let item = Skins.named(id), on = id == (focus ?? skins.skin.id)
                let status = SkinStatus(item, current: skins.skin.id, level: level, member: member)
                Button {
                    withAnimation(reduceMotion ? nil : .snappy) { focus = id }
                    SoundFX.tick(enabled: skins.soundOn)
                } label: {
                    VStack(spacing: 7) {
                        SkinImage(.badge).environment(\.skin, item)
                            .frame(width: 42, height: 42)
                            .frame(width: 56, height: 56)
                            .background(RoundedRectangle(cornerRadius: 16).fill(item.color(\.page)))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(skin.color(\.line), lineWidth: 1.5))
                            .padding(3)
                            .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(skin.color(\.ink), lineWidth: on ? 2 : 0))
                        Text(status.caption).skinFont(.mono(10)).foregroundStyle(on ? skin.color(\.ink) : skin.color(\.sub))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.name)，\(status.caption)")
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("skin-badge-\(id)")
            }
        }
    }

    /// 「← 滑動試穿 →」 on the skin being worn, 「換上這套」 on one that is open, otherwise the way to open it.
    @ViewBuilder private func applyButton(_ focused: Skin, status: SkinStatus) -> some View {
        switch status {
        case .wearing:
            SkinButton("← 滑動試穿 →", primary: false) { turn(by: 1) }
                .accessibilityIdentifier("skin-apply")
        case .unlocked:
            SkinButton("換上這套") {
                Haptics.tick()
                skins.select(focused.id)
                navigation.toLobby()
            }
            .accessibilityIdentifier("skin-apply")
        case .needsLevel:
            // Levels come from the lobby's monthly quests and the DCA streak.
            SkinButton("去升級", primary: false) { navigation.toLobby() }
                .accessibilityIdentifier("skin-apply")
        case .needsMember:
            // 換膚 is opened from 會員, one step back.
            SkinButton("看會員", primary: false) { dismiss() }
                .accessibilityIdentifier("skin-apply")
        }
    }

    private func turn(by step: Int) {
        let order = Skins.carouselOrder, index = order.firstIndex(of: focus ?? skins.skin.id) ?? 0
        withAnimation(reduceMotion ? nil : .snappy) { focus = order[(index + step + order.count) % order.count] }
    }
}

/// The cards: each skin's own pocket on its own page colour, nothing else, and no figures (spec 5.13). The middle card
/// is full size with a white frame; its neighbours peek in at the sides, smaller and tilted.
struct SkinCarousel: View {
    @Binding var focus: String?
    @Binding var tryOn: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var skins = SkinStore.shared
    /// The card being held; reset by SwiftUI however the touch ends, even when the scroll view takes it over.
    @GestureState private var holding: String? = nil
    static let cardSize = CGSize(width: 176, height: 300)

    var body: some View {
        GeometryReader { proxy in
          ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(Skins.carouselOrder, id: \.self) { id in
                        card(Skins.named(id), centred: id == (focus ?? skins.skin.id))
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.86)
                                    .rotationEffect(.degrees(reduceMotion ? 0 : phase.value * 9))
                            }
                            .id(id)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 10)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $focus, anchor: .center)
            .safeAreaPadding(.horizontal, max(0, (proxy.size.width - Self.cardSize.width) / 2))
            .scrollClipDisabled()
            // The bound position alone does not move a scroll view that has not laid out yet: start on the worn skin.
            .onAppear { DispatchQueue.main.async { reader.scrollTo(focus ?? skins.skin.id, anchor: .center) } }
          }
        }
        .frame(height: Self.cardSize.height + 20)
        // The page's side padding would cut the neighbours off; let them run to the screen edges.
        .padding(.horizontal, -16)
        .onAppear { if focus == nil { focus = skins.skin.id } }
        .onChange(of: focus) { _, _ in Haptics.tick() }
        .onChange(of: holding) { _, value in tryOn = value; if value != nil { Haptics.tick() } }
    }

    private func card(_ item: Skin, centred: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28).fill(item.color(\.page))
            if item.style.button == .paperStitch {
                StitchSeam(color: item.color(\.dim), cornerRadius: 22, inset: 7, lineWidth: 1.5)
            }
            SkinImage(.pocket).environment(\.skin, item)
                .frame(width: 160, height: 160)
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.white, lineWidth: centred ? 3 : 0))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .updating($holding) { value, state, _ in
                    if case .second(true, _) = value { state = item.id }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name)皮膚的口袋")
        .accessibilityHint("長按可以全螢幕試穿")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("skin-card-\(item.id)")
    }
}

/// Holding a card: the whole screen in that skin, drawn at the root above the bottom bar, decoration, its pocket, a tag and a button, without changing
/// anything. Lifting the finger puts the page back.
struct TryOnPreview: View {
    let skin: Skin
    var body: some View {
        ZStack {
            skin.color(\.page)
            SkinDecor(page: .lobby)
            VStack(spacing: 18) {
                Text("試穿中").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
                SkinStage(size: 250) { SkinImage(.pocket).frame(width: 210, height: 210) }
                Text(skin.name).skinFont(.title(34)).skinForeground(\.ink)
                SkinTag("放開就還原")
                SkinButton("換上這套", primary: true) {}.allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .environment(\.skin, skin)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在試穿\(skin.name)")
    }
}
