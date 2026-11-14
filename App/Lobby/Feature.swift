import SwiftUI

/// The five places the lobby and the quick pick open (spec 4.1). Each one is the first screen above the lobby.
enum Feature: String, CaseIterable, Hashable {
    case find, dividends, pocket, tools, achievements

    var title: String {
        switch self {
        case .find: return "找 ETF"
        case .dividends: return "配息"
        case .pocket: return "口袋"
        case .tools: return "工具"
        case .achievements: return "成就"
        }
    }

    /// The object that stands for the feature in the lobby and on the quick-pick discs.
    var art: SkinArtName {
        switch self {
        case .find: return .find
        case .dividends: return .dividends
        case .pocket: return .pocketIcon
        case .tools: return .tools
        case .achievements: return .achievements
        }
    }

    /// `--open <feature>` at launch (UI tests and the CI screenshots). `lobby`, `skinKit` or nothing opens the lobby.
    static func launch(_ arguments: [String]) -> Feature? {
        guard let i = arguments.firstIndex(of: "--open"), arguments.indices.contains(i + 1) else { return nil }
        return Feature(rawValue: arguments[i + 1])
    }
}

extension AppRoute {
    /// `--open member` and `--open skins` (UI tests, screenshots): 工具 with 會員, and 換膚 above it. With
    /// `--ui-testing` only, `--open detail --symbol <code>` and `--open dex --symbol <code>`: 找 ETF with that fund's
    /// 詳情, or its 圖鑑卡, above it (the CI four-skin screenshot matrix). The code defaults to 0050.
    static func launchStack(_ arguments: [String]) -> [AppRoute]? {
        guard let i = arguments.firstIndex(of: "--open"), arguments.indices.contains(i + 1) else { return nil }
        let testing = arguments.contains("--ui-testing")
        let symbol = arguments.firstIndex(of: "--symbol").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "0050"
        switch arguments[i + 1] {
        case "member": return [.feature(.tools), .member]
        case "skins": return [.feature(.tools), .member, .skins]
        case "detail" where testing: return [.feature(.find), .fundDetail(symbol)]
        case "dex" where testing: return [.feature(.find), .dexCard(symbol)]
        case "reminders" where testing: return [.feature(.tools), .reminders]
        case "goalPlanner" where testing: return [.feature(.tools), .goalPlanner]
        case "backtest" where testing: return [.feature(.tools), .backtest]
        case "activeTracking" where testing: return [.feature(.tools), .activeTracking]
        case "priceAlerts" where testing: return [.feature(.tools), .priceAlerts]
        case "exposure" where testing: return [.feature(.tools), .exposure]
        default: return nil
        }
    }
}

/// How screens move around the lobby. Set by the root view; the defaults do nothing (previews, renderers).
struct LobbyNavigation {
    /// Back to the lobby from any depth.
    var toLobby: () -> Void = {}
    /// Straight to a feature's first screen, replacing whatever was open (lobby objects, quick pick).
    var open: (Feature) -> Void = { _ in }
    /// Pushes a screen on top of the current one.
    var push: (AppRoute) -> Void = { _ in }
}

private struct LobbyNavigationKey: EnvironmentKey { static let defaultValue = LobbyNavigation() }
private struct LobbyNamespaceKey: EnvironmentKey { static let defaultValue: Namespace.ID? = nil }

extension EnvironmentValues {
    var lobbyNavigation: LobbyNavigation {
        get { self[LobbyNavigationKey.self] }
        set { self[LobbyNavigationKey.self] = newValue }
    }
    /// Shared by the lobby's objects and the feature screens they zoom into.
    var lobbyNamespace: Namespace.ID? {
        get { self[LobbyNamespaceKey.self] }
        set { self[LobbyNamespaceKey.self] = newValue }
    }
}

