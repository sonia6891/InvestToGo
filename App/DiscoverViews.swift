import SwiftUI
import Charts

/// Filters from the design: market, management, strategy, industry, distribution frequency, asset class and structure.
struct FundFilter: Equatable {
    var strategies: Set<Strategy> = []
    var markets: Set<String> = []
    var management: String? = nil
    var themes: Set<String> = []
    var industries: Set<String> = []
    var frequencies: Set<String> = []
    var assets: Set<String> = []
    var structures: Set<String> = []
    var isEmpty: Bool { self == FundFilter() }
    func matches(_ fund: Fund, frequency: String?) -> Bool {
        if !strategies.isEmpty && !strategies.contains(fund.strategy) { return false }
        if !markets.isEmpty && !markets.contains(fund.marketName) { return false }
        if let management, management != fund.managementType { return false }
        if !themes.isEmpty && !themes.contains(fund.theme) { return false }
        if !industries.isEmpty && !industries.contains(fund.industry ?? "") { return false }
        if !frequencies.isEmpty && !frequencies.contains(frequency ?? "") { return false }
        if !assets.isEmpty && !assets.contains(fund.assetKind) { return false }
        if !structures.isEmpty && !structures.contains(fund.structure) { return false }
        return true
    }
    var chips: [String] {
        var result: [String] = Strategy.allCases.filter { strategies.contains($0) }.map(\.rawValue)
        result += markets.sorted()
        if let management { result.append(management) }
        result += themes.sorted()
        result += industries.sorted()
        result += frequencies.sorted()
        result += assets.sorted()
        result += structures.sorted()
        return result
    }
    mutating func remove(_ chip: String) {
        if let strategy = Strategy(rawValue: chip) { strategies.remove(strategy) }
        if management == chip { management = nil }
        markets.remove(chip); themes.remove(chip); industries.remove(chip); frequencies.remove(chip); assets.remove(chip); structures.remove(chip)
    }
}
enum FilterGroup: CaseIterable {
    case market, management, theme, industry, frequency, asset, structure
    var title: String { ["交易市場", "管理方式", "投資策略", "產業類別", "配息頻率", "資產類別", "商品結構"][Self.allCases.firstIndex(of: self)!] }
    var icon: String { ["building.columns", "gearshape", "chart.bar.fill", "square.stack.3d.up", "calendar", "chart.pie", "point.3.connected.trianglepath.dotted"][Self.allCases.firstIndex(of: self)!] }
    var options: [String] {
        switch self {
        case .market: return ["上市", "上櫃"]
        case .management: return ["主動型", "被動型"]
        case .theme: return ["市值型", "高股息", "產業主題"]
        case .industry: return ["科技", "金融", "傳產", "跨產業"]
        case .frequency: return ["月配", "雙月配", "季配", "半年配", "年配", "不配息"]
        case .asset: return ["股票", "債券", "商品"]
        case .structure: return ["一般型", "槓桿型", "反向型"]
        }
    }
    func isOn(_ filter: FundFilter, _ option: String) -> Bool {
        switch self {
        case .market: return filter.markets.contains(option)
        case .management: return filter.management == option
        case .theme: return filter.themes.contains(option)
        case .industry: return filter.industries.contains(option)
        case .frequency: return filter.frequencies.contains(option)
        case .asset: return filter.assets.contains(option)
        case .structure: return filter.structures.contains(option)
        }
    }
    func isEmpty(_ filter: FundFilter) -> Bool { options.allSatisfy { !isOn(filter, $0) } }
    func toggle(_ filter: inout FundFilter, _ option: String?) {
        guard let option else { clear(&filter); return }
        func flip(_ set: inout Set<String>) { if set.contains(option) { set.remove(option) } else { set.insert(option) } }
        switch self {
        case .market: flip(&filter.markets)
        case .management: filter.management = filter.management == option ? nil : option
        case .theme: flip(&filter.themes)
        case .industry: flip(&filter.industries)
        case .frequency: flip(&filter.frequencies)
        case .asset: flip(&filter.assets)
        case .structure: flip(&filter.structures)
        }
    }
    func clear(_ filter: inout FundFilter) {
        switch self {
        case .market: filter.markets = []
        case .management: filter.management = nil
        case .theme: filter.themes = []
        case .industry: filter.industries = []
        case .frequency: filter.frequencies = []
        case .asset: filter.assets = []
        case .structure: filter.structures = []
        }
    }
}
struct OptionChip: View {
    let title: String
    let on: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(on ? .white : Palette.ink)
                .background(on ? Palette.blue : Palette.cardSoft, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// 找 ETF (spec 5.4): title with the skin's magnifier, the search box, series chips (全部、市值型、高股息、債券、主題) and
/// the list: code in the big numeral font, name, price and the day's move as ▲/▼ with a percentage.
struct DiscoverView: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.skin) private var skin
    @ObservedObject private var connectivity = Connectivity.shared
    @State private var query = ""
    /// The series chip; nil is 全部.
    @State private var series: DexSeries?
    /// 更多條件: the full filter sheet, on top of the series.
    @State private var filter = FundFilter()
    @State private var showFilter = false
    @FocusState private var searchFocused: Bool
    private var funds: [Fund] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return store.funds.filter { fund in
            (series == nil || DexSeries.of(fund) == series)
                && filter.matches(fund, frequency: store.official.frequency(fund.id))
                && (text.isEmpty || fund.id.localizedCaseInsensitiveContains(text) || fund.name.localizedCaseInsensitiveContains(text))
        }
    }
    var body: some View {
        let items = funds
        Page {
            header
            SkinSearchField(text: $query, prompt: "輸入代號或名稱", focus: $searchFocused, identifier: "fund-search")
                .onSubmit { searchFocused = false }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    SkinChip("全部", selected: series == nil) { series = nil }
                    ForEach(DexSeries.allCases, id: \.self) { item in
                        SkinChip(item.rawValue, selected: series == item) { series = series == item ? nil : item }
                    }
                }
            }
            countRow(items.count)
            if store.catalogRefreshing { LoadingFloat(art: .find) }
            else if store.catalogFailed || connectivity.offline {
                // The list below is still the last one that came through (spec 9 讀取失敗).
                LoadFailed(message: connectivity.offline ? "目前沒有網路，先顯示上次取得的 ETF 名單。" : "ETF 名單這次沒有更新成功，先顯示上次的名單。",
                           retry: { Task { await store.refreshCatalog() } },
                           lastUpdated: LoadFailed.stamp(store.catalog?.fetchedAt, day: store.catalog?.fetchedDay))
            }
            list(items)
            footer
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成搜尋") { searchFocused = false } } }
        .sheet(isPresented: $showFilter) { FilterSheet(filter: $filter).silencesScrollTop() }
        .onAppear(perform: applyRequest)
        .onChange(of: store.discoverRequest) { _, _ in applyRequest() }
    }
    private func applyRequest() {
        guard let request = store.discoverRequest else { return }
        store.discoverRequest = nil
        if request.search {
            // A search from the home page starts clean, so an earlier ETF filter cannot hide its results.
            filter = FundFilter(); series = nil; query = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { searchFocused = true }
        }
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FIND×ETF").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
                Text("找 ETF").skinFont(.title(34)).skinForeground(\.ink)
                Text("台灣上市・上櫃 ETF").skinFont(.body(12)).skinForeground(\.sub)
            }
            Spacer(minLength: 8)
            // The skin's decoration stays inside the magnifier's own square, away from the title and the search box.
            SkinImage(.find).frame(width: 104, height: 104)
                .background(SkinDecor(page: .other))
                .accessibilityHidden(true)
        }
    }
    private func countRow(_ count: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(series?.rawValue ?? "全部") · \(count) 檔").skinFont(.mono(11)).skinForeground(\.sub)
            Spacer(minLength: 8)
            if !filter.isEmpty {
                Button("清除條件") { filter = FundFilter() }.buttonStyle(.plain)
                    .skinFont(.mono(11)).skinForeground(\.sub).frame(minHeight: 44)
            }
            Button(filter.isEmpty ? "更多條件" : "更多條件（\(filter.chips.count)）") { showFilter = true }.buttonStyle(.plain)
                .skinFont(.mono(11)).foregroundStyle(skin.lightText ? skin.color(\.accent) : skin.color(\.ink)).frame(minHeight: 44)
        }
    }
    @ViewBuilder private func list(_ items: [Fund]) -> some View {
        if items.isEmpty {
            Text(query.isEmpty ? "沒有符合條件的 ETF" : "找不到「\(query)」").skinFont(.body(14)).skinForeground(\.sub)
                .frame(maxWidth: .infinity).padding(.vertical, 24)
        }
        LazyVStack(spacing: 0) {
            ForEach(items) { fund in
                NavigationLink(value: fund) { FundRow(fund: fund) }.buttonStyle(.plain)
                Rectangle().fill(skin.color(\.line)).frame(height: 1).accessibilityHidden(true)
            }
        }
    }
    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("上市 \(store.funds.filter { $0.market == "TWSE" }.count) · 上櫃 \(store.funds.filter { $0.market == "TPEx" }.count) 個代碼。系列依名稱與基金類型歸類；配息頻率依近一年除息次數推算。")
            if let catalog = store.catalog { Text("上市資料日 \(catalog.listedDate) · 上櫃取得日 \(catalog.fetchedDay)") }
            if let message = store.catalogMessage, !store.catalogFailed { Text(message) }
        }
        .skinFont(.body(11)).skinForeground(\.sub)
        Button(store.catalogRefreshing ? "更新中…" : "更新上市櫃名單") { Task { await store.refreshCatalog() } }
            .buttonStyle(.plain).skinFont(.mono(11)).skinForeground(\.ink).frame(minHeight: 44)
            .disabled(store.catalogRefreshing)
    }
}
/// One 找 ETF row: code (big numerals) and name, price and the day's move.
struct FundRow: View {
    @EnvironmentObject var store: PortfolioStore
    let fund: Fund
    var body: some View {
        let quote = store.quote(fund.id)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(fund.id).skinFont(.big(22)).skinForeground(\.ink).lineLimit(1).minimumScaleFactor(0.6)
                Text(fund.name).skinFont(.body(12)).skinForeground(\.sub).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(quote.map { priceText($0.price) } ?? "—").skinFont(.mono(14)).skinForeground(\.ink)
                SkinChange(quote: quote, size: 11).accessibilityIdentifier("fund-change-\(fund.id)")
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
/// 完整分類: every filter group from the design.
struct FilterSheet: View {
    @EnvironmentObject var store: PortfolioStore
    @Binding var filter: FundFilter
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let count = store.funds.filter { filter.matches($0, frequency: store.official.frequency($0.id)) }.count
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(FilterGroup.allCases.filter { $0 != .frequency || !store.official.freq.isEmpty }, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(group.title, systemImage: group.icon).font(.headline).foregroundStyle(Palette.ink)
                            FlowChips {
                                OptionChip(title: "全部", on: group.isEmpty(filter)) { group.clear(&filter) }
                                ForEach(group.options, id: \.self) { option in OptionChip(title: option, on: group.isOn(filter, option)) { group.toggle(&filter, option) } }
                            }
                        }.padding(.vertical, 12)
                        Divider()
                    }
                    Text("交易市場、資產類別依官方名單的基金類型；產業與商品結構依名稱歸類；配息頻率依近一年除息次數推算，需累積滿一年的官方公告（上櫃 ETF 不提供），在那之前不列入篩選。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 12)
                }
                .padding(20)
            }
            .background { Palette.page.ignoresSafeArea() }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button { filter = FundFilter() } label: { Text("清除條件").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14).foregroundStyle(Palette.ink).background(Palette.card, in: RoundedRectangle(cornerRadius: 14)) }
                    Button { dismiss() } label: { Text("查看 \(count) 檔結果").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14).foregroundStyle(.white).background(Palette.hero, in: RoundedRectangle(cornerRadius: 14)) }
                }.buttonStyle(.plain).padding(.horizontal, 20).padding(.vertical, 10).background(.ultraThinMaterial)
            }
            .navigationTitle("完整分類").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("關閉") } }
        }
        .presentationDetents([.large])
    }
}
/// Wrapping row of chips.
struct FlowChips<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { FlowLayout(spacing: 8) { content } }
}
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing; row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}

