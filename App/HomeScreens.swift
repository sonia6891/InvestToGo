import SwiftUI
import Charts

/// Every pushed screen, so all five tab stacks share one set of destinations.
enum AppRoute: Hashable {
    case overview, monthDividends(next: Bool), notices, settings, sources, privacy, about
    case recentDividends, yearDividends, dividendDetail(UUID), dividendForm(id: UUID?, symbol: String?, officialEx: String?, holding: UUID? = nil), dividendDone(UUID)
    case holdingDetail(UUID), holdingForm(id: UUID?, symbol: String?), tradeForm
    case watchlist, basis(String)
    case plan, goal, calculator, comparison, exposure, backup, broker, connection, reminders
    case stock(String), combo, comboAdding(String), comboSettings, comboResult, trades, allocation
}
struct RouteView: View {
    let route: AppRoute
    var body: some View {
        switch route {
        case .overview: OverviewView()
        case .monthDividends(let next): MonthDividendsView(startNextMonth: next)
        case .notices: NoticesView()
        case .settings: SettingsView()
        case .sources: SourcesView()
        case .privacy: PrivacyView()
        case .about: AboutView()
        case .recentDividends: RecentDividendsView()
        case .yearDividends: YearDividendsView()
        case .dividendDetail(let id): DividendDetailView(id: id)
        case .dividendForm(let id, let symbol, let ex, let holding): DividendFormView(id: id, symbol: symbol, officialEx: ex, holding: holding)
        case .dividendDone(let id): DividendDoneView(id: id)
        case .holdingDetail(let id): HoldingDetailView(id: id)
        case .holdingForm(let id, let symbol): HoldingFormView(id: id, symbol: symbol)
        case .tradeForm: TradeFormView()
        case .watchlist: WatchlistView()
        case .basis(let symbol): BasisView(symbol: symbol)
        case .plan: PlanView()
        case .goal: GoalView()
        case .calculator: CalculatorView()
        case .comparison: ComparisonView()
        case .exposure: ExposureView()
        case .backup: BackupView()
        case .broker: BrokerView()
        case .connection: ConnectionView()
        case .reminders: ReminderCenterView()
        case .stock(let symbol): StockDetailView(symbol: symbol)
        case .combo: ComboView()
        case .comboAdding(let symbol): ComboView(addSymbol: symbol)
        case .comboSettings: ComboSettingsView()
        case .comboResult: ComboResultView()
        case .trades: Page { TradeLogSection() }.navigationTitle("交易紀錄").navigationBarTitleDisplayMode(.inline)
        case .allocation: Page { AllocationSection() }.navigationTitle("資產配置").navigationBarTitleDisplayMode(.inline)
        }
    }
}
extension View {
    func appRoutes() -> some View {
        navigationDestination(for: AppRoute.self) { RouteView(route: $0).tabBarSpace() }
            .navigationDestination(for: Fund.self) { FundDetail(fund: $0).tabBarSpace() }
    }
}

