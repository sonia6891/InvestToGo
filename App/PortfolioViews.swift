import SwiftUI
import Charts

enum HoldingSort: String, CaseIterable, Identifiable {
    case value = "市值大小", cost = "成本大小", profit = "損益", symbol = "代號"
    var id: String { rawValue }
}
extension PortfolioStore {
    func fund(for holding: Holding) -> Fund { funds.first { $0.id == holding.symbol } ?? Fund(id: holding.symbol, name: holding.name, strategy: holding.strategy) }
    /// 市值 as brokers show it: after the estimated selling fee and tax (SellCosts), unless that is turned off.
    func marketValue(of holding: Holding) -> Double? {
        guard let quote = quote(holding.symbol), quote.isTWD else { return nil }
        let gross = quote.price * holding.shares
        guard SellCosts.enabled else { return gross }
        return SellCosts.net(gross, stock: isStock(holding.symbol), bond: fund(for: holding).assetKind == "債券", rate: SellCosts.rate(for: holding.broker))
    }
}
struct HoldingsView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var kind = 0
    @AppStorage("hideAmounts") private var hidden = false
    var body: some View {
        let holdings = store.data.holdings
        let stocks = sorted(holdings.filter { store.isStock($0.symbol) })
        let etfs = sorted(holdings.filter { !store.isStock($0.symbol) })
        let stockValue = stocks.reduce(0.0) { $0 + (store.marketValue(of: $1) ?? 0) }
        let etfValue = etfs.reduce(0.0) { $0 + (store.marketValue(of: $1) ?? 0) }
        let missing = holdings.filter { store.marketValue(of: $0) == nil }.count
        Page {
            HStack {
                Text("我的持有").font(.title.bold()).foregroundStyle(Palette.ink)
                Spacer()
                NavigationLink(value: AppRoute.holdingForm(id: nil, symbol: nil)) {
                    Label("新增持有", systemImage: "plus").font(.subheadline.bold()).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8).background(Palette.hero, in: Capsule())
                }.accessibilityIdentifier("add-holding")
            }.padding(.top, 6)
            SegmentBar(items: ["全部", "個股", "ETF"], selection: $kind, pill: true, filled: true)
            hero(stockValue: stockValue, etfValue: etfValue)
            if holdings.isEmpty {
                Card {
                    ContentUnavailableView("把股票與 ETF 放進口袋", systemImage: "bag", description: Text("選擇股票或 ETF，填入股數與總成本，之後就能持續追蹤。"))
                    NavigationLink(value: AppRoute.holdingForm(id: nil, symbol: nil)) { PrimaryButtonLabel(title: "新增持有") }.buttonStyle(.plain)
                }
            } else {
                dataRow(holdings)
                if kind != 2 && !stocks.isEmpty { table(title: "個股持有", items: stocks, tint: Palette.pink) }
                if kind != 1 && !etfs.isEmpty { table(title: "ETF 持有", items: etfs, tint: Palette.blue) }
                if (kind == 1 && stocks.isEmpty) || (kind == 2 && etfs.isEmpty) {
                    Card { Text(kind == 1 ? "還沒有個股持有，按右上角「新增持有」加入。" : "還沒有 ETF 持有，按右上角「新增持有」加入。").font(.subheadline).foregroundStyle(Palette.muted) }
                }
                if missing > 0 { Text("\(missing) 筆持有尚缺報價，未計入總市值。").font(.caption).foregroundStyle(Palette.muted) }
                if SellCosts.enabled, holdings.contains(where: { !SellCosts.isSet(for: $0.broker) }) {
                    NavigationLink(value: AppRoute.settings) {
                        Label("市值目前用原價手續費估算，到設定填入你的券商折扣會更準", systemImage: "info.circle").font(.caption).foregroundStyle(Palette.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
                NavigationLink(value: AppRoute.combo) { PrimaryButtonLabel(title: "個股 + ETF 組合試算", icon: "function") }.buttonStyle(.plain).accessibilityIdentifier("holdings-combo")
                Label("行情更新不等於券商持股同步", systemImage: "info.circle").font(.caption).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
                Card(padding: 12) {
                    NavigationLink(value: AppRoute.trades) { ToolRow(title: "交易紀錄", subtitle: "買進、賣出、調整與匯入", icon: "arrow.left.arrow.right") }.buttonStyle(.plain).accessibilityIdentifier("holdings-trades")
                    Divider()
                    NavigationLink(value: AppRoute.allocation) { ToolRow(title: "資產配置", subtitle: "類型、產業分佈與持股透視", icon: "chart.pie") }.buttonStyle(.plain).accessibilityIdentifier("holdings-allocation")
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await store.refresh() }
    }
    private func sorted(_ items: [Holding]) -> [Holding] {
        items.sorted { (store.marketValue(of: $0) ?? -1) > (store.marketValue(of: $1) ?? -1) }
    }
    private func hero(stockValue: Double, etfValue: Double) -> some View {
        let total = stockValue + etfValue
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "wallet.pass").font(.title3).frame(width: 40, height: 40).background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                Text("總市值").font(.subheadline.weight(.semibold))
                Text("(TWD)").font(.caption).opacity(0.8)
                Spacer()
                Button { hidden.toggle() } label: { Image(systemName: hidden ? "eye.slash" : "eye") }.accessibilityLabel(hidden ? "顯示金額" : "隱藏金額")
            }
            Text(shown(total > 0 ? money(total) : "—", hidden: hidden)).font(.system(size: 36, weight: .heavy, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1).accessibilityIdentifier("holdings-total")
            HStack(spacing: 10) {
                splitTile(title: "個股", value: stockValue, total: total, tint: Palette.pink)
                splitTile(title: "ETF", value: etfValue, total: total, tint: Palette.blue)
            }
        }
        .padding(18)
        .foregroundStyle(.white)
        .background(alignment: .topTrailing) { HeroDeco().padding(.top, 54).padding(.trailing, 16) }
        .background(Palette.hero, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: Palette.blue.opacity(0.25), radius: 12, y: 5)
    }
    private func splitTile(title: String, value: Double, total: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: "chart.bar.fill").font(.subheadline.bold()).foregroundStyle(Palette.ink).labelStyle(TintedIconLabel(tint: tint))
            Text(shown(money(value), hidden: hidden)).font(.title3.bold()).monospacedDigit().foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1)
            Text(total > 0 ? "\(decimal(value / total * 100))%" : "—").font(.subheadline.bold()).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background { RoundedRectangle(cornerRadius: 16).fill(Palette.card).overlay(RoundedRectangle(cornerRadius: 16).fill(tint.opacity(0.12))) }
    }
    private func dataRow(_ holdings: [Holding]) -> some View {
        let dates = holdings.compactMap { store.quote($0.symbol)?.date }.sorted()
        return HStack {
            Text("資料日期：\(dates.last?.replacingOccurrences(of: "-", with: "/") ?? "—")")
            Spacer()
            Button(store.refreshing ? "更新中…" : "更新報價") { Task { await store.refresh() } }.disabled(store.refreshing)
        }
        .font(.caption).foregroundStyle(Palette.muted)
    }
    private func table(title: String, items: [Holding], tint: Color) -> some View {
        Card(padding: 12) {
            Label(title, systemImage: "chart.bar.fill").font(.headline).foregroundStyle(Palette.ink).labelStyle(TintedIconLabel(tint: tint))
            HStack(spacing: 4) {
                Text("商品").frame(maxWidth: .infinity, alignment: .leading)
                Text("股數").frame(width: 42, alignment: .trailing)
                Text("現價").frame(width: 54, alignment: .trailing)
                Text("市值").frame(width: 58, alignment: .trailing)
                Text("損益").frame(width: 62, alignment: .trailing)
                Color.clear.frame(width: 10, height: 1)
            }
            .font(.caption2.bold()).foregroundStyle(Palette.muted).padding(.top, 10)
            ForEach(items) { holding in
                Divider().padding(.vertical, 6)
                row(holding)
            }
        }
    }
    private func row(_ h: Holding) -> some View {
        let quote = store.quote(h.symbol), value = store.marketValue(of: h)
        let gain = value.map { $0 - h.cost }
        let tint = gain.map(Palette.trend) ?? Palette.muted
        return NavigationLink(value: AppRoute.holdingDetail(h.id)) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) { Text(h.symbol).font(.caption.bold()); Text(h.name).font(.caption).lineLimit(1) }
                    MarketBadge(symbol: h.symbol)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(decimal(h.shares)).frame(width: 42, alignment: .trailing)
                Text(quote.map { priceText($0.price) } ?? "—").frame(width: 54, alignment: .trailing)
                Text(value.map { shown(wanText($0), hidden: hidden) } ?? "—").frame(width: 58, alignment: .trailing)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(gain.map { shown(signed($0), hidden: hidden) } ?? "—")
                    if let gain, h.cost > 0 { Text(shown(percentText(gain / h.cost * 100), hidden: hidden)) }
                }
                .font(.caption2.bold()).foregroundStyle(tint)
                .padding(.horizontal, 5).padding(.vertical, 3)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .frame(width: 62, alignment: .trailing)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.muted).frame(width: 10)
            }
            .font(.caption).monospacedDigit().foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
