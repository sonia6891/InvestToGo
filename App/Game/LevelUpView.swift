import SwiftUI

/// One LEVEL×UP to show: the level reached, why, and what came with it.
struct LevelUpMoment: Identifiable, Equatable {
    /// The level celebrated before this one: the numeral rolls up from here.
    let from: Int
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
            list.append("解鎖「\(now.1)」外觀主題")
        } else if let next = levelSkins.filter({ $0.0 > level }).min(by: { $0.0 < $1.0 }) {
            list.append("LV.\(next.0) 解鎖「\(next.1)」外觀主題，還差 \(next.0 - level) 級")
        }
        return list
    }

    /// Where the numeral starts: the last celebrated level, but never above `level - 1` and never below 1 (a save with
    /// no usable celebrated level rolls from `level - 1`).
    static func from(celebrated: Int, level: Int) -> Int { min(max(celebrated, 1), max(level - 1, 1)) }

    /// Built before 收下 marks the level celebrated, so `game.celebratedLevel` is still the previous one.
    static func moment(_ game: GameState, level: Int, now: Date) -> LevelUpMoment {
        LevelUpMoment(from: from(celebrated: game.celebratedLevel, level: level), level: level,
                      reason: reason(game, now: now), rewards: rewards(game, level: level))
    }
}

/// The stage, LEVEL×UP, the level and the reason; shared by the screen and the picture it shares.
struct LevelUpHeader: View {
    let moment: LevelUpMoment
    var appeared = true
    /// The numeral on show while it rolls; the accessibility label always reads the final level.
    var shownLevel: Int?
    /// A short swell as the numeral lands.
    var swell = false
    @Environment(\.skin) private var skin
    @Environment(\.motionReduced) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            SkinStage(size: 200) { SkinImage(.dividends).padding(36) }
                .background { SkinDecor(page: .splash).frame(width: 390, height: 280).allowsHitTesting(false) }
                .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)
                .padding(.bottom, 18)
            Text("LEVEL×UP").skinFont(.mono(13)).tracking(3).foregroundStyle(skin.color(\.sub))
            Text("LV.\(shownLevel ?? moment.level)").skinFont(.big(72)).foregroundStyle(skin.color(\.ink))
                .lineLimit(1).minimumScaleFactor(0.5)
                .contentTransition(.numericText(countsDown: false))
                .scaleEffect(swell && !reduceMotion ? 1.18 : 1)
                .accessibilityLabel("LV.\(moment.level)")
                .accessibilityIdentifier("levelup-level")
            SkinTag(moment.reason)
        }
    }
}

/// Rays behind the stage, turning slowly and faded toward the edge. Still, not absent, when motion is off.
private struct LevelUpRays: View {
    var spinning: Bool
    @Environment(\.skin) private var skin