struct WatchlistView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var tab = 0
    @State private var editing = false
    @State private var selection: [String] = []
    @State private var compare = false
    var body: some View {
        let favorites = store.data.favorites.sorted().map { code in store.funds.first { $0.id == code } ?? Fund(id: code, name: store.name(for: code), strategy: .unclassified) }
        let groups = [favorites, favorites.filter { $0.market == "TWSE" }, favorites.filter { $0.market == "TPEx" }]
        let chosen = selection.isEmpty ? Array(favorites.prefix(3).map(\.id)) : selection
        Page {
            SegmentBar(items: ["全部 (\(groups[0].count))", "台灣上市 (\(groups[1].count))", "台灣上櫃 (\(groups[2].count))"], selection: $tab, pill: true, filled: true)
            Card(padding: 12) {
                if groups[tab].isEmpty { ContentUnavailableView("還沒有自選", systemImage: "star", description: Text("在探索清單或詳情頁點星號，就能把 ETF 加入自選。")) }
                VStack(spacing: 0) {
                    if !groups[tab].isEmpty {
                        HStack(spacing: 8) { if editing { Spacer().frame(width: 22) }; Text("代號／名稱"); Spacer(); Text("最新價").frame(width: 64, alignment: .trailing); Text("漲跌").frame(width: 58, alignment: .trailing); Text("自選").frame(width: 30) }
                            .font(.caption2.bold()).foregroundStyle(Palette.muted).padding(.bottom, 6)
                    }
                    ForEach(groups[tab]) { fund in
                        let quote = store.quote(fund.id), picked = chosen.contains(fund.id)
                        Divider()
                        HStack(spacing: 8) {
                            if editing {
                                Button { toggle(fund.id, chosen: chosen) } label: { Image(systemName: picked ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(picked ? Palette.blue : Palette.muted) }
                                    .buttonStyle(.plain).frame(width: 22).accessibilityLabel(picked ? "取消選取 \(fund.id)" : "選取 \(fund.id)")
                            }
                            SymbolLink(symbol: fund.id) {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) { HStack(spacing: 4) { Text(fund.id).font(.subheadline.bold()); MarketBadge(symbol: fund.id) }; Text(fund.name).font(.caption2).foregroundStyle(Palette.muted).lineLimit(1) }
                                    Spacer(minLength: 4)
                                    Text(quote.map { priceText($0.price) } ?? "--").font(.subheadline.bold()).monospacedDigit().frame(width: 64, alignment: .trailing)
                                    Text(quote?.changePercent.map(percentText) ?? "--").font(.caption.bold()).monospacedDigit().foregroundStyle(quote?.changePercent.map(Palette.trend) ?? Palette.muted).frame(width: 58, alignment: .trailing)
                                }.contentShape(Rectangle())
                            }
                            Button { store.favorite(fund.id) } label: { Image(systemName: "star.fill").foregroundStyle(Palette.orange) }.buttonStyle(.plain).frame(width: 30).accessibilityLabel("取消自選 \(fund.id)")
                        }
                        .foregroundStyle(Palette.ink)
                        .padding(.vertical, 10)
                    }
                }
            }
            if editing { Text("點選要比較的 ETF，最多 3 檔。").font(.caption).foregroundStyle(Palette.muted) }
            if !favorites.isEmpty {
                Button {
                    var next = store.data; next.comparison = Array(chosen.prefix(3))
                    do { try store.commit(next); editing = false; compare = true } catch { store.message = error.localizedDescription }
                } label: { Text("比較所選標的 (\(min(chosen.count, 3)))").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13).foregroundStyle(Palette.blue).overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.blue, lineWidth: 1.5)) }
                    .buttonStyle(.plain).disabled(chosen.count < 2)
            }
        }
        .navigationTitle("我的自選").navigationBarTitleDisplayMode(.inline)
        .toolbar { if !favorites.isEmpty { ToolbarItem(placement: .topBarTrailing) { Button(editing ? "完成" : "編輯") { if !editing && selection.isEmpty { selection = Array(favorites.prefix(3).map(\.id)) }; editing.toggle() } } } }
        .navigationDestination(isPresented: $compare) { ComparisonView().gameBarSpace().silencesScrollTop() }
    }
    private func toggle(_ code: String, chosen: [String]) {
        var next = chosen
        if let i = next.firstIndex(of: code) { next.remove(at: i) } else if next.count < 3 { next.append(code) } else { store.message = "最多比較 3 檔。"; return }
        selection = next
    }
}

