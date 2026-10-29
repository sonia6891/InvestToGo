import SwiftUI
import Charts

/* ---------- shared pieces for stocks and ETFs ---------- */
/// Rounded square with the company's first two characters (stocks) or the code (ETFs).
struct SymbolAvatar: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    var size: CGFloat = 42
    private static let colors: [Color] = [Palette.blue, Palette.pink, Palette.teal, Palette.orange, Palette.purple, Palette.green, Palette.red, Color(red: 0.23, green: 0.48, blue: 0.84)]
    var body: some View {
        let stock = store.isStock(symbol)
        let label = stock ? String(store.name(for: symbol).prefix(2)) : symbol
        let hash = symbol.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 997 }
        let color = stock ? Self.colors[hash % Self.colors.count] : Palette.blue
        Text(label)
            .font(.system(size: stock ? size * 0.33 : (symbol.count > 5 ? size * 0.24 : size * 0.29), weight: .heavy, design: .rounded))
            .lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [color.opacity(0.65), color], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}
/// 上市 / 上櫃 for stocks, ETF for funds.
struct MarketBadge: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    var body: some View {
        if store.isStock(symbol) {
            let tpex = store.stock(symbol)?.market == "TPEx"
            TintPill(title: tpex ? "上櫃" : "上市", color: tpex ? Palette.teal : Palette.blue)
        } else {
            TintPill(title: "ETF", color: Palette.orange)
        }
    }
}
/// Opens the stock page for company shares and the ETF page for funds.
struct SymbolLink<Label: View>: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    @ViewBuilder var label: Label
    var body: some View {
        if store.isStock(symbol) {
            NavigationLink(value: AppRoute.stock(symbol)) { label }.buttonStyle(.plain)
        } else {
            NavigationLink(value: store.funds.first { $0.id == symbol } ?? Fund(id: symbol, name: store.name(for: symbol), strategy: .unclassified)) { label }.buttonStyle(.plain)
        }
    }
}
/// Avatar, code and name, market badge, price and change, watchlist star.
struct SymbolRow: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    var subtitle: String? = nil
    var body: some View {
        let quote = store.quote(symbol), on = store.data.favorites.contains(symbol)
        HStack(spacing: 6) {
            SymbolLink(symbol: symbol) {
                HStack(spacing: 10) {
                    SymbolAvatar(symbol: symbol)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) { Text(symbol).font(.subheadline.bold()).monospacedDigit(); Text(store.name(for: symbol)).font(.subheadline.bold()).lineLimit(1) }.foregroundStyle(Palette.ink)
                        HStack(spacing: 6) { MarketBadge(symbol: symbol); if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(Palette.muted).lineLimit(1) } }
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(quote.map { priceText($0.price) } ?? "—").font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.ink)
                            .contentTransition(.numericText(value: quote?.price ?? 0)).animation(.snappy, value: quote?.price)
                        QuoteChange(quote: quote, font: .caption2)
                    }
                }.contentShape(Rectangle())
            }
            Button { store.favorite(symbol) } label: {
                Image(systemName: on ? "star.fill" : "star").foregroundStyle(on ? Palette.orange : Palette.muted.opacity(0.5)).frame(width: 32, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(on ? "取消自選 \(symbol)" : "加入自選 \(symbol)")
        }
        .padding(.vertical, 6)
    }
}

struct TintedIconLabel: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon.foregroundStyle(tint); configuration.title }
    }
}