/* ---------- notices ---------- */
struct AppNotice: Identifiable {
    let id: String
    let kind: String
    let icon: String
    let color: Color
    let text: String
    let day: String
    let route: AppRoute?
    /// Built from the user's dividend records, official announcements for held ETFs and app news.
    @MainActor static func all(_ store: PortfolioStore) -> [AppNotice] {
        let calendar = Calendar.current, today = calendar.startOfDay(for: Date()), todayText = DataChecks.day()
        let past = calendar.date(byAdding: .day, value: -60, to: today) ?? today, soon = calendar.date(byAdding: .day, value: 14, to: today) ?? today
        var items: [AppNotice] = []
        for x in store.data.dividends where x.status == .paid && x.date >= past && x.date <= Date() {
            items.append(AppNotice(id: "paid-\(x.id.uuidString)", kind: "配息入帳通知", icon: "calendar", color: Palette.pink, text: "\(x.symbol) 已入帳股息 \(money(x.amount)) 元", day: DataChecks.day(x.date), route: .dividendDetail(x.id)))
        }
        for x in store.data.dividends where x.status != .paid && x.date >= today && x.date <= soon {
            items.append(AppNotice(id: "due-\(x.id.uuidString)-\(DataChecks.day(x.date))", kind: "配息提醒", icon: "bell.fill", color: Palette.orange, text: "\(x.symbol) 預計 \(monthDay(x.date)) 入帳 \(money(x.amount)) 元", day: todayText, route: .dividendDetail(x.id)))
        }
        let horizon = DataChecks.day(calendar.date(byAdding: .day, value: 30, to: today) ?? today)
        var announced = Set<String>()  // one notice per code and ex-date, however many holdings it has
        for entry in store.officialForHoldings() where entry.event.ex >= todayText && entry.event.ex <= horizon {
            guard announced.insert(entry.symbol + entry.event.ex).inserted else { continue }
            let ex = entry.event.ex.suffix(5).replacingOccurrences(of: "-", with: "/")
            items.append(AppNotice(id: "ex-\(entry.symbol)-\(entry.event.ex)", kind: "除息公告", icon: "megaphone.fill", color: Palette.blue, text: "\(entry.symbol) 將於 \(ex) 除息\(entry.event.amount.map { "，每單位 \(decimal($0)) 元" } ?? "，金額待公布")", day: todayText, route: .dividendForm(id: nil, symbol: entry.symbol, officialEx: entry.event.ex)))
        }
        items.append(AppNotice(id: "app-2026-10-16", kind: "App 重要通知", icon: "sparkles", color: Palette.purple, text: "新版介面上線：資產總覽、交易紀錄、配息明細、年度統計與官方配息資料", day: "2026-10-16", route: nil))
        items.append(AppNotice(id: "tip-yield", kind: "投資知識分享", icon: "book.fill", color: Palette.teal, text: "配息率不等於報酬率：配息可能來自本金，記得一起看淨值變化。", day: "2026-10-16", route: nil))
        return items.sorted { $0.day > $1.day }
    }
}
struct NoticesView: View {
    @EnvironmentObject var store: PortfolioStore
    @AppStorage("readNotices") private var readNotices = ""
    @State private var tab = 0
    private var readIDs: Set<String> { Set(readNotices.split(separator: ",").map(String.init)) }
    var body: some View {
        let all = AppNotice.all(store), unread = all.filter { !readIDs.contains($0.id) }, read = all.filter { readIDs.contains($0.id) }
        let list = [all, unread, read][tab]
        Page {
            SegmentBar(items: ["全部 (\(all.count))", "未讀 (\(unread.count))", "已讀 (\(read.count))"], selection: $tab, pill: true, filled: true)
            Card(padding: 12) {
                if list.isEmpty { ContentUnavailableView("沒有通知", systemImage: "bell", description: Text("配息入帳、除息公告與資料更新會出現在這裡。")) }
                ForEach(list) { notice in
                    if let route = notice.route {
                        NavigationLink(value: route) { row(notice, unread: !readIDs.contains(notice.id)) }.buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded { markRead(notice.id) })
                    } else {
                        Button { markRead(notice.id) } label: { row(notice, unread: !readIDs.contains(notice.id)) }.buttonStyle(.plain)
                    }
                    if notice.id != list.last?.id { Divider() }
                }
            }
            NavigationLink(value: AppRoute.reminders) { Card(padding: 12) { ToolRow(title: "配息入帳提醒", subtitle: "在預計入帳日早上 9 點以本機通知提醒", icon: "bell.badge") } }.buttonStyle(.plain)
            Text("通知依你的配息紀錄、持有 ETF 的官方除息公告與 App 消息整理。").font(.caption).foregroundStyle(Palette.muted)
        }
        .navigationTitle("通知中心").navigationBarTitleDisplayMode(.inline)
        .toolbar { if !unread.isEmpty { ToolbarItem(placement: .topBarTrailing) { Button("全部已讀") { readNotices = (readIDs.union(all.map(\.id))).sorted().suffix(300).joined(separator: ",") } } } }
    }
    private func markRead(_ id: String) { var ids = readIDs; ids.insert(id); readNotices = ids.sorted().suffix(300).joined(separator: ",") }
    private func row(_ notice: AppNotice, unread: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: notice.icon).font(.headline).foregroundStyle(.white).frame(width: 38, height: 38).background(notice.color, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                HStack { Text(notice.kind).font(.subheadline.bold()).foregroundStyle(Palette.ink); Spacer(); Text(DataChecks.date(notice.day).map(monthDay) ?? "").font(.caption2).monospacedDigit().foregroundStyle(Palette.muted) }
                Text(notice.text).font(.caption).foregroundStyle(Palette.muted).multilineTextAlignment(.leading)
            }
            if unread { Circle().fill(Palette.red).frame(width: 8, height: 8).accessibilityLabel("未讀") }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/* ---------- asset overview ---------- */
