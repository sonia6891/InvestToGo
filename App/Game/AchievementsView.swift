import SwiftUI

/// 成就 (spec 5.11): the 3D target top right, 「成就」 and how many are unlocked, then a three-column badge wall.
/// Unlocked: the skin's stage with an object and the day it was reached. Locked: a dark 「?」, a progress bar and
/// the numbers. One whose feature is not in the app yet is left off the wall (`Achievements.shown`); were it shown
/// (`Upcoming.visible`), it would say 「即將推出」 instead of a bar stuck at 0 (ruling R31).
/// Goals are counts, never money (spec 6.5).
struct AchievementsView: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.skin) private var skin
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)

    var body: some View {
        let game = store.data.game ?? GameState(), now = Date()
        let wall = Achievements.shown()
        let unlocked = wall.filter { game.unlocked[$0.id] != nil }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BADGE×\(String(format: "%03d", unlocked))").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
                        Text("成就").skinFont(.title(34)).skinForeground(\.ink)
                        Text("已解鎖 \(unlocked) / \(wall.count)").skinFont(.mono(12)).skinForeground(\.sub)
                            .accessibilityIdentifier("achievements-count")
                    }
                    Spacer()
                    SkinImage(.achievements).frame(width: 96, height: 96).accessibilityHidden(true)
                }
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(wall) { item in badge(item, game: game, now: now) }
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
        }
        .modifier(ReportsScrollTop())
        .background(skin.color(\.page).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        // Achievements reached since the last visit are recorded with today's date.
        .onAppear { try? store.updateGame { _ = $0.refreshAchievements(store.data, now: Date()) } }
    }

    @ViewBuilder private func badge(_ item: Achievement, game: GameState, now: Date) -> some View {
        let date = game.unlocked[item.id]
        let progress = min(max(item.progress(game, store.data, now), 0), item.goal)
        VStack(spacing: 6) {
            if let date {
                SkinStage(size: 84) { SkinImage(Self.art(item.id)).padding(18) }
                Text(item.title).skinFont(.title(12)).skinForeground(\.ink)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                Text(Self.day(date)).skinFont(.mono(10)).skinForeground(\.sub)
            } else {
                ZStack {
                    Circle().fill(skin.color(\.card))
                    Circle().strokeBorder(skin.color(\.line), lineWidth: 2)
                    Text("?").skinFont(.big(30)).skinForeground(\.dim)
                }
                .frame(width: 84, height: 84)
                Text(item.title).skinFont(.title(12)).skinForeground(\.sub)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                if item.comingSoon {
                    Text(Self.comingSoon).skinFont(.mono(10)).skinForeground(\.sub)
                } else {
                    Capsule().fill(skin.color(\.line))
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule().fill(skin.color(\.dim)).frame(width: geo.size.width * CGFloat(progress) / CGFloat(max(item.goal, 1)))
                            }
                        }
                        .frame(width: 64, height: 5)
                    Text("\(progress) / \(item.goal)").skinFont(.mono(10)).skinForeground(\.sub)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(date.map { "已解鎖 \(Self.day($0))" } ?? (item.comingSoon ? Self.comingSoon : "\(progress) / \(item.goal)"))
        .accessibilityIdentifier("achievement-\(item.id)")
    }

    static let comingSoon = "即將推出"

    /// The object on an unlocked badge, from the skin's own art.
    static func art(_ id: String) -> SkinArtName {
        switch id {
        case "dividendStreak": return .dividends
        case "holdingAnniversary": return .crown
        case "dcaPunchCard": return .heroDollar
        case "steadyYear": return .pocketIcon
        case "reconcileMaster": return .tools
        case "feeSaver": return .fees
        case "checkupDone": return .goal
        case "dexCollector": return .find
        case "exDividendSkin": return .badge
        case "yearReport": return .calc
        case "dividendMilestone": return .crown
        default: return .badge
        }
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = GameRules.taipei.timeZone
        f.dateFormat = "yyyy.MM.dd"
        return f
    }()
    static func day(_ date: Date) -> String { dayFormat.string(from: date) }
}
