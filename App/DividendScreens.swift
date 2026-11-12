import SwiftUI
import Charts

/// "10/22 除息・11/11 發放・每單位 1.35 元" for an official distribution.
func officialSummary(_ event: OfficialDistribution, separator: String = "・") -> String {
    let ex = event.ex.suffix(5).replacingOccurrences(of: "-", with: "/")
    let pay: String = event.pay.isEmpty ? "" : "\(separator)\(event.pay.suffix(5).replacingOccurrences(of: "-", with: "/")) 發放"
    let amount: String = event.amount.map { "每單位 \(decimal($0)) 元" } ?? "金額待公布"
    return "\(ex) 除息\(pay)\(separator)\(amount)"
}
private func verb(_ item: Dividend) -> String { item.status == .paid ? "入帳" : (item.status == .announced ? "發放" : "預估") }
/// Accent-bar row used by the dividend lists.
struct DividendAccentRow: View {
    @EnvironmentObject var store: PortfolioStore
    let item: Dividend
    var hidden = false
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) { Text(item.symbol).font(.subheadline.bold()); Text(store.name(for: item.symbol)).font(.subheadline.bold()).lineLimit(1) }.foregroundStyle(Palette.ink)
                Text("\(ymdText(item.date)) \(verb(item))").font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 4)
            StatusPill(status: item.status)
            Text("\(shown(money(item.amount), hidden: hidden)) 元").font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.ink).lineLimit(1)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
        }
        .accentRow(Palette.status(item.status))
    }
}

/// 配息's figures for the current year (spec 5.8): what was received so far, in how many payments, the months that
/// had one, and the same period of last year to compare with. Only received (paid) records count.
struct DividendYear: Equatable {
    var total: Double = 0
    var count = 0
    var months: Set<Int> = []
    /// Received from 1 January to this day, a year ago.
    var previous: Double = 0

    static func of(_ dividends: [Dividend], now: Date, calendar: Calendar = .current) -> DividendYear {
        let year = calendar.component(.year, from: now)
        let paid = dividends.filter { $0.status == .paid }
        let thisYear = paid.filter { calendar.component(.year, from: $0.date) == year }
        let cutoff = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        let lastYear = paid.filter { calendar.component(.year, from: $0.date) == year - 1 && $0.date <= cutoff }
        return DividendYear(total: thisYear.reduce(0) { $0 + $1.amount }, count: thisYear.count,
                            months: Set(thisYear.map { calendar.component(.month, from: $0.date) }),
                            previous: lastYear.reduce(0) { $0 + $1.amount })
    }

    /// 「領了 7 次 · 比去年多 1,920」; just the count when last year's same period had nothing to compare with.
    func tag(hidden: Bool) -> String {
        let times = "領了 \(count) 次"
        guard previous > 0 else { return times }
        let difference = (total - previous).rounded()
        if difference == 0 { return "\(times) · 和去年同期一樣" }
        return "\(times) · 比去年\(difference > 0 ? "多" : "少") \(shown(money(abs(difference)), hidden: hidden))"
    }
}

/// A coming ex-dividend of a held ETF from the official announcements: the day, the amount per unit and an estimate
/// for the shares held. One per code and ex-date, whatever the number of brokers holding it.
struct UpcomingDividend: Identifiable, Equatable {
    let symbol: String
    /// The ex-date, "2026-11-18".
    let ex: String
    let perShare: Double?
    let shares: Double
    /// The holding to record against when only one holds the code.
    let holding: UUID?
    var id: String { "\(symbol)-\(ex)" }
    /// Before tax and fees, so the page marks it 「≈」.
    var estimate: Double? { perShare.map { ($0 * shares).rounded() } }

    static func from(_ entries: [(symbol: String, event: OfficialDistribution, shares: Double, holding: Holding)], today: String) -> [UpcomingDividend] {
        var result: [UpcomingDividend] = []
        for entry in entries where entry.event.ex >= today {
            if let i = result.firstIndex(where: { $0.symbol == entry.symbol && $0.ex == entry.event.ex }) {
                let old = result[i]
                result[i] = UpcomingDividend(symbol: old.symbol, ex: old.ex, perShare: old.perShare, shares: old.shares + entry.shares, holding: nil)
            } else {
                result.append(UpcomingDividend(symbol: entry.symbol, ex: entry.event.ex, perShare: entry.event.amount, shares: entry.shares, holding: entry.holding.id))
            }
        }
        return result.sorted { ($0.ex, $0.symbol) < ($1.ex, $1.symbol) }
    }
}