struct OverviewView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var range = ChartRange.year
    @State private var spread = 0
    @AppStorage("hideAmounts") private var hidden = false
    private func fund(_ h: Holding) -> Fund { store.funds.first { $0.id == h.symbol } ?? Fund(id: h.symbol, name: h.name, strategy: h.strategy) }
    private func spreadKey(_ h: Holding) -> String {
        switch spread {
        case 0: return fund(h).industry ?? fund(h).assetKind
        case 1: return fund(h).region
        default: return store.data.quotes[h.symbol]?.isTWD == false ? "外幣" : "新台幣"
        }
    }
    var body: some View {
        let summary = store.summary
        let useValue = summary.marketValue != nil
        let value: (Holding) -> Double = { h in useValue ? (store.marketValue(of: h) ?? 0) : h.cost }
        let points = TrendMath.slice(TrendMath.portfolio(store.effectiveData), range)
        let total = store.data.holdings.reduce(0.0) { $0 + value($1) }
        let structure = makeSlices(store.data.holdings, key: { fund($0).assetKind }, value: value)
        Page {
            RangeChips(options: [.week, .month, .quarter, .year, .all], selection: $range)
            Card {
                HStack {
                    SectionHeading(title: "資產歷史走勢")
                    if points.count >= 2 { let change = (points.last!.value / max(points.first!.value, 0.000001) - 1) * 100; Text(percentText(change)).font(.caption.bold()).monospacedDigit().foregroundStyle(Palette.trend(change)) }
                }
                if points.count >= 2 { ValueChart(points: points, showAxes: true, height: 160).padding(.top, 12) }
                else { Text("每檔持有都取得報價與歷史走勢後才會顯示，不用試算資料代替。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 8) }
            }
            Card {
                SectionHeading(title: "資產結構 (TWD)")
                if structure.isEmpty { Text("還沒有持有紀錄。").foregroundStyle(Palette.muted).padding(.top, 8) }
                else { DonutChart(slices: structure, center: ("總資產", shown(wanText(total), hidden: hidden)), showAmounts: true, hidden: hidden).padding(.top, 12) }
                Text("\(useValue ? "依持有市值" : "尚缺報價，暫依投入成本")・依 ETF 類型分為股票、債券、商品；不含未記錄的現金。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 10)
            }
            Card {
                SectionHeading(title: "持有標的分布")
                SegmentBar(items: ["產業", "國家", "幣別"], selection: $spread, pill: true).padding(.vertical, 12)
                let rows = makeSlices(store.data.holdings, key: { spreadKey($0) }, value: value)
                if rows.isEmpty { Text("還沒有持有紀錄。").foregroundStyle(Palette.muted) } else { BarList(slices: rows) }
                Text(["依 ETF 名稱歸類的主題，債券與商品另列；不是成分股的產業權重（成分股請看持股透視）。", "依基金類型與名稱判斷投資地區。", "依報價的交易幣別；外幣級別不計入台幣市值。"][spread]).font(.caption).foregroundStyle(Palette.muted).padding(.top, 10)
            }
        }
        .navigationTitle("資產總覽").navigationBarTitleDisplayMode(.inline)
    }
}

/* ---------- this month's dividends ---------- */
struct MonthDividendsView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var month: Date
    @State private var tab: Int
    @AppStorage("hideAmounts") private var hidden = false
    init(startNextMonth: Bool) {
        let calendar = Calendar.current, start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        _month = State(initialValue: startNextMonth ? (calendar.date(byAdding: .month, value: 1, to: start) ?? start) : start)
        _tab = State(initialValue: startNextMonth ? 1 : 0)
    }
    var body: some View {
        let calendar = Calendar.current
        let entries = store.data.dividends.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }.sorted { $0.date < $1.date }
        let paid = entries.filter { $0.status == .paid }, pending = entries.filter { $0.status != .paid }
        let history = store.data.dividends.filter { $0.status == .paid && $0.date < month }.sorted { $0.date > $1.date }.prefix(3)
        Page {
            MonthSwitcher(month: $month)
            HStack(spacing: 10) {
                bigTile("已領配息", amount: paid.reduce(0) { $0 + $1.amount }, note: "\(paid.count) 筆已入帳", art: "div-coins", tint: Palette.orange, valueColor: Palette.ink)
                bigTile("待領配息", amount: pending.reduce(0) { $0 + $1.amount }, note: "\(pending.count) 筆預估入帳", art: "div-calendar", tint: Palette.pink, valueColor: Palette.pink)
            }
            SegmentBar(items: ["已領配息 (\(paid.count))", "待領配息 (\(pending.count))"], selection: $tab, pill: true, filled: true)
            Card(padding: 12) {
                let list = tab == 0 ? paid : pending
                if list.isEmpty { Text("這個月沒有紀錄。").font(.subheadline).foregroundStyle(Palette.muted).padding(4) }
                ForEach(list) { item in NavigationLink(value: AppRoute.dividendDetail(item.id)) { DividendDateRow(item: item, hidden: hidden) }.buttonStyle(.plain) }
            }
            HStack { SectionHeading(title: "歷史紀錄"); NavigationLink(value: AppRoute.yearDividends) { HStack(spacing: 2) { Text("查看全部"); Image(systemName: "chevron.right") }.font(.caption.bold()) } }
            Card(padding: 12) {
                if history.isEmpty { Text("還沒有更早的已入帳紀錄。").font(.subheadline).foregroundStyle(Palette.muted).padding(4) }
                ForEach(Array(history)) { item in NavigationLink(value: AppRoute.dividendDetail(item.id)) { DividendDateRow(item: item, hidden: hidden) }.buttonStyle(.plain) }
            }
        }
        .navigationTitle("本月股息").navigationBarTitleDisplayMode(.inline)
    }
    private func bigTile(_ title: String, amount: Double, note: String, art: String, tint: Color, valueColor: Color) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.bold()).foregroundStyle(Palette.ink)
                Text(shown(money(amount), hidden: hidden)).font(.title2.bold()).monospacedDigit().foregroundStyle(valueColor).minimumScaleFactor(0.6).lineLimit(1)
                Text(note).font(.caption2).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            Artwork(name: art, size: 54)
        }
        .padding(12)
        .background(LinearGradient(colors: [tint.opacity(0.16), Palette.card], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: Palette.blue.opacity(0.06), radius: 8, y: 3)
    }
}
struct MonthSwitcher: View {
    @Binding var month: Date
    var body: some View {
        HStack(spacing: 18) {
            Button { change(-1) } label: { Image(systemName: "chevron.left").padding(8) }.accessibilityLabel("上一個月")
            Text("\(String(Calendar.current.component(.year, from: month)))年 \(Calendar.current.component(.month, from: month))月").font(.title3.bold()).monospacedDigit().foregroundStyle(Palette.ink).frame(minWidth: 130)
            Button { change(1) } label: { Image(systemName: "chevron.right").padding(8) }.accessibilityLabel("下一個月")
        }.frame(maxWidth: .infinity)
    }
    private func change(_ amount: Int) { month = Calendar.current.date(byAdding: .month, value: amount, to: month) ?? month }
}
/// Date box, ETF, status and amount: the design's dividend list row.
struct DividendDateRow: View {
    @EnvironmentObject var store: PortfolioStore
    let item: Dividend
    var hidden = false
    var body: some View {
        HStack(spacing: 10) {
            DateBox(date: item.date)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) { Text(item.symbol).font(.subheadline.bold()); Text(store.name(for: item.symbol)).font(.subheadline).lineLimit(1) }.foregroundStyle(Palette.ink)
                StatusPill(status: item.status)
            }
            Spacer(minLength: 6)
            Text(shown(money(item.amount), hidden: hidden)).font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.ink)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/* ---------- settings ---------- */
