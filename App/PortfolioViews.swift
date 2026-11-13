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
        return SellCosts.net(gross, stock: !isETF(holding.symbol), bond: fund(for: holding).assetKind == "債券", rate: SellCosts.rate(for: holding.broker))
    }
}
/* ---------- 口袋 pieces (spec 5.7) ---------- */
/// The pocket's figures: each holding's value, its share of the total and its gain on cost. Only holdings with a TWD
/// price are added up; the others count in `missing` and stay in the list without a value.
struct PocketSummary {
    struct Row: Identifiable {
        let holding: Holding
        let value: Double?
        /// Percent of the total, for the allocation bar and 「名稱 · 49.8%」.
        let share: Double?
        /// Gain or loss on cost, in percent.
        let gainPercent: Double?
        var id: UUID { holding.id }
    }
    /// Largest value first; holdings without a price last.
    let rows: [Row]
    /// Nil when no holding has a price.
    let total: Double?
    /// Total gain or loss of the priced holdings, and that as a percent of their cost.
    let gain: Double
    let gainPercent: Double?
    let missing: Int

    static func of(_ holdings: [Holding], value: (Holding) -> Double?) -> PocketSummary {
        let valued = holdings.map { (holding: $0, value: value($0)) }
        let priced = valued.filter { $0.value != nil }
        let total: Double? = priced.isEmpty ? nil : priced.reduce(0) { $0 + ($1.value ?? 0) }
        let cost = priced.reduce(0) { $0 + $1.holding.cost }
        let gain = (total ?? 0) - cost
        let rows = valued.map { item -> Row in
            let share: Double? = item.value.flatMap { v in total.flatMap { $0 > 0 ? v / $0 * 100 : nil } }
            let percent: Double? = item.value.flatMap { v in item.holding.cost > 0 ? (v - item.holding.cost) / item.holding.cost * 100 : nil }
            return Row(holding: item.holding, value: item.value, share: share, gainPercent: percent)
        }
        .sorted { ($0.value ?? -1) > ($1.value ?? -1) }
        return PocketSummary(rows: rows, total: total, gain: gain, gainPercent: total != nil && cost > 0 ? gain / cost * 100 : nil,
                             missing: valued.count - priced.count)
    }
}

extension Skin {
    /// One colour per holding in the pocket's allocation bar, in turn: the skin's accent, ink, its flat accents, then
    /// its secondary and hint colours. Never `up` or `down`, which mean gains and losses.
    var allocationColors: [Color] {
        [color(\.accent), color(\.ink)] + colors.extra.prefix(2).map { Color(rgb: $0) } + [color(\.sub), color(\.dim)]
    }
}

/// The allocation bar: one segment per holding, as wide as its share of the total. The rows below carry the same
/// shares in words, so the bar itself is not read by VoiceOver.
struct AllocationBar: View {
    @Environment(\.skin) private var skin
    let parts: [(share: Double, color: Color)]
    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 3
            let sum = parts.reduce(0) { $0 + $1.share }
            let room = max(geo.size.width - gap * CGFloat(max(parts.count - 1, 0)), 0)
            HStack(spacing: gap) {
                ForEach(parts.indices, id: \.self) { i in
                    Rectangle().fill(parts[i].color).frame(width: sum > 0 ? room * parts[i].share / sum : 0)
                }
            }
        }
        .frame(height: 10)
        .clipShape(RoundedRectangle(cornerRadius: skin.style.button == .pixelBlock ? 0 : 5))
        .accessibilityHidden(true)
    }
}

/// A holding in the pocket: its colour, the code in the big face, 「名稱 · 占比」, the value and the gain or loss on
/// cost (▲ / ▼ and a percentage, in the up / down colour).
struct PocketHoldingRow: View {
    @Environment(\.skin) private var skin
    let row: PocketSummary.Row
    let color: Color
    let hidden: Bool
    /// Has a quote, but not in NT$ (so no value): 「外幣報價」 rather than 「尚無報價」.
    var quoted = false
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: skin.style.button == .pixelBlock ? 0 : 5).fill(color).frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.holding.symbol).skinFont(.big(20)).skinForeground(\.ink).lineLimit(1).minimumScaleFactor(0.6)
                Text(detail).skinFont(.body(11)).skinForeground(\.sub).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(row.value.map { shown(money($0), hidden: hidden) } ?? (quoted ? "外幣報價" : "尚無報價"))
                    .skinFont(.mono(13)).foregroundStyle(skin.color(row.value == nil ? \SkinColors.sub : \SkinColors.ink))
                if hidden {
                    Text("＊＊＊＊").skinFont(.mono(11)).skinForeground(\.sub)
                } else {
                    SkinChange(percent: row.gainPercent).accessibilityIdentifier("pocket-change-\(row.holding.symbol)")
                }
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    private var detail: String {
        let name = row.holding.name.isEmpty ? row.holding.symbol : row.holding.name
        return row.share.map { "\(name) · \(String(format: "%.1f", $0))%" } ?? name
    }
}

