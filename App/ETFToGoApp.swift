import SwiftUI

@main struct ETFToGoApp: App {
    @StateObject private var store: PortfolioStore
    @AppStorage("appearance") private var appearance = "light"
    /// The skin decides light or dark text; every screen redraws when it changes.
    @ObservedObject private var skins = SkinStore.shared
    init() {
        // Sentry (Task 14): off without a DSN (Debug, CI), with --ui-testing and under XCTest.
        CrashReporting.start()
        let args = ProcessInfo.processInfo.arguments
        let testing = args.contains("--ui-testing")
        let testURL = testing ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ETFToGo/ui-test.json") : nil
        // `--reset` wipes the records only in UI tests: a stale scheme argument never empties the real file.
        let store = PortfolioStore(url: testURL, reset: testing && args.contains("--reset"))
        Onboarding.reset(args)
        ReportSettings.reset(args)
        // Someone upgrading with records on the phone has started already: no first-launch flow for them.
        Onboarding.adoptExisting(store.data)
        // One-time migrations of the game progress: DCA months backfilled from the records, with no experience.
        try? store.updateGame { $0.migrate(store.data) }
        // UI tests and screenshots set up game progress with `--demo-…` (only with `--ui-testing`).
        try? store.updateGame { DemoArguments.apply(to: &$0, args: args, now: Date()) }
        DemoArguments.seedPocket(store, args: args, now: Date())
        DemoArguments.seedHeld(store, args: args)
        DemoArguments.seedActive(store, args: args)
        _store = StateObject(wrappedValue: store)
        // A launch in the background on a locked phone reads the records later; the two steps above are then redone.
        store.onRecordsRead = { store in
            Onboarding.adoptExisting(store.data)
            try? store.updateGame { $0.migrate(store.data) }
        }
        // 到價提醒: iOS wants the background task's handler before launch ends. Nothing is registered in UI tests.
        PriceAlertMonitor.start(store, testing: testing)
        // StoreKit is followed from launch (Apple asks for the Transaction.updates listener then), so renewals and Ask
        // to Buy answers that arrive during the splash or onboarding are not missed. Once StoreKit has answered, a skin
        // the player may no longer wear is taken off, with a notice.
        let membership = MembershipStore.shared
        membership.level = { [weak store] in GameRules.level(xp: store?.data.game?.xp ?? 0) }
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
/// The first launch goes splash → onboarding → lobby (spec 5.1, 5.2); every later launch opens on the lobby.
struct LaunchGate: View {
    @AppStorage(Onboarding.doneKey) private var onboarded = false
    @Environment(\.motionReduced) private var reduceMotion
    /// Decided once per launch, so finishing the flow is what leaves it (also when a screenshot forced it open).
    @State private var start: OnboardingStart?

    init() {
        _start = State(initialValue: Onboarding.start(ProcessInfo.processInfo.arguments,
                                                      onboarded: UserDefaults.standard.bool(forKey: Onboarding.doneKey)))
    }

    var body: some View {
        ZStack {
            if let start {
                FirstLaunchView(start: start) {
                    onboarded = true
                    UserDefaults.standard.synchronize()
                    withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.35)) { self.start = nil }
                }
                .transition(.opacity)
            } else {
                RootView().transition(.opacity)
            }
        }
    }
}

/// The lobby is the navigation root; every feature is pushed above it (spec 4.1). Feature screens share the bottom
/// bar: 「‹ 大廳」, the quick pick, the page name.
struct RootView: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.motionReduced) private var reduceMotion
    @Namespace private var lobby
    @State private var path: NavigationPath
    /// The feature at the bottom of the stack; nil in the lobby and on screens pushed straight from it.
    @State private var feature: Feature?
    @ObservedObject private var skins = SkinStore.shared
    /// The LEVEL×UP on screen (spec 5.12); the level is saved as celebrated when it is accepted.
    @State private var levelUp: LevelUpMoment?
    @ObservedObject private var connectivity = Connectivity.shared

    init() {
        // `--open <feature>` starts on a feature (UI tests, screenshots); otherwise the lobby.
        let arguments = ProcessInfo.processInfo.arguments
        if let stack = AppRoute.launchStack(arguments) {
            if case .feature(let first) = stack.first { _feature = State(initialValue: first) } else { _feature = State(initialValue: nil) }
            _path = State(initialValue: NavigationPath(stack))
        } else {
            let start = Feature.launch(arguments)
            _feature = State(initialValue: start)
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
            .tint(Palette.blue)
            .id(skins.skin.id)
            // The toast region (ruling R25): 記一筆配息's coin drop and 「+20」, and one-line notices such as 「收進圖鑑
            // +30 經驗」. On the stack, not the whole column, so while offline it sits below 「離線中」 and never hides it.
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
        .onChange(of: path) { _, value in if value.isEmpty { feature = nil } }
        // Crossing a whole level shows LEVEL×UP once, over everything (spec 5.12).
        .fullScreenCover(item: $levelUp) { moment in
            LevelUpView(moment: moment) { accept(moment) }
                .environmentObject(store)
                .environment(\.skin, skins.skin)
                .preferredColorScheme(skins.colorScheme)
        }
        .task(id: store.data.game?.levelUpDue) { await celebrateWhenDue() }
        .modifier(SkinKitLaunch())
        .task { if !ProcessInfo.processInfo.arguments.contains("--ui-testing") { await store.refreshCatalog(automatic: true) } }
        // Live prices while the app is in front during the trading session; stopped in the background, where iOS
        // would suspend the connection anyway. Indices and prices are also refreshed once on every return.
        .task(id: phase) {
            guard phase == .active else { return }
            // The records could not be opened at a launch in the background (locked phone): read them now.
            store.reloadIfLocked()
            guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
            store.live.start()
            await store.followMarket()
            // 到價提醒 (spec 5.7): judged on the prices just refreshed, when the app comes to the front (five minutes
            // apart at least).
            await PriceAlertMonitor.checkOnReturn()
        }
        .onChange(of: phase) { _, value in if value == .background { store.live.stop(); PriceAlertMonitor.scheduleNext() } }
        // Locked records are empty, not gone: the reminders already scheduled stay until they can be read.
        .task(id: store.data.dividends.map(\.id)) { if !store.recordsLocked { await DividendReminders.syncIfEnabled(store.data.dividends) } }
        .alert("投資袋著走", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("知道了", role: .cancel) { store.message = nil } } message: { Text(store.message ?? "") }
    }

    /// Waits for the action's own feedback first: 記一筆配息's toast appears 0.6 s after the save and the coin drops
    /// (ruling R25); LEVEL×UP follows about two seconds later, so neither is lost. Achievements reached with the
    /// level are recorded here; the rewards are read from the saved game, so a replay after a relaunch lists them too.
    private func celebrateWhenDue() async {
        guard store.data.game?.levelUpDue != nil, levelUp == nil else { return }
        try? await Task.sleep(for: .milliseconds(150))
        let hadReward = store.pendingReward > 0
        var waits = 0
        while store.pendingReward > 0, waits < 20, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(150)); waits += 1
        }
        if hadReward { try? await Task.sleep(for: .seconds(2)) }
        guard !Task.isCancelled, levelUp == nil, let level = store.data.game?.levelUpDue else { return }
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
