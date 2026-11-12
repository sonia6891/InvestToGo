import SwiftUI
import UIKit

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

/// A feature's first screen. Pulling down from the top third of it returns to the lobby (spec 4.3); it zooms out of
/// the lobby object that opened it.
struct FeatureScreen: View {
    let feature: Feature
    @Environment(\.lobbyNavigation) private var navigation
    @Environment(\.lobbyNamespace) private var namespace
    @State private var height: CGFloat = 0

    var body: some View {
        content
            .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                if Self.isPullToLobby(start: value.startLocation, translation: value.translation, height: height) { navigation.toLobby() }
            })
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .modifier(ZoomFromLobby(feature: feature, namespace: namespace))
    }

    @ViewBuilder private var content: some View {
        switch feature {
        case .find: DiscoverView()
        case .dividends: DividendsView()
        case .pocket: HomeView()
        case .tools: ToolsView()
        case .achievements: AchievementListView()
        }
    }

    /// A downward drag of more than 120pt that starts in the top third of the screen and is mostly vertical.
    static func isPullToLobby(start: CGPoint, translation: CGSize, height: CGFloat) -> Bool {
        height > 0 && start.y < height / 3 && translation.height > 120 && abs(translation.width) < translation.height
    }
}

/// The lobby object grows to fill the screen and fades into the feature (about 350ms, the system zoom). With Reduce
/// Motion on, the system turns the zoom into a cross-fade.
private struct ZoomFromLobby: ViewModifier {
    let feature: Feature
    let namespace: Namespace.ID?
    @ViewBuilder func body(content: Content) -> some View {
        if let namespace { content.navigationTransition(.zoom(sourceID: feature, in: namespace)) } else { content }
    }
}

/// 成就 until the badge wall arrives (Task 11): every achievement with a check and its progress.
struct AchievementListView: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.skin) private var skin

    var body: some View {
        let game = store.data.game ?? GameState(), now = Date()
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BADGE×\(String(format: "%03d", game.unlocked.count))").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
                        Text("成就").skinFont(.title(34)).skinForeground(\.ink)
                    }
                    Spacer()
                    SkinImage(.achievements).frame(width: 96, height: 96).accessibilityHidden(true)
                }
                SkinCard {
                    VStack(spacing: 12) {
                        ForEach(Achievement.all) { item in
                            let progress = min(item.progress(game, store.data, now), item.goal)
                            HStack(spacing: 10) {
                                SkinCheck(done: game.unlocked[item.id] != nil)
                                Text(item.title).skinFont(.body(14))
                                Spacer()
                                Text("\(progress)/\(item.goal)").skinFont(.mono(12)).skinForeground(\.sub)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
        }
        .background(skin.color(\.page).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// With the navigation bar hidden (lobby, pocket, tools), UIKit turns off the swipe from the left edge. Keep it on
/// whenever there is a screen to go back to (spec 4.3: 左緣右滑回上一層).
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer == interactivePopGestureRecognizer ? viewControllers.count > 1 : true
    }
}