/// 配息 (spec 5.8): the skin's coin pile, this year's received total in the big face with a tag (how many times, and
/// against last year), twelve month checks (this month underlined), the coming ex-dividends of held ETFs, and
/// 「記一筆配息」. Logging one earns a flat +20 and, back on this page, a coin drops onto the pile (a fade with Reduce
/// Motion). A newcomer sees the pile, one sentence and the button — never an NT$ 0 (ruling R15).
struct DividendsView: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.skin) private var skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hideAmounts") private var hidden = false
    /// How many dividends had been logged when the page last appeared; more on the way back plays the coin drop.
    /// The 記一筆配息 count when 配息 last appeared. Kept outside the view so a page rebuilt on the way back from the
    /// form still knows a dividend was logged meanwhile; −1 until the first visit.
    @AppStorage("dividendLogsSeen") private var seenLogs = -1
    @State private var drops = 0
    @State private var rewarded = false

    var body: some View {
        let now = Date()
        let year = DividendYear.of(store.data.dividends, now: now)
        let newbie = store.data.dividends.isEmpty && store.data.holdings.isEmpty
        Page {
            Text("DIV×\(String(Calendar.current.component(.year, from: now)))").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
            hero(year)
            if newbie {
                VStack(spacing: 18) {
                    Text("每記下一筆配息，就有一枚金幣掉進這裡。")
                        .skinFont(.body(15)).skinForeground(\.ink).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("dividends-newbie")
                    logButton(primary: true)
                }
                .frame(maxWidth: .infinity)
            } else {
                received(year)
                months(year, now: now)
                upcoming
                logButton(primary: false).frame(maxWidth: .infinity)
                more
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { if rewarded { toast } }
        .onAppear(perform: appeared)
    }

    // MARK: Hero

    private func hero(_ year: DividendYear) -> some View {
        ZStack {
            // The coin pile is read as what it stands for.
            SkinImage(.dividends)
                .accessibilityElement()
                .accessibilityLabel(year.total > 0 ? "金幣堆，今年已領股息 NT$ \(shown(money(year.total), hidden: hidden))" : "金幣堆，今年還沒有領到股息")
            CoinDrop(trigger: drops)
        }
        .frame(width: 200, height: 200)
        .frame(maxWidth: .infinity)
    }

    /// This year's total, or one sentence while nothing has come in yet this year.
    @ViewBuilder private func received(_ year: DividendYear) -> some View {
        VStack(spacing: 8) {
            if year.total > 0 {
                Text("今年已領股息").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
                Text("NT$ \(shown(money(year.total), hidden: hidden))")
                    .skinFont(.big(44)).skinForeground(\.ink)
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .accessibilityIdentifier("dividends-total")
                SkinTag(year.tag(hidden: hidden))
            } else {
                Text("今年還沒有入帳的股息，記下第一筆就會出現在這裡。")
                    .skinFont(.body(14)).skinForeground(\.sub).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Months

    /// Twelve checks: a month with a received dividend is ticked; this month's number is underlined.
    private func months(_ year: DividendYear, now: Date) -> some View {
        let current = Calendar.current.component(.month, from: now)
        return HStack(spacing: 0) {
            ForEach(1...12, id: \.self) { month in
                let done = year.months.contains(month), isNow = month == current
                VStack(spacing: 5) {
                    SkinCheck(done: done, size: 18)
                    Text("\(month)").underline(isNow).skinFont(.mono(9))
                        .foregroundStyle(skin.color(isNow ? \SkinColors.ink : \SkinColors.dim))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(month) 月，\(done ? "已領" : "未領")\(isNow ? "，本月" : "")")
                .accessibilityIdentifier("dividend-month-\(month)")
            }
        }
    }

    // MARK: Coming ex-dividends

    private var upcoming: some View {
        let items = Array(UpcomingDividend.from(store.officialForHoldings(), today: DataChecks.day()).prefix(5))
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("即將除息")
                Spacer()
                Text("預估入帳")
            }
            .skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
            .padding(.bottom, 4)
            if items.isEmpty {
                Text(store.data.holdings.isEmpty ? "口袋裡有 ETF 後，這裡會列出它的除息日。" : "口袋裡的 ETF 目前沒有已公告的除息。")
                    .skinFont(.body(12)).skinForeground(\.sub)
                    .padding(.vertical, 10)
            }
            ForEach(items) { item in
                NavigationLink(value: AppRoute.dividendForm(id: nil, symbol: item.symbol, officialEx: item.ex, holding: item.holding)) {
                    upcomingRow(item)
                }
                .buttonStyle(.plain)
                .accessibilityHint("記下這筆配息")
                Rectangle().fill(skin.color(\.line)).frame(height: 1).accessibilityHidden(true)
            }
        }
    }

    private func upcomingRow(_ item: UpcomingDividend) -> some View {
        let day = item.ex.suffix(5).replacingOccurrences(of: "-", with: "/")
        let dayColor = skin.color(skin.lightText ? \SkinColors.accent : \SkinColors.sub)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                (Text(item.symbol) + Text(" · \(day)").foregroundStyle(dayColor))
                    .skinFont(.big(17)).skinForeground(\.ink).lineLimit(1).minimumScaleFactor(0.6)
                Text("\(store.name(for: item.symbol)) · \(item.perShare.map { "每股 \(decimal($0)) 元" } ?? "金額待公布")")
                    .skinFont(.body(11)).skinForeground(\.sub).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(item.estimate.map { "≈ \(shown(money($0), hidden: hidden))" } ?? "—").skinFont(.mono(13)).skinForeground(\.sub)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func logButton(primary: Bool) -> some View {
        NavigationLink(value: AppRoute.dividendForm(id: nil, symbol: nil, officialEx: nil)) { Text("記一筆配息") }
            .buttonStyle(SkinButtonStyle(primary: primary, seed: SkinSeed.of("記一筆配息")))
            .accessibilityIdentifier("dividends-log")
    }

    /// The record lists and statistics, below the page.
    private var more: some View {
        SkinCard {
            VStack(spacing: 0) {
                NavigationLink(value: AppRoute.recentDividends) { SkinLinkRow(title: "近期配息", subtitle: "每筆狀態與官方公告一鍵加入") }
                    .buttonStyle(.plain).accessibilityIdentifier("dividends-recent")
                Rectangle().fill(skin.color(\.line)).frame(height: 1).accessibilityHidden(true)
                NavigationLink(value: AppRoute.monthDividends(next: false)) { SkinLinkRow(title: "本月股息", subtitle: "已領與待領一次看") }
                    .buttonStyle(.plain).accessibilityIdentifier("dividends-month")
                Rectangle().fill(skin.color(\.line)).frame(height: 1).accessibilityHidden(true)
                NavigationLink(value: AppRoute.yearDividends) { SkinLinkRow(title: "年度配息統計", subtitle: "每月長條圖與紀錄匯出") }
                    .buttonStyle(.plain).accessibilityIdentifier("dividends-year")
            }
        }
        .padding(.top, 8)
    }

    // MARK: Reward

    private var toastText: String { "記一筆配息 +\(GameRules.xp[.dividendLogged] ?? 0) 經驗" }
    private var toast: some View {
        Text(toastText)
            .skinFont(.title(14))
            .foregroundStyle(skin.onFill(skin.colors.accent))
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(Capsule().fill(skin.color(\.accent)))
            .padding(.top, 8)
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            .accessibilityIdentifier("dividend-xp-toast")
    }

    /// Ticks 看一次配息 when it is one of this month's quests, and plays the coin drop for dividends logged since the
    /// page last appeared (on the way back from the form).
    private func appeared() {
        try? store.updateGame { _ = $0.complete(.dividendsViewed, now: Date()) }
        let logs = (store.data.game ?? GameState()).counter(.dividendLogged)
        if seenLogs >= 0, logs > seenLogs { celebrate() }
        seenLogs = logs
    }

    private func celebrate() {
        drops += 1
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .snappy
        withAnimation(animation) { rewarded = true }
        AccessibilityNotification.Announcement(toastText).post()
        Task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation(animation) { rewarded = false }
        }
    }
}

struct RecentDividendsView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var tab = 0
    @AppStorage("hideAmounts") private var hidden = false
    var body: some View {
        let from = Calendar.current.date(byAdding: .day, value: -45, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let all = store.data.dividends.filter { $0.date >= from }.sorted { $0.date < $1.date }
        let groups: [[Dividend]] = [all, all.filter { $0.status == .paid }, all.filter { $0.status == .announced }, all.filter { $0.status == .estimated }]
        let official = store.officialForHoldings()
        Page {
            SegmentBar(items: ["全部 (\(groups[0].count))", "已入帳 (\(groups[1].count))", "已公告 (\(groups[2].count))", "預估 (\(groups[3].count))"], selection: $tab, pill: true, filled: true)
            if groups[tab].isEmpty { Card { ContentUnavailableView("近期沒有紀錄", systemImage: "calendar", description: Text("新增配息紀錄，或從下面的官方公告加入。")) } }
            VStack(spacing: 10) { ForEach(groups[tab]) { item in NavigationLink(value: AppRoute.dividendDetail(item.id)) { DividendAccentRow(item: item, hidden: hidden) }.buttonStyle(.plain) } }
            SectionHeading(title: "官方公告・你持有的 ETF")
            Card(padding: 12) {
                if official.isEmpty { Text(store.data.holdings.isEmpty ? "新增持有後，這裡會列出該 ETF 的官方配息公告。" : "你持有的 ETF 目前沒有尚未記錄的公告。").font(.subheadline).foregroundStyle(Palette.muted).padding(4) }
                ForEach(Array(official.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 10) {
                        DateBox(date: DataChecks.date(entry.event.pay.isEmpty ? entry.event.ex : entry.event.pay) ?? Date())
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) { Text(entry.symbol).font(.subheadline.bold()); Text(store.name(for: entry.symbol)).font(.subheadline).lineLimit(1) }.foregroundStyle(Palette.ink)
                            Text(officialSummary(entry.event)).font(.caption).foregroundStyle(Palette.muted)
                            if store.data.holdings.filter({ $0.symbol == entry.symbol }).count > 1 {
                                Text("\(entry.holding.broker.isEmpty ? "未填券商" : entry.holding.broker)・\(decimal(entry.shares)) 股").font(.caption).foregroundStyle(Palette.muted)
                            }
                        }
                        Spacer(minLength: 4)
                        if entry.event.amount != nil { NavigationLink("加入", value: AppRoute.dividendForm(id: nil, symbol: entry.symbol, officialEx: entry.event.ex, holding: entry.holding.id)).font(.caption.bold()).buttonStyle(.bordered).buttonBorderShape(.capsule) }
                    }.padding(.vertical, 6)
                }
            }
            Text("官方公告資料日 \(store.official.sources["twse"] ?? "內建")，可到「設定 › 資料更新」立即更新。").font(.caption).foregroundStyle(Palette.muted)
        }
        .navigationTitle("近期配息").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink(value: AppRoute.dividendForm(id: nil, symbol: nil, officialEx: nil)) { Image(systemName: "plus") }.accessibilityLabel("新增配息紀錄") } }
    }
}

