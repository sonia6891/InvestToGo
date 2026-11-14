import SwiftUI

/// What 口袋月報 remembers on the phone, outside the records.
enum ReportSettings {
    /// 顯示領息金額: on until it is switched off.
    static let showDividendsKey = "reportShowDividends"
    /// The month (「2026-10」) whose report the lobby last announced.
    static let seenMonthKey = "reportSeenMonth"

    /// `--ui-testing --reset` starts as a fresh install: 領息金額 shown, nothing announced yet.
    static func reset(_ arguments: [String], defaults: UserDefaults = .standard) {
        guard arguments.contains("--ui-testing"), arguments.contains("--reset") else { return }
        for key in [showDividendsKey, seenMonthKey] { defaults.removeObject(forKey: key) }
    }
}

/// Which report the screen shows.
enum ReportTab: String, CaseIterable, Identifiable {
    case month = "月報", year = "年報", yearToDate = "今年到目前"
    var id: String { rawValue }
    /// The small line over the card's period.
    var heading: String {
        switch self {
        case .month: return "口袋月報"
        case .year: return "口袋年報"
        case .yearToDate: return "今年到目前"
        }
    }
}

/// 口袋月報／年報 (spec 5.5, 口袋會員): one card of what the person did and received in a period. It never shows what
/// the holdings are worth, what they cost or what they gained, so it can be shared; the dividend amount can be left
/// off too. 「分享」 hands the system share sheet a picture of the card, drawn on the phone.
struct PocketReportView: View {
    @EnvironmentObject private var store: PortfolioStore
    @Environment(\.skin) private var skin
    @State private var tab = ReportTab.month
    /// The month and the year on screen; they start at the last ones that have ended.
    @State private var month: YearMonth
    @State private var year: Int
    @AppStorage(ReportSettings.showDividendsKey) private var showDividends = true
    /// The picture 「分享」 hands over, with what it was drawn from: it is only offered while that is still what the
    /// screen shows, so a card that has just changed (領息金額 switched off, say) is never shared as it was before.
    @State private var shared: (drawn: Drawn, image: Image)?
    /// Read once, when the screen opens, so the periods do not move under the reader.
    @State private var now: Date

    init(now: Date = Date()) {
        _now = State(initialValue: now)
        _month = State(initialValue: Self.lastMonth(now))
        _year = State(initialValue: Self.lastYear(now))
    }

    /// The newest month and year with a report: the ones that have ended. The current ones are never shown as a
    /// 月報 or 年報; 今年到目前 covers them.
    static func lastMonth(_ now: Date) -> YearMonth { YearMonth(now).previous() }
    static func lastYear(_ now: Date) -> Int { YearMonth(now).year - 1 }

    private var period: ReportPeriod {
        switch tab {
        case .month: return .month(month)
        case .year: return .year(year)
        case .yearToDate: return .yearToDate(YearMonth(now).year)
        }
    }

    var body: some View {
        Page {
            MemberLock(.report) { report } preview: { preview }
            Text("只整理你記下的領息與習慣，不含市值與損益。圖片在手機上產生，不會上傳。")
                .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("report-note")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { VStack(spacing: 0) { Text("口袋月報／年報").font(.headline).foregroundStyle(Palette.ink); Text("這段時間領了多少息、做到哪些習慣").font(.caption2).foregroundStyle(Palette.muted) } } }
    }

    // MARK: Member

    @ViewBuilder private var report: some View {
        let card = PocketReport.make(period, portfolio: store.data, now: now)
        let drawn = Drawn(card: card, heading: tab.heading, isMonth: tab == .month, showDividends: showDividends, skin: skin.id)
        Picker("報告", selection: $tab) {
            ForEach(ReportTab.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).accessibilityIdentifier("report-tabs")
        if tab != .yearToDate { stepper }
        ReportCardView(card: card, heading: drawn.heading, isMonth: drawn.isMonth, showDividends: showDividends)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("report-card")
        Card {
            Toggle("顯示領息金額", isOn: $showDividends)
                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).tint(Palette.blue)
                .accessibilityIdentifier("report-show-dividends")
            Text("關掉後，畫面上的卡片和分享的圖片都不會出現領息金額。").font(.caption).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            share(drawn).padding(.top, 12)
        }
        // Drawn again whenever what the card shows changes.
        .task(id: drawn) {
            shared = Self.picture(of: drawn.card, heading: drawn.heading, isMonth: drawn.isMonth, showDividends: drawn.showDividends, skin: skin)
                .map { (drawn: drawn, image: Image(uiImage: $0)) }
        }
    }

