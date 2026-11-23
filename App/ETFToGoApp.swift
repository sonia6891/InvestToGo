import SwiftUI
import UserNotifications

@main struct ETFToGoApp: App {
    @StateObject private var store: PortfolioStore
    @AppStorage("appearance") private var appearance = "light"
    /// The skin decides light or dark text; every screen redraws when it changes.
    @ObservedObject private var skins = SkinStore.shared
    init() {
        // Sentry (Task 14): off without a DSN (Debug, CI), with --ui-testing and under XCTest.
        CrashReporting.start()
        // App Store 評分視窗: made at launch, so it follows the keyboard from the start (it never asks over one).
        _ = ReviewPrompt.shared
        let args = ProcessInfo.processInfo.arguments
        let testing = args.contains("--ui-testing")
        let testURL = testing ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ETFToGo/ui-test.json") : nil
        // `--reset` wipes the records only in UI tests: a stale scheme argument never empties the real file.
        let store = PortfolioStore(url: testURL, reset: testing && args.contains("--reset"))
        // Nothing is written from records that are locked or failed to read (a damaged file): the widget keeps its streak.
        WidgetSync.shared.locked = WidgetSync.locked(by: store)
        store.onCommit = { WidgetSync.shared.sync($0) }
        Onboarding.reset(args)
        ReportSettings.reset(args)
        LobbyShownStore.reset(args)
        BacktestSettings.reset(args)
        // Someone upgrading with records on the phone has started already: no first-launch flow for them.
        Onboarding.adoptExisting(store.data)
        // One-time migrations of the game progress: DCA months backfilled from the records, with no experience.
        try? store.updateGame { $0.migrate(store.data) }
        // UI tests and screenshots set up game progress with `--demo-…` (only with `--ui-testing`).
        try? store.updateGame { DemoArguments.apply(to: &$0, args: args, now: Date()) }
        DemoArguments.seedPocket(store, args: args, now: Date())
        DemoArguments.seedHeld(store, args: args)
        DemoArguments.seedActive(store, args: args)
        DemoArguments.seedStore(store, args: args, now: Date())
        // `--ui-testing --open quickDCA`: as if the debit-day reminder had just been tapped (also beside `--open levelup`).
        if testing, args.indices.contains(where: { args[$0] == "--open" && args.indices.contains($0 + 1) && args[$0 + 1] == "quickDCA" }) {
            AppRouter.shared.quickDCARequested = true
        }
        _store = StateObject(wrappedValue: store)
        // A launch in the background on a locked phone reads the records later; the two steps above are then redone.
        // The worn skin was not judged while they were locked (the level read 1): it is now.
        store.onRecordsRead = { store in
            Onboarding.adoptExisting(store.data)
            try? store.updateGame { $0.migrate(store.data) }
            MembershipStore.shared.recordsRead()
        }
        // 到價提醒: iOS wants the background task's handler before launch ends. Nothing is registered in UI tests.
        PriceAlertMonitor.start(store, testing: testing)
        // Banners over the open app, and a tapped reminder opening 記一筆: also in UI tests.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        // StoreKit is followed from launch (Apple asks for the Transaction.updates listener then), so renewals and Ask
        // to Buy answers that arrive during the splash or onboarding are not missed. Once StoreKit has answered, a skin
        // the player may no longer wear is taken off, with a notice.
        let membership = MembershipStore.shared
        membership.level = { [weak store] in GameRules.level(xp: store?.data.game?.xp ?? 0) }
        membership.achievements = { [weak store] in Set((store?.data.game?.unlocked ?? [:]).keys) }
        membership.recordsLocked = { [weak store] in store?.recordsLocked ?? false }
        membership.onLapse = { [weak store] notice in store?.pendingNotice = notice }
        Task { await membership.start() }
    }
    var body: some Scene {
        WindowGroup {
            LaunchGate().environmentObject(store)
                // The skin kit's components read the current skin from here.
                .environment(\.skin, skins.skin)
                .preferredColorScheme(skins.colorScheme)
        }
    }
}
/// The first launch goes splash → onboarding → lobby (spec 5.1, 5.2); every later launch opens on the lobby. Every cold
/// launch first plays the opening (2026-11-21 design): on the first launch it is the splash itself, on later ones it
/// stands in front of the lobby until it ends or is skipped. Coming back from the background never replays it.
///
/// App 上鎖 (2026-11-22 design) comes after the opening: with the lock on, the opening goes on to the lock screen, and
/// the lobby is built only once it is passed. Onboarding is never locked. The lock screen and the privacy cover are in
/// `LockWindow`, above the app's window; the scene's phases reach `AppLock` from here.
struct LaunchGate: View {
    @AppStorage(Onboarding.doneKey) private var onboarded = false
    @Environment(\.motionReduced) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @ObservedObject private var lock = AppLock.shared
    /// Decided once per launch, so finishing the flow is what leaves it (also when a screenshot forced it open).
    @State private var start: OnboardingStart?
    /// How the opening plays at this launch, decided once with `start`.
    @State private var play: OpeningPlay
    /// A later launch's opening is in front of the lobby. The lobby is built only once it has gone, so its entrance and
    /// LEVEL×UP are never spent behind the opening.
    @State private var opening: Bool
    /// The first launch's splash has gone (the onboarding pages are showing).
    @State private var pastSplash = false