struct SettingsView: View {
    @EnvironmentObject var store: PortfolioStore
    @AppStorage("appearance") private var appearance = "light"
    @AppStorage("hideAmounts") private var hidden = false
    @AppStorage(SellCosts.netKey) private var netValue = true
    @State private var feeRates: [String: FeeRate] = [:]
    var body: some View {
        Page {
            Card(padding: 12) {
                row("sun.max.fill", Palette.orange, "外觀設定") {
                    Picker("外觀設定", selection: $appearance) { Text("淺色").tag("light"); Text("深色").tag("dark"); Text("跟隨系統").tag("system") }.pickerStyle(.segmented).frame(width: 190)
                }
                Divider()
                row("eye.fill", Palette.blue, "隱藏金額") { Toggle("隱藏金額", isOn: $hidden).labelsHidden().tint(Palette.blue) }
            }
            Card(padding: 12) {
                row("dollarsign.circle.fill", Palette.green, "市值扣除預估賣出費用") { Toggle("市值扣除預估賣出費用", isOn: $netValue).labelsHidden().tint(Palette.blue) }
                if netValue {
                    // The brokers in the holdings, then a default for any other.
                    ForEach(Set(store.data.holdings.map { SellCosts.brokerKey($0.broker) }).filter { !$0.isEmpty }.sorted() + [""], id: \.self) { broker in
                        Divider()
                        feeRow(broker)
                    }
                }
                Text(netValue ? "市值＝股數 × 收盤價 − 預估賣出手續費（0.1425% × 折扣，無條件捨去，不低於最低手續費）− 證交稅（股票 0.3%、ETF 0.1%、債券 ETF 免稅）。國泰、永豐金、元大、富邦、凱基、群益先帶入常見的電子下單優惠，其他券商用原價（不打折、最低 20 元）；每個帳戶的優惠不同，請改成你自己的折扣。融資部位用同一家券商的折扣。"
                     : "市值＝股數 × 收盤價，不扣賣出手續費與證交稅。")
                    .font(.caption).foregroundStyle(Palette.muted).padding(.top, 6)
            }
            .onChange(of: netValue) { _, _ in store.objectWillChange.send() }
            .onAppear { feeRates = SellCosts.rates() }
            Card(padding: 12) {
                link("cylinder.split.1x2.fill", Palette.blue, "資料更新", "報價、配息與 ETF 名單的更新狀態", .sources)
                Divider()
                link("icloud.and.arrow.up.fill", Palette.teal, "資料備份與還原", "本地匯出・匯入", .backup)
                Divider()
                link("key.fill", Palette.purple, "富果行情連線", "使用你自己的 API Key", .connection)
                Divider()
                link("checkmark.shield.fill", Palette.green, "隱私與安全", "資料存放與金鑰保存", .privacy)
                Divider()
                link("info.circle.fill", Palette.deepBlue, "關於 投資袋著走", "版本・使用說明", .about)
            }
        }
        .navigationTitle("設定").navigationBarTitleDisplayMode(.inline)
    }
    /// One broker's discount and minimum fee; editing either stores the broker's own rate.
    private func feeRow(_ broker: String) -> some View {
        let shown = feeRates[broker] ?? (broker.isEmpty ? SellCosts.standard : SellCosts.preset(for: broker) ?? feeRates[""] ?? SellCosts.standard)
        func field(_ path: WritableKeyPath<FeeRate, Double>) -> Binding<Double> {
            Binding(get: { shown[keyPath: path] }, set: { value in
                var rate = shown; rate[keyPath: path] = value
                feeRates[broker] = rate.valid
                SellCosts.save(feeRates)
                store.objectWillChange.send()
            })
        }
        let name = broker.isEmpty ? "其他券商（預設）" : broker
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(name).font(.subheadline.bold()).foregroundStyle(Palette.ink)
                if feeRates[broker] == nil {
                    if SellCosts.preset(for: broker) != nil { Text("常見優惠").font(.caption2.bold()).foregroundStyle(Palette.blue) }
                    else { Text(broker.isEmpty || feeRates[""] == nil ? "未設定・原價" : "未設定・用預設").font(.caption2.bold()).foregroundStyle(Palette.orange) }
                }
            }
            HStack(spacing: 6) {
                Text("折扣").font(.caption).foregroundStyle(Palette.muted)
                TextField("10", value: field(\.discount), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .frame(width: 56).textFieldStyle(.roundedBorder).accessibilityLabel("\(name) 手續費折扣（折）")
                Text("折").font(.caption).foregroundStyle(Palette.muted)
                Spacer(minLength: 8)
                Text("最低").font(.caption).foregroundStyle(Palette.muted)
                TextField("20", value: field(\.minimum), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .frame(width: 56).textFieldStyle(.roundedBorder).accessibilityLabel("\(name) 最低手續費（元）")
                Text("元").font(.caption).foregroundStyle(Palette.muted)
            }
        }.padding(.vertical, 6)
    }
    private func row<Trailing: View>(_ icon: String, _ color: Color, _ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(.white).frame(width: 30, height: 30).background(color, in: RoundedRectangle(cornerRadius: 9))
            Text(title).font(.subheadline.bold()).foregroundStyle(Palette.ink)
            Spacer(minLength: 6)
            trailing()
        }.padding(.vertical, 6)
    }
    private func link(_ icon: String, _ color: Color, _ title: String, _ subtitle: String, _ route: AppRoute) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.subheadline).foregroundStyle(.white).frame(width: 30, height: 30).background(color, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.bold()).foregroundStyle(Palette.ink); Text(subtitle).font(.caption).foregroundStyle(Palette.muted) }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
            }.padding(.vertical, 6).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