/// A feature's first screen. Pulling down from its top third returns to the lobby (spec 4.3), but only while its
/// list is scrolled to the top (ruling R21), so scrolling back up never leaves the page; 口袋 pulls to refresh
/// instead and has no pull-to-lobby. It zooms out of the lobby object that opened it, or fades with Reduce Motion.
struct FeatureScreen: View {
    let feature: Feature
    @Environment(\.lobbyNavigation) private var navigation
    @Environment(\.lobbyNamespace) private var namespace
    @State private var height: CGFloat = 0
    /// Whether this screen's own list is at the top. Only its root scroller reports here: pushed pages and sheets
    /// get a silent `scrollAtTop`, and reports that arrive while the screen is covered are ignored, so the value is
    /// still the root list's own when the screen comes back.
    @State private var atTop = true
    @State private var visible = false
    /// The drag being tracked, keyed by where it started, with whether the list was at the top when it began. A new
    /// start location latches afresh, so a drag the scroll view cancelled (no `onEnded`) never leaves a stale value.
    @State private var drag: (start: CGPoint, atTop: Bool)?

    var body: some View {
        content
            .environment(\.scrollAtTop) { value in if visible, atTop != value { atTop = value } }
            .simultaneousGesture(DragGesture(minimumDistance: 24)
                .onChanged { value in if drag?.start != value.startLocation { drag = (start: value.startLocation, atTop: atTop) } }
                .onEnded { value in
                    let wasAtTop = drag?.start == value.startLocation ? drag?.atTop ?? atTop : atTop
                    drag = nil
                    guard feature.pullsToLobby, wasAtTop else { return }
                    if Self.isPullToLobby(start: value.startLocation, translation: value.translation, height: height) { navigation.toLobby() }
                })
            .onAppear { visible = true; drag = nil }
            .onDisappear { visible = false; drag = nil }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .modifier(ZoomFromLobby(feature: feature, namespace: namespace))
    }

    @ViewBuilder private var content: some View {
        switch feature {
        case .find: DiscoverView()
        case .dividends: DividendsView()
        case .pocket: HomeView()
        case .tools: ToolsView()
        case .achievements: AchievementsView()
        }
    }

    /// A downward drag of more than 120pt that starts in the top third of the screen and is mostly vertical.
    static func isPullToLobby(start: CGPoint, translation: CGSize, height: CGFloat) -> Bool {
        height > 0 && start.y < height / 3 && translation.height > 120 && abs(translation.width) < translation.height
    }
}

extension Feature {
    /// 口袋 pulls down to refresh prices, so pulling down there never leaves for the lobby (ruling R21).
    var pullsToLobby: Bool { self != .pocket }
}

/// The lobby object grows to fill the screen and fades into the feature (about 350ms, the system zoom). With Reduce
/// Motion on there is no zoom: the root view pushes without animation and the screen fades in.
private struct ZoomFromLobby: ViewModifier {
    let feature: Feature
    let namespace: Namespace.ID?
    @Environment(\.motionReduced) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        if let namespace, !reduceMotion { content.navigationTransition(.zoom(sourceID: feature, in: namespace)) } else { content.modifier(FadeInWithReducedMotion()) }
    }
}

/// With Reduce Motion, screens the root view switches without animation fade in instead (spec 3.5). Only the first
/// appearance fades: coming back from a pushed page or a sheet shows the screen at once.
struct FadeInWithReducedMotion: ViewModifier {
    @Environment(\.motionReduced) private var reduceMotion
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion && !shown ? 0 : 1)
            .onAppear { if !shown { withAnimation(.easeOut(duration: 0.25)) { shown = true } } }
    }
}

/// Feature screens' scroll views report whether they are at the top (`Page` and the achievement wall do).
private struct ScrollAtTopKey: EnvironmentKey { static let defaultValue: (Bool) -> Void = { _ in } }

extension EnvironmentValues {
    var scrollAtTop: (Bool) -> Void {
        get { self[ScrollAtTopKey.self] }
        set { self[ScrollAtTopKey.self] = newValue }
    }
}

extension View {
    /// Pushed pages and sheets keep their scroll position to themselves; only a feature's root list reports.
    func silencesScrollTop() -> some View { environment(\.scrollAtTop) { _ in } }
}

/// Reports to `scrollAtTop` whether the scroll view's content is at (or pulled past) its top.
struct ReportsScrollTop: ViewModifier {
    @Environment(\.scrollAtTop) private var report
    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y + $0.contentInsets.top <= 1 }) { _, value in report(value) }
    }
}
