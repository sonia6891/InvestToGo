import SwiftUI

@main struct ETFToGoApp: App {
    @StateObject private var store: PortfolioStore
    @AppStorage("appearance") private var appearance = "light"
    init() {
        let args = ProcessInfo.processInfo.arguments
        let testURL = args.contains("--ui-testing") ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ETFToGo/ui-test.json") : nil
        _store = StateObject(wrappedValue: PortfolioStore(url: testURL, reset: args.contains("--reset")))
    }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .preferredColorScheme(appearance == "light" ? .light : (appearance == "dark" ? .dark : nil))
        }
    }
}
struct RootView: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    /// Re-selecting a tab returns it to its first screen.
    @State private var resets = [0, 0, 0, 0, 0]
    @State private var minimized = false
    var body: some View {
        TabView(selection: $tab) {
            stack(0) { HomeView(tab: $tab, resetDiscover: { resets[1] += 1 }) }
            stack(1) { DiscoverView() }
            stack(2) { HoldingsView() }
            stack(3) { DividendsView() }
            stack(4) { ToolsView() }
        }
        .tint(Palette.blue)
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $tab, minimized: minimized, reselect: { resets[$0] += 1 }, expand: { minimized = false }).ignoresSafeArea(.keyboard)
        }
        .environment(\.tabBarMinimize) { value in if minimized != value { minimized = value } }
        .onChange(of: tab) { _, _ in minimized = false }
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
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "--tab"), args.indices.contains(i + 1), let value = Int(args[i + 1]) { tab = value }
        }
        .alert("投資袋著走", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("知道了", role: .cancel) { store.message = nil } } message: { Text(store.message ?? "") }
    }
    private func stack<Content: View>(_ index: Int, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack { content().appRoutes() }
            .id(resets[index])
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 76) }
            .toolbar(.hidden, for: .tabBar)
            .tag(index)
    }
}
