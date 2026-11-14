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

    /// UI tests and screenshots never see the notice: the lobby they check stays as it was.
    private static let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")

    var body: some View {
        let game = store.data.game ?? GameState(), now = Date()
        let hero = LobbyHero.of(game, now: now)
        ScrollView {
            VStack(spacing: 10) {
                topBar(game)
                Text("\(skin.code) · \(skin.name)").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .top) { entry(.find); Spacer(); entry(.dividends) }
                HeroNumber(value: hero.value, caption: hero.caption, label: hero.label) { navigation.push(.dcaHistory) }
                    .background(alignment: .top) {
                        SkinDecor(page: .lobby).frame(height: HeroNumber.numeralHeight).padding(.horizontal, -20)
                    }
                VStack(spacing: 6) {
                    SkinTag(hero.tag)
                    if let record = hero.record { Text(record).skinFont(.mono(12)).skinForeground(\.sub) }
                }
                HStack(alignment: .top) { entry(.pocket); Spacer(); entry(.tools) }
                if reportNotice, membership.has(.report) { reportNoticeCard }
                questCard(game, month: YearMonth(now))
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

    private func topBar(_ game: GameState) -> some View {
        let level = GameRules.level(xp: game.xp), progress = GameRules.progress(xp: game.xp)
        let fraction = CGFloat(progress.into) / CGFloat(max(progress.needed, 1))
        return HStack(spacing: 8) {
            Text("LV.\(level)").skinFont(.big(13))
                .foregroundStyle(skin.onFill(skin.colors.accent))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: skin.style.button == .pixelBlock ? 0 : 6).fill(skin.color(\.accent)))
                .accessibilityLabel("等級 \(level)")
            Capsule().fill(skin.color(\.line))
                .overlay(alignment: .leading) { GeometryReader { geo in Capsule().fill(skin.color(\.ink)).frame(width: geo.size.width * fraction) } }
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

    private func entry(_ feature: Feature) -> some View {
        Button { navigation.open(feature) } label: {
            VStack(spacing: 6) {
                SkinImage(feature.art).frame(width: 76, height: 76)
                SkinTag(feature.title)
            }
            .frame(minWidth: 96)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(ZoomSource(feature: feature, namespace: namespace))
        .accessibilityLabel(feature.title)
        .accessibilityIdentifier("lobby-\(feature.rawValue)")
    }

    // MARK: Quests

    private func questCard(_ game: GameState, month: YearMonth) -> some View {
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
                    Text("+\(reward) XP").foregroundStyle(skin.color(skin.lightText ? \.accent : \.ink))
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