    /// 產品工作站 (2026-11-22 design): the app is in front, past the opening (the splash on the first launch) and the
    /// lock screen. Each time this turns true the day's anonymous open is reported (`UsageStats`), at most once a day.
    private var usageReady: Bool {
        guard phase == .active, !opening, !lock.locked else { return false }
        return start == nil ? lock.lobbyReleased : pastSplash
    }

    /// App Store 評分視窗: the app is in front past the opening, onboarding and the lock (and its cover). Each time this
    /// turns true the day of use is counted and, on an eligible day, the rating sheet waits for a free moment
    /// (`ReviewPrompt`); turning false cancels the wait.
    private var reviewReady: Bool {
        phase == .active && !opening && start == nil && lock.lobbyReleased && !lock.locked && !lock.covered
    }

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let start = Onboarding.start(arguments, onboarded: UserDefaults.standard.bool(forKey: Onboarding.doneKey))
        let launch = OpeningLaunch.shared
        // `didReceive` usually arrives after this init, so `fromNotification` is mostly still false here: the real
        // handling is in SplashView (its onChange, and the check in `begin()`). `played`: a scene iOS builds again while
        // the process lives does not replay the opening.
        let play = Opening.play(firstLaunch: start == .splash, arguments: arguments, fromNotification: launch.fromNotification,
                                alreadyPlayed: launch.played)
        _start = State(initialValue: start)
        _play = State(initialValue: play)
        _opening = State(initialValue: start == nil && play == .animated)
    }

    var body: some View {
        ZStack {
            if opening {
                SplashView(play: play, ending: .continues) {
                    withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.35)) { opening = false }
                }
                .transition(.opacity)
            } else if let start {
                FirstLaunchView(start: start, play: play, onPastSplash: { pastSplash = true }) {
                    onboarded = true
                    UserDefaults.standard.synchronize()
                    withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.35)) { self.start = nil }
                }
                .transition(.opacity)
            } else if lock.lobbyReleased {
                RootView().transition(.opacity)
            } else {
                // Until the cold launch is decided and, with the lock on, passed: the cover, never the lobby.
                LockCover()
                    .task {
                        try? await Task.sleep(for: .seconds(1))
                        if !Task.isCancelled { lock.openingFallback() }
                    }
            }
        }
        .background(LockWindowAnchor().frame(width: 0, height: 0).accessibilityHidden(true))
        .onChange(of: phase, initial: true) { _, value in lock.scene(value) }
        .onAppear { if !opening { lock.openingEnded(onboarding: start != nil) } }
        .onChange(of: opening) { _, value in if !value { lock.openingEnded(onboarding: start != nil) } }
        // A moment after, so a lock that comes up as the app returns cancels it; the work itself runs in the
        // background and never holds up the screen. Nothing is sent under --ui-testing (`UsageGate`).
        .task(id: usageReady) {
            guard usageReady else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { UsageStats.appOpened() }
        }
        .task(id: reviewReady) {
            guard reviewReady else { return }
            await ReviewPrompt.shared.opened()
        }
    }
}