struct HoldingRow: View {
    @EnvironmentObject var store: PortfolioStore
    let holding: Holding
    var hidden = false
    var body: some View {
        let value = store.marketValue(of: holding), gain = value.map { $0 - holding.cost }
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) { Text(holding.symbol).font(.headline); Text(holding.name).font(.subheadline.bold()).lineLimit(1) }.foregroundStyle(Palette.ink)
                Text("\(decimal(holding.shares)) 股 ｜ 成本 \(shown(money(holding.cost), hidden: hidden))\(holding.broker.isEmpty ? "" : " · \(holding.broker)")").font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(value.map { shown(money($0), hidden: hidden) } ?? (store.quote(holding.symbol) == nil ? "尚無報價" : "外幣報價")).font(.headline).monospacedDigit().foregroundStyle(value == nil ? Palette.muted : Palette.ink)
                if let gain, holding.cost > 0 {
                    Text(shown(signed(gain), hidden: hidden)).font(.caption.bold()).monospacedDigit().foregroundStyle(Palette.trend(gain))
                    Text(shown(percentText(gain / holding.cost * 100), hidden: hidden)).font(.caption2.bold()).monospacedDigit().foregroundStyle(Palette.trend(gain))
                }
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
        }
        .accentRow(Palette.theme(store.fund(for: holding).theme))
    }
}

