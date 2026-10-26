import SwiftUI
import Charts
import UniformTypeIdentifiers

struct ComponentsView: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    @State private var busy = false
    @State private var importing = false
    @State private var error: String?
    private var snapshot: ComponentSnapshot? { store.data.components?[symbol] }
    var body: some View { Page {
        Card {
            Text("\(symbol) 成分股").font(.title2.bold())
            Button(busy ? "取得中…" : "更新成分股") { Task { busy = true; error = nil; defer { busy = false }; do { try store.saveComponents(await Fugle.components(symbol: symbol)) } catch { self.error = error.localizedDescription } } }.buttonStyle(.borderedProminent).disabled(busy || store.isDemo).padding(.vertical, 12)
            Button("匯入成分股 JSON") { importing = true }.disabled(store.isDemo)
            Text("連線需要富果成分股資料權限；也可匯入有來源及日期的成分檔。").font(.caption).foregroundStyle(.secondary).padding(.top, 12)
        }
        if let error { Text(error).foregroundStyle(.red) }
        if let snapshot {
            Card { LabeledContent("資料日期", value: snapshot.date); LabeledContent("揭露股票權重", value: "\(decimal(snapshot.totalWeight))%").padding(.vertical, 12); Text(snapshot.source ?? "未提供來源").font(.caption).foregroundStyle(.secondary) }
            Text("只包含已揭露股票部位，可能未含現金、債券與期貨；不是基金全部資產。").font(.caption).foregroundStyle(.secondary)
            LazyVStack(spacing: 10) { ForEach(snapshot.components.sorted { $0.weight > $1.weight }) { c in Card { HStack { VStack(alignment: .leading) { Text(c.name ?? c.symbol).font(.headline); Text(c.symbol).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(decimal(c.weight))%").font(.headline).foregroundStyle(Palette.blue) } } } }
        } else { ContentUnavailableView("尚無成分資料", systemImage: "square.grid.2x2", description: Text("沒有資料不代表沒有重疊持股。")) }
    }.navigationTitle("成分股與權重").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in do { let bytes = try DataChecks.readFile(result.get(), limit: 1_000_000); try store.saveComponents(ComponentSnapshot.imported(bytes, symbol: symbol)) } catch { self.error = error.localizedDescription } }
    }
}
struct ExposureView: View {
    @EnvironmentObject var store: PortfolioStore
    private var etfs: Set<String>? { store.funds.isEmpty ? nil : Set(store.funds.map(\.id)) }
    private var rows: [ExposureRow] { ResearchMath.exposures(store.data, etfs: etfs) }
    private var covered: [Holding] { store.data.holdings.filter { h in store.data.quotes[h.symbol]?.isTWD == true && (store.data.components?[h.symbol] != nil || etfs?.contains(h.symbol) == false) } }
    var body: some View { Page {
        Card { Text("ETF 背後的持股").font(.title2.bold()); Text("納入 \(covered.count)／\(store.data.holdings.count) 筆持有").padding(.top, 10); Text("依台幣報價 × 股數 × 揭露權重加總，直接持有的個股併入同一檔股票。不同 ETF 可能使用不同公告日期；不含缺少資料、未確認幣別或外幣報價的部位。").font(.caption).foregroundStyle(.secondary).padding(.top, 10) }
        if rows.isEmpty { ContentUnavailableView("資料還不完整", systemImage: "chart.pie", description: Text("先在 ETF 詳情更新成分股與報價。")) }
        ForEach(rows) { row in Card { HStack { Text(row.name).font(.headline); Spacer(); Text("$\(money(row.value))").font(.headline).foregroundStyle(Palette.blue) }; Text("\(row.symbol) · 來自 \(row.funds.sorted().joined(separator: "、"))").font(.caption).foregroundStyle(.secondary).padding(.top, 10) } }
    }.navigationTitle("持股穿透").navigationBarTitleDisplayMode(.inline) }
}
struct OverlapPanel: View {
    @EnvironmentObject var store: PortfolioStore
    let left: String
    let right: String
    var body: some View { Card {
        Text("成分股重疊").font(.title3.bold())
        if left == right { Text("請選擇兩檔不同 ETF。").padding(.top, 10) }
        else if let a = store.data.components?[left], let b = store.data.components?[right] {
            let rows = ResearchMath.overlap(a, b)
            LabeledContent("共同股票", value: "\(rows.count) 檔").padding(.top, 14)
            LabeledContent("共同權重下限", value: "\(decimal(rows.reduce(0) { $0 + min($1.left, $1.right) }))%").padding(.vertical, 10)
            Text("\(left)：\(a.date)（揭露 \(decimal(a.totalWeight))%）\n\(right)：\(b.date)（揭露 \(decimal(b.totalWeight))%）").font(.caption).foregroundStyle(.secondary)
            if a.date != b.date { Text("公告日期不同，結果並非同日比較。").font(.caption).foregroundStyle(.orange).padding(.top, 8) }
            Text("共同權重為各共同股票兩邊較小權重的加總，未揭露部位不推估。沒有共同股票也不表示整體風險沒有重疊。").font(.caption).foregroundStyle(.secondary).padding(.vertical, 10)
            ForEach(rows) { row in HStack { Text(row.name).font(.subheadline); Spacer(); Text("\(decimal(row.left))% / \(decimal(row.right))%").font(.caption) }.padding(.vertical, 6) }
        } else { Text("尚缺成分資料，無法計算重疊。").foregroundStyle(.secondary).padding(.vertical, 14) }
        HStack { NavigationLink("\(left) 成分股") { ComponentsView(symbol: left) }; Spacer(); NavigationLink("\(right) 成分股") { ComponentsView(symbol: right) } }.font(.subheadline).padding(.top, 14)
    } }
}
struct HistoryView: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    @State private var years = 3
    @State private var busy = false
    @State private var error: String?
    private var history: PriceHistory? { store.data.histories?[symbol] }
    var body: some View { Page {
        Card {
            Picker("查詢期間", selection: $years) { Text("1 年").tag(1); Text("3 年").tag(3); Text("5 年").tag(5); Text("10 年").tag(10); Text("最長 16 年").tag(16) }.pickerStyle(.menu)
            Button(busy ? "分段取得歷史資料…" : "更新歷史績效") { Task { busy = true; error = nil; defer { busy = false }; do { try store.saveHistory(await Fugle.history(symbol: symbol, years: years)) } catch { self.error = error.localizedDescription } } }.buttonStyle(.borderedProminent).disabled(busy || store.isDemo)
            Text("取實際還原日收盤價，最早自 2010 年或基金上市日開始。長區間會分段查詢，約需數十秒。").font(.caption).foregroundStyle(.secondary).padding(.top, 12)
        }
        if let error { Text(error).foregroundStyle(.red) }
        if let history, let stats = try? PerformanceStats(history) {
            Card {
                Text("還原價格走勢").font(.headline)
                Chart(history.points) { point in LineMark(x: .value("日期", DataChecks.date(point.date)!), y: .value("還原價格", point.close)).foregroundStyle(Palette.blue) }.frame(height: 220).padding(.vertical, 15)
                Text("\(history.points.first!.date) ～ \(history.points.last!.date) · \(history.points.count) 筆").font(.caption).foregroundStyle(.secondary)
            }
            Card {
                stat("區間報酬", stats.change); Divider().padding(.vertical, 12)
                stat("年化報酬", stats.annualized); Divider().padding(.vertical, 12)
                stat("最大回撤", stats.drawdown); Divider().padding(.vertical, 12)
                stat("年化波動率", stats.volatility)
            }
            Text("資料：\(history.source)，取得日 \(history.fetchedDay)。依供應商還原價格計算，並非你的交易損益；未另計稅費、匯率或個人配息再投入。年化報酬至少需一年，波動率至少需 20 個報酬樣本。無資料期間不補造價格。").font(.caption).foregroundStyle(.secondary)
        } else { ContentUnavailableView("尚無歷史資料", systemImage: "chart.xyaxis.line", description: Text("使用你的富果金鑰取得資料後才計算，不使用情境試算代替。")) }
    }.navigationTitle("\(symbol) 歷史績效").navigationBarTitleDisplayMode(.inline) }
    private func stat(_ title: String, _ value: Double?) -> some View { LabeledContent(title, value: value.map { "\(decimal($0 * 100))%" } ?? "資料期間不足") }
}
struct FeesView: View {
    @EnvironmentObject var store: PortfolioStore
    let fund: Fund
    @State private var editing = false
    var body: some View { Page {
        Card {
            Text("已公布的年度實際費用").font(.title2.bold()).accessibilityIdentifier("annual-fee-heading")
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
                Text("統計截至 \(String(fee.year))/12/31；取得日 \(catalog.fetchedDay)。來源：投信投顧公會，各投信申報。基金統編 \(fee.fundID)。").font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                Text("全年累計實際比率，並非現行契約費率；當年新成立基金可能未涵蓋完整一年。總費用率使用原始公布值，各項四捨五入後可能不完全相加一致。交易費用扣抵申購／買回交易費，不能全部相加。").font(.caption).foregroundStyle(.secondary).padding(.top, 10)
                Link("查看公會月／季／年報表", destination: URL(string: catalog.sourceURL)!).padding(.top, 12)
            } else {
                Text("這檔尚未配對到已核對的年度費用資料。新掛牌、主動式、期貨型或更名基金可能缺值；不顯示為 0%。").foregroundStyle(.secondary).padding(.top, 14)
                Link("查看公會費用報表", destination: URL(string: "https://www.sitca.org.tw/ROC/Industry/IN2211.aspx?pid=IN2222_01")!).padding(.top, 12)
            }
        }
        Card {
            Text("費用率與級距").font(.title2.bold())
            if let fee = store.data.fees?[fund.id] {
                Text("經理費").font(.headline).padding(.top, 18); Text(fee.management).padding(.top, 5)
                Text("保管費").font(.headline).padding(.top, 18); Text(fee.custody).padding(.top, 5)
                if let rate = fee.annualExpensePercent, let year = fee.expenseYear { LabeledContent("\(String(year)) 年總費用率", value: "\(decimal(rate))%").padding(.top, 18) }
                Text("資料日期：\(fee.effectiveDate)").font(.caption).foregroundStyle(.secondary).padding(.top, 14)
                Text(fee.note).font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                if let url = URL(string: fee.sourceURL) { Link("查看記錄的資料來源", destination: url).padding(.top, 12) }
                Text("使用者記錄，尚未由 App 核驗最新契約。").font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            } else { Text("尚未收錄經核對的費用率，缺值不當成 0%。").foregroundStyle(.secondary).padding(.vertical, 14) }
            Button("記錄／更新費用資料") { editing = true }.buttonStyle(.bordered).padding(.top, 14)
        }
        Card { Text("三種費用不能混用").font(.headline); Text("經理費與保管費可能依基金規模分級距；年度總費用率還包含其他實際支出。不要把兩項契約費率相加，當成完整年度總費用率。").font(.subheadline).padding(.top, 12) }
        Link("前往官方 ETF 資料專區", destination: URL(string: fund.market == "TPEx" ? "https://info.tpex.org.tw/ETF/zh/" : "https://www.twse.com.tw/zh/ETFortune/etfInfo/\(fund.id)")!)
    }.navigationTitle("\(fund.id) 費用資料").navigationBarTitleDisplayMode(.inline).sheet(isPresented: $editing) { FeeEditor(symbol: fund.id) } }
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
        Section("依公開說明書或投信公告填寫") { DatePicker("有效／查核日期", selection: $date, in: ...Date(), displayedComponents: .date); TextField("經理費與完整級距", text: $management, axis: .vertical); TextField("保管費與完整級距", text: $custody, axis: .vertical); TextField("資料來源網址 HTTPS", text: $source).textInputAutocapitalization(.never).keyboardType(.URL) }
        Section("選填：已公布的年度實際費用") { TextField("總費用率 %", text: $expense).keyboardType(.decimalPad); TextField("西元統計年度", text: $year).keyboardType(.numberPad); TextField("備註", text: $note, axis: .vertical) }
        if let error { Text(error).foregroundStyle(.red) }
    }.navigationTitle("記錄費用資料").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("儲存") { do {
        if (!expense.isEmpty && Double(expense) == nil) || (!year.isEmpty && Int(year) == nil) { throw AppDataError("費用率及年度須為數字。") }
        try store.saveFee(FeeRecord(symbol: symbol, effectiveDate: DataChecks.day(date), management: management, custody: custody, annualExpensePercent: Double(expense), expenseYear: Int(year), sourceURL: source, note: note)); dismiss()
    } catch { self.error = error.localizedDescription } } } }.onAppear { if let value = store.data.fees?[symbol] { date = DataChecks.date(value.effectiveDate) ?? Date(); management = value.management; custody = value.custody; expense = value.annualExpensePercent.map { String($0) } ?? ""; year = value.expenseYear.map { String($0) } ?? ""; source = value.sourceURL; note = value.note } } } }
}