/// The lobby is the navigation root; every feature is pushed above it (spec 4.1). Feature screens share the bottom
/// bar: 「‹ 大廳」, the quick pick, the page name.
struct RootView: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.motionReduced) private var reduceMotion
    @ObservedObject private var router = AppRouter.shared
    @Namespace private var lobby
    @State private var path: NavigationPath
    /// The feature at the bottom of the stack; nil in the lobby and on screens pushed straight from it.
    @State private var feature: Feature?
    @ObservedObject private var skins = SkinStore.shared
    /// The LEVEL×UP on screen (spec 5.12); the level is saved as celebrated when it is accepted. It comes up only over
    /// the lobby, once its experience bar has filled (`celebrateIfDue`, spec 5.4).
    @State private var levelUp: LevelUpMoment?
    /// LEVEL×UP is being prepared (waiting for a reward toast to finish).
    @State private var celebration: Task<Void, Never>?
    /// The feature last on screen above the lobby: the lobby's replay flies its coins from that object.
    @State private var returningFrom: Feature?
    @ObservedObject private var connectivity = Connectivity.shared
    // The debit-day reminder's settings: a change re-runs `.task(id: reminderInputs)`.
    @AppStorage(Onboarding.remindKey) private var remindOn = false
    @AppStorage(Onboarding.dayKey) private var remindDay = 0
    @AppStorage(Onboarding.remindMinutesKey) private var remindMinutes = 9 * 60
    @AppStorage(Onboarding.remindEveKey) private var remindEve = false
    @AppStorage(DCAReminders.showAmountKey) private var remindShowAmount = true
    @AppStorage(Onboarding.monthlyKey) private var monthly = 0
    @AppStorage(Onboarding.symbolKey) private var onboardingSymbol = ""
    private var reminderInputs: DCAReminderInputs? { DCAReminders.inputs(store.data) }

    /// LEVEL×UP is due, being prepared or on screen: the rating sheet waits (`ReviewPrompt` hold "levelUp").
    private var levelUpComing: Bool {
        celebration != nil || levelUp != nil || store.data.game?.levelUpDue != nil
    }

    /// 記一筆 is up or asked for: the rating sheet waits (`ReviewPrompt` hold "quickDCA", `QuickDCARoute.busy`).
    private var quickDCABusy: Bool {
        QuickDCARoute.busy(showing: router.quickDCAShowing, requested: router.quickDCARequested)
    }

    init() {
        // `--open <feature>` starts on a feature (UI tests, screenshots); otherwise the lobby.
        let arguments = ProcessInfo.processInfo.arguments
        if let stack = AppRoute.launchStack(arguments) {
            var first: Feature?
            if case .feature(let bottom) = stack.first { first = bottom }
            _feature = State(initialValue: first)
            _returningFrom = State(initialValue: first)
            _path = State(initialValue: NavigationPath(stack))
        } else {
            let start = Feature.launch(arguments)
            _feature = State(initialValue: start)
            _returningFrom = State(initialValue: start)
            _path = State(initialValue: start.map { NavigationPath([AppRoute.feature($0)]) } ?? NavigationPath())
        }
    }

    var body: some View {
        // 離線中: a thin strip above every screen. The stack starts below it (a VStack, not a safe-area inset, which
        // screens without a navigation bar scrolled under), so no title or hero is ever drawn behind the strip.
        VStack(spacing: 0) {
            if connectivity.offline { OfflineBar() }
            NavigationStack(path: $path) {
                LobbyView().appRoutes()
            }
            .environment(\.lobbyNavigation, navigation)
            .environment(\.lobbyNamespace, lobby)
            .environment(\.celebrateIfDue, celebrateIfDue)
            .environment(\.returningFrom, returningFrom)
            .environment(\.lobbyCovered, levelUp != nil)
            .environment(\.lobbyModalPending, levelUp != nil || celebration != nil)
            .tint(Palette.blue)
            .id(skins.skin.id)
            // The toast region (ruling R25): 記一筆配息's coin drop and 「+20」, and one-line notices such as the
            // membership lapse. On the stack, not the whole column, so while offline it sits below 「離線中」 and never hides it.
            .overlay(alignment: .top) { RewardToast() }
        }
        .overlay(alignment: .bottom) {
            if !path.isEmpty, let feature {
                GameBottomBar(title: feature.title, onLobby: navigation.toLobby, onPick: navigation.open)
                    .ignoresSafeArea(.keyboard)
            }
        }
        // Holding a 換膚 card tries that skin on over everything, the bottom bar included, until the finger lifts.
        .overlay {
            ZStack { if let id = skins.tryOn { TryOnPreview(skin: Skins.named(id)).transition(.opacity) } }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: skins.tryOn)
        }
        // Back in the lobby, the feature that was last above it is where the replay's coins come from.
        // A tapped reminder: back to the lobby, which opens 記一筆 there.
        .onChange(of: router.quickDCARequested) { if $1 { navigation.toLobby() } }
        .onChange(of: path) { _, value in if value.isEmpty { feature = nil } else { returningFrom = feature } }
        // Crossing a whole level shows LEVEL×UP once, over the lobby when its bar fills (spec 5.4).
        .fullScreenCover(item: $levelUp) { moment in
            LevelUpView(moment: moment) { accept(moment) }
                .environmentObject(store)
                .environment(\.skin, skins.skin)
                .preferredColorScheme(skins.colorScheme)
        }
        .modifier(SkinKitLaunch())
        // A tap on the 連續定投 widget (etftogo://lobby): back to the lobby.
        .onOpenURL { if AppURL.opensLobby($0) { navigation.toLobby() } }
        // App Store 評分視窗: never over LEVEL×UP, nor while it is on its way (waiting for a reward toast to finish).
        .onChange(of: levelUpComing, initial: true) { _, coming in ReviewPrompt.shared.hold("levelUp", while: coming) }
        // Nor over 記一筆, from the tap (or tapped reminder) until the sheet has gone; its release asks again.
        .onChange(of: quickDCABusy, initial: true) { _, busy in ReviewPrompt.shared.hold("quickDCA", while: busy) }
        .onDisappear { ReviewPrompt.shared.release("levelUp"); ReviewPrompt.shared.release("quickDCA") }
        .task {
            // The cached lists are read after the first screen is up; the fetch below judges what they already hold.
            await store.ensureSideFiles()
            if !ProcessInfo.processInfo.arguments.contains("--ui-testing") { await store.refreshCatalog(automatic: true) }
        }
        // Live prices while the app is in front during the trading session; stopped in the background, where iOS
        // would suspend the connection anyway. Indices and prices are also refreshed once on every return.
        // The widget's file follows the worn skin; this also runs on first appear (the first write after an update).
        .task(id: skins.skin.id) { WidgetSync.shared.sync(store.data) }
        .task(id: phase) {
            guard phase == .active else { return }
            // The records could not be opened at a launch in the background (locked phone): read them now.
            store.reloadIfLocked()
            // Also asks the widget to read its file again, written or not (a tile drawn before the first unlock).
            WidgetSync.shared.returned(store.data)
            if !store.recordsLocked { await DCAReminders.sync(reminderInputs) }
            // 口袋會員前 7 天全開: judged again on every return, wherever the app is (not only over the lobby), so the
            // tools close at the end on any screen.
            MembershipStore.shared.refreshOpen()
            guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
            store.live.start()
            await store.followMarket()
            // 到價提醒 (spec 5.7): judged on the prices just refreshed, when the app comes to the front (five minutes
            // apart at least).
            await PriceAlertMonitor.checkOnReturn()
        }
        // Rebuilt from the records, so logging a DCA (or deleting it) and a new month change what is pending.
        .task(id: reminderInputs) { if !store.recordsLocked { await DCAReminders.sync(reminderInputs) } }
        .onChange(of: phase) { _, value in if value == .background { store.live.stop(); PriceAlertMonitor.scheduleNext() } }
        // Locked records are empty, not gone: the reminders already scheduled stay until they can be read.
        .task(id: store.data.dividends.map(\.id)) { if !store.recordsLocked { await DividendReminders.syncIfEnabled(store.data.dividends) } }
        .alert("投資袋著走", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("知道了", role: .cancel) { store.message = nil } } message: { Text(store.message ?? "") }
    }

    /// LEVEL×UP, when one is due and the lobby is the screen in front (spec 5.4): never over a feature screen, where it
    /// waits for the next time the lobby is seen, nor over 記一筆 or a 口袋會員全開 note, after which the lobby asks again
    /// (their `onDismiss`).
    /// The lobby calls this once its bar has filled.
    private func celebrateIfDue() {
        guard path.isEmpty, levelUp == nil, celebration == nil, !router.quickDCAShowing, !router.memberNoteShowing,
              store.data.game?.levelUpDue != nil else { return }
        celebration = Task {
            await celebrateWhenDue()
            celebration = nil
        }
    }

    /// Waits for the action's own feedback first: 記一筆配息's toast appears 0.6 s after the save and the coin drops
    /// (ruling R25); LEVEL×UP follows about two seconds later, so neither is lost. Achievements reached with the
    /// level are recorded here; the rewards are read from the saved game, so a replay after a relaunch lists them too.
    /// The lobby left meanwhile: it waits for the next time.
    private func celebrateWhenDue() async {
        guard store.data.game?.levelUpDue != nil, levelUp == nil else { return }
        try? await Task.sleep(for: .milliseconds(150))
        let hadReward = store.pendingReward > 0
        var waits = 0
        while store.pendingReward > 0, waits < 20, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(150)); waits += 1
        }
        if hadReward { try? await Task.sleep(for: .seconds(2)) }
        // 記一筆 or a note came up meanwhile: it is held, and the lobby asks again once the sheet has gone.
        guard !Task.isCancelled, levelUp == nil, path.isEmpty, !router.quickDCAShowing, !router.memberNoteShowing,
              let level = store.data.game?.levelUpDue else { return }
        try? store.updateGame { _ = $0.refreshAchievements(store.data, now: Date()) }
        levelUp = LevelUp.moment(store.data.game ?? GameState(), level: level, now: Date())
    }

    /// 收下: saved as celebrated, so it is never shown again (not after leaving a screen, nor after a relaunch).
    private func accept(_ moment: LevelUpMoment) {
        do { try store.updateGame { $0.celebrate(moment.level) } } catch { store.message = error.localizedDescription }
        levelUp = nil
    }

    private var navigation: LobbyNavigation {
        LobbyNavigation(
            toLobby: { move { path = NavigationPath(); feature = nil } },
            open: { next in move { feature = next; path = NavigationPath([AppRoute.feature(next)]) } },
            push: { route in move { path.append(route) } })
    }

    /// With Reduce Motion, screens change without the push or zoom; the new screen fades in instead (spec 3.5).
    private func move(_ change: () -> Void) {
        guard reduceMotion else { change(); return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }
}