    var body: some View {
        let motion = SkinMotion.of(skin)
        let tint = skin.color(\.accent)
        TimelineView(.animation(paused: !spinning)) { timeline in
            Canvas { context, size in
                let t = spinning ? timeline.date.timeIntervalSinceReferenceDate : 0
                let turn = (motion.stepped ? (t * 8).rounded(.down) / 8 : t) * 0.15
                let c = CGPoint(x: size.width / 2, y: size.height / 2), r = max(size.width, size.height)
                let rays = 16
                for i in 0..<rays {
                    let a = turn + Double(i) / Double(rays) * 2 * .pi, w = .pi / Double(rays) * 0.6
                    var path = Path()
                    path.move(to: c)
                    path.addLine(to: CGPoint(x: c.x + cos(a - w) * r, y: c.y + sin(a - w) * r))
                    path.addLine(to: CGPoint(x: c.x + cos(a + w) * r, y: c.y + sin(a + w) * r))
                    path.closeSubpath()
                    context.fill(path, with: .color(tint.opacity(0.2)))
                }
            }
        }
        .mask(RadialGradient(colors: [.black, .clear], center: .center, startRadius: 30, endRadius: 190))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 升級 (spec 5.12), shown once over everything by the root view when experience crosses a whole level.
struct LevelUpView: View {
    let moment: LevelUpMoment
    let onAccept: () -> Void
    @Environment(\.skin) private var skin
    @Environment(\.motionReduced) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var appeared = false
    @State private var bursts = 0
    @State private var shown: Int
    @State private var revealed: Int
    @State private var swell = false
    @State private var shareImage: Image?

    init(moment: LevelUpMoment, onAccept: @escaping () -> Void) {
        self.moment = moment
        self.onAccept = onAccept
        // UI tests and screenshots open on the final state; otherwise the numeral rolls up from the last level.
        let final = AmbientMotion.uiTesting
        _shown = State(initialValue: final ? moment.level : moment.from)
        _revealed = State(initialValue: final ? moment.rewards.count : 0)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                LevelUpHeader(moment: moment, appeared: appeared, shownLevel: shown, swell: swell)
                    .background(alignment: .top) {
                        LevelUpRays(spinning: !reduceMotion && !AmbientMotion.uiTesting)
                            .frame(width: 380, height: 380).offset(y: -80).opacity(appeared ? 1 : 0)
                    }
                SkinCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("獎勵").skinFont(.mono(11)).foregroundStyle(skin.color(\.sub))
                        ForEach(Array(moment.rewards.enumerated()), id: \.offset) { index, reward in
                            HStack(spacing: 8) {
                                SkinCheck(done: true, size: 18).accessibilityHidden(true)
                                Text(reward).skinFont(.body(14)).fixedSize(horizontal: false, vertical: true)
                            }
                            .opacity(index < revealed ? 1 : 0)
                            .offset(y: index < revealed || reduceMotion ? 0 : 10)
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
            BurstView(trigger: bursts, center: .center, colors: skin.burst.map { Color(rgb: $0) })
                .frame(width: 360, height: 260).padding(.top, 40)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        // Drawn once the entrance has settled, so rendering never stalls the animation.
        .task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            render()
        }
        // The moment itself: the numeral rolls up, lands with a burst, a heavy haptic and the skin's sound (once), then
        // what it unlocked appears one by one. Reduce Motion: final numbers, the rewards fading in.
        .task { await play() }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.45, dampingFraction: 0.6)) { appeared = true }
            AccessibilityNotification.Announcement("升到等級 \(moment.level)，\(moment.reason)").post()
        }
    }

    private func play() async {
        let motion = SkinMotion.of(skin)
        if AmbientMotion.uiTesting {
            land(burst: false)
            return
        }
        if reduceMotion {
            shown = moment.level
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            land(burst: false)
            withAnimation(.easeOut(duration: 0.3)) { revealed = moment.rewards.count }
            return
        }
        try? await Task.sleep(for: .milliseconds(450))
        let steps = max(moment.level - moment.from, 0)
        let gap = steps > 0 ? min(0.32, 1.4 / Double(steps)) : 0
        if steps > 0 {
            for level in (moment.from + 1)...moment.level {
                guard !Task.isCancelled else { return }
                withAnimation(motion.stepped ? .linear(duration: 0.05) : .snappy(duration: min(0.25, gap))) { shown = level }
                SoundFX.tick(enabled: SkinStore.shared.soundOn)
                try? await Task.sleep(for: .milliseconds(Int(gap * 1000)))
            }
        }
        guard !Task.isCancelled else { return }
        shown = moment.level
        land(burst: true)
        withAnimation(motion.spring) { swell = true }
        try? await Task.sleep(for: .milliseconds(220))
        withAnimation(motion.spring) { swell = false }
        for index in 0..<moment.rewards.count {
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }
            withAnimation(motion.spring) { revealed = index + 1 }
        }
    }

    /// The landing: a heavy haptic and the skin's own sound, once.
    private func land(burst: Bool) {
        if burst { bursts += 1 }
        Haptics.confirm(.heavy)
        SoundFX.confirm(skin, enabled: SkinStore.shared.soundOn)
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
