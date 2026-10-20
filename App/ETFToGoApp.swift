import SwiftUI

@main struct ETFToGoApp: App {
    @StateObject private var store: PortfolioStore
    init() {
        let args = ProcessInfo.processInfo.arguments
        let testURL = args.contains("--ui-testing") ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ETFToGo/ui-test.json") : nil
        _store = StateObject(wrappedValue: PortfolioStore(url: testURL, demo: args.contains("--demo"), reset: args.contains("--reset")))
    }
    var body: some Scene { WindowGroup { RootView().environmentObject(store).preferredColorScheme(.light) } }
}
enum Palette {
    static let blue = Color(red: 0.08, green: 0.36, blue: 0.87)
    static let ink = Color(red: 0.08, green: 0.15, blue: 0.28)
    static let background = Color(red: 0.95, green: 0.97, blue: 0.99)
    static let red = Color(red: 0.75, green: 0.16, blue: 0.24)
    static let green = Color(red: 0.0, green: 0.45, blue: 0.34)
    static func strategy(_ value: Strategy) -> Color { switch value { case .saving: return blue; case .income: return Color(red: 0.0, green: 0.47, blue: 0.43); case .risk: return Color(red: 0.65, green: 0.34, blue: 0.08); case .unclassified: return .secondary } }
}
func money(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
func decimal(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: 0) { content }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.ink.opacity(0.04))) }
}
struct StrategyPill: View {
    let strategy: Strategy
    var body: some View { Label(strategy.rawValue, systemImage: strategy.symbol).font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 6).foregroundStyle(Palette.strategy(strategy)).background(Palette.strategy(strategy).opacity(0.08), in: Capsule()) }
}
struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.title3.bold()).foregroundStyle(Palette.ink); if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading) }
}
struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 22) { content }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 28) }.background(Palette.background) }
}
struct RootView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView(tab: $tab) }.tabItem { Label("首頁", systemImage: "square.grid.2x2.fill") }.tag(0)
            NavigationStack { DiscoverView() }.tabItem { Label("找 ETF", systemImage: "magnifyingglass") }.tag(1)
            NavigationStack { HoldingsView() }.tabItem { Label("我的持有", systemImage: "wallet.bifold") }.tag(2)
            NavigationStack { DividendsView() }.tabItem { Label("配息", systemImage: "calendar") }.tag(3)
            NavigationStack { ToolsView() }.tabItem { Label("工具", systemImage: "slider.horizontal.3") }.tag(4)
        }
        .tint(Palette.blue)
        .task { if !ProcessInfo.processInfo.arguments.contains("--ui-testing") { await store.refreshCatalog() } }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "--tab"), args.indices.contains(i + 1), let value = Int(args[i + 1]) { tab = value }
        }
        .alert("ETF 袋著走", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("知道了", role: .cancel) { store.message = nil } } message: { Text(store.message ?? "") }
    }
}
struct HomeView: View {
    @EnvironmentObject var store: PortfolioStore
    @Binding var tab: Int
    @State private var add = false
    private var paid: Double { store.data.dividends.filter { $0.status == .paid }.reduce(0) { $0 + $1.amount } }
    private var currentMonth: [Dividend] { store.data.dividends.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) } }
    var body: some View {
        Page {
            HStack(spacing: 12) {
                Image("Pocket").resizable().scaledToFit().frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) { Text("ETF 袋著走").font(.headline); Text("把每一份累積，看清楚。").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise").font(.headline).padding(12).background(.white, in: Circle()) }.disabled(store.refreshing).accessibilityLabel("更新持有行情")
            }
            if store.isDemo { Label("介面預覽・金額及報價均為示範", systemImage: "info.circle").font(.caption).foregroundStyle(Palette.blue) }
            VStack(alignment: .leading, spacing: 19) {
                HStack { Label("持有總市值", systemImage: "wallet.bifold").font(.subheadline); Spacer(); Text("TWD").font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 5).background(.white.opacity(0.13), in: Capsule()) }
                Text(store.data.marketValue.map(money) ?? "—").font(.system(size: 43, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1).accessibilityIdentifier("portfolio-value")
                if let value = store.data.marketValue {
                    HStack(spacing: 6) { Image(systemName: value >= store.data.cost ? "arrow.up.right" : "arrow.down.right"); Text("未實現損益 \(value >= store.data.cost ? "+" : "")\(money(value - store.data.cost))").fontWeight(.semibold) }.font(.subheadline).foregroundStyle(Color(red: 0.65, green: 0.88, blue: 1))
                } else { Text("加入持有並連接行情，即可查看估值").font(.subheadline).foregroundStyle(.white.opacity(0.8)) }
                Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
                HStack {
                    heroStat("投入成本", value: money(store.data.cost)); Spacer(); heroStat("累計已入帳股息", value: money(paid))
                }
                if !store.data.quotes.isEmpty { Text(store.isDemo ? "示範報價，非即時市場資訊" : "依已取得報價估算・不含交易費用").font(.caption2).foregroundStyle(.white.opacity(0.7)) }
            }.padding(24).foregroundStyle(.white).background(LinearGradient(colors: [Palette.blue, Color(red: 0.06, green: 0.19, blue: 0.47)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
            HStack(spacing: 12) {
                Button { add = true } label: { Label("新增持有", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 15) }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 15)).accessibilityIdentifier("home-add-holding")
                Button { tab = 3 } label: { Label("查看配息", systemImage: "calendar").frame(maxWidth: .infinity).padding(.vertical, 15) }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 15))
            }
            SectionHeading(title: "這個月，收進口袋", subtitle: Date().formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_Hant_TW"))))
            Card {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) { Text("已入帳").font(.subheadline).foregroundStyle(.secondary); Text("$\(money(currentMonth.filter { $0.status == .paid }.reduce(0) { $0 + $1.amount }))").font(.title.bold()).foregroundStyle(Palette.ink) }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 9) { Text("已公告待入帳").font(.subheadline).foregroundStyle(.secondary); Text("$\(money(currentMonth.filter { $0.status == .announced }.reduce(0) { $0 + $1.amount }))").font(.title2.bold()).foregroundStyle(Palette.blue) }
                }
                Divider().padding(.vertical, 12)
                if currentMonth.isEmpty { Text("新增一筆配息，開始記錄你的現金流。").font(.subheadline).foregroundStyle(.secondary) }
                else { ForEach(currentMonth.prefix(2)) { item in HStack { Text(item.symbol).font(.subheadline.bold()); Text(item.date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_Hant_TW")))).font(.caption).foregroundStyle(.secondary); Spacer(); Text(item.status.rawValue).font(.caption).foregroundStyle(item.status == .paid ? Palette.green : Palette.blue) }.padding(.vertical, 4) } }
            }
            HStack { SectionHeading(title: "我的配置", subtitle: "依投入成本計算"); Button("查看全部") { tab = 2 }.font(.subheadline) }
            Card {
                if store.data.holdings.isEmpty { Label("你的第一筆投資，從這裡開始。", systemImage: "leaf").foregroundStyle(.secondary) }
                else { ForEach(Strategy.allCases) { strategy in
                    let amount = store.data.holdings.filter { $0.strategy == strategy }.reduce(0) { $0 + $1.cost }
                    if amount > 0 { VStack(spacing: 8) { HStack { StrategyPill(strategy: strategy); Spacer(); Text("\(Int(amount / max(store.data.cost, 1) * 100))%").font(.subheadline.bold()) }; ProgressView(value: amount, total: max(store.data.cost, 1)).tint(Palette.strategy(strategy)) }.padding(.bottom, 12) }
                } }
            }
        }.toolbar(.hidden, for: .navigationBar).sheet(isPresented: $add) { HoldingEditor() }
    }
    private func heroStat(_ title: String, value: String) -> some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.caption).foregroundStyle(.white.opacity(0.75)); Text(value).font(.title3.bold()).monospacedDigit() } }
}
struct FundRow: View {
    @EnvironmentObject var store: PortfolioStore
    let fund: Fund
    var body: some View {
        HStack(spacing: 13) {
            Text(String(fund.id.suffix(2))).font(.system(.title3, design: .rounded).bold()).foregroundStyle(Palette.strategy(fund.strategy)).frame(width: 46, height: 46).background(Palette.strategy(fund.strategy).opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 6) { Text(fund.name).font(.subheadline.bold()).foregroundStyle(Palette.ink); HStack { Text(fund.id).font(.caption).foregroundStyle(.secondary); Text("· \(fund.strategy.rawValue)").font(.caption).foregroundStyle(Palette.strategy(fund.strategy)) } }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) { Text(store.data.quotes[fund.id].map { decimal($0.price) } ?? "—").font(.headline).foregroundStyle(Palette.ink); Text(store.data.quotes[fund.id] == nil ? "尚未取得報價" : (store.isDemo ? "示範報價" : store.data.quotes[fund.id]!.date)).font(.system(size: 10)).foregroundStyle(.secondary) }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }.padding(.vertical, 8)
    }
}
struct DiscoverView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var query = ""
    @State private var filter = "全部"
    @State private var favoritesOnly = false
    @FocusState private var searchFocused: Bool
    var funds: [Fund] { store.funds.filter { (query.isEmpty || $0.id.localizedCaseInsensitiveContains(query) || $0.name.localizedCaseInsensitiveContains(query)) && (filter == "全部" || $0.strategy.rawValue == filter) && (!favoritesOnly || store.data.favorites.contains($0.id)) } }
    var body: some View {
        let visible = funds
        Page {
            Text("找到適合你的累積方式").font(.subheadline).foregroundStyle(.secondary)
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("搜尋代碼或名稱", text: $query).autocorrectionDisabled().textInputAutocapitalization(.never).focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }.accessibilityIdentifier("fund-search"); if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除搜尋") } }.padding(15).background(.white, in: RoundedRectangle(cornerRadius: 16))
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(["全部"] + Strategy.allCases.filter { $0 != .unclassified }.map(\.rawValue), id: \.self) { value in Button { filter = value } label: { Text(value).font(.subheadline.weight(.semibold)).padding(.horizontal, 17).padding(.vertical, 11).background(filter == value ? Palette.blue : .white, in: Capsule()).foregroundStyle(filter == value ? .white : Palette.ink) } } } }
            if filter != "全部", let s = Strategy(rawValue: filter) { Text("\(s.subtitle)・策略標籤不代表保本或保證獲利。").font(.caption).foregroundStyle(.secondary) }
            HStack { Text("ETF 清單").font(.title3.bold()); Text("\(visible.count)").font(.caption.bold()).padding(6).background(.white, in: Circle()); Spacer(); Button { favoritesOnly.toggle() } label: { Label("收藏", systemImage: favoritesOnly ? "star.fill" : "star") }.font(.subheadline) }
            Card {
                if visible.isEmpty { ContentUnavailableView.search(text: query) }
                ForEach(visible) { fund in
                    NavigationLink(value: fund) { FundRow(fund: fund) }
                    if fund.id != visible.last?.id { Divider() }
                }
            }
            Text(store.isDemo ? "示範清單；正式模式使用上市與上櫃名單。" : "上市 \(store.funds.filter { $0.market == "TWSE" }.count) · 上櫃 \(store.funds.filter { $0.market == "TPEx" }.count) 個代碼。外幣級別分開計數，代碼數不等於獨立基金數。" ).font(.caption).foregroundStyle(.secondary)
        if let catalog = store.catalog, !store.isDemo { Text("上市資料日 \(catalog.listedDate) · 上櫃取得日 \(catalog.fetchedDay)").font(.caption).foregroundStyle(.secondary) }; if let message = store.catalogMessage { Text(message).font(.caption).foregroundStyle(.secondary) }; Button(store.catalogRefreshing ? "更新中…" : "更新上市櫃名單") { Task { await store.refreshCatalog() } }.disabled(store.catalogRefreshing || store.isDemo)
        }.navigationTitle("找 ETF").navigationDestination(for: Fund.self) { FundDetail(fund: $0) }
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成搜尋") { searchFocused = false } } }
    }
}
struct FundDetail: View {
    @EnvironmentObject var store: PortfolioStore
    let fund: Fund
    @State private var add = false
    var body: some View {
        Page {
            StrategyPill(strategy: fund.strategy)
            Text(fund.name).font(.title.bold())
            Card { Text("最近取得的報價").font(.subheadline).foregroundStyle(.secondary); Text(store.data.quotes[fund.id].map { "$\(decimal($0.price))" } ?? "尚未連線").font(.largeTitle.bold()).padding(.vertical, 8); Text(store.data.quotes[fund.id].map { "報價日期：\($0.date)" } ?? "接上你的富果行情後即可更新。").font(.caption).foregroundStyle(.secondary); Button("更新這檔報價") { Task { await store.refresh(symbols: [fund.id]) } }.buttonStyle(.bordered).disabled(store.refreshing).padding(.top, 10) }
            Button { add = true } label: { Label("新增到我的持有", systemImage: "plus").frame(maxWidth: .infinity).padding(10) }.buttonStyle(.borderedProminent)
            Card { Label("策略怎麼看", systemImage: "info.circle").font(.headline); Text("\(fund.strategy.rawValue)是整理持有的方式，不是收益保證。配息可能來自收益或本金；槓桿策略需注意每日重設及波動風險。").font(.subheadline).foregroundStyle(.secondary).padding(.top, 8) }
        Card {
                NavigationLink("成分股與權重") { ComponentsView(symbol: fund.id) }.padding(.vertical, 10)
                Divider()
                NavigationLink("歷史績效") { HistoryView(symbol: fund.id) }.padding(.vertical, 10)
                Divider()
                NavigationLink("費用率與級距") { FeesView(fund: fund) }.padding(.vertical, 10)
            }
        }.navigationTitle(fund.id).navigationBarTitleDisplayMode(.inline).toolbar { Button { store.favorite(fund.id) } label: { Image(systemName: store.data.favorites.contains(fund.id) ? "star.fill" : "star") }.accessibilityLabel("切換收藏") }.sheet(isPresented: $add) { HoldingEditor(fund: fund) }
    }
}
