import SwiftUI

/// How far the card reveal has got: the card's back, its face, the reward line, then the two buttons.
enum DexRevealPhase: Int, Comparable {
    case back, face, reward, buttons
    static func < (a: DexRevealPhase, b: DexRevealPhase) -> Bool { a.rawValue < b.rawValue }
}

enum DexReveal {
    /// UI tests open on the final state; Reduce Motion skips the back and the flip.
    static func start(reduceMotion: Bool, uiTesting: Bool) -> DexRevealPhase {
        if uiTesting { return .buttons }
        return reduceMotion ? .face : .back
    }

    /// The reward line: the experience paid, or just the fact it was collected once the month's cap is spent.
    static func rewardText(_ visit: FundVisit) -> String {
        visit.cardXP > 0 ? "+\(visit.cardXP) 經驗" : "收進圖鑑"
    }

    /// What VoiceOver reads for the whole moment; with no experience paid there is no trailing reward.
    static func spoken(_ fund: Fund, visit: FundVisit) -> String {
        let head = "收進圖鑑：\(fund.id) \(fund.name)"
        return visit.cardXP > 0 ? "\(head)，\(rewardText(visit))" : head
    }
}

/// One card to reveal: the fund's code and what the visit paid.
struct DexRevealItem: Identifiable, Equatable {
    let symbol: String
    let visit: FundVisit
    var id: String { symbol }
}

/// The first 詳情 visit of a fund (spec 7): the card's back, a flip to its face, the reward, then 收下 / 看圖鑑.
struct DexRevealView: View {
    let item: DexRevealItem
    let onAccept: () -> Void
    let onOpen: () -> Void
    @EnvironmentObject private var store: PortfolioStore
    @Environment(\.skin) private var skin
    @Environment(\.motionReduced) private var reduceMotion
    @State private var phase: DexRevealPhase
    /// The catalogue's facts and unique funds, built once in `.task`.
    @State private var ranking: (facts: DexFacts, funds: [Fund])?
    @State private var angle = 0.0
    @State private var showFace: Bool
    @AccessibilityFocusState private var acceptFocused: Bool

    init(item: DexRevealItem, onAccept: @escaping () -> Void, onOpen: @escaping () -> Void) {
        self.item = item
        self.onAccept = onAccept
        self.onOpen = onOpen
        let start = DexReveal.start(reduceMotion: MotionPreference.forced || UIAccessibility.isReduceMotionEnabled,
                                    uiTesting: AmbientMotion.uiTesting)
        _phase = State(initialValue: start)
        _showFace = State(initialValue: start >= .face)
    }

    var body: some View {
        let fund = store.dexFund(item.symbol)
        VStack(spacing: 16) {
            ZStack {
                if showFace {
                    ScrollView {
                        Group {
                            if let ranking {
                                DexCard(fund: fund, facts: ranking.facts, among: ranking.funds)
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    back
                }
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(DexReveal.rewardText(item.visit))
                .skinFont(.title(20)).foregroundStyle(skin.color(\.accent))
                .opacity(phase >= .reward ? 1 : 0)
                .offset(y: phase >= .reward || reduceMotion ? 0 : 8)
                .accessibilityLabel(DexReveal.spoken(fund, visit: item.visit))
                .accessibilityIdentifier("dex-reveal-reward")
            HStack(spacing: 12) {
                Button("收下", action: onAccept)
                    .buttonStyle(SkinButtonStyle(primary: true, seed: SkinSeed.of("收下")))
                    .accessibilityFocused($acceptFocused)
                    .accessibilityIdentifier("dex-reveal-accept")
                Button("看圖鑑", action: onOpen)
                    .buttonStyle(SkinButtonStyle(primary: false, seed: SkinSeed.of("看圖鑑")))
                    .accessibilityIdentifier("dex-reveal-open")
            }
            .opacity(phase >= .buttons ? 1 : 0)
            .allowsHitTesting(phase >= .buttons)
            .accessibilityHidden(phase < .buttons)
            .padding(.bottom, 12)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(skin.color(\.page).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dex-reveal")
        .onChange(of: phase) { _, now in if now == .buttons { acceptFocused = true } }
        .task { await play() }
    }

    /// The back of the card: the skin's pattern, its badge and 「ETF 圖鑑」 in its title font.
    private var back: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(skin.color(\.card))
            SkinDecor(page: .other).clipShape(RoundedRectangle(cornerRadius: 20))
            VStack(spacing: 14) {
                SkinImage(.badge).frame(width: 120, height: 120)
                Text("ETF 圖鑑").skinFont(.title(24)).foregroundStyle(skin.color(\.ink))
            }
            RoundedRectangle(cornerRadius: 20).strokeBorder(skin.color(\.accent), lineWidth: 3)
        }
        .frame(width: 260, height: 380)
        .accessibilityHidden(true)
    }

    private func play() async {
        if ranking == nil { ranking = (store.dexFacts(), store.dexFunds) }
        if AmbientMotion.uiTesting { return }
        if reduceMotion {
            land()
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { phase = .reward }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { phase = .buttons }
            return
        }
        let motion = SkinMotion.of(skin)
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        // Edge-on, swap to the face, then turn it the rest of the way.
        withAnimation(.easeIn(duration: 0.22)) { angle = 90 }
        try? await Task.sleep(for: .milliseconds(230))
        guard !Task.isCancelled else { return }
        var swap = Transaction()
        swap.disablesAnimations = true
        withTransaction(swap) { showFace = true; angle = -90 }
        withAnimation(motion.spring) { angle = 0; phase = .face }
        land()
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        withAnimation(motion.spring) { phase = .reward }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.25)) { phase = .buttons }
    }

    /// The face landing: the skin's own sound and haptic, once.
    private func land() { ConfirmFeedback.confirm(skin) }
}
