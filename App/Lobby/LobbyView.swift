import SwiftUI

/// What the lobby's hero says (spec 4.2, 5.3; ruling R15). A running streak shows its months; a newbie, or anyone
/// whose run broke, sees a lone 1 and 「今天開始」 — never a bare 0 — and after a break also their best run.
struct LobbyHero: Equatable {
    var value: Int
    var caption: String
    var tag: String
    var record: String?
    /// VoiceOver label of the numeral.
    var label: String

    static func of(_ game: GameState, now: Date) -> LobbyHero {
        let streak = game.streak(now: now)
        if streak > 0 {
            return LobbyHero(value: streak, caption: "\(streak) 個月", tag: "連續定期定額", record: nil, label: "連續定投 \(streak) 個月")
        }
        let record = game.isNewbie ? nil : "最長紀錄 \(max(game.longestStreak, 1)) 個月"
        return LobbyHero(value: 1, caption: "第 1 個月", tag: "今天開始", record: record,
                         label: ["第 1 個月，今天開始", record].compactMap { $0 }.joined(separator: "，"))
    }
}

/// The navigation root (spec 4.2): level, experience, coins and the achievements target along the top; the four
/// feature objects around the streak numeral; this month's quests; 「→ 點物件進入 ←」. The skin's decoration lives
/// only in the numeral's zone.
struct LobbyView: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.skin) private var skin
    @Environment(\.lobbyNavigation) private var navigation
    @Environment(\.lobbyNamespace) private var namespace
    @ObservedObject private var membership = MembershipStore.shared
    /// The month (「2026-10」) whose 口袋月報 the lobby last announced; each month is announced once.
    @AppStorage(ReportSettings.seenMonthKey) private var reportSeenMonth = ""
    /// 「上個月的口袋月報出爐了」 is on screen: from the moment it is due until it is opened or the app is closed.
    @State private var reportNotice = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.motionReduced) private var reduceMotion
    @ObservedObject private var power = PowerState.shared
    /// The lobby is on screen (not under a pushed feature).
    @State private var onScreen = false
    /// The opening has played (spec 5.1); false at launch until it plays, unless it is skipped.
    @State private var opened = LobbyOpening.skippedAtLaunch
    /// The app went to the background: the next time the lobby is seen, the opening plays again.
    @State private var opensAgain = false
    /// Taps on each object, to play its ring.
    @State private var taps: [Feature: Int] = [:]

    /// UI tests and screenshots never see the notice: the lobby they check stays as it was.
    private static let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")

    /// Ambient motion (spec 5.1, 6): only while the lobby is on screen, the app is in front, and nothing argues against
    /// it (Reduce Motion, Low Power Mode, `--ui-testing`).
    private var ambient: Bool {
        AmbientMotion.allowed(reduceMotion: reduceMotion, lowPower: power.lowPower, uiTesting: AmbientMotion.uiTesting,
                              onScreen: onScreen, active: scenePhase == .active)
    }

    var body: some View {
        let game = store.data.game ?? GameState(), now = Date()
        let hero = LobbyHero.of(game, now: now)
        let ambient = self.ambient
        ScrollView {
            VStack(spacing: 10) {
                topBar(game, ambient: ambient)
                Text("\(skin.code) · \(skin.name)").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .top) { entry(.find, ambient: ambient); Spacer(); entry(.dividends, ambient: ambient) }
                HeroNumber(value: hero.value, caption: hero.caption, label: hero.label, action: { navigation.push(.dcaHistory) }, ambient: ambient)
                    // The opening: the numeral drops into place.
                    .offset(y: opened ? 0 : -36)
                    .opacity(opened ? 1 : 0)
                    .animation(LobbyOpening.animation(skin, delay: LobbyOpening.numeralDelay), value: opened)
                    .background(alignment: .top) {
                        ZStack {
                            SkinDecor(page: .lobby, drifts: ambient).padding(.horizontal, -20)
                            // Specks rising from around the numeral.
                            AmbientParticles(enabled: ambient).frame(width: 260)
                        }
                        .frame(height: HeroNumber.numeralHeight)
                    }
                VStack(spacing: 6) {
                    SkinTag(hero.tag)
                    if let record = hero.record { Text(record).skinFont(.mono(12)).skinForeground(\.sub) }
                }
                HStack(alignment: .top) { entry(.pocket, ambient: ambient); Spacer(); entry(.tools, ambient: ambient) }
                if reportNotice, membership.has(.report) { reportNoticeCard }
                questCard(game, month: YearMonth(now), ambient: ambient)
                Text("→ 點物件進入 ←").skinFont(.mono(11)).skinForeground(\.dim).padding(.top, 4)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .modifier(FadeInWithReducedMotion())
        .background(skin.color(\.page).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        // Decided each time the lobby comes up, and again once StoreKit has said whether this is a member.
        .task(id: membership.has(.report)) { announceReport(now: Date()) }
        .onAppear { onScreen = true; playOpening() }
        .onDisappear { onScreen = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { opensAgain = true } else if phase == .active, onScreen { playOpening() }
        }
    }

    // MARK: Opening

    /// Plays the opening when it is due: the first time the lobby is seen after launch, and the first time after the
    /// app was in the background. Reduce Motion and `--ui-testing` go straight to the final state.
    private func playOpening() {
        guard !opened || opensAgain else { return }
        opensAgain = false
        var still = Transaction(); still.disablesAnimations = true
        guard !reduceMotion, !AmbientMotion.uiTesting else {
            withTransaction(still) { opened = true }
            return
        }
        // Hidden at once (already so at launch; back from the background they were showing), then popped in on the
        // next turn of the run loop, so the change is a fresh animated one.
        withTransaction(still) { opened = false }
        DispatchQueue.main.async { opened = true }
    }

    // MARK: 口袋月報 notice

    /// Shows the notice when last month's report has not been announced yet (members whose records reach back to
    /// that month), and records the month at once, so it is announced a single time.
    private func announceReport(now: Date) {
        guard !Self.testing, PocketReport.noticeDue(now: now, seen: reportSeenMonth, isMember: membership.has(.report), portfolio: store.data) else { return }
        reportSeenMonth = PocketReport.noticeMonth(now: now).key
        reportNotice = true
    }

    private var reportNoticeCard: some View {
        Button {
            reportNotice = false
            navigation.push(.report)
        } label: {
            SkinCard {
                HStack(spacing: 10) {
                    MemberCrown().frame(width: 22, height: 22)
                    Text("上個月的口袋月報出爐了").skinFont(.title(14)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Text("看看 ›").skinFont(.mono(12)).skinForeground(\.sub)
                }
                .frame(minHeight: 28)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("上個月的口袋月報出爐了，打開看看")
        .accessibilityIdentifier("lobby-report-notice")
    }

    // MARK: Top bar

    private func topBar(_ game: GameState, ambient: Bool) -> some View {
        let level = GameRules.level(xp: game.xp), progress = GameRules.progress(xp: game.xp)
        let fraction = CGFloat(progress.into) / CGFloat(max(progress.needed, 1))
        return HStack(spacing: 8) {
            Text("LV.\(level)").skinFont(.big(13))
                .foregroundStyle(skin.onFill(skin.colors.accent))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: skin.style.button == .pixelBlock ? 0 : 6).fill(skin.color(\.accent)))
                .accessibilityLabel("等級 \(level)")
            Capsule().fill(skin.color(\.line))
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule().fill(skin.color(\.ink))
                            // A highlight runs along the fill.
                            .overlay { BarShine(enabled: ambient, color: skin.lightText ? skin.color(\.accent) : .white) }
                            .clipShape(Capsule())
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(width: 92, height: 6)
                .accessibilityElement()
                .accessibilityLabel("經驗")
                .accessibilityValue("\(game.xp) 經驗")
                .accessibilityIdentifier("lobby-xp")
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                Circle().fill(skin.color(\.accent)).overlay(Circle().strokeBorder(skin.color(\.line), lineWidth: 3)).frame(width: 14, height: 14)
                Text(game.coins.formatted()).skinFont(.mono(12)).skinForeground(\.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("金幣 \(game.coins)")
            Button { navigation.open(.achievements) } label: {
                SkinImage(.achievements).frame(width: 40, height: 40).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .modifier(ZoomSource(feature: .achievements, namespace: namespace))
            .accessibilityLabel("成就")
            .accessibilityIdentifier("lobby-achievements")
        }
    }

    // MARK: Entries

    /// A lobby object: it bobs and does its signature move while `ambient` (spec 5.1); a tap squashes it, spreads a
    /// ring and plays the skin's confirm, and opens the feature in the same tap (5.2).
    private func entry(_ feature: Feature, ambient: Bool) -> some View {
        Button {
            taps[feature, default: 0] += 1
            ConfirmFeedback.confirm(skin)
            navigation.open(feature)
        } label: {
            VStack(spacing: 6) {
                SkinImage(feature.art).frame(width: 76, height: 76)
                    .signatureMove(feature, enabled: ambient)
                    .ambientBob(phase: LobbySignature.phase(feature), enabled: ambient)
                    .overlay { RingBurst(trigger: taps[feature] ?? 0, color: skin.color(\.accent)).frame(width: 150, height: 150) }
                SkinTag(feature.title)
            }
            .frame(minWidth: 96)
            .contentShape(Rectangle())
            // The opening: the objects pop in one after another.
            .scaleEffect(opened ? 1 : 0.4)
            .opacity(opened ? 1 : 0)
            .animation(LobbyOpening.animation(skin, delay: LobbyOpening.delay(feature)), value: opened)
        }
        .buttonStyle(PressableStyle())
        .modifier(ZoomSource(feature: feature, namespace: namespace))
        .accessibilityLabel(feature.title)
        .accessibilityIdentifier("lobby-\(feature.rawValue)")
    }

    // MARK: Quests

    private func questCard(_ game: GameState, month: YearMonth, ambient: Bool) -> some View {
        let quests = Quests.forMonth(month, habit: game.habit ?? .dca, isNewbie: game.isNewbie)
        let done = quests.filter { game.isDone($0, in: month) }.count
        let reward = quests.count * (GameRules.xp[.questDone] ?? 0)
        let rows = ForEach(quests) { quest in
            HStack(spacing: 7) {
                SkinCheck(done: game.isDone(quest, in: month), size: 18)
                Text(quest.title).skinFont(.body(12)).fixedSize(horizontal: false, vertical: true)
            }
        }
        return SkinCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("本月任務 \(done)/\(quests.count)")
                    Spacer()
                    // The reward not yet earned breathes (spec 5.1).
                    Text("+\(reward) XP").foregroundStyle(skin.color(skin.lightText ? \.accent : \.ink))
                        .breathes(ambient && done < quests.count, anchor: .trailing)
                }
                .skinFont(.mono(11)).skinForeground(\.sub)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { rows }
                    VStack(alignment: .leading, spacing: 8) { rows }
                }
            }
        }
    }
}

/// Marks a lobby object as the source the feature screen zooms out of.
struct ZoomSource: ViewModifier {
    let feature: Feature
    let namespace: Namespace.ID?
    @ViewBuilder func body(content: Content) -> some View {
        if let namespace { content.matchedTransitionSource(id: feature, in: namespace) } else { content }
    }
}
