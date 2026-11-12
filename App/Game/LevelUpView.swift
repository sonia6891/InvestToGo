import SwiftUI

/// One LEVEL×UP to show: the level reached, why, and what came with it.
struct LevelUpMoment: Identifiable, Equatable {
    let level: Int
    let reason: String
    let rewards: [String]
    var id: Int { level }
}

enum LevelUp {
    /// The reason tag under LV.n (spec 5.12): the experience event that crossed the level.
    static func reason(_ game: GameState, now: Date) -> String {
        switch game.lastAward {
        case .monthlyDCA?: return "連續定投 \(max(game.streak(now: now), 1)) 個月"
        case .questDone?: return "完成本月任務"
        case .firstDexCard?: return "收進新的圖鑑卡"
        case .dividendLogged?: return "記一筆配息"
        case .reconciled?: return "完成一次對帳"
        case nil: return "累積 \(game.xp) 經驗"
        }
    }

    /// The rewards list (spec 5.12): coins earned and achievements unlocked since the last LEVEL×UP, and the next
    /// skin a level opens. Read from the saved game, so a celebration replayed after a relaunch lists the same.
    static func rewards(_ game: GameState, level: Int) -> [String] {
        var list = ["金幣 +\(game.coinsSinceCelebration.formatted())"]
        for id in game.achievementsSinceCelebration { if let item = Achievements.all.first(where: { $0.id == id }) { list.append("新成就「\(item.title)」") } }
        let levelSkins = Skins.all.compactMap { skin -> (Int, String)? in
            if case .level(let needed) = skin.unlock { return (needed, skin.name) }
            return nil
        }
        if let now = levelSkins.first(where: { $0.0 == level }) {
            list.append("解鎖「\(now.1)」皮膚")
        } else if let next = levelSkins.filter({ $0.0 > level }).min(by: { $0.0 < $1.0 }) {
            list.append("LV.\(next.0) 解鎖「\(next.1)」皮膚，還差 \(next.0 - level) 級")
        }
        return list
    }

    static func moment(_ game: GameState, level: Int, now: Date) -> LevelUpMoment {
        LevelUpMoment(level: level, reason: reason(game, now: now), rewards: rewards(game, level: level))
    }
}

/// The stage, LEVEL×UP, the level and the reason; shared by the screen and the picture it shares.
struct LevelUpHeader: View {
    let moment: LevelUpMoment
    var appeared = true
    @Environment(\.skin) private var skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            SkinStage(size: 200) { SkinImage(.dividends).padding(36) }
                .background { SkinDecor(page: .splash).frame(width: 390, height: 280).allowsHitTesting(false) }
                .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)
                .padding(.bottom, 18)
            Text("LEVEL×UP").skinFont(.mono(13)).tracking(3).foregroundStyle(skin.color(\.sub))
            Text("LV.\(moment.level)").skinFont(.big(72)).foregroundStyle(skin.color(\.ink))
                .lineLimit(1).minimumScaleFactor(0.5)
                .accessibilityIdentifier("levelup-level")
            SkinTag(moment.reason)
        }
    }
}

/// 升級 (spec 5.12), shown once over everything by the root view when experience crosses a whole level.
struct LevelUpView: View {
    let moment: LevelUpMoment
    let onAccept: () -> Void
    @Environment(\.skin) private var skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var appeared = false
    @State private var drops = 0
    @State private var shareImage: Image?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                LevelUpHeader(moment: moment, appeared: appeared)
                SkinCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("獎勵").skinFont(.mono(11)).foregroundStyle(skin.color(\.sub))
                        ForEach(moment.rewards, id: \.self) { reward in
                            HStack(spacing: 8) {
                                SkinCheck(done: true, size: 18).accessibilityHidden(true)
                                Text(reward).skinFont(.body(14)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 36).padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        // 收下 and 分享這一刻 stay on screen, even on small phones where the rest scrolls.
        .safeAreaInset(edge: .bottom) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { actions }
                VStack(spacing: 10) { actions }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(skin.color(\.page).ignoresSafeArea())
        }
        .background(skin.color(\.page).ignoresSafeArea())
        .overlay(alignment: .top) {
            CoinDrop(trigger: drops).frame(width: 200, height: 160).padding(.top, 60)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        // Drawn once the entrance has settled, so rendering never stalls the animation.
        .task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            render()
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.45, dampingFraction: 0.6)) { appeared = true }
            drops += 1
            AccessibilityNotification.Announcement("升到等級 \(moment.level)，\(moment.reason)").post()
        }
    }

    @ViewBuilder private var actions: some View {
        SkinButton("收下", action: onAccept)
            .accessibilityIdentifier("levelup-accept")
        if let shareImage {
            ShareLink(item: shareImage, preview: SharePreview("升到 LV.\(moment.level)", image: shareImage)) {
                Text("分享這一刻")
            }
            .buttonStyle(SkinButtonStyle(primary: false))
            .accessibilityIdentifier("levelup-share")
        } else {
            // The picture is drawn after the entrance; until then the button waits.
            Button {} label: { Text("分享這一刻") }
                .buttonStyle(SkinButtonStyle(primary: false))
                .disabled(true)
                .accessibilityIdentifier("levelup-share")
        }
    }

    /// The picture 分享這一刻 shares: the header and the app's line on the skin's page colour.
    private func render() {
        let card = VStack(spacing: 14) {
            LevelUpHeader(moment: moment)
            Text("ETF 袋著走 · 存 ETF，也存下好習慣。").skinFont(.body(13)).foregroundStyle(skin.color(\.sub))
        }
        .padding(.vertical, 32)
        .frame(width: 390)
        .background(skin.color(\.page))
        .environment(\.skin, skin)
        let renderer = ImageRenderer(content: card)
        renderer.scale = displayScale
        if let image = renderer.uiImage { shareImage = Image(uiImage: image) }
    }
}
