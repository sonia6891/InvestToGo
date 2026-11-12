import SwiftUI

@main struct ETFToGoApp: App {
    @StateObject private var store: PortfolioStore
    @AppStorage("appearance") private var appearance = "light"
    /// The skin decides light or dark text; every screen redraws when it changes.
    @ObservedObject private var skins = SkinStore.shared
    init() {
        let args = ProcessInfo.processInfo.arguments
        let testURL = args.contains("--ui-testing") ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ETFToGo/ui-test.json") : nil
        let store = PortfolioStore(url: testURL, reset: args.contains("--reset"))
        // UI tests and screenshots set up game progress with `--demo-…` (only with `--ui-testing`).
        try? store.updateGame { DemoArguments.apply(to: &$0, args: args, now: Date()) }
        DemoArguments.seedPocket(store, args: args, now: Date())
        _store = StateObject(wrappedValue: store)
    }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                // The skin kit's components read the current skin from here.
                .environment(\.skin, skins.skin)
                .preferredColorScheme(skins.colorScheme)
        }
    }
}
/// The lobby is the navigation root; every feature is pushed above it (spec 4.1). Feature screens share the bottom
/// bar: 「‹ 大廳」, the quick pick, the page name.
struct RootView: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var lobby
    @State private var path: NavigationPath
    /// The feature at the bottom of the stack; nil in the lobby and on screens pushed straight from it.
    @State private var feature: Feature?
    @ObservedObject private var skins = SkinStore.shared

    init() {
        // `--open <feature>` starts on a feature (UI tests, screenshots); otherwise the lobby.
        let start = Feature.launch(ProcessInfo.processInfo.arguments)
        _feature = State(initialValue: start)
        _path = State(initialValue: start.map { NavigationPath([AppRoute.feature($0)]) } ?? NavigationPath())
    }

    var body: some View {
        NavigationStack(path: $path) {
            LobbyView().appRoutes()
        }
        .environment(\.lobbyNavigation, navigation)
        .environment(\.lobbyNamespace, lobby)
        .tint(Palette.blue)
        .id(skins.skin.id)
        .overlay(alignment: .bottom) {
            if !path.isEmpty, let feature {
                GameBottomBar(title: feature.title, onLobby: navigation.toLobby, onPick: navigation.open)
                    .ignoresSafeArea(.keyboard)
            }
        }
        .onChange(of: path) { _, value in if value.isEmpty { feature = nil } }
        .fullScreenCover(isPresented: $skins.showcaseOpen) { DesignShowcase(close: { skins.showcaseOpen = false }) }
        .modifier(SkinKitLaunch())
        .task { if !ProcessInfo.processInfo.arguments.contains("--ui-testing") { await store.refreshCatalog(automatic: true) } }
        // Live prices while the app is in front during the trading session; stopped in the background, where iOS
        // would suspend the connection anyway. Indices and prices are also refreshed once on every return.
        .task(id: phase) {
            guard phase == .active, !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
            store.live.start()
            await store.followMarket()
        }
        .onChange(of: phase) { _, value in if value == .background { store.live.stop() } }
        .task(id: store.data.dividends.map(\.id)) { await DividendReminders.syncIfEnabled(store.data.dividends) }
        .alert("投資袋著走", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("知道了", role: .cancel) { store.message = nil } } message: { Text(store.message ?? "") }
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
