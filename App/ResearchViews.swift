import SwiftUI
import Charts
import UniformTypeIdentifiers

struct ComponentsView: View {
    let symbol: String
    var body: some View { Page { ComponentsContent(symbol: symbol) }.navigationTitle("成分股與權重").navigationBarTitleDisplayMode(.inline) }
}
struct ComponentsContent: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    @State private var busy = false
    @State private var importing = false
    @State private var error: String?
    private var snapshot: ComponentSnapshot? { store.data.components?[symbol] }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                Text("\(symbol) 成分股").font(.title3.bold()).foregroundStyle(Palette.ink)
                Button(busy ? "取得中…" : "更新成分股") { Task { busy = true; error = nil; defer { busy = false }; do { try store.saveComponents(await Fugle.components(symbol: symbol)) } catch { self.error = error.localizedDescription } } }.buttonStyle(.borderedProminent).disabled(busy).padding(.vertical, 12)
                Button("匯入成分股 JSON") { importing = true }
                Text("連線需要行情金鑰的成分股權限；也可匯入有日期的成分檔。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 12)
            }
            if let error { Text(error).foregroundStyle(Palette.red) }
            if let snapshot {
                Card { LabeledContent("資料日期", value: snapshot.date); LabeledContent("揭露股票權重", value: "\(decimal(snapshot.totalWeight))%").padding(.vertical, 12) }
                Text("只包含已揭露股票部位，可能未含現金、債券與期貨；不是基金全部資產。").font(.caption).foregroundStyle(Palette.muted)
                Card(padding: 12) {
                    LazyVStack(spacing: 0) {
                        ForEach(snapshot.components.sorted { $0.weight > $1.weight }) { c in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { VStack(alignment: .leading, spacing: 2) { Text(c.name ?? c.symbol).font(.subheadline.bold()).foregroundStyle(Palette.ink); Text(c.symbol).font(.caption).foregroundStyle(Palette.muted) }; Spacer(); Text("\(decimal(c.weight))%").font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.blue) }
                                ProgressView(value: min(c.weight, 100), total: 100).tint(Palette.blue)
                            }.padding(.vertical, 8)
                        }
                    }
                }
            } else { ContentUnavailableView("尚無成分資料", systemImage: "square.grid.2x2", description: Text("沒有資料不代表沒有重疊持股。")) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in do { let bytes = try DataChecks.readFile(result.get(), limit: 1_000_000); try store.saveComponents(ComponentSnapshot.imported(bytes, symbol: symbol)) } catch { self.error = error.localizedDescription } }
    }
}
extension PortfolioStore {
    /// Look-through exposure with directly held stocks merged in, priced the same way as the holdings' market value.
    var exposures: [ExposureRow] { ResearchMath.exposures(data, stocks: Set(data.holdings.map(\.symbol).filter { self.isStock($0) }), quote: { self.quote($0) }) }
}
struct ExposureView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var tab = 0
    @State private var busy = false
    @State private var error: String?
    private var rows: [ExposureRow] { store.exposures }
    private var covered: [Holding] { store.data.holdings.filter { store.quote($0.symbol)?.isTWD == true && (store.data.components?[$0.symbol] != nil || store.isStock($0.symbol)) } }
    var body: some View {
        // Directly held stocks have no ETF components to fetch.
        let missing = Array(Set(store.data.holdings.map(\.symbol))).sorted().filter { store.data.components?[$0] == nil && !store.isStock($0) }
        Page {
            SegmentBar(items: ["持股集中度", "重疊成分"], selection: $tab, pill: true, filled: true)
            if tab == 0 { concentration } else { overlaps }
            if !missing.isEmpty {
                Button(busy ? "取得中…" : "取得 \(missing.count) 檔持有 ETF 的成分股") { Task { await load(missing) } }.buttonStyle(.bordered).disabled(busy)
                if let error { Text(error).font(.caption).foregroundStyle(Palette.red) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { VStack(spacing: 0) { Text("持股透視").font(.headline).foregroundStyle(Palette.ink); Text("分析持股集中度與重疊成分，掌握投資組合風險").font(.caption2).foregroundStyle(Palette.muted) } } }
    }
    @ViewBuilder private var concentration: some View {
        let total = store.data.holdings.reduce(0.0) { $0 + (store.marketValue(of: $1) ?? 0) }
        if rows.isEmpty {
            Card {
                SectionHeading(title: "ETF 集中度")
                let byFund = makeSlices(store.data.holdings, key: { $0.symbol }, value: { store.marketValue(of: $0) ?? $0.cost })
                if byFund.isEmpty { Text("還沒有持有紀錄。").foregroundStyle(Palette.muted).padding(.top, 8) } else { DonutChart(slices: byFund).padding(.top, 12) }
                Text("取得持有 ETF 的成分股後，會改為顯示背後的個股與前十大持股。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 10)
            }
        } else {
            let top = Array(rows.prefix(10)), base = max(total, 1)
            let topShare = top.reduce(0.0) { $0 + $1.value } / base * 100
            let five = Array(top.prefix(5))
            let rest = max(base - five.reduce(0.0) { $0 + $1.value }, 0)
            let named: [Slice] = five.enumerated().map { pair in Slice(label: pair.element.name, amount: pair.element.value, color: Palette.series[pair.offset]) }
            let slices: [Slice] = named + [Slice(label: "其他", amount: rest, color: Palette.series[6])]
            Card {
                SectionHeading(title: "持股分布")
                DonutChart(slices: slices, center: ("前十大", "\(decimal(topShare))%")).padding(.top, 12)
            }
            Card {
                SectionHeading(title: "前十大持股明細")
                ForEach(Array(top.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 10) {
                        Text("\(index + 1)").font(.caption.bold()).monospacedDigit().frame(width: 18)
                        Text(row.name).font(.subheadline).lineLimit(1).frame(width: 96, alignment: .leading)
                        GeometryReader { proxy in ZStack(alignment: .leading) { Capsule().fill(Palette.blue.opacity(0.1)); Capsule().fill(Palette.blue).frame(width: proxy.size.width * row.value / max(top[0].value, 0.000001)) } }.frame(height: 7)
                        Text("\(decimal(row.value / base * 100))%").font(.caption.bold()).monospacedDigit().frame(width: 52, alignment: .trailing)
                    }.foregroundStyle(Palette.ink).padding(.vertical, 6)
                }
                Text("比重＝透過 ETF 間接持有加上直接持有的金額 ÷ 你的台幣持有市值；納入 \(covered.count)／\(store.data.holdings.count) 筆持有。不同 ETF 可能使用不同公告日期。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 8)
            }
        }
    }
    @ViewBuilder private var overlaps: some View {
        let symbols = Array(Set(store.data.holdings.map(\.symbol))).sorted().filter { store.data.components?[$0] != nil }
        let pairs: [(String, String, Int, Double)] = symbols.indices.flatMap { i in symbols.indices.filter { $0 > i }.compactMap { j -> (String, String, Int, Double)? in
            guard let a = store.data.components?[symbols[i]], let b = store.data.components?[symbols[j]] else { return nil }
            let shared = ResearchMath.overlap(a, b)
            return (symbols[i], symbols[j], shared.count, shared.reduce(0) { $0 + min($1.left, $1.right) })
        } }.sorted { $0.3 > $1.3 }
        Card(padding: 12) {
            if pairs.isEmpty { Text("至少需要兩檔持有 ETF 的成分資料才能比較重疊。").font(.subheadline).foregroundStyle(Palette.muted).padding(4) }
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                HStack { Text("\(pair.0) × \(pair.1)").font(.subheadline.bold()).foregroundStyle(Palette.ink); Spacer(); Text("共同 \(pair.2) 檔").font(.caption).foregroundStyle(Palette.muted); Text("\(decimal(pair.3))%").font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.blue).frame(width: 64, alignment: .trailing) }.padding(.vertical, 8)
            }
        }
        Text("重疊權重下限＝共同成分在兩檔 ETF 權重的較小值加總。沒有共同股票也不表示整體風險沒有重疊。").font(.caption).foregroundStyle(Palette.muted)
    }
    private func load(_ symbols: [String]) async {
        busy = true; error = nil
        defer { busy = false }
        for symbol in symbols {
            do { try store.saveComponents(await Fugle.components(symbol: symbol)) } catch { self.error = "\(symbol)：\(error.localizedDescription)" }
        }
    }
}
struct OverlapPanel: View {
    @EnvironmentObject var store: PortfolioStore
    let left: String
    let right: String
    var body: some View { Card {
        Text("成分股重疊 · \(left) × \(right)").font(.headline).foregroundStyle(Palette.ink)
        if left == right { Text("請選擇兩檔不同 ETF。").padding(.top, 10) }
        else if let a = store.data.components?[left], let b = store.data.components?[right] {
            let rows = ResearchMath.overlap(a, b)
            LabeledContent("共同股票", value: "\(rows.count) 檔").padding(.top, 14)
            LabeledContent("共同權重下限", value: "\(decimal(rows.reduce(0) { $0 + min($1.left, $1.right) }))%").padding(.vertical, 10)
            Text("\(left)：\(a.date)（揭露 \(decimal(a.totalWeight))%）\n\(right)：\(b.date)（揭露 \(decimal(b.totalWeight))%）").font(.caption).foregroundStyle(Palette.muted)
            if a.date != b.date { Text("公告日期不同，結果並非同日比較。").font(.caption).foregroundStyle(Palette.orange).padding(.top, 8) }
            Text("共同權重為各共同股票兩邊較小權重的加總，未揭露部位不推估。沒有共同股票也不表示整體風險沒有重疊。").font(.caption).foregroundStyle(Palette.muted).padding(.vertical, 10)
            ForEach(rows) { row in HStack { Text(row.name).font(.subheadline); Spacer(); Text("\(decimal(row.left))% / \(decimal(row.right))%").font(.caption) }.padding(.vertical, 6) }
        } else { Text("尚缺成分資料，無法計算重疊。").foregroundStyle(Palette.muted).padding(.vertical, 14) }
        HStack { NavigationLink("\(left) 成分股") { ComponentsView(symbol: left) }; Spacer(); NavigationLink("\(right) 成分股") { ComponentsView(symbol: right) } }.font(.subheadline).padding(.top, 14)
    } }
}
struct HistoryContent: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    @State private var years = 3
    @State private var range = ChartRange.all
    @State private var busy = false
    @State private var error: String?
    private var history: PriceHistory? { store.data.histories?[symbol] }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                Picker("查詢期間", selection: $years) { Text("1 年").tag(1); Text("3 年").tag(3); Text("5 年").tag(5); Text("10 年").tag(10); Text("最長 16 年").tag(16) }.pickerStyle(.menu)
                Button(busy ? "分段取得歷史資料…" : "更新歷史績效") { Task { busy = true; error = nil; defer { busy = false }; do { try store.saveHistory(await Fugle.history(symbol: symbol, years: years)) } catch { self.error = error.localizedDescription } } }.buttonStyle(.borderedProminent).disabled(busy)
                Text("取實際還原日收盤價，最早自 2010 年或基金上市日開始。長區間會分段查詢，約需數十秒。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 12)
            }
            if let error { Text(error).foregroundStyle(Palette.red) }
            if let history, let stats = try? PerformanceStats(history) {
                let points = TrendMath.slice(TrendMath.points(history), range)
                Card(padding: 14) {
                    Text("還原價格走勢").font(.headline).foregroundStyle(Palette.ink)
                    RangeChips(options: [.month, .year, .fiveYears, .all], selection: $range).padding(.vertical, 10)
                    if points.count >= 2 { ValueChart(points: points, showAxes: true, height: 220) } else { Text("此區間資料不足。").font(.caption).foregroundStyle(Palette.muted) }
                    Text("\(history.points.first!.date) ～ \(history.points.last!.date) · \(history.points.count) 筆").font(.caption).foregroundStyle(Palette.muted).padding(.top, 8)
                }
                Card {
                    stat("區間報酬", stats.change); Divider().padding(.vertical, 12)
                    stat("年化報酬", stats.annualized); Divider().padding(.vertical, 12)
                    stat("最大回撤", stats.drawdown); Divider().padding(.vertical, 12)
                    stat("年化波動率", stats.volatility)
                }
                Text("資料取得日 \(history.fetchedDay)。依還原價格計算，並非你的交易損益；未另計稅費、匯率或個人配息再投入。年化報酬至少需一年，波動率至少需 20 個報酬樣本。無資料期間不補造價格。").font(.caption).foregroundStyle(Palette.muted)
            } else { ContentUnavailableView("尚無歷史資料", systemImage: "chart.xyaxis.line", description: Text("使用你的行情金鑰取得資料後才計算，不使用情境試算代替。")) }
        }
    }
    private func stat(_ title: String, _ value: Double?) -> some View { LabeledContent(title, value: value.map { "\(decimal($0 * 100))%" } ?? "資料期間不足") }
}
struct FeesContent: View {
    @EnvironmentObject var store: PortfolioStore
    let fund: Fund
    @State private var editing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                Text("已公布的年度實際費用").font(.title3.bold()).foregroundStyle(Palette.ink).accessibilityIdentifier("annual-fee-heading")
                if let catalog = AnnualFeeCatalog.bundled, let fee = catalog.records[fund.id] {
                    LabeledContent("\(String(fee.year)) 年總費用率", value: "\(decimal(fee.total))%")
                        .font(.headline).padding(.vertical, 16)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(String(fee.year)) 年總費用率")
                        .accessibilityValue("\(decimal(fee.total))%")
                        .accessibilityIdentifier("annual-fee-total")
                    feeLine("經理費", fee.management); feeLine("保管費", fee.custody)
                    feeLine("交易手續費", fee.commission); feeLine("交易稅", fee.tax)
                    feeLine("申購／買回交易費（扣抵）", fee.subscriptionOffset)
                    feeLine("保證費", fee.guarantee); feeLine("其他費用", fee.other)
                    Text("統計截至 \(String(fee.year))/12/31；取得日 \(catalog.fetchedDay)。基金統編 \(fee.fundID)。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 12)
                    Text("全年累計實際比率，並非現行契約費率；當年新成立基金可能未涵蓋完整一年。總費用率使用原始公布值，各項四捨五入後可能不完全相加一致。交易費用扣抵申購／買回交易費，不能全部相加。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 10)
                } else {
                    Text("這檔尚未配對到已核對的年度費用資料。新掛牌、主動式、期貨型或更名基金可能缺值；不顯示為 0%。").foregroundStyle(Palette.muted).padding(.top, 14)
                }
            }
            Card {
                Text("費用率與級距").font(.title3.bold()).foregroundStyle(Palette.ink)
                if let fee = store.data.fees?[fund.id] {
                    Text("經理費").font(.headline).padding(.top, 18); Text(fee.management).padding(.top, 5)
                    Text("保管費").font(.headline).padding(.top, 18); Text(fee.custody).padding(.top, 5)
                    if let rate = fee.annualExpensePercent, let year = fee.expenseYear { LabeledContent("\(String(year)) 年總費用率", value: "\(decimal(rate))%").padding(.top, 18) }
                    Text("資料日期：\(fee.effectiveDate)").font(.caption).foregroundStyle(Palette.muted).padding(.top, 14)
                    Text(fee.note).font(.caption).foregroundStyle(Palette.muted).padding(.top, 8)
                    Text("使用者記錄，尚未由 App 核驗最新契約。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 8)
                } else { Text("尚未收錄經核對的費用率，缺值不當成 0%。").foregroundStyle(Palette.muted).padding(.vertical, 14) }
                Button("記錄／更新費用資料") { editing = true }.buttonStyle(.bordered).padding(.top, 14)
            }
            Card { Text("三種費用不能混用").font(.headline).foregroundStyle(Palette.ink); Text("經理費與保管費可能依基金規模分級距；年度總費用率還包含其他實際支出。不要把兩項契約費率相加，當成完整年度總費用率。").font(.subheadline).padding(.top, 12) }
            Link("前往官方 ETF 資料專區", destination: URL(string: fund.market == "TPEx" ? "https://info.tpex.org.tw/ETF/zh/" : "https://www.twse.com.tw/zh/ETFortune/etfInfo/\(fund.id)")!)
        }
        .sheet(isPresented: $editing) { FeeEditor(symbol: fund.id) }
    }
    private func feeLine(_ title: String, _ value: Double) -> some View { LabeledContent(title, value: "\(decimal(value))%").font(.subheadline).padding(.vertical, 6) }
}
struct FeeEditor: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.dismiss) var dismiss
    let symbol: String
    @State private var date = Date()
    @State private var management = ""
    @State private var custody = ""
    @State private var expense = ""
    @State private var year = ""
    @State private var source = ""
    @State private var note = ""
    @State private var error: String?
    var body: some View { NavigationStack { Form {
        Section("依公開說明書或投信公告填寫") { DatePicker("有效／查核日期", selection: $date, in: ...Date(), displayedComponents: .date); TextField("經理費與完整級距", text: $management, axis: .vertical); TextField("保管費與完整級距", text: $custody, axis: .vertical) }
        Section("選填：已公布的年度實際費用") { TextField("總費用率 %", text: $expense).keyboardType(.decimalPad); TextField("西元統計年度", text: $year).keyboardType(.numberPad); TextField("備註", text: $note, axis: .vertical) }
        if let error { Text(error).foregroundStyle(.red) }
    }.navigationTitle("記錄費用資料").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("儲存") { do {
        if (!expense.isEmpty && Double(expense) == nil) || (!year.isEmpty && Int(year) == nil) { throw AppDataError("費用率及年度須為數字。") }
        try store.saveFee(FeeRecord(symbol: symbol, effectiveDate: DataChecks.day(date), management: management, custody: custody, annualExpensePercent: Double(expense), expenseYear: Int(year), sourceURL: source, note: note)); dismiss()
    } catch { self.error = error.localizedDescription } } } }.onAppear { if let value = store.data.fees?[symbol] { date = DataChecks.date(value.effectiveDate) ?? Date(); management = value.management; custody = value.custody; expense = value.annualExpensePercent.map { String($0) } ?? ""; year = value.expenseYear.map { String($0) } ?? ""; source = value.sourceURL; note = value.note } } } }
}