/* ---------- stock detail ---------- */
struct StockDetailView: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    @State private var section = 0
    @State private var range = ChartRange.year
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        let info = store.stock(symbol), quote = store.quote(symbol)
        Page {
            Card(padding: 14) {
                HStack(spacing: 12) {
                    SymbolAvatar(symbol: symbol, size: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) { Text(symbol).font(.title2.bold()).monospacedDigit(); Text(store.name(for: symbol)).font(.title3.bold()).lineLimit(1); MarketBadge(symbol: symbol) }.foregroundStyle(Palette.ink)
                        Text(info?.fullName ?? info?.industry ?? "").font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                Card(padding: 14) {
                    Text(quote.map { priceText($0.price) } ?? "—").font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1)
                        .contentTransition(.numericText(value: quote?.price ?? 0)).animation(.snappy, value: quote?.price)
                    QuoteChange(quote: quote, font: .subheadline).padding(.top, 4)
                }
                Card(padding: 12) { sourceInfo(quote) }
            }
            SegmentBar(items: ["總覽", "走勢", "財務", "股利"], selection: $section, pill: true, filled: true)
            switch section {
            case 1: HistoryContent(symbol: symbol)
            case 2: finance
            case 3: dividends(quote)
            default: overview(info, quote)
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .task { await store.refreshDaily() }
        .onAppear { store.liveFocus = symbol; store.live.syncSoon() }
        .onDisappear { if store.liveFocus == symbol { store.liveFocus = nil; store.live.syncSoon() } }
        .navigationTitle("個股詳情").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                LiveQuoteButton(symbol: symbol, market: store.stock(symbol)?.market)
                Button { store.favorite(symbol) } label: { Image(systemName: store.data.favorites.contains(symbol) ? "star.fill" : "star").foregroundStyle(Palette.orange) }.accessibilityLabel("切換自選")
                ShareLink(item: "\(symbol) \(store.name(for: symbol))｜投資袋著走") { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("分享")
            }
        }
    }
    /// 盤中即時 while the viewer's key streams today's trades; otherwise the trading day the price closed on.
    private func sourceInfo(_ quote: Quote?) -> some View {
        let live = quote.map { !$0.isDailyClose && store.liveStatus.running && $0.fetchedAt.timeIntervalSinceNow > -600 } ?? false
        let state: (String, Color) = live ? ("盤中即時", Palette.green)
            : (quote == nil ? ("尚無報價", Palette.pink) : (quote!.isDailyClose || !TaiwanMarket.isOpen() ? ("收盤價", Palette.blue) : ("最近報價", Palette.orange)))
        let updated: String = quote.map { $0.date.replacingOccurrences(of: "-", with: "/") + (live ? " " + $0.fetchedAt.formatted(date: .omitted, time: .shortened) : ($0.isDailyClose ? " 收盤" : "")) } ?? "—"
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) { Circle().fill(state.1).frame(width: 8, height: 8); Text(state.0).font(.caption.bold()) }.foregroundStyle(state.1)
            Text("更新時間：\(updated)").font(.caption2)
        }.foregroundStyle(Palette.muted)
    }
    private func overview(_ info: StockInfo?, _ quote: Quote?) -> some View {
        let points = store.data.histories?[symbol].map(TrendMath.points) ?? []
        let visible = TrendMath.slice(points, range)
        return VStack(alignment: .leading, spacing: 16) {
            Card(padding: 14) {
                Label("股價走勢", systemImage: "chart.bar.fill").font(.headline).foregroundStyle(Palette.ink)
                RangeChips(options: [.week, .month, .quarter, .year, .all], selection: $range).padding(.vertical, 10)
                if visible.count >= 2 {
                    ValueChart(points: visible, showAxes: true, height: 170)
                } else {
                    Text("尚無歷史走勢").font(.subheadline.bold()).foregroundStyle(Palette.ink)
                    Text("使用你的行情金鑰取得近 5 年還原日收盤價，約需 10 秒；不以試算資料代替。").font(.caption).foregroundStyle(Palette.muted).padding(.vertical, 6)
                    Button(busy ? "取得中…" : "取得歷史走勢") { Task { busy = true; error = nil; defer { busy = false }; do { try store.saveHistory(await Fugle.history(symbol: symbol, years: 5)) } catch { self.error = error.localizedDescription } } }.buttonStyle(.borderedProminent).disabled(busy)
                    if let error { Text(error).font(.caption).foregroundStyle(Palette.red).padding(.top, 6) }
                }
            }
            Card(padding: 12) {
                HStack(spacing: 0) {
                    stat("成交量", quote?.volume.map { "\(money($0)) 張" })
                    Divider().frame(height: 34)
                    stat("開盤", quote?.open.map(priceText))
                    Divider().frame(height: 34)
                    stat("最高", quote?.high.map(priceText))
                    Divider().frame(height: 34)
                    stat("最低", quote?.low.map(priceText))
                }
            }
            if let info {
                Card(padding: 14) {
                    Text("公司資料").font(.headline).foregroundStyle(Palette.ink).padding(.bottom, 6)
                    LabeledContent("產業", value: info.industry); Divider().padding(.vertical, 6)
                    LabeledContent("市場", value: info.marketName); Divider().padding(.vertical, 6)
                    LabeledContent("上市櫃日期", value: info.listingDate.replacingOccurrences(of: "-", with: "/")); Divider().padding(.vertical, 6)
                    LabeledContent("公司全名", value: info.fullName)
                }.font(.subheadline)
            }
            if let quote, store.data.quotes[symbol] == nil, store.liveQuotes[symbol] == nil { Text("收盤價・資料日 \(quote.date.replacingOccurrences(of: "-", with: "/"))（非即時）").font(.caption).foregroundStyle(Palette.muted) }
            Button(store.refreshing ? "更新中…" : "更新報價") { Task { await store.refresh(symbols: [symbol]) } }.font(.caption.bold()).disabled(store.refreshing)
        }
    }
    private func stat(_ title: String, _ value: String?) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(Palette.muted)
            Text(value ?? "—").font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity)
    }
    private var finance: some View {
        let revenue = store.stockSnapshot?.revenue[symbol], eps = store.stockSnapshot?.earnings[symbol]
        return VStack(alignment: .leading, spacing: 16) {
            Card(padding: 14) {
                Label("月營收", systemImage: "chart.bar.xaxis").font(.headline).foregroundStyle(Palette.ink)
                if let revenue {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(amountText(revenue.amount)).font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1)
                        Text("\(revenue.month.prefix(4)) 年 \(Int(revenue.month.suffix(2)) ?? 0) 月").font(.caption).foregroundStyle(Palette.muted)
                    }.padding(.vertical, 8)
                    HStack { Text("月增率").foregroundStyle(Palette.muted); Spacer(); changeText(revenue.monthChange) }; Divider().padding(.vertical, 6)
                    HStack { Text("年增率").foregroundStyle(Palette.muted); Spacer(); changeText(revenue.yearChange) }; Divider().padding(.vertical, 6)
                    HStack { Text("今年累計營收").foregroundStyle(Palette.muted); Spacer(); Text(amountText(revenue.cumulative)).font(.subheadline.bold()).monospacedDigit() }; Divider().padding(.vertical, 6)
                    HStack { Text("累計年增率").foregroundStyle(Palette.muted); Spacer(); changeText(revenue.cumulativeChange) }
                } else { Text("尚未收錄這家公司的月營收。").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 8) }
            }.font(.subheadline)
            Card(padding: 14) {
                Label("基本每股盈餘（EPS）", systemImage: "dollarsign.circle").font(.headline).foregroundStyle(Palette.ink)
                if let eps {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(decimal(eps.value)) 元").font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Palette.ink)
                        Text(eps.quarter == 4 ? "\(String(eps.year)) 年全年" : "\(String(eps.year)) 年前 \(eps.quarter) 季累計").font(.caption).foregroundStyle(Palette.muted)
                    }.padding(.top, 8)
                } else { Text("尚未收錄這家公司的財報每股盈餘。").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 8) }
            }
            Text("資料取得日 \(store.stockSnapshot?.fetchedDay ?? "—")。月營收為公司自結數，原始單位千元。").font(.caption).foregroundStyle(Palette.muted)
        }
    }
    /// Revenue is reported in thousand NT$.
    private func amountText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value >= 100_000 ? "\(decimal(value / 100_000)) 億元" : "\(decimal(value / 10)) 萬元"
    }
    private func changeText(_ value: Double?) -> some View {
        Text(value.map(percentText) ?? "—").font(.subheadline.bold()).monospacedDigit().foregroundStyle(value.map(Palette.trend) ?? Palette.muted)
    }
    private func policyTitle(_ item: StockSnapshot.Policy) -> String {
        let year = (Int(item.year) ?? 0) + 1911
        return item.period == "年度" ? "\(year) 年度" : "\(year) 年 \(item.period)"
    }
    private func dividends(_ quote: Quote?) -> some View {
        let snapshot = store.stockSnapshot
        let cash = snapshot?.trailingCash(symbol) ?? 0
        let price: Double = quote?.price ?? 0
        let yield: Double = cash > 0 && price > 0 ? cash / price * 100 : 0
        let history = snapshot?.exHistory[symbol] ?? [], upcoming = snapshot?.exUpcoming[symbol] ?? [], policies = snapshot?.policies[symbol] ?? []
        // The history builds up from the exchanges' open data from `since`; no yield until it covers a year.
        let since = snapshot?.exHistorySince.map { $0.replacingOccurrences(of: "-", with: "/") }
        let covered = snapshot?.exHistoryCoversYear ?? false
        return VStack(alignment: .leading, spacing: 16) {
            Card(padding: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text("近一年現金股利（除息）").font(.caption).foregroundStyle(Palette.muted); Text(cash > 0 ? "\(decimal(cash)) 元" : "—").font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Palette.ink) }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) { Text("現金殖利率").font(.caption).foregroundStyle(Palette.muted); Text(yield > 0 ? "\(decimal(yield))%" : "—").font(.title3.bold()).monospacedDigit().foregroundStyle(Palette.ink) }
                }
                Text(yield > 0 ? "依現價計算；除權息同時進行的不計入。" : (covered ? "近一年沒有純除息紀錄。" : "除權息紀錄自 \(since ?? "今日") 起累積，滿一年後才計算殖利率。")).font(.caption).foregroundStyle(Palette.muted).padding(.top, 6)
            }
            if !policies.isEmpty {
                Card(padding: 14) {
                    SectionHeading(title: "最新股利政策")
                    ForEach(policies.prefix(4)) { item in
                        Divider().padding(.vertical, 6)
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(policyTitle(item)).font(.subheadline.bold())
                                TintPill(title: item.progress, color: item.progress.contains("股東會") ? Palette.green : Palette.blue)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("現金 \(decimal(item.cash)) 元／股").font(.subheadline)
                                if item.stock > 0 { Text("股票 \(decimal(item.stock)) 元／股").font(.subheadline) }
                            }
                        }.foregroundStyle(Palette.ink)
                    }
                }
            }
            if !upcoming.isEmpty {
                Card(padding: 14) {
                    SectionHeading(title: "近期除權息")
                    ForEach(upcoming) { item in HStack { Text("\(item.date.replacingOccurrences(of: "-", with: "/"))（\(item.kind)）"); Spacer(); Text(item.value.map { "\(decimal($0)) 元" } ?? "—").bold() }.font(.subheadline).padding(.top, 8) }
                }
            }
            Card(padding: 12) {
                if history.isEmpty {
                    Text(since.map { "除權息紀錄自 \($0) 起累積，目前還沒有紀錄。" } ?? "近兩年沒有除權息紀錄。").font(.subheadline).foregroundStyle(Palette.muted)
                } else {
                    HStack { Text("除權息日"); Spacer(); Text("類型").frame(width: 60); Text("權值＋息值").frame(width: 90, alignment: .trailing) }.font(.caption.bold()).foregroundStyle(Palette.muted)
                    ForEach(history.prefix(12)) { item in
                        Divider().padding(.vertical, 6)
                        HStack { Text(item.date.replacingOccurrences(of: "-", with: "/")).monospacedDigit(); Spacer(); Text(item.kind).frame(width: 60); Text(item.value.map { "\(decimal($0)) 元" } ?? "—").bold().monospacedDigit().frame(width: 90, alignment: .trailing) }.font(.subheadline).foregroundStyle(Palette.ink)
                    }
                    Text("紀錄自 \(since ?? "—") 起累積；上市配股的權值不在交易所開放資料中，顯示「—」。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 8)
                }
            }
            NavigationLink(value: AppRoute.dividendForm(id: nil, symbol: symbol, officialEx: nil)) { PrimaryButtonLabel(title: "記錄這檔配息") }.buttonStyle(.plain)
        }
    }
    private var actionBar: some View {
        let favorite = store.data.favorites.contains(symbol)
        return HStack(spacing: 12) {
            Button { store.favorite(symbol) } label: {
                Label(favorite ? "已加入自選" : "加入自選", systemImage: favorite ? "star.fill" : "star").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
                    .foregroundStyle(Palette.blue).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.blue, lineWidth: 1.2))
            }
            // A route, not a presented destination: screens pushed from there must stack above it.
            NavigationLink(value: AppRoute.comboAdding(symbol)) {
                Label("加入試算", systemImage: "function").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
                    .foregroundStyle(.white).background(Palette.hero, in: RoundedRectangle(cornerRadius: 14))
            }.accessibilityIdentifier("stock-add-combo")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