/// A row that opens another page: title, a line of explanation and 「›」, at least 44pt tall.
struct SkinLinkRow: View {
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).skinFont(.title(15)).skinForeground(\.ink)
                Text(subtitle).skinFont(.body(11)).skinForeground(\.sub)
            }
            Spacer(minLength: 8)
            Text("›").skinFont(.mono(16)).skinForeground(\.sub).accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
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
        .sheet(item: $selected) { TradeDetailSheet(trade: $0).silencesScrollTop() }
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
                    // The cost of the shares sold is what was received less the result.
                    if let realized = trade.realized {
                        LabeledContent("已實現損益") {
                            if let pct = TrendText.percent(realized, of: trade.total - realized) { TrendText(percent: pct, amount: realized, font: .body) }
                            else { Text(TrendText.arrowed(realized)).foregroundStyle(Palette.trend(realized)) }
                        }
                    }
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
                    let rows = makeSlices(store.data.holdings, key: { store.fund(for: $0).theme }, value: value).map { Slice(label: $0.label, amount: $0.amount, color: Palette.theme($0.label)) }
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
    /// The theme from the ETF's name; bonds and commodities by asset kind.
    func industryKey(_ holding: Holding) -> String {
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
                                if let market = fund.market { TintPill(title: market == "TPEx" ? "台灣上櫃" : "台灣上市", color: Palette.muted) }
                                TintPill(title: store.isETF(h.symbol) ? fund.theme : "非 ETF（舊紀錄）", color: Palette.blue)
                                if !h.broker.isEmpty { TintPill(title: h.broker, color: Palette.muted) }
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(value.map { shown(money($0), hidden: hidden) } ?? "—").font(.title2.bold()).monospacedDigit().foregroundStyle(Palette.ink)
                            if let gain, let pct = TrendText.percent(gain, of: h.cost) { TrendText(percent: pct, amount: gain, hidden: hidden).accessibilityIdentifier("holding-gain") }
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
                        VStack(alignment: .leading, spacing: 3) { Text("未實現損益").font(.caption).foregroundStyle(Palette.muted); if let gain, let pct = TrendText.percent(gain, of: h.cost) { TrendText(percent: pct, amount: gain, font: .subheadline.bold(), hidden: hidden).accessibilityIdentifier("holding-unrealized") } else { Text(gain == nil ? "尚缺報價" : "—").font(.subheadline.bold()).foregroundStyle(Palette.muted) } }
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
                    Text("搜尋 ETF 代號、名稱").font(.caption.bold()).foregroundStyle(Palette.muted)
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
            if let known = store.funds.first(where: { $0.id == code })?.name { name = known }
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
        } else if let known = store.funds.first(where: { $0.id == symbol })?.name { name = known }
    }
    private func save() {
        let code = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let s = Double(shares.replacingOccurrences(of: ",", with: "")) ?? 0, t = Double(total.replacingOccurrences(of: ",", with: "")) ?? -1
        let fund = store.funds.first { $0.id == code }
        guard DataChecks.code(code) else { error = "請輸入正確的 ETF 代號，例如 0050、00878。"; return }
        guard fund != nil else { error = "目前只支援 ETF，請輸入 ETF 名單中的代號。"; return }
        guard s > 0 else { error = "持有股數須大於 0。"; return }
        guard t >= 0 else { error = "請填寫總成本（含手續費）。"; return }
        let h = Holding(id: existing?.id ?? UUID(), symbol: code, name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (fund?.name ?? "") : name.trimmingCharacters(in: .whitespacesAndNewlines), shares: s, unitCost: t / s, broker: broker.trimmingCharacters(in: .whitespacesAndNewlines), strategy: existing.map { $0.symbol == code ? $0.strategy : (fund?.strategy ?? .unclassified) } ?? (fund?.strategy ?? .unclassified), sourceAccount: existing?.sourceAccount, purchaseDate: date)
        SellCosts.remember(feeRate, for: broker)
        do { try store.save(h, logBuy: existing == nil); ConfirmFeedback.confirm(SkinStore.shared.skin); dismiss() } catch { self.error = error.localizedDescription }
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
                    Text("ETF 代號").font(.caption.bold()).foregroundStyle(Palette.muted)
                    HStack { Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted); TextField("例如 00878", text: $symbol).textInputAutocapitalization(.characters).autocorrectionDisabled() }
                        .padding(11).background(Palette.cardSoft, in: RoundedRectangle(cornerRadius: 12))
                    let code = symbol.trimmingCharacters(in: .whitespaces).uppercased()
                    if let known = store.funds.first(where: { $0.id == code })?.name { Text(known).font(.caption).foregroundStyle(Palette.muted) }
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
            try store.applyTrade(kind == 1 ? .sell : .buy, symbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), date: date, shares: s, amount: a, broker: broker.trimmingCharacters(in: .whitespacesAndNewlines), logBuy: true)
            ConfirmFeedback.confirm(SkinStore.shared.skin)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
