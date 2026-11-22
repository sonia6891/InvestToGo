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
    /// The object the viewer just came back from, while it gives its one small bounce.
    @State private var bouncing: Feature?
    /// LEVEL×UP covers the lobby (a full-screen cover from the root view: no `onDisappear` here).
    @Environment(\.lobbyCovered) private var covered
    /// LEVEL×UP is up or about to come up (and, later, any other prompt from the root view): 記一筆 waits for it.
    @Environment(\.lobbyModalPending) private var modalPending
    /// A tapped debit-day reminder asks for 記一筆 here.
    @ObservedObject private var router = AppRouter.shared
    @Environment(\.celebrateIfDue) private var celebrateIfDue
    @Environment(\.returningFrom) private var returningFrom
    /// The replay of what was earned since the lobby was last seen (spec 5.3).
    @StateObject private var replayer = LobbyReplayPlayer()
    /// Where the replay's coins fly from and to, in the lobby's own coordinates.
    @State private var spots: [ReplaySpot: CGRect] = [:]
    /// 記一筆 is up (`quickDCA`) or still closing (`sheetUp`): the replay waits until it is gone, never plays under it.
    @State private var quickDCA = false
    @State private var sheetUp = false
    /// The quests that were ticked when 記一筆 opened: nothing new ticks until the replay, after the sheet has gone.
    @State private var ticksAtOpen: Set<String> = []
    private let shownStore = LobbyShownStore()
    private static let space = "lobby-replay"

    /// UI tests and screenshots never see the notice: the lobby they check stays as it was.
    private static let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")

    /// Ambient motion (spec 5.1, 6): only while the lobby is on screen, the app is in front, and nothing argues against
    /// it (Reduce Motion, Low Power Mode, `--ui-testing`).
    private var ambient: Bool {
        AmbientMotion.allowed(reduceMotion: reduceMotion, lowPower: power.lowPower, uiTesting: AmbientMotion.uiTesting,
                              onScreen: onScreen && !covered, active: scenePhase == .active)
    }

    var body: some View {
        let game = store.data.game ?? GameState(), now = Date()
        let hero = LobbyHero.of(game, now: now)
        let ambient = self.ambient
        ScrollView {
            VStack(spacing: 10) {
                topBar(game, ambient: ambient)
                // 口袋會員前 7 天全開: on every day of the 7, at the top, so everyone knows (nothing outside them).
                MemberOpenBanner()
                Text("\(skin.code) · \(skin.name)").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .top) { entry(.find, ambient: ambient); Spacer(); entry(.dividends, ambient: ambient) }
                HeroNumber(value: hero.value, caption: hero.caption, label: hero.label, action: { navigation.push(.dcaHistory) }, ambient: ambient)
                    .marksSpot(in: Self.space) { spots[.numeral] = $0 }
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
            .overlay { replayOverlay }
            .coordinateSpace(.named(Self.space))
        }
        .scrollBounceBehavior(.basedOnSize)
        // A tap anywhere during the replay jumps to the final numbers; the tap itself still does what it does.
        .simultaneousGesture(TapGesture().onEnded { replayer.cancel() }, including: replayer.playing ? .all : .subviews)
        .modifier(FadeInWithReducedMotion())
        .background(skin.color(\.page).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        // 口袋會員前 7 天全開's notes, each once, only while the lobby is in front with nothing over it or about to be.
        .modifier(MemberOpenNotes(ready: onScreen && !covered && !replayer.playing && game.levelUpDue == nil && !store.recordsLocked))
        // Decided each time the lobby comes up, and again once StoreKit has said whether this is a member.
        .task(id: membership.has(.report)) { announceReport(now: Date()) }
        .onAppear {
            onScreen = true
            let opening = (!opened || opensAgain) && !reduceMotion && !AmbientMotion.uiTesting
            playOpening()
            if !opening { bounceReturning() }
            arrive(lead: opening ? 0.5 : 0.15)
            // A lobby that comes up without its sheet (rebuilt for a new skin, say) has no 記一筆 on screen.
            if !sheetUp { router.quickDCAClosed() }
            presentQuickDCA()
        }
        // A waiting request opens as soon as the lobby is free: asked for, the records read, a replay or a prompt over.
        .onChange(of: router.quickDCARequested) { _, _ in presentQuickDCA() }
        .onChange(of: store.recordsLocked) { _, _ in presentQuickDCA() }
        .onChange(of: replayer.playing) { _, playing in if !playing { presentQuickDCA() } }
        .onChange(of: modalPending) { _, pending in if !pending { presentQuickDCAAfterCover() } }
        .onDisappear { onScreen = false; replayer.cancel(); ReviewPrompt.shared.release("replay") }
        // App Store 評分視窗: never over the lobby's replay (coins flying, the bar filling).
        .onChange(of: replayer.playing, initial: true) { _, playing in ReviewPrompt.shared.hold("replay", while: playing) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { opensAgain = true } else if phase == .active, onScreen { playOpening() }
        }
        // Earned while the lobby is in front (or the records were read late): replayed there and then.
        .onChange(of: LobbySnapshot.of(game, records: store.data, now: now)) { _, _ in arrive(lead: 0.15) }
        .onChange(of: covered) { _, isCovered in
            if isCovered { replayer.coverOpened() } else { replayer.coverClosed(); arrive(lead: 0.15); presentQuickDCAAfterCover() }
        }
        // 記一筆: what it earns is replayed once the sheet has gone (spec 3.2), never under it. A LEVEL×UP held while it
        // was up follows the replay (or comes at once, with nothing to replay).
        .sheet(isPresented: $quickDCA, onDismiss: { sheetUp = false; router.quickDCAClosed(); arrive(lead: 0.15); presentQuickDCA() }) {
            QuickDCASheet { quickDCA = false }
        }
    }

    /// The lobby can take 記一筆 now (`QuickDCARoute.lobbyFree`).
    private var lobbyFree: Bool {
        QuickDCARoute.lobbyFree(onScreen: onScreen, covered: covered, modalPending: modalPending, replaying: replayer.playing,
                                closing: sheetUp && !quickDCA)
    }

    /// The one way 記一筆 opens, for the lobby's button and a tapped reminder alike (final review I2): a request
    /// (`router.quickDCARequested`) opens the sheet once the lobby is free (`lobbyFree`), so it is never up together
    /// with LEVEL×UP or a replay, then the request is cleared. While the records are locked the request waits, and the
    /// sheet opens once they are read (`onChange(of: store.recordsLocked)`): never records over the lock. Nothing is
    /// saved by this; the person still taps 「記好了」.
    private func presentQuickDCA() {
        guard router.quickDCARequested else { return }
        switch QuickDCARoute.decide(locked: store.recordsLocked, showing: quickDCA, free: lobbyFree) {
        case .wait: return
        case .drop: router.quickDCARequested = false
        case .open:
            router.quickDCARequested = false
            let game = store.data.game ?? GameState(), month = YearMonth(Date())
            ticksAtOpen = Set(Quests.forMonth(month, habit: game.habit ?? .dca, isNewbie: game.isNewbie)
                .filter { game.isDone($0, in: month, records: store.data) }.map(\.id))
            quickDCA = true; sheetUp = true
            router.quickDCAOpened()
        }
    }

    /// Once a cover over the lobby has finished going away: a sheet asked for in the middle of it may not come up.
    private func presentQuickDCAAfterCover() {
        guard router.quickDCARequested else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { presentQuickDCA() }
    }

    /// Back from a feature: its object swells once and settles, as the coins start to fly from it. Still under Reduce
    /// Motion and `--ui-testing`.
    private func bounceReturning() {
        guard let feature = returningFrom, !reduceMotion, !AmbientMotion.uiTesting else { return }
        bouncing = feature
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { bouncing = nil }
    }

    // MARK: Replay (spec 5.3, 5.4)

    /// The lobby comes on screen: what grew since it was last seen is replayed, and what it shows now is remembered at
    /// once. Nothing to replay: LEVEL×UP right away, if one is due. Reduce Motion and `--ui-testing` show the final
    /// numbers at once and go straight to LEVEL×UP.
    private func arrive(lead: Double) {
        guard onScreen, !covered, !quickDCA, !sheetUp, !replayer.playing, !store.recordsLocked else { return }
        let game = store.data.game ?? GameState(), date = Date()
        let order = Quests.forMonth(YearMonth(date), habit: game.habit ?? .dca, isNewbie: game.isNewbie).map(\.id)
        let snapshot = LobbySnapshot.of(game, records: store.data, now: date)
        let shown = shownStore.load()
        let replay = LobbyReplay.arrival(shown: shown, now: snapshot, questOrder: order, levelUpDue: game.levelUpDue, celebratedLevel: game.celebratedLevel)
        shownStore.save(snapshot)
        guard let replay, !reduceMotion, !AmbientMotion.uiTesting else {
            // Once the zoom back to the lobby has settled: a cover asked for in the middle of it may not come up.
            // A replay that started meanwhile ends in its own celebrate: not two big events at once.
            let celebrate = celebrateIfDue, replayer = replayer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { if !replayer.playing { celebrate() } }
            return
        }
        replayer.play(replay, lead: lead, skin: skin, celebrate: celebrateIfDue)
    }

    /// The coins flying and 「+N XP」 floating, drawn over the lobby in its own coordinates.
    private var replayOverlay: some View {
        ZStack {
            if let start = replayer.flight, let to = spots[.coins], let from = flightOrigin {
                ReplayCoinFlight(start: start, from: from, to: CGPoint(x: to.minX + 7, y: to.midY))
            }
            if let float = replayer.xpFloat, let bar = spots[.bar] {
                ReplayXPFloat(float: float, at: CGPoint(x: bar.midX, y: bar.maxY + 12))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The object just left, or the numeral when none was (launch, or a page pushed from the lobby itself).
    private var flightOrigin: CGPoint? {
        if let feature = returningFrom, let rect = spots[.feature(feature)] { return CGPoint(x: rect.midX, y: rect.midY) }
        guard let numeral = spots[.numeral] else { return nil }
        return CGPoint(x: numeral.midX, y: numeral.minY + HeroNumber.numeralHeight / 2)
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
        // While a replay plays, the bar, the level and the coins show its numbers; VoiceOver always hears the saved ones.
        let level = GameRules.level(xp: game.xp), display = replayer.display
        let fraction = CGFloat(display?.fraction ?? LobbyReplayPlayer.fraction(xp: game.xp))
        let coins = display?.coins ?? game.coins
        return HStack(spacing: 8) {
            Text("LV.\(display?.level ?? level)").skinFont(.big(13))
                .contentTransition(.numericText())
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
                // The full bar's flash before LEVEL×UP.
                .overlay {
                    Capsule().fill(Color.white).opacity(replayer.flashing ? 0.9 : 0)
                        .shadow(color: skin.color(\.accent), radius: replayer.flashing ? 6 : 0)
                        .allowsHitTesting(false)
                }
                .frame(width: 92, height: 6)
                .scaleEffect(y: replayer.flashing ? 1.6 : 1)
                .marksSpot(in: Self.space) { spots[.bar] = $0 }
                .accessibilityElement()
                .accessibilityLabel("經驗")
                .accessibilityValue("\(game.xp) 經驗")
                .accessibilityIdentifier("lobby-xp")
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                Circle().fill(skin.color(\.accent)).overlay(Circle().strokeBorder(skin.color(\.line), lineWidth: 3)).frame(width: 14, height: 14)
                Text(coins.formatted()).skinFont(.mono(12)).skinForeground(\.ink)
                    .contentTransition(.numericText(value: Double(coins)))
            }
            .marksSpot(in: Self.space) { spots[.coins] = $0 }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("金幣 \(game.coins)")
            Button { navigation.open(.achievements) } label: {
                SkinImage(.achievements).frame(width: 40, height: 40).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .modifier(ZoomSource(feature: .achievements, namespace: namespace))
            .marksSpot(in: Self.space) { spots[.feature(.achievements)] = $0 }
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
        .scaleEffect(bouncing == feature ? 1.12 : 1)
        .animation(SkinMotion.of(skin).spring, value: bouncing)
        .modifier(ZoomSource(feature: feature, namespace: namespace))
        .marksSpot(in: Self.space) { spots[.feature(feature)] = $0 }
        .accessibilityLabel(feature.title)
        .accessibilityIdentifier("lobby-\(feature.rawValue)")
    }

    // MARK: Quests

    private func questCard(_ game: GameState, month: YearMonth, ambient: Bool) -> some View {
        let quests = Quests.forMonth(month, habit: game.habit ?? .dca, isNewbie: game.isNewbie)
        // A quest done elsewhere ticks when the replay reaches it.
        let unticked = replayer.display?.unticked ?? []
        let holdsTicks = quickDCA || sheetUp
        let shownDone = { (quest: Quest) in
            game.isDone(quest, in: month, records: store.data) && !unticked.contains(quest.id) && (!holdsTicks || ticksAtOpen.contains(quest.id))
        }
        let done = quests.filter(shownDone).count
        let finalDone = quests.filter { game.isDone($0, in: month, records: store.data) }.count
        let reward = quests.count * (GameRules.xp[.questDone] ?? 0)
        let confetti = skin.burst.map { Color(rgb: $0) }
        // 記一筆 sits at the end of the DCA row until this month's DCA is on record.
        func rows(stretch: Bool) -> some View {
            ForEach(quests) { quest in
                HStack(spacing: 7) {
                    SkinCheck(done: shownDone(quest), size: 18)
                        // VoiceOver reads the real state, not the replay's in-between one (spec 6).
                        .accessibilityLabel(game.isDone(quest, in: month, records: store.data) ? "已完成" : "未完成")
                        .scaleEffect(replayer.popping == quest.id ? 1.4 : 1)
                        .overlay { BurstView(trigger: replayer.confetti[quest.id] ?? 0, center: .center, colors: confetti).frame(width: 64, height: 64) }
                    Text(quest.title).skinFont(.body(12)).fixedSize(horizontal: false, vertical: true)
                    if quest.trigger == .dcaLogged, !game.isDone(quest, in: month, records: store.data), !store.recordsLocked {
                        if stretch { Spacer(minLength: 8) }
                        Button {
                            // As any tap during the replay does: the final numbers at once, then the sheet.
                            replayer.cancel()
                            router.quickDCARequested = true
                            presentQuickDCA()
                        } label: {
                            SkinTag("記一筆").padding(.vertical, 6).contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("記一筆本月定投")
                        .accessibilityIdentifier("lobby-quick-dca")
                    }
                }
            }
        }
        return SkinCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("本月任務 \(done)/\(quests.count)")
                        .contentTransition(.numericText(value: Double(done)))
                        .accessibilityLabel("本月任務 \(finalDone)/\(quests.count)")
                        .scaleEffect(replayer.popping != nil ? 1.12 : 1, anchor: .leading)
                    Spacer()
                    // The reward not yet earned breathes (spec 5.1).
                    Text("+\(reward) XP").foregroundStyle(skin.color(skin.lightText ? \.accent : \.ink))
                        .breathes(ambient && done < quests.count, anchor: .trailing)
                }
                .skinFont(.mono(11)).skinForeground(\.sub)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { rows(stretch: false) }
                    VStack(alignment: .leading, spacing: 8) { rows(stretch: true) }
                }
            }
        }
    }
}

/// The places on the lobby the replay's coins and 「+N XP」 come from and go to.
enum ReplaySpot: Hashable {
    case feature(Feature), numeral, coins, bar
}

extension View {
    /// Reports this view's frame in the named coordinate space whenever it changes (the lobby's replay spots).
    func marksSpot(in space: String, _ report: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(space)) }, action: report)
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