    /// 「‹ 2026 年 10 月 ›」: back to earlier months or years, and forward again as far as the last one that ended.
    private var stepper: some View {
        let earliest = PocketReport.earliestMonth(store.data, now: now)
        let canGoBack = earliest.map { tab == .month ? $0 < month : $0.year < year } ?? false
        let canGoForward = tab == .month ? month < Self.lastMonth(now) : year < Self.lastYear(now)
        return HStack(spacing: 12) {
            Button { if tab == .month { month = month.previous() } else { year -= 1 } } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(!canGoBack).accessibilityLabel(tab == .month ? "上一個月" : "上一年").accessibilityIdentifier("report-previous")
            Text(period.title(now: now)).font(.headline).monospacedDigit().foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity).accessibilityIdentifier("report-period")
            Button { if tab == .month { month = month.next() } else { year += 1 } } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(!canGoForward).accessibilityLabel(tab == .month ? "下一個月" : "下一年").accessibilityIdentifier("report-next")
        }
        .buttonStyle(.plain).foregroundStyle(Palette.blue)
    }

    @ViewBuilder private func share(_ drawn: Drawn) -> some View {
        if let shared, shared.drawn == drawn {
            // The picture alone: no text and no link go with it.
            ShareLink(item: shared.image, preview: SharePreview("\(drawn.heading) \(drawn.card.title)", image: shared.image)) {
                PrimaryButtonLabel(title: "分享", icon: "square.and.arrow.up")
            }
            .buttonStyle(.plain).accessibilityIdentifier("report-share")
        } else {
            // Until the picture is drawn the button waits.
            Button {} label: { PrimaryButtonLabel(title: "分享", icon: "square.and.arrow.up") }
                .buttonStyle(.plain).disabled(true).opacity(0.5).accessibilityIdentifier("report-share")
        }
    }

    /// What the shared picture depends on.
    private struct Drawn: Equatable {
        var card: ReportCard
        var heading: String
        var isMonth: Bool
        var showDividends: Bool
        var skin: String
    }

    /// The picture of a card: the card at a fixed width on the skin's page colour. `ImageRenderer` draws outside the
    /// screen's view tree and inherits nothing from it, so the skin is handed over here; the picture is the same on
    /// every phone and at every text size.
    @MainActor static func picture(of card: ReportCard, heading: String, isMonth: Bool, showDividends: Bool, skin: Skin) -> UIImage? {
        let content = ReportCardView(card: card, heading: heading, isMonth: isMonth, showDividends: showDividends)
            .padding(20)
            .frame(width: 360)
            .background(skin.color(\.page))
            .environment(\.skin, skin)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        return renderer.uiImage
    }

    // MARK: Preview behind the lock

    /// A made-up card: what the report looks like, never anyone's own.
    private var preview: some View {
        ReportCardView(card: ReportCard(title: "2026 年 10 月", dividends: 3_200, dcaMonths: 1, reconciles: 1, newDexCards: 2, level: 5, xpEarned: 180,
                                        notes: ["領息 2 筆，來自 2 檔。"]),
                       heading: ReportTab.month.heading, isMonth: true, showDividends: true)
    }
}

/// The report card itself, on screen and in the picture that is shared: drawn with the skin kit, so it wears the
/// current skin. Dividends received, habits kept, cards collected and the level; never market value, cost or returns.
struct ReportCardView: View {
    let card: ReportCard
    /// 「口袋月報」, 「口袋年報」 or 「今年到目前」.
    let heading: String
    /// A month's card says whether there was a 定期定額; a longer one counts the months.
    let isMonth: Bool
    /// Off: the dividend amount is left out altogether.
    let showDividends: Bool
    @Environment(\.skin) private var skin

    var body: some View {
        SkinCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(heading).skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
                        .accessibilityIdentifier("report-heading")
                    Text(card.title).skinFont(.title(24)).skinForeground(\.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("report-title")
                }
                if showDividends {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("領息").skinFont(.mono(11)).skinForeground(\.sub)
                        Text("\(money(card.dividends)) 元").skinFont(.big(40)).skinForeground(\.ink)
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("report-dividends")
                }
                Rectangle().fill(skin.color(\.line)).frame(height: 1).accessibilityHidden(true)
                VStack(spacing: 10) {
                    row("定期定額", isMonth ? (card.dcaMonths > 0 ? "有做到" : "沒有紀錄") : "\(card.dcaMonths) 個月", id: "report-dca")
                    row("對帳", "\(card.reconciles) 次", id: "report-reconciles")
                    row("新收集的圖鑑卡", "\(card.newDexCards) 張", id: "report-dex")
                    row("等級", "LV.\(card.level)", id: "report-level")
                    if let xp = card.xpEarned { row("獲得經驗", "+\(xp)", id: "report-xp") }
                }
                ForEach(card.notes, id: \.self) { note in
                    Text(note).skinFont(.body(13)).skinForeground(\.sub).fixedSize(horizontal: false, vertical: true)
                }
                Text("ETF 袋著走").skinFont(.mono(11)).tracking(1.5).skinForeground(\.dim)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 6)
        }
    }

    private func row(_ title: String, _ value: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).skinFont(.body(14)).skinForeground(\.sub)
            Spacer(minLength: 12)
            Text(value).skinFont(.title(16)).skinForeground(\.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}