/// ETF 詳情 (spec 5.5): the big code, name, series tag, price and move; tabs 走勢／持股／配息／資訊; the skin's trend
/// line with 1月／3月／1年／5年／全部 and four facts; 「加入口袋」 and 「用 0050 試算定期定額」. The first visit collects the
/// fund's dex card (spec 6.4) and shows 「收進圖鑑 +30 經驗」 once.
struct FundDetail: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.skin) private var skin
    @ObservedObject private var connectivity = Connectivity.shared
    @Environment(\.motionReduced) private var reduceMotion
    let fund: Fund
    @State private var section = 0
    @State private var range = ChartRange.year
    @State private var collected = false
    private static let tabs = ["走勢", "持股", "配息", "資訊"]
    private var quote: Quote? { store.quote(fund.id) }
    var body: some View {
        Page {
            if store.quoteFailure != nil || connectivity.offline {
                // The price below is still the last one that came through (spec 9 讀取失敗).
                LoadFailed(message: connectivity.offline ? "目前沒有網路，先顯示上次的報價。" : "報價這次沒有更新成功：\(store.quoteFailure ?? "")",
                           retry: { Task { await store.refresh(symbols: [fund.id], inline: true) } },
                           lastUpdated: LoadFailed.stamp(quote?.fetchedAt, day: quote?.date))
            }
            header
            HStack(spacing: 6) {
                ForEach(Self.tabs.indices, id: \.self) { i in SkinChip(Self.tabs[i], selected: section == i) { section = i } }
            }
            switch section {
            case 1: FundHoldingsContent(fund: fund)
            case 2: FundDividends(fund: fund)
            case 3: FundInfo(fund: fund)
            default: trend
            }
        }
        .safeAreaInset(edge: .bottom) { actions }
        .overlay(alignment: .top) { if collected { toast } }
        .task { await store.refreshDaily() }
        .onAppear {
            store.quoteFailure = nil
            store.liveFocus = fund.id; store.live.syncSoon()
            if store.collectDexCard(fund.id) { showToast() }
        }
        .onDisappear { if store.liveFocus == fund.id { store.liveFocus = nil; store.live.syncSoon() } }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                LiveQuoteButton(symbol: fund.id, market: fund.market)
                favoriteButton
                ShareLink(item: "\(fund.id) \(fund.name)｜投資袋著走") { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("分享")
            }
        }
    }
    private var favoriteButton: some View {
        let on = store.data.favorites.contains(fund.id)
        return Button { store.favorite(fund.id) } label: { Text(on ? "★ 已收藏" : "☆ 收藏").skinFont(.mono(12)).skinForeground(\.sub) }
            .accessibilityLabel(on ? "取消收藏" : "收藏")
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ETF×\(fund.id)").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
                    Text(fund.id).skinFont(.big(84)).skinForeground(\.ink).lineLimit(1).minimumScaleFactor(0.5)
                        .accessibilityIdentifier("detail-code")
                }
                Spacer(minLength: 8)
                NavigationLink(value: AppRoute.dexCard(fund.id)) { Text("圖鑑卡") }
                    .buttonStyle(SkinButtonStyle(primary: false, horizontal: 16, seed: SkinSeed.of("圖鑑卡")))
            }
            HStack(spacing: 10) {
                Text(fund.name).skinFont(.title(18)).skinForeground(\.ink).lineLimit(2)
                SkinTag(DexSeries.of(fund).rawValue)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(quote.map { priceText($0.price) } ?? "—").skinFont(.mono(24)).skinForeground(\.ink)
                SkinChange(quote: quote, size: 12, withAmount: true)
            }
            HStack {
                Text(updatedText).skinFont(.mono(10)).skinForeground(\.sub)
                Spacer(minLength: 8)
                Button(store.refreshing ? "更新中…" : "更新報價") { Task { await store.refresh(symbols: [fund.id], inline: true) } }
                    .buttonStyle(.plain).skinFont(.mono(11)).skinForeground(\.ink).frame(minHeight: 44).disabled(store.refreshing)
            }
        }
    }
    private var updatedText: String {
        guard let quote else { return "尚無報價・按「更新報價」取得" }
        if quote.isDailyClose { return "\(quote.date.replacingOccurrences(of: "-", with: "/")) 收盤價" }
        return "報價日期 \(quote.date) · 取得於 \(quote.fetchedAt.formatted(date: .abbreviated, time: .shortened))"
    }
    /// 走勢: the line, the four facts, then fetching the history and its statistics.
    private var trend: some View {
        let points = store.data.histories?[fund.id].map(TrendMath.points) ?? []
        let visible = TrendMath.slice(points, range)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 4) {
                ForEach([ChartRange.month, .quarter, .year, .fiveYears, .all]) { option in
                    SkinChip(option.rawValue, selected: range == option) { range = option }
                }
            }
            if visible.count >= 2 {
                SkinTrendLine(points: visible, height: 150)
                Text("還原日收盤價 · 資料至 \(store.data.histories?[fund.id]?.points.last?.date ?? "")").skinFont(.mono(10)).skinForeground(\.sub)
            } else {
                VStack(spacing: 6) {
                    Text("尚無歷史資料").skinFont(.title(15)).skinForeground(\.ink)
                    Text("用你的行情金鑰取得還原日收盤價後才畫走勢，不用試算資料代替。").skinFont(.body(12)).skinForeground(\.sub)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
            facts
            HistoryContent(symbol: fund.id)
        }
    }
    /// 內扣費用、近一年殖利率、配息頻率、成分股數; "—" when a fact is not known.
    private var facts: some View {
        let fee = AnnualFeeCatalog.bundled?.records[fund.id]
        let items: [(String, String)] = [
            (fee.map { "\(decimal($0.total))%" } ?? "—", "內扣費用 / 年"),
            (store.trailingYield(fund.id).map { "\(decimal($0))%" } ?? "—", "近一年殖利率"),
            (store.official.frequency(fund.id) ?? "—", "配息頻率"),
            (store.data.components?[fund.id].map { "\($0.components.count) 檔" } ?? "—", "成分股"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 24, alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 3) {
                    Text(items[i].0).skinFont(.mono(16)).skinForeground(\.ink)
                    Text(items[i].1).skinFont(.body(11)).skinForeground(\.sub)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .overlay(alignment: .top) { Rectangle().fill(skin.color(\.line)).frame(height: 1) }
                .accessibilityElement(children: .combine)
            }
        }
    }
    /// The main button and the DCA link, kept above the game bar.
    private var actions: some View {
        VStack(spacing: 0) {
            NavigationLink(value: AppRoute.holdingForm(id: nil, symbol: fund.id)) { Text("加入口袋") }
                .buttonStyle(SkinButtonStyle(primary: true, seed: SkinSeed.of("加入口袋")))
            NavigationLink(value: AppRoute.comboAdding(fund.id)) {
                Text("→ 用 \(fund.id) 試算定期定額 ←").skinFont(.mono(11)).skinForeground(\.sub)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("用 \(fund.id) 試算定期定額")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .background(skin.color(\.page).ignoresSafeArea(edges: .bottom))
    }
    private var toastText: String { "收進圖鑑 +\(GameRules.xp[.firstDexCard] ?? 0) 經驗" }
    private var toast: some View {
        Text(toastText)
            .skinFont(.title(14))
            .foregroundStyle(skin.onFill(skin.colors.accent))
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(Capsule().fill(skin.color(\.accent)))
            .padding(.top, 8)
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }
    private func showToast() {
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .snappy
        withAnimation(animation) { collected = true }
        AccessibilityNotification.Announcement(toastText).post()
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(animation) { collected = false }
        }
    }
}
/// 持股 tab: component weights from the existing research view, plus fund facts.
struct FundHoldingsContent: View {
    @EnvironmentObject var store: PortfolioStore
    let fund: Fund
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let snapshot = store.data.components?[fund.id] {
                let top = snapshot.components.sorted { $0.weight > $1.weight }.prefix(10)
                let topWeight = top.reduce(0.0) { $0 + $1.weight }
                let five = Array(top.prefix(5))
                let rest = max(100 - five.reduce(0.0) { $0 + $1.weight }, 0)
                let named: [Slice] = five.enumerated().map { pair in Slice(label: pair.element.name ?? pair.element.symbol, amount: pair.element.weight, color: Palette.series[pair.offset]) }
                let rows: [Slice] = named + [Slice(label: "其他", amount: rest, color: Palette.series[6])]
                SkinPanel {
                    HStack { SectionHeading(title: "持股組成"); Text("前十大合計 \(decimal(topWeight))%").font(.caption.bold()).foregroundStyle(Palette.blue) }
                    DonutChart(slices: rows, center: ("前十大", "\(decimal(topWeight))%")).padding(.top, 12)
                    Text("資料日 \(snapshot.date)").font(.caption).foregroundStyle(Palette.muted).padding(.top, 8)
                }
            }
            ComponentsContent(symbol: fund.id)
            SkinPanel {
                SectionHeading(title: "基金資訊")
                let fee = AnnualFeeCatalog.bundled?.records[fund.id]
                VStack(spacing: 0) {
                    if let issuer = fund.issuer { line("基金公司", issuer) }
                    if let full = fund.fullName { line("基金全名", full) }
                    if let type = fund.fundType { line("基金類型", type) }
                    if let fee { line("經理費", "\(decimal(fee.management))%（\(String(fee.year)) 年實際）"); line("年度總費用率", "\(decimal(fee.total))%") }
                    if let frequency = store.official.frequency(fund.id) { line("配息頻率", frequency) }
                    if let listing = fund.listingDate { line("掛牌日期", listing) }
                }.padding(.top, 6)
                Text("基金公司依基金名稱判斷；費用為公布的年度實際比率。追蹤指數、基金規模與保管銀行暫不顯示。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 8)
            }
        }
    }
    private func line(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) { Text(title).font(.subheadline).foregroundStyle(Palette.muted); Spacer(minLength: 12); Text(value).font(.subheadline).foregroundStyle(Palette.ink).multilineTextAlignment(.trailing) }.padding(.vertical, 7)
    }
}
struct FundDividends: View {
    @EnvironmentObject var store: PortfolioStore
    let fund: Fund
    @AppStorage("hideAmounts") private var hidden = false
    var body: some View {
        let items = store.data.dividends.filter { $0.symbol == fund.id }.sorted { $0.date > $1.date }
        let official = Array(store.official.list(fund.id).prefix(12))
        VStack(alignment: .leading, spacing: 14) {
            SkinPanel {
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text("官方配息頻率").font(.caption).foregroundStyle(Palette.muted); Text(store.official.frequency(fund.id) ?? (store.official.coversYear ? "未收錄" : "累積中")).font(.title2.bold()).foregroundStyle(Palette.ink) }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) { Text("你記錄的已入帳").font(.caption).foregroundStyle(Palette.muted); Text(shown(money(items.filter { $0.status == .paid }.reduce(0) { $0 + $1.amount }), hidden: hidden)).font(.title3.bold()).monospacedDigit().foregroundStyle(Palette.ink) }
                }
            }
            SkinPanel {
                if official.isEmpty {
                    Text(store.official.coversYear ? "近一年沒有這檔的除息公告。" : "目前沒有這檔的除息公告；官方公告自 \((store.official.since ?? "").replacingOccurrences(of: "-", with: "/")) 起累積。").font(.subheadline).foregroundStyle(Palette.muted).padding(4)
                } else {
                    VStack(spacing: 8) {
                        HStack { Text("除息日").frame(maxWidth: .infinity, alignment: .leading); Text("發放日").frame(maxWidth: .infinity, alignment: .leading); Text("每單位").frame(width: 80, alignment: .trailing) }.font(.caption2.bold()).foregroundStyle(Palette.muted)
                        ForEach(official, id: \.self) { event in
                            HStack {
                                Text(event.ex.replacingOccurrences(of: "-", with: "/")).font(.caption).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
                                Text(event.pay.isEmpty ? "—" : event.pay.replacingOccurrences(of: "-", with: "/")).font(.caption).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
                                Text(event.amount.map { "\(decimal($0)) 元" } ?? "待公布").font(.caption.bold()).monospacedDigit().frame(width: 80, alignment: .trailing)
                            }.foregroundStyle(Palette.ink)
                        }
                        Text("交易所開放資料只有除息日與金額，沒有發放日，請以投信公告為準。").font(.caption).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            NavigationLink(value: AppRoute.dividendForm(id: nil, symbol: fund.id, officialEx: nil)) { PrimaryButtonLabel(title: "記錄這檔配息") }.buttonStyle(.plain)
            VStack(spacing: 10) { ForEach(items) { item in NavigationLink(value: AppRoute.dividendDetail(item.id)) { DividendAccentRow(item: item, hidden: hidden) }.buttonStyle(.plain) } }
        }
    }
}
struct FundInfo: View {
    let fund: Fund
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SkinPanel {
                Text("基本資料").font(.headline).foregroundStyle(Palette.ink).padding(.bottom, 6)
                row("代號", fund.id); row("名稱", fund.name)
                if let full = fund.fullName { row("基金全名", full) }
                if let type = fund.fundType { row("基金類型", type) }
                row("管理方式", fund.managementType); row("資產類別", fund.assetKind); row("商品結構", fund.structure); row("投資地區", fund.region)
                row("市場", fund.marketName)
                if let listing = fund.listingDate { row("掛牌日期", listing) }
            }
            // Was the 總覽 tab: the system's label for the fund, what it means, and where the label comes from.
            SkinPanel {
                Text("系統分類：\(fund.strategy.rawValue)・風險\(fund.riskLevel)").font(.headline).foregroundStyle(Palette.ink)
                Text(fund.strategy.explanation + (fund.strategy == .unclassified ? "" : fund.riskSentence)).font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 8)
                NavigationLink(value: AppRoute.basis(fund.id)) { HStack(spacing: 2) { Text("為什麼這樣分類？查看分類依據"); Image(systemName: "chevron.right") }.font(.caption.bold()).frame(minHeight: 44) }
                Text("策略分類是整理持有的方式，不是收益保證。配息可能來自收益或本金；槓桿策略需注意每日重設及波動風險。").font(.caption).foregroundStyle(Palette.muted)
            }
            FeesContent(fund: fund)
        }
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).font(.subheadline).foregroundStyle(Palette.muted)
            Spacer(minLength: 12)
            Text(value).font(.subheadline).foregroundStyle(Palette.ink).multilineTextAlignment(.trailing)
        }.padding(.vertical, 6)
    }
}
/// 分類依據: the measured facets and how the label was actually assigned.
struct BasisView: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    var body: some View {
        let fund = store.funds.first { $0.id == symbol } ?? Fund(id: symbol, name: store.name(for: symbol), strategy: .unclassified)
        let stats = store.data.histories?[symbol].flatMap { try? PerformanceStats($0) }
        let components = store.data.components?[symbol]
        let yearAgo = DataChecks.day(Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date())
        let recent = store.official.list(symbol).filter { $0.ex > yearAgo && $0.ex <= DataChecks.day() }.count
        let missing = stats == nil || components == nil
        let topTen: Double? = components.map { snapshot in snapshot.components.sorted { $0.weight > $1.weight }.prefix(10).reduce(0.0) { $0 + $1.weight } }
        Page {
            Card {
                SectionHeading(title: "系統評估的主要面向")
                HStack(spacing: 8) {
                    facet("point.3.connected.trianglepath.dotted", Palette.purple, "分散性", topTen.map { "前十大 \(decimal($0))%" } ?? "需成分資料")
                    facet("waveform.path.ecg", Palette.teal, "波動度", stats?.volatility.map { "年化 \(decimal($0 * 100))%" } ?? "需歷史資料")
                    facet("chart.line.downtrend.xyaxis", Palette.red, "最大回檔", stats.map { "\(decimal($0.drawdown * 100))%" } ?? "需歷史資料")
                    facet("dollarsign", Palette.orange, "配息歷史", store.official.frequency(symbol).map { "\($0)・近一年 \(recent) 次" } ?? (store.official.coversYear ? "未收錄" : "累積中"))
                }.padding(.top, 12)
            }
            Card {
                Label("系統自動判讀", systemImage: "cpu").font(.headline).foregroundStyle(Palette.ink)
                Text("依 ETF 名稱規則，歸類為：").font(.subheadline).foregroundStyle(Palette.ink).padding(.top, 8)
                HStack(spacing: 8) {
                    TagChip(title: fund.strategy.tagline, icon: "tag.fill", art: fund.strategy.artwork)
                    if missing { TagChip(title: "資料不足：待觀察", icon: "info.circle", tint: Palette.blue) }
                }.padding(.top, 6)
                Text("上面四個面向是輔助參考的實際數據，目前分類只依名稱規則，不是綜合評分。\(missing ? "取得歷史走勢與成分股後，會顯示完整數據。" : "")").font(.caption).foregroundStyle(Palette.muted).padding(.top, 10)
            }
            Card {
                Label("用途不等於風險等級", systemImage: "info.circle.fill").font(.headline).foregroundStyle(Palette.blue)
                Text("分類是協助你快速理解 ETF 可能的用途，不代表報酬保證，也不直接等同於風險等級。投資前請詳閱公開說明書。").font(.subheadline).foregroundStyle(Palette.ink).padding(.top, 6)
            }
            Card { Text(Strategy.basis).font(.caption).foregroundStyle(Palette.ink) }
            HStack(spacing: 10) {
                StatTile(title: "資料基準日", value: store.catalog?.listedDate ?? "—", icon: "calendar")
            }
        }
        .navigationTitle("分類依據").navigationBarTitleDisplayMode(.inline)
    }
    private func facet(_ icon: String, _ color: Color, _ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.subheadline.bold()).foregroundStyle(.white).frame(width: 34, height: 34).background(color, in: RoundedRectangle(cornerRadius: 10))
            Text(title).font(.caption.bold()).foregroundStyle(Palette.ink)
            Text(value).font(.caption2).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 2)
        .background(Palette.cardSoft, in: RoundedRectangle(cornerRadius: 14))
    }
}