struct SourcesView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var hasKey = false
    var body: some View {
        let lastTrade = (store.data.trades ?? []).max { $0.date < $1.date }
        let latestQuote = store.data.quotes.values.map(\.fetchedAt).max()
        Page {
            Card(padding: 12) {
                row("chart.bar.fill", Palette.blue, "市場報價（台股）", status: hasKey ? ("盤中即時", Palette.green) : ("每日收盤", Palette.blue), lines: hasKey ? ["最後更新：\(latestQuote.map { $0.formatted(date: .numeric, time: .shortened) } ?? "—")"] : ["收盤資料日：\(store.daily?.day.replacingOccurrences(of: "-", with: "/") ?? "—")", "看盤中即時價：在「行情連線」貼上自己的金鑰"]) {
                    Button(store.refreshing ? "更新中…" : "立即更新") { Task { await store.refresh() } }.disabled(store.refreshing)
                }
                Divider()
                row("bag.fill", Palette.orange, "我的持有", status: ("已儲存", Palette.green), lines: ["最後異動：\(lastTrade.map { ymdText($0.date) } ?? "—")"]) {
                    NavigationLink("匯入／更新", value: AppRoute.broker)
                }
                Divider()
                row("calendar", Palette.pink, "配息資料", status: ("官方公告", Palette.green), lines: ["更新：上市 \(store.official.sources["twse"] ?? "—")・上櫃 \(store.official.sources["tpex"] ?? "—")"]) {
                    Button(store.officialRefreshing ? "更新中…" : "立即更新") { Task { await store.refreshOfficial() } }.disabled(store.officialRefreshing)
                }
                Divider()
                row("list.bullet.rectangle", Palette.teal, "ETF 名單", status: ("官方名單", Palette.green), lines: ["上市資料日 \(store.catalog?.listedDate ?? "—")・上櫃取得日 \(store.catalog?.fetchedDay ?? "—")", "共 \(store.catalog?.funds.count ?? 0) 個代碼"]) {
                    Button(store.catalogRefreshing ? "更新中…" : "立即更新") { Task { await store.refreshCatalog() } }.disabled(store.catalogRefreshing)
                }
                Divider()
                row("powerplug.fill", Palette.muted, "外部整合", status: ("未連線", Palette.red), lines: ["第三方券商整合（開發中）"]) { Button("連結帳戶") {}.disabled(true) }
            }
            if let message = store.officialMessage ?? store.catalogMessage { Text(message).font(.caption).foregroundStyle(Palette.muted) }
            Text("你自己的配息紀錄仍以券商入帳為準；官方資料用來帶入每單位金額與日期、推算配息頻率。上櫃 ETF 只有近期除權息預告，沒有歷史紀錄與發放日。").font(.caption).foregroundStyle(Palette.muted)
        }
        .navigationTitle("資料更新").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await store.refreshOfficial(); if !store.data.holdings.isEmpty { await store.refresh() } } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("全部更新") } }
        .onAppear { hasKey = !((try? SecureKey.read()) ?? "").isEmpty }
    }
    private func row<Action: View>(_ icon: String, _ color: Color, _ title: String, status: (String, Color), lines: [String], @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.headline).foregroundStyle(.white).frame(width: 40, height: 40).background(color, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) { Text(title).font(.subheadline.bold()).foregroundStyle(Palette.ink); TintPill(title: "● \(status.0)", color: status.1) }
                ForEach(lines, id: \.self) { Text($0).font(.caption).foregroundStyle(Palette.muted) }
            }
            Spacer(minLength: 4)
            action().font(.caption.bold()).buttonStyle(.bordered).buttonBorderShape(.capsule)
        }.padding(.vertical, 8)
    }
}
struct PrivacyView: View {
    var body: some View {
        Page {
            Card { Text("資料存放").font(.headline).foregroundStyle(Palette.ink); Text("持有、配息與交易紀錄只存在這支 iPhone 的 App 資料夾，可在「資料備份與還原」匯出。").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 6) }
            Card { Text("富果金鑰").font(.headline).foregroundStyle(Palette.ink); Text("使用 iOS Keychain 保存，只傳給富果官方 API，不寫入備份。").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 6) }
            Card { Text("Face ID・應用程式鎖定").font(.headline).foregroundStyle(Palette.ink); Text("目前未提供 App 內上鎖；可用 iPhone 設定的「螢幕使用時間」限制，或使用 iOS 18 以上的「鎖定 App」。").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 6) }
        }
        .navigationTitle("隱私與安全").navigationBarTitleDisplayMode(.inline)
    }
}
struct AboutView: View {
    @EnvironmentObject var store: PortfolioStore
    var body: some View {
        Page {
            Card {
                VStack(spacing: 8) {
                    Image("Pocket").resizable().scaledToFit().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 18))
                    Text("投資袋著走").font(.title3.bold()).foregroundStyle(Palette.ink)
                    Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")").font(.caption).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity)
            }
            Card { Text("使用說明").font(.headline).foregroundStyle(Palette.ink); Text("策略分類依 ETF 名稱規則整理，不是投資建議或收益保證。沒有可靠資料的欄位不顯示估計值；試算結果是情境假設。").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 6) }
            Card {
                Text("資料來源與授權").font(.headline).foregroundStyle(Palette.ink)
                VStack(alignment: .leading, spacing: 8) {
                    Text("每日開盤、收盤價與指數衍生自臺灣證券交易所「上市個股日成交資訊」「每日收盤行情－大盤統計資訊」及證券櫃檯買賣中心「上櫃股票收盤行情」「櫃買指數歷史資料」，該資料係依據政府資料開放授權條款（Open Government Data License）進行公眾釋出，使用者於遵守本條款各項規定之前提下，得利用之。")
                    Link("政府資料開放授權條款：data.gov.tw/license", destination: URL(string: "https://data.gov.tw/license")!).font(.subheadline.bold())
                    Text("公司基本資料、ETF 名單（臺灣證券交易所「基金基本資料彙總表」）與配息公告（「上市股票除權除息預告表」「上櫃股票除權除息預告表」）同樣取自兩所的開放資料。使用你自己的富果金鑰時，盤中行情由富果提供；資訊來源：臺灣證券交易所、證券櫃檯買賣中心。")
                    Text("本 App 與上述機構沒有合作或背書關係；資料僅供參考，交易請以券商與交易所公告為準。")
                }.font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 6)
            }
        }
        .navigationTitle("關於 投資袋著走").navigationBarTitleDisplayMode(.inline)
    }
}