/* ---------- Explore: stocks ---------- */
struct StockDiscoverContent: View {
    @EnvironmentObject var store: PortfolioStore
    @Binding var query: String
    @State private var market = ""
    @State private var industry = ""
    @State private var showAll = false
    var body: some View {
        let text = query.trimmingCharacters(in: .whitespaces)
        let all = store.stockSnapshot?.stocks ?? []
        let items = all.filter { (market.isEmpty || $0.market == market) && (industry.isEmpty || $0.industry == industry) && (text.isEmpty || $0.id.localizedCaseInsensitiveContains(text) || $0.name.localizedCaseInsensitiveContains(text)) }
        let visible = showAll ? items : Array(items.prefix(60))
        VStack(alignment: .leading, spacing: 14) {
            Card(padding: 14) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) { Capsule().fill(Palette.orange).frame(width: 3, height: 14); Text("市場").font(.subheadline.bold()).foregroundStyle(Palette.ink) }.frame(width: 64, alignment: .leading)
                    OptionChip(title: "全部", on: market.isEmpty) { market = "" }
                    OptionChip(title: "上市", on: market == "TWSE") { market = "TWSE" }
                    OptionChip(title: "上櫃", on: market == "TPEx") { market = "TPEx" }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    HStack(spacing: 6) { Capsule().fill(Palette.orange).frame(width: 3, height: 14); Text("產業").font(.subheadline.bold()).foregroundStyle(Palette.ink) }.frame(width: 64, alignment: .leading)
                    Menu {
                        Button("全部產業") { industry = "" }
                        ForEach((store.stockSnapshot?.industries ?? []).sorted(), id: \.self) { name in Button(name) { industry = name } }
                    } label: { HStack(spacing: 4) { Text(industry.isEmpty ? "全部產業" : industry); Image(systemName: "chevron.down") }.font(.subheadline.bold()) }
                    Spacer(minLength: 0)
                }.padding(.top, 12)
            }
            HStack {
                Text("\(text.isEmpty && market.isEmpty && industry.isEmpty ? "全部個股" : "符合條件") (\(items.count))").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                NavigationLink(value: AppRoute.watchlist) { Label("我的自選 \(store.data.favorites.count)", systemImage: "star.fill").font(.caption.bold()) }
            }
            Card(padding: 12) {
                if items.isEmpty { Text(all.isEmpty ? "個股名單載入失敗。" : "找不到符合的股票，換個代號、名稱或產業試試。").font(.subheadline).foregroundStyle(Palette.muted) }
                LazyVStack(spacing: 0) {
                    ForEach(visible) { stock in
                        SymbolRow(symbol: stock.id, subtitle: stock.industry)
                        if stock.id != visible.last?.id { Divider() }
                    }
                }
                if items.count > visible.count { Button("顯示全部 \(items.count) 檔") { showAll = true }.font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.top, 10) }
            }
            if let snapshot = store.stockSnapshot {
                Text("上市 \(all.filter { $0.market == "TWSE" }.count) · 上櫃 \(all.filter { $0.market == "TPEx" }.count) 家公司（資料日 \(snapshot.fetchedDay)）。開盤時間會即時更新報價，尚未更新的顯示 \(snapshot.closeDate["twse"] ?? "") 收盤價。").font(.caption).foregroundStyle(Palette.muted)
            }
        }
    }
}