struct DividendDetailView: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var doneID: UUID?
    @State private var deleting = false
    @AppStorage("hideAmounts") private var hidden = false
    var body: some View {
        Page {
            if let item = store.data.dividends.first(where: { $0.id == id }) {
                Card {
                    HStack(spacing: 10) {
                        Artwork(name: "div-coins", size: 54)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(item.symbol) \(store.name(for: item.symbol))").font(.headline).foregroundStyle(Palette.ink)
                            Text("\(String(Calendar.current.component(.year, from: item.date)))年\(Calendar.current.component(.month, from: item.date))月配息").font(.caption).foregroundStyle(Palette.muted)
                        }
                        Spacer(minLength: 4)
                        StatusPill(status: item.status)
                    }
                    VStack(spacing: 0) {
                        line("配息金額（每股）", item.perShare.map { "\(decimal($0)) 元" } ?? "—")
                        line("符合資格股數", item.shares.map { "\(decimal($0)) 股" } ?? "—")
                        line("除息日", item.exDate.map(ymdText) ?? "—")
                        line("發放日", ymdText(item.date))
                    }.padding(.top, 10)
                }
                Card {
                    if let gross = item.gross {
                        line("應得股息（稅前）", "\(shown(money(gross), hidden: hidden)) 元")
                        line("扣繳費用", "− \(shown(money(item.deduction ?? 0), hidden: hidden)) 元")
                    }
                    HStack {
                        Text(item.status == .paid ? "實際入帳金額" : "預計入帳金額").font(.subheadline.bold()).foregroundStyle(Palette.blue)
                        Spacer()
                        Text("\(shown(money(item.amount), hidden: hidden)) 元").font(.title3.bold()).monospacedDigit().foregroundStyle(Palette.blue)
                    }
                    .padding(12).background(Palette.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 12)).padding(.top, 6)
                    if let source = item.source { line("紀錄類型", source) }
                    if let note = item.note, !note.isEmpty { line("備註", note) }
                }
                if item.status != .paid {
                    Button {
                        do { doneID = try store.confirmPaid(item).id } catch { store.message = error.localizedDescription }
                    } label: { Label("我已確認入帳", systemImage: "checkmark.circle.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15).foregroundStyle(Palette.blue).background(Palette.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 16)) }
                        .buttonStyle(.plain)
                }
                HStack(spacing: 12) {
                    NavigationLink(value: AppRoute.dividendForm(id: item.id, symbol: nil, officialEx: nil)) { Label("編輯", systemImage: "pencil").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12).background(Palette.card, in: RoundedRectangle(cornerRadius: 14)) }
                    Button(role: .destructive) { deleting = true } label: { Label("刪除", systemImage: "trash").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(Palette.red).background(Palette.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14)) }
                }.buttonStyle(.plain)
                Text("扣繳費用可填二代健保補充保費、匯費等實際扣除的金額；實際入帳金額以券商帳務為準。").font(.caption).foregroundStyle(Palette.muted)
                    .confirmationDialog("刪除這筆配息紀錄？", isPresented: $deleting, titleVisibility: .visible) {
                        Button("確認刪除", role: .destructive) { do { try store.removeDividend(item); dismiss() } catch { store.message = error.localizedDescription } }
                    }
            } else {
                Card { ContentUnavailableView("找不到這筆紀錄", systemImage: "calendar", description: Text("可能已被刪除。")) }
            }
        }
        .navigationTitle("配息明細").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $doneID) { DividendDoneView(id: $0).silencesScrollTop() }
    }
    private func line(_ title: String, _ value: String) -> some View {
        HStack { Text(title).font(.subheadline).foregroundStyle(Palette.muted); Spacer(); Text(value).font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.ink) }.padding(.vertical, 8)
    }
}
struct DividendDoneView: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    var body: some View {
        Page {
            if let item = store.data.dividends.first(where: { $0.id == id }) {
                VStack(spacing: 6) {
                    Artwork(name: "div-confirm", size: 180)
                    Text("配息已入帳！").font(.title.bold()).foregroundStyle(Palette.ink)
                    Text("此筆配息已依實際入帳金額完成紀錄").font(.subheadline).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity)
                Card {
                    HStack(spacing: 10) {
                        Artwork(name: "div-coins", size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(item.symbol) \(store.name(for: item.symbol))").font(.headline).foregroundStyle(Palette.ink)
                            Text("\(String(Calendar.current.component(.year, from: item.date)))年\(Calendar.current.component(.month, from: item.date))月配息").font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                    LabeledContent("實際入帳金額") { Text("\(money(item.amount)) 元").font(.title3.bold()).foregroundStyle(Palette.blue) }.padding(.top, 12)
                    LabeledContent("入帳日期", value: ymdText(item.date)).padding(.vertical, 8)
                    LabeledContent("備註", value: item.note ?? "從\(item.source ?? "證券帳務")確認")
                }.font(.subheadline)
                Button { dismiss() } label: { PrimaryButtonLabel(title: "完成", icon: "checkmark") }.buttonStyle(.plain)
                Text("金額不對？回到配息明細按「編輯」修改實際入帳金額或扣繳費用。").font(.caption).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("確認入帳").navigationBarTitleDisplayMode(.inline)
    }
}

struct DividendFormView: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.dismiss) private var dismiss
    let id: UUID?
    @State private var symbol: String
    @State private var shares = ""
    @State private var perShare = ""
    @State private var date = Date()
    @State private var hasExDate = false
    @State private var exDate = Date()
    @State private var deduction = ""
    @State private var source = DividendSource.broker
    @State private var note = ""
    @State private var total = ""
    @State private var legacy = false
    @State private var error: String?
    @State private var loaded = false
    /// 帶入 of an announcement without a payment day (the open data has none): the date is the viewer's to set.
    @State private var needsPayDate = false
    private let officialEx: String?
    /// Recorded from one holding: its shares, not every holding of the code.
    private let holdingID: UUID?
    init(id: UUID?, symbol: String?, officialEx: String?, holding: UUID? = nil) {
        self.id = id; self.officialEx = officialEx; self.holdingID = holding
        _symbol = State(initialValue: symbol ?? "")
    }
    private var code: String { symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    private var latestOfficial: OfficialDistribution? { store.official.list(code).first { $0.amount != nil } }
    var body: some View {
        Page {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ETF 代號／名稱").font(.caption.bold()).foregroundStyle(Palette.muted)
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                        TextField("例如 0050", text: $symbol).textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("dividend-symbol")
                    }.padding(11).background(Palette.cardSoft, in: RoundedRectangle(cornerRadius: 12))
                    if let fund = store.funds.first(where: { $0.id == code }) { Text(fund.name).font(.caption).foregroundStyle(Palette.muted) }
                }
                if let event = latestOfficial {
                    HStack(spacing: 8) {
                        Image(systemName: "megaphone.fill").foregroundStyle(Palette.green)
                        Text("官方公告：" + officialSummary(event, separator: "、")).font(.caption)
                        Spacer(minLength: 4)
                        Button("帶入") { apply(event) }.font(.caption.bold())
                    }.padding(10).background(Palette.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12)).padding(.top, 8)
                    if event.pay.isEmpty { Text("公告沒有發放日：帶入後請依投信公告填寫發放日期。").font(.caption).foregroundStyle(Palette.muted) }
                }
                VStack(spacing: 2) {
                    FieldRow(title: "符合資格股數") { UnitField(placeholder: "股數", text: $shares, unit: "股", identifier: "dividend-shares") }
                    if let one = holdingID.flatMap({ id in store.data.holdings.first { $0.id == id } }) {
                        Text("這筆持有：\(one.broker.isEmpty ? "未填券商" : one.broker) \(decimal(one.shares)) 股").font(.caption).foregroundStyle(Palette.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    FieldRow(title: "每股配息金額") { UnitField(placeholder: "每股", text: $perShare, unit: "元", identifier: "dividend-per-share") }
                    FieldRow(title: "發放日期") { DatePicker("發放日期", selection: $date, displayedComponents: .date).labelsHidden() }
                    FieldRow(title: "除息日（可選）") { HStack { Toggle("有除息日", isOn: $hasExDate).labelsHidden(); if hasExDate { DatePicker("除息日", selection: $exDate, displayedComponents: .date).labelsHidden() } } }
                    FieldRow(title: "扣繳費用（可選）") { UnitField(placeholder: "0", text: $deduction, unit: "元") }
                    FieldRow(title: "紀錄類型") { Picker("紀錄類型", selection: $source) { ForEach(DividendSource.allCases) { Text("\($0.rawValue)（\($0.status.rawValue)）").tag($0) } }.labelsHidden() }
                    FieldRow(title: "備註（可選）") { TextField("例如：玉山證券", text: $note) }
                    if legacy { FieldRow(title: "入帳總額") { UnitField(placeholder: "總額", text: $total, unit: "元") } }
                }.padding(.top, 10)
                if let preview { Text(preview).font(.caption).foregroundStyle(Palette.ink).padding(.top, 8) }
                if let error { Text(error).font(.caption).foregroundStyle(Palette.red).padding(.top, 6) }
            }
            HStack(spacing: 12) {
                Button { save() } label: { Text("儲存紀錄").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14).foregroundStyle(.white).background(Palette.hero, in: RoundedRectangle(cornerRadius: 14)) }.accessibilityIdentifier("save-dividend")
                Button { dismiss() } label: { Text("取消").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14).foregroundStyle(Palette.ink).background(Palette.card, in: RoundedRectangle(cornerRadius: 14)) }
            }.buttonStyle(.plain)
            Text("紀錄類型決定狀態：證券帳務＝已入帳、投信公告＝已公告、自行預估＝預估。公告與預估不計入已入帳股息。").font(.caption).foregroundStyle(Palette.muted)
        }
        .navigationTitle(id == nil ? "新增配息紀錄" : "編輯配息紀錄").navigationBarTitleDisplayMode(.inline)
        .onChange(of: date) { _, _ in needsPayDate = false }
        .onAppear(perform: load)
    }
    private var preview: String? {
        guard let s = Double(shares), let p = Double(perShare), s > 0, p > 0 else { return nil }
        let gross = (s * p).rounded(), ded = Double(deduction) ?? 0
        return "應得股息 \(money(gross)) 元\(ded > 0 ? " − 扣繳 \(money(ded)) 元" : "") ＝ \(source == .broker ? "實際入帳" : "預計入帳") \(money(gross - ded)) 元"
    }
    private func load() {
        guard !loaded else { return }; loaded = true
        if let id, let item = store.data.dividends.first(where: { $0.id == id }) {
            symbol = item.symbol; date = item.date; note = item.note ?? ""
            source = DividendSource(rawValue: item.source ?? "") ?? (item.status == .paid ? .broker : (item.status == .announced ? .announcement : .estimate))
            if let ex = item.exDate { hasExDate = true; exDate = ex }
            if let s = item.shares, let p = item.perShare { shares = decimal(s).replacingOccurrences(of: ",", with: ""); perShare = String(p); deduction = item.deduction.map { String($0) } ?? "" }
            else { legacy = true; total = String(item.amount) }
            return
        }
        if let officialEx, let event = store.official.list(code).first(where: { $0.ex == officialEx }) { apply(event) }
        else if shares.isEmpty { fillShares() }
    }
    private func fillShares() {
        let held = store.dividendShares(code, holding: holdingID)
        if held > 0 { shares = String(Int(held)) }
    }
    private func apply(_ event: OfficialDistribution) {
        if let amount = event.amount { perShare = String(amount) }
        hasExDate = true; exDate = DataChecks.date(event.ex) ?? exDate
        // Without a payment day (the open data has none) the date stays for the viewer, and it is an announcement.
        if let pay = DataChecks.date(event.pay) { date = pay; source = event.pay > DataChecks.day() ? .announcement : .broker } else { source = .announcement; needsPayDate = true }
        if shares.isEmpty { fillShares() }
    }
    private func save() {
        error = nil
        guard DataChecks.code(code) else { error = "請輸入正確的 ETF 代號。"; return }
        guard !needsPayDate else { error = "公告沒有發放日，請依投信公告選擇發放日期再儲存。"; return }
        let ded = Double(deduction.replacingOccurrences(of: ",", with: "")) ?? 0
        var item = store.data.dividends.first { $0.id == id } ?? Dividend(symbol: code, date: date, amount: 0, status: source.status)
        item.symbol = code; item.date = date; item.status = source.status; item.source = source.rawValue
        if let holdingID { item.holdingID = holdingID }
        item.exDate = hasExDate ? exDate : nil; item.note = note.isEmpty ? nil : String(note.prefix(80))
        if let s = Double(shares.replacingOccurrences(of: ",", with: "")), let p = Double(perShare), s > 0, p > 0 {
            item.shares = s; item.perShare = p; item.deduction = ded; item.amount = (s * p).rounded() - ded
        } else if legacy, let value = Double(total.replacingOccurrences(of: ",", with: "")), value > 0 {
            item.amount = value
        } else { error = "請填寫符合資格股數與每股配息金額。"; return }
        // 「記一筆配息」: a new record earns the flat +20 in the same write; the dividends page then plays the coin drop.
        do { try store.saveDividend(item, rewardNew: id == nil); dismiss() } catch { self.error = error.localizedDescription }
    }
}