/* ---------- trade log ---------- */
struct TradeLogSection: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var symbol = ""
    @State private var action = ""
    @State private var broker = ""
    @State private var selected: Trade?
    @AppStorage("hideAmounts") private var hidden = false
    private func color(_ action: TradeAction) -> Color { switch action { case .buy: return Palette.red; case .sell: return Palette.green; case .adjust: return Palette.blue; case .remove: return Palette.muted; case .brokerImport: return Palette.purple } }
    var body: some View {
        let all = store.data.trades ?? []
        let items = all.filter { (symbol.isEmpty || $0.symbol == symbol) && (action.isEmpty || $0.action.rawValue == action) && (broker.isEmpty || $0.broker == broker) }.sorted { $0.date > $1.date }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("交易紀錄").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                NavigationLink(value: AppRoute.tradeForm) { Label("新增紀錄", systemImage: "plus").font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7).background(Palette.hero, in: Capsule()) }
            }
            HStack(spacing: 8) {
                filter("全部檔案", selection: $symbol, options: Array(Set(all.map(\.symbol))).sorted())
                filter("全部類型", selection: $action, options: TradeAction.allCases.map(\.rawValue))
                filter("全部券商", selection: $broker, options: Array(Set(all.map(\.broker).filter { !$0.isEmpty })).sorted())
            }
            Card(padding: 12) {
                if items.isEmpty {
                    ContentUnavailableView("還沒有交易紀錄", systemImage: "list.bullet.rectangle", description: Text("新增紀錄，或新增、修改、刪除持有時，會自動記在這裡。"))
                } else {
                    VStack(spacing: 0) {
                        tradeLine("日期", "標的", "類型", "股數", "金額", header: true).padding(.bottom, 6)
                        ForEach(items) { trade in
                            Divider()
                            Button { selected = trade } label: {
                                HStack(spacing: 6) {
                                    Text(ymdText(trade.date)).font(.caption).monospacedDigit().frame(width: 78, alignment: .leading)
                                    Text(trade.symbol).font(.caption.bold()).frame(width: 56, alignment: .leading)
                                    Text(trade.action.rawValue).font(.caption.bold()).foregroundStyle(color(trade.action)).frame(width: 34, alignment: .leading)
                                    Spacer(minLength: 0)
                                    Text(decimal(trade.shares)).font(.caption).monospacedDigit().frame(width: 52, alignment: .trailing)
                                    Text(shown(money(trade.total), hidden: hidden)).font(.caption.bold()).monospacedDigit().frame(width: 72, alignment: .trailing)
                                }
                                .foregroundStyle(Palette.ink).padding(.vertical, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Text("交易紀錄是你在這裡的操作與手動輸入，不是券商成交回報。新增買進／賣出會同步調整持有股數。").font(.caption).foregroundStyle(Palette.muted)
        }
        .sheet(item: $selected) { TradeDetailSheet(trade: $0) }
    }
    private func tradeLine(_ a: String, _ b: String, _ c: String, _ d: String, _ e: String, header: Bool) -> some View {
        HStack(spacing: 6) {
            Text(a).frame(width: 78, alignment: .leading); Text(b).frame(width: 56, alignment: .leading); Text(c).frame(width: 34, alignment: .leading)
            Spacer(minLength: 0)
            Text(d).frame(width: 52, alignment: .trailing); Text(e).frame(width: 72, alignment: .trailing)
        }.font(.caption2.bold()).foregroundStyle(Palette.muted)
    }
    private func filter(_ title: String, selection: Binding<String>, options: [String]) -> some View {
        Menu {
            Button(title) { selection.wrappedValue = "" }
            ForEach(options, id: \.self) { option in Button(option) { selection.wrappedValue = option } }
        } label: {
            HStack(spacing: 4) { Text(selection.wrappedValue.isEmpty ? title : selection.wrappedValue).lineLimit(1); Image(systemName: "chevron.down").font(.caption2) }
                .font(.caption.bold()).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
struct TradeDetailSheet: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.dismiss) private var dismiss
    let trade: Trade
    @State private var confirm = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("標的", value: "\(trade.symbol) \(trade.name)")
                    LabeledContent("類型", value: trade.action.rawValue)
                    LabeledContent("日期", value: ymdText(trade.date))
                    LabeledContent("股數", value: "\(decimal(trade.shares)) 股")
                    LabeledContent("金額", value: "\(money(trade.total)) 元")
                    if trade.shares > 0 { LabeledContent("每股", value: priceText(trade.total / trade.shares)) }
                    if let realized = trade.realized { LabeledContent("已實現損益") { Text(signed(realized)).foregroundStyle(Palette.trend(realized)) } }
                    if !trade.broker.isEmpty { LabeledContent("券商", value: trade.broker) }
                }
                Section { Button("刪除紀錄", role: .destructive) { confirm = true } } footer: { Text("刪除交易紀錄不會改動目前的持有股數；需要時請到持有明細編輯。") }
            }
            .navigationTitle("交易明細").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .confirmationDialog("刪除這筆交易紀錄？", isPresented: $confirm, titleVisibility: .visible) { Button("確認刪除", role: .destructive) { do { try store.removeTrade(trade); dismiss() } catch { store.message = error.localizedDescription } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/* ---------- allocation ---------- */
struct AllocationSection: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var tab = 0
    @AppStorage("hideAmounts") private var hidden = false
    var body: some View {
        let summary = store.summary
        let useValue = summary.marketValue != nil
        let value: (Holding) -> Double = { useValue ? (store.marketValue(of: $0) ?? 0) : $0.cost }
        let total = store.data.holdings.reduce(0.0) { $0 + value($1) }
        let bySymbol = makeSlices(store.data.holdings, key: { $0.symbol }, value: value)
        let topTwo = total > 0 ? bySymbol.prefix(2).reduce(0.0) { $0 + $1.amount } / total * 100 : 0
        VStack(alignment: .leading, spacing: 14) {
            SegmentBar(items: ["類型分類", "產業分佈", "持股透視"], selection: $tab, pill: true)
            Card {
                switch tab {
                case 0:
                    let rows = makeSlices(store.data.holdings, key: { store.isStock($0.symbol) ? "個股" : store.fund(for: $0).theme }, value: value).map { Slice(label: $0.label, amount: $0.amount, color: Palette.theme($0.label)) }
                    if rows.isEmpty { Text("還沒有持有紀錄。").foregroundStyle(Palette.muted) } else { DonutChart(slices: rows, center: (useValue ? "總市值" : "總成本", shown(wanText(total), hidden: hidden)), showAmounts: true, hidden: hidden) }
                case 1:
                    let rows = makeSlices(store.data.holdings, key: { industryKey($0) }, value: value)
                    if rows.isEmpty { Text("還沒有持有紀錄。").foregroundStyle(Palette.muted) } else { DonutChart(slices: rows, center: (useValue ? "總市值" : "總成本", shown(wanText(total), hidden: hidden)), showAmounts: true, hidden: hidden) }
                default:
                    let rows = store.exposures
                    if rows.isEmpty { Text("需要持有 ETF 的成分股資料。到 ETF 詳情 › 持股 更新成分股後，這裡會合併計算。").font(.subheadline).foregroundStyle(Palette.muted) }
                    else { BarList(slices: rows.prefix(8).enumerated().map { Slice(label: $0.element.name, amount: $0.element.value, color: Palette.series[$0.offset % Palette.series.count]) }) }
                    NavigationLink(value: AppRoute.exposure) { HStack(spacing: 2) { Text("查看持股透視"); Image(systemName: "chevron.right") }.font(.caption.bold()) }.padding(.top, 8)
                }
                Text("\(useValue ? "依持有市值" : "尚缺報價，暫依投入成本")。\(tab == 0 ? "類型依 ETF 名稱與策略整理。" : (tab == 1 ? "依 ETF 名稱歸類的主題，債券與商品另列。" : ""))").font(.caption).foregroundStyle(Palette.muted).padding(.top, 10)
            }
            if bySymbol.count >= 3 && topTwo >= 60 {
                NavigationLink(value: AppRoute.overview) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Palette.orange)
                        VStack(alignment: .leading, spacing: 2) { Text("前二大持股占比 \(decimal(topTwo))%").font(.subheadline.bold()).foregroundStyle(Palette.ink); Text("建議適度分散，降低單一標的的風險").font(.caption).foregroundStyle(Palette.muted) }
                        Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.orange)
                    }.padding(12).background(Palette.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
            SectionHeading(title: "券商帳戶", subtitle: "依券商整理持有")
            let brokers = Array(Set(store.data.holdings.map { $0.broker.isEmpty ? "未指定券商" : $0.broker })).sorted()
            if brokers.isEmpty { Card { Text("新增持有時填入券商，或匯入券商庫存 CSV。").font(.subheadline).foregroundStyle(Palette.muted) } }
            ForEach(brokers, id: \.self) { name in
                let items = store.data.holdings.filter { ($0.broker.isEmpty ? "未指定券商" : $0.broker) == name }
                Card(padding: 12) {
                    HStack { Label(name, systemImage: "building.columns").font(.subheadline.bold()).foregroundStyle(Palette.ink); Spacer(); Text("\(items.count) 筆 · 成本 \(shown(money(items.reduce(0) { $0 + $1.cost }), hidden: hidden))").font(.caption).foregroundStyle(Palette.muted) }
                }
            }
            NavigationLink(value: AppRoute.broker) { Card(padding: 12) { ToolRow(title: "匯入券商庫存", subtitle: "所有券商 CSV 欄位對應與預覽", icon: "square.and.arrow.down") } }.buttonStyle(.plain)
        }
    }
}

extension AllocationSection {
    /// Stocks use the company's industry; ETFs the theme from their name.
    func industryKey(_ holding: Holding) -> String {
        if store.isStock(holding.symbol) { return store.stock(holding.symbol)?.industry ?? "個股" }
        let fund = store.fund(for: holding)
        return fund.industry ?? fund.assetKind
    }
}

/* ---------- holding detail and forms ---------- */
struct HoldingDetailView: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var deleting = false
    @AppStorage("hideAmounts") private var hidden = false
    var body: some View {
        Page {
            if let h = store.data.holdings.first(where: { $0.id == id }) {
                let fund = store.fund(for: h), value = store.marketValue(of: h), gain = value.map { $0 - h.cost }
                // This holding's records, and those of the whole code (現股 and 融資 are separate holdings).
                let divs = store.data.dividends.filter { $0.symbol == h.symbol && ($0.holdingID == nil || $0.holdingID == h.id) }.sorted { $0.date > $1.date }
                Card {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) { Text(h.symbol).font(.title3.bold()); Text(h.name).font(.headline).lineLimit(1) }.foregroundStyle(Palette.ink)
                            HStack(spacing: 6) {
                                if let market = fund.market ?? store.stock(h.symbol)?.market { TintPill(title: market == "TPEx" ? "台灣上櫃" : "台灣上市", color: Palette.muted) }
                                TintPill(title: store.isStock(h.symbol) ? "個股" : fund.theme, color: Palette.blue)
                                if !h.broker.isEmpty { TintPill(title: h.broker, color: Palette.muted) }
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(value.map { shown(money($0), hidden: hidden) } ?? "—").font(.title2.bold()).monospacedDigit().foregroundStyle(Palette.ink)
                            if let gain, h.cost > 0 { Text(shown("\(signed(gain)) (\(percentText(gain / h.cost * 100)))", hidden: hidden)).font(.caption.bold()).monospacedDigit().foregroundStyle(Palette.trend(gain)) }
                        }
                    }
                    HStack(spacing: 0) {
                        stat("持有股數", "\(decimal(h.shares)) 股", nil)
                        Divider().frame(height: 40)
                        stat("平均成本", priceText(h.unitCost), "(含手續費)")
                        Divider().frame(height: 40)
                        stat("市值", value.map { shown(money($0), hidden: hidden) } ?? "—", store.quote(h.symbol).map { "(\(priceText($0.price))/股)" })
                    }.padding(.vertical, 10).background(Palette.cardSoft, in: RoundedRectangle(cornerRadius: 14)).padding(.top, 12)
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) { Text("未實現損益").font(.caption).foregroundStyle(Palette.muted); Text(gain.map { shown("\(signed($0)) (\(percentText($0 / max(h.cost, 0.000001) * 100)))", hidden: hidden) } ?? "尚缺報價").font(.subheadline.bold()).monospacedDigit().foregroundStyle(gain.map(Palette.trend) ?? Palette.muted) }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Palette.cardSoft, in: RoundedRectangle(cornerRadius: 14))
                        HStack(spacing: 8) {
                            Image(systemName: "dollarsign").font(.headline.bold()).foregroundStyle(.white).frame(width: 34, height: 34).background(LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.3), Color(red: 0.96, green: 0.64, blue: 0.06)], startPoint: .top, endPoint: .bottom), in: Circle())
                            VStack(alignment: .leading, spacing: 2) { Text("已領配息").font(.caption).foregroundStyle(Palette.muted); Text(shown(money(divs.filter { $0.status == .paid }.reduce(0) { $0 + $1.amount }), hidden: hidden)).font(.headline).monospacedDigit().foregroundStyle(Palette.ink) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Palette.cardSoft, in: RoundedRectangle(cornerRadius: 14))
                    }.padding(.top, 10)
                    if let date = h.purchaseDate { Text("購入日期 \(ymdText(date))").font(.caption).foregroundStyle(Palette.muted).padding(.top, 8) }
                }
                HStack(spacing: 12) {
                    NavigationLink(value: AppRoute.holdingForm(id: h.id, symbol: nil)) { Label("編輯持有", systemImage: "pencil").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13).foregroundStyle(.white).background(Palette.hero, in: RoundedRectangle(cornerRadius: 14)) }
                    Button { deleting = true } label: { Label("刪除持有", systemImage: "trash").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13).foregroundStyle(Palette.red).background(Palette.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14)) }
                }.buttonStyle(.plain)
                HStack { SectionHeading(title: "配息紀錄"); if !divs.isEmpty { SymbolLink(symbol: h.symbol) { HStack(spacing: 2) { Text("查看全部"); Image(systemName: "chevron.right") }.font(.caption.bold()).foregroundStyle(Palette.blue) } } }
                Card(padding: 12) {
                    if divs.isEmpty { Text("還沒有這檔的配息紀錄。").font(.subheadline).foregroundStyle(Palette.muted).padding(4) }
                    ForEach(divs.prefix(5)) { item in
                        NavigationLink(value: AppRoute.dividendDetail(item.id)) {
                            HStack {
                                Text("\(String(Calendar.current.component(.year, from: item.date)))/\(String(format: "%02d", Calendar.current.component(.month, from: item.date)))").font(.subheadline.bold()).monospacedDigit().frame(width: 72, alignment: .leading)
                                Text("現金股利").font(.subheadline); StatusPill(status: item.status)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) { Text(shown(money(item.amount), hidden: hidden)).font(.subheadline.bold()).monospacedDigit(); if let p = item.perShare { Text("(\(decimal(p))/股)").font(.caption2).foregroundStyle(Palette.muted) } }
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                            }.foregroundStyle(Palette.ink).padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                NavigationLink(value: AppRoute.dividendForm(id: nil, symbol: h.symbol, officialEx: nil, holding: h.id)) { Label("記錄這檔配息", systemImage: "plus").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 12).background(Palette.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain).foregroundStyle(Palette.blue)
                Text("")
                    .confirmationDialog("刪除這筆持有？配息紀錄會保留。", isPresented: $deleting, titleVisibility: .visible) {
                        Button("確認刪除", role: .destructive) { do { try store.remove(h); dismiss() } catch { store.message = error.localizedDescription } }
                    }
            } else {
                Card { ContentUnavailableView("找不到這筆持有", systemImage: "bag", description: Text("可能已被刪除。")) }
            }
        }
        .navigationTitle("持有明細").navigationBarTitleDisplayMode(.inline)
    }
    private func stat(_ title: String, _ value: String, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Palette.muted)
            Text(value).font(.headline).monospacedDigit().foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1)
            if let detail { Text(detail).font(.caption2).foregroundStyle(Palette.muted) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
    }
}
struct HoldingFormView: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.dismiss) private var dismiss
    let id: UUID?
    @State private var symbol: String
    @State private var name = ""
    @State private var shares = ""
    @State private var total = ""
    @State private var date = Date()
    @State private var broker = ""
    @State private var feeRate = SellCosts.standard
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var loaded = false
    init(id: UUID?, symbol: String?) { self.id = id; _symbol = State(initialValue: symbol ?? "") }
    private var existing: Holding? { id.flatMap { id in store.data.holdings.first { $0.id == id } } }
    var body: some View {
        Page {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("搜尋股票或 ETF 代號、名稱").font(.caption.bold()).foregroundStyle(Palette.muted)
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                        TextField("例如 2330 或 0050", text: $symbol).textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("holding-symbol")
                        if !symbol.isEmpty { Button { symbol = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }.accessibilityLabel("清除代號") }
                    }.padding(11).background(Palette.cardSoft, in: RoundedRectangle(cornerRadius: 12))
                    TextField("名稱（清單沒有時填寫）", text: $name).padding(11).background(Palette.cardSoft, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("holding-name")
                }
                VStack(spacing: 2) {
                    FieldRow(title: "持有股數") { UnitField(placeholder: "1,000 股 = 1 張", text: $shares, unit: "股", identifier: "holding-shares") }
                    FieldRow(title: "總成本（含手續費）") { UnitField(placeholder: "實際付出金額", text: $total, unit: "元", identifier: "holding-cost") }
                    FieldRow(title: "購入日期") { DatePicker("購入日期", selection: $date, displayedComponents: .date).labelsHidden() }
                    BrokerFeeRows(broker: $broker, rate: $feeRate, identifier: "holding-broker")
                }.padding(.top, 10)
                if let s = Double(shares.replacingOccurrences(of: ",", with: "")), let t = Double(total.replacingOccurrences(of: ",", with: "")), s > 0, t > 0 { Text("平均成本 \(priceText(t / s)) 元／股").font(.caption).foregroundStyle(Palette.muted).padding(.top, 8) }
                if let error { Text(error).font(.caption).foregroundStyle(Palette.red).padding(.top, 6) }
            }
            HStack(spacing: 12) {
                Button { dismiss() } label: { Text("取消").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14).foregroundStyle(Palette.ink).background(Palette.card, in: RoundedRectangle(cornerRadius: 14)) }
                Button { save() } label: { Text(existing == nil ? "儲存" : "儲存更新").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14).foregroundStyle(.white).background(Palette.hero, in: RoundedRectangle(cornerRadius: 14)) }.accessibilityIdentifier("save-holding")
            }.buttonStyle(.plain)
            if existing != nil {
                Button(role: .destructive) { confirmDelete = true } label: { Label("刪除持有", systemImage: "trash").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(Palette.red).background(Palette.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain)
            }
            Text("輸入 1,000 股代表 1 張。總成本請填實際付出的台幣金額（含手續費），會換算成平均成本。").font(.caption).foregroundStyle(Palette.muted)
        }
        .navigationTitle(existing == nil ? "新增持有" : "編輯持有").navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: symbol) { _, value in
            let code = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if let known = store.funds.first(where: { $0.id == code })?.name ?? store.stock(code)?.name { name = known }
        }
        .confirmationDialog("刪除這筆持有？配息紀錄會保留。", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("確認刪除", role: .destructive) { if let existing { do { try store.remove(existing); dismiss() } catch { self.error = error.localizedDescription } } }
        }
    }
    private func load() {
        guard !loaded else { return }; loaded = true
        if let h = existing {
            symbol = h.symbol; name = h.name; shares = h.shares == h.shares.rounded() ? String(Int(h.shares)) : String(h.shares)
            total = String((h.cost * 100).rounded() / 100); broker = h.broker; date = h.purchaseDate ?? Date()
        } else if let known = store.funds.first(where: { $0.id == symbol })?.name ?? store.stock(symbol)?.name { name = known }
    }
    private func save() {
        let code = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let s = Double(shares.replacingOccurrences(of: ",", with: "")) ?? 0, t = Double(total.replacingOccurrences(of: ",", with: "")) ?? -1
        let fund = store.funds.first { $0.id == code }
        guard DataChecks.code(code) else { error = "請輸入正確的股票或 ETF 代號，例如 2330、0050。"; return }
        guard s > 0 else { error = "持有股數須大於 0。"; return }
        guard t >= 0 else { error = "請填寫總成本（含手續費）。"; return }
        let h = Holding(id: existing?.id ?? UUID(), symbol: code, name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (fund?.name ?? store.stock(code)?.name ?? "") : name.trimmingCharacters(in: .whitespacesAndNewlines), shares: s, unitCost: t / s, broker: broker.trimmingCharacters(in: .whitespacesAndNewlines), strategy: existing.map { $0.symbol == code ? $0.strategy : (fund?.strategy ?? .unclassified) } ?? (fund?.strategy ?? .unclassified), sourceAccount: existing?.sourceAccount, purchaseDate: date)
        SellCosts.remember(feeRate, for: broker)
        do { try store.save(h); dismiss() } catch { self.error = error.localizedDescription }
    }
}
struct TradeFormView: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind = 0
    @State private var symbol = ""
    @State private var date = Date()
    @State private var shares = ""
    @State private var amount = ""
    @State private var broker = ""
    @State private var feeRate = SellCosts.standard
    @State private var error: String?
    var body: some View {
        Page {
            SegmentBar(items: ["買進", "賣出"], selection: $kind, pill: true, filled: true)
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("股票／ETF 代號").font(.caption.bold()).foregroundStyle(Palette.muted)
                    HStack { Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted); TextField("例如 00878", text: $symbol).textInputAutocapitalization(.characters).autocorrectionDisabled() }
                        .padding(11).background(Palette.cardSoft, in: RoundedRectangle(cornerRadius: 12))
                    let code = symbol.trimmingCharacters(in: .whitespaces).uppercased()
                    if let known = store.funds.first(where: { $0.id == code })?.name ?? store.stock(code)?.name { Text(known).font(.caption).foregroundStyle(Palette.muted) }
                }
                VStack(spacing: 2) {
                    FieldRow(title: "交易日期") { DatePicker("交易日期", selection: $date, displayedComponents: .date).labelsHidden() }
                    FieldRow(title: "股數") { UnitField(placeholder: "股數", text: $shares, unit: "股") }
                    FieldRow(title: kind == 1 ? "成交金額（扣除費用後）" : "成交金額（含手續費）") { UnitField(placeholder: "金額", text: $amount, unit: "元") }
                    BrokerFeeRows(broker: $broker, rate: $feeRate)
                }.padding(.top, 10)
                if let error { Text(error).font(.caption).foregroundStyle(Palette.red).padding(.top, 6) }
            }
            HStack(spacing: 12) {
                Button { dismiss() } label: { Text("取消").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14).foregroundStyle(Palette.ink).background(Palette.card, in: RoundedRectangle(cornerRadius: 14)) }
                Button { save() } label: { Text("儲存紀錄").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14).foregroundStyle(.white).background(Palette.hero, in: RoundedRectangle(cornerRadius: 14)) }
            }.buttonStyle(.plain)
            Text(kind == 1 ? "賣出會從同一券商的持有扣除股數，平均成本不變；股數歸零時移除該筆持有。" : "買進會加到同一檔、同一券商的持有並重新計算平均成本；沒有時新增一筆持有。").font(.caption).foregroundStyle(Palette.muted)
        }
        .navigationTitle("新增交易紀錄").navigationBarTitleDisplayMode(.inline)
    }
    private func save() {
        error = nil
        guard let s = Double(shares.replacingOccurrences(of: ",", with: "")), let a = Double(amount.replacingOccurrences(of: ",", with: "")) else { error = "請填寫股數與成交金額。"; return }
        SellCosts.remember(feeRate, for: broker)
        do {
            try store.applyTrade(kind == 1 ? .sell : .buy, symbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), date: date, shares: s, amount: a, broker: broker.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