struct YearDividendsView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var exportURL: URL?
    @AppStorage("hideAmounts") private var hidden = false
    var body: some View {
        let calendar = Calendar.current, now = Date()
        let paid = store.data.dividends.filter { $0.status == .paid }
        let inYear = paid.filter { calendar.component(.year, from: $0.date) == year }.sorted { $0.date > $1.date }
        let total = inYear.reduce(0) { $0 + $1.amount }
        let cutoff = calendar.date(byAdding: .year, value: -1, to: year == calendar.component(.year, from: now) ? now : (calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? now)) ?? now
        let previous = paid.filter { calendar.component(.year, from: $0.date) == year - 1 && $0.date <= cutoff }.reduce(0) { $0 + $1.amount }
        let months = (1...12).map { m in inYear.filter { calendar.component(.month, from: $0.date) == m }.reduce(0) { $0 + $1.amount } }
        let highlight = year == calendar.component(.year, from: now) ? calendar.component(.month, from: now) : (months.firstIndex(of: months.max() ?? 0) ?? 0) + 1
        Page {
            HStack(spacing: 18) {
                Button { year -= 1; exportURL = nil } label: { Image(systemName: "chevron.left").padding(8) }.accessibilityLabel("上一年")
                Text("\(String(year))年").font(.title3.bold()).foregroundStyle(Palette.ink)
                Button { year += 1; exportURL = nil } label: { Image(systemName: "chevron.right").padding(8) }.accessibilityLabel("下一年")
            }.frame(maxWidth: .infinity)
            Card {
                HStack(spacing: 10) {
                    Image(systemName: "dollarsign").font(.title3.bold()).foregroundStyle(.white).frame(width: 44, height: 44).background(LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.3), Color(red: 0.96, green: 0.64, blue: 0.06)], startPoint: .top, endPoint: .bottom), in: Circle())
                    VStack(alignment: .leading, spacing: 2) { Text("本年已入帳總金額").font(.caption).foregroundStyle(Palette.muted); Text("\(shown(money(total), hidden: hidden)) 元").font(.title2.bold()).monospacedDigit().foregroundStyle(Palette.ink) }
                    Spacer()
                    if previous > 0 { let change = (total / previous - 1) * 100; VStack(alignment: .trailing, spacing: 2) { Text("\(change >= 0 ? "▲" : "▼") \(percentText(change))").font(.subheadline.bold()).foregroundStyle(Palette.trend(change)); Text("較去年同期").font(.caption2).foregroundStyle(Palette.muted) } }
                }
                Chart(Array(months.enumerated()), id: \.offset) { index, value in
                    BarMark(x: .value("月份", "\(index + 1)月"), y: .value("金額", value))
                        .foregroundStyle(index + 1 == highlight ? Palette.blue : Palette.blue.opacity(0.4))
                        .cornerRadius(4)
                        .annotation(position: .top) { if index + 1 == highlight && value > 0 { Text(money(value)).font(.caption2.bold()).foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2).background(Palette.blue, in: Capsule()) } }
                }
                .chartYAxis(.hidden)
                .frame(height: 150).padding(.top, 14)
            }
            HStack {
                SectionHeading(title: "年度配息紀錄 (\(inYear.count)筆)")
                if let exportURL { ShareLink(item: exportURL) { Label("分享", systemImage: "square.and.arrow.up").font(.caption.bold()) } }
                else if !inYear.isEmpty { Button { exportURL = export(inYear) } label: { Label("匯出", systemImage: "square.and.arrow.down").font(.caption.bold()) } }
            }
            if inYear.isEmpty { Card { ContentUnavailableView("這一年沒有已入帳紀錄", systemImage: "tray", description: Text("入帳後的配息會依年度整理在這裡。")) } }
            VStack(spacing: 10) { ForEach(inYear) { item in NavigationLink(value: AppRoute.dividendDetail(item.id)) { DividendAccentRow(item: item, hidden: hidden) }.buttonStyle(.plain) } }
        }
        .navigationTitle("年度配息統計").navigationBarTitleDisplayMode(.inline)
    }
    private func export(_ items: [Dividend]) -> URL? {
        let quote: (String) -> String = { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        var lines = [["入帳日期", "代號", "名稱", "除息日", "每單位配息", "股數", "扣繳費用", "入帳金額", "紀錄類型", "備註"].joined(separator: ",")]
        for x in items.sorted(by: { $0.date < $1.date }) {
            let exDay: String = x.exDate.map { DataChecks.day($0) } ?? ""
            let perShare: String = x.perShare.map { String($0) } ?? ""
            let shares: String = x.shares.map { String($0) } ?? ""
            let cells: [String] = [DataChecks.day(x.date), x.symbol, store.name(for: x.symbol), exDay, perShare, shares, String(x.deduction ?? 0), String(x.amount), x.source ?? "", x.note ?? ""]
            lines.append(cells.map(quote).joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("配息紀錄-\(year).csv")
        do { try ("\u{FEFF}" + lines.joined(separator: "\r\n")).write(to: url, atomically: true, encoding: .utf8); return url } catch { store.message = error.localizedDescription; return nil }
    }
}
