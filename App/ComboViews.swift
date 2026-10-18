import SwiftUI

/* ---------- 個股＋ETF 組合試算 ----------
   Monthly compounding of an assumed annual total return (dividends included, never added twice), new money at month
   end (or start), split between stocks and ETFs by the chosen mix. Without reinvestment a cash yield is paid out each
   month and kept as cash. Scenarios shift both assumptions: 保守 −7 points, 樂觀 +3 points; the stress test applies
   −30% in the first year, then the base assumptions. Same method as the web app. */
enum ComboScenario: String, Codable, CaseIterable, Identifiable {
    case conservative = "保守", base = "基準", optimistic = "樂觀", stress = "壓力測試"
    var id: String { rawValue }
    func rate(_ base: Double) -> Double {
        switch self { case .conservative: return base - 7; case .optimistic: return base + 3; case .base, .stress: return base }
    }
    var color: Color {
        switch self { case .conservative: return Palette.pink; case .base: return Palette.blue; case .optimistic: return Palette.green; case .stress: return Palette.deepBlue }
    }
}
struct ComboItem: Codable, Hashable, Identifiable {
    var symbol: String
    var amount: Double
    var id: String { symbol }
}
struct ComboSettings: Codable, Equatable {
    /// 0 = 我的持有, 1 = 模擬組合.
    var source = 0
    var simulated: [ComboItem] = []
    var excluded: [String] = []
    var includeStocks = true
    var includeETFs = true
    var snapshotAt: Date? = nil
    var monthly: Double = 10000
    /// Share of new money going to stocks; nil follows the current mix.
    var stockPercent: Double? = nil
    var startOfMonth = false
    var years = 5
    var stockReturn: Double = 5
    var etfReturn: Double = 5
    var reinvest = true
    var stockYield: Double? = nil
    var etfYield: Double? = nil
    var buyFee = false
    var scenario = ComboScenario.base
    init() {}
    /// Every field is optional in stored data, so a file written by another version still opens.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = ComboSettings()
        source = try c.decodeIfPresent(Int.self, forKey: .source) ?? base.source
        simulated = try c.decodeIfPresent([ComboItem].self, forKey: .simulated) ?? []
        excluded = try c.decodeIfPresent([String].self, forKey: .excluded) ?? []
        includeStocks = try c.decodeIfPresent(Bool.self, forKey: .includeStocks) ?? true
        includeETFs = try c.decodeIfPresent(Bool.self, forKey: .includeETFs) ?? true
        snapshotAt = try c.decodeIfPresent(Date.self, forKey: .snapshotAt)
        monthly = try c.decodeIfPresent(Double.self, forKey: .monthly) ?? base.monthly
        stockPercent = try c.decodeIfPresent(Double.self, forKey: .stockPercent)
        startOfMonth = try c.decodeIfPresent(Bool.self, forKey: .startOfMonth) ?? false
        years = try c.decodeIfPresent(Int.self, forKey: .years) ?? base.years
        stockReturn = try c.decodeIfPresent(Double.self, forKey: .stockReturn) ?? base.stockReturn
        etfReturn = try c.decodeIfPresent(Double.self, forKey: .etfReturn) ?? base.etfReturn
        reinvest = try c.decodeIfPresent(Bool.self, forKey: .reinvest) ?? true
        stockYield = try c.decodeIfPresent(Double.self, forKey: .stockYield)
        etfYield = try c.decodeIfPresent(Double.self, forKey: .etfYield)
        buyFee = try c.decodeIfPresent(Bool.self, forKey: .buyFee) ?? false
        scenario = (try? c.decodeIfPresent(ComboScenario.self, forKey: .scenario)) ?? .base
    }
    var isValid: Bool {
        let numbers = [monthly, stockReturn, etfReturn] + [stockPercent, stockYield, etfYield].compactMap { $0 } + simulated.map(\.amount)
        return numbers.allSatisfy { $0.isFinite } && monthly >= 0 && monthly <= 1e9 && [3, 5, 10].contains(years)
            && simulated.count <= 60 && simulated.allSatisfy { DataChecks.code($0.symbol) && $0.amount >= 0 && $0.amount <= 1e12 }
            && excluded.count <= 500 && abs(stockReturn) < 50 && abs(etfReturn) < 50
    }
}
enum ComboMath {
    struct Part { let start: Double; let invested: Double; let value: Double; let cash: Double; var end: Double { value + cash } }
    struct Result { let stock: Part; let etf: Part; let invested: Double; var end: Double { stock.end + etf.end } }
    static func project(stockStart: Double, etfStart: Double, settings c: ComboSettings, stockShare: Double, years: Int, scenario: ComboScenario) -> Result {
        let fee = c.buyFee ? 0.001425 : 0
        let shareStock = !c.includeETFs ? 1 : (!c.includeStocks ? 0 : stockShare)
        func part(_ start: Double, share: Double, rate: Double, yield: Double) -> Part {
            var value = start, cash = 0.0
            for month in 1...(years * 12) {
                let annual = scenario == .stress && month <= 12 ? -0.3 : rate / 100
                let growth = pow(1 + annual, 1.0 / 12) - 1
                let put = c.monthly * share * (1 - fee)
                if c.startOfMonth { value += put }
                let paid = value * yield / 12
                value = value * (1 + growth) - paid
                cash += paid
                if !c.startOfMonth { value += put }
            }
            return Part(start: start, invested: c.monthly * share * Double(years * 12), value: value, cash: cash)
        }
        let stock = part(stockStart, share: shareStock, rate: scenario.rate(c.stockReturn), yield: c.reinvest ? 0 : (c.stockYield ?? 0) / 100)
        let etf = part(etfStart, share: 1 - shareStock, rate: scenario.rate(c.etfReturn), yield: c.reinvest ? 0 : (c.etfYield ?? 0) / 100)
        return Result(stock: stock, etf: etf, invested: c.monthly * Double(years * 12))
    }
}
struct ComboLine: Identifiable {
    let symbol: String
    let amount: Double
    let isStock: Bool
    var id: String { symbol }
}
extension PortfolioStore {
    var combo: ComboSettings { data.combo ?? ComboSettings() }
    func saveCombo(_ value: ComboSettings) {
        var next = data; next.combo = value
        do { try commit(next) } catch { message = error.localizedDescription }
    }
    func comboLines(_ c: ComboSettings) -> [ComboLine] {
        if c.source == 1 { return c.simulated.map { ComboLine(symbol: $0.symbol, amount: $0.amount, isStock: isStock($0.symbol)) } }
        var totals: [String: Double] = [:]
        for holding in data.holdings { totals[holding.symbol, default: 0] += marketValue(of: holding) ?? holding.cost }
        return totals.filter { !c.excluded.contains($0.key) }.map { ComboLine(symbol: $0.key, amount: $0.value, isStock: isStock($0.key)) }.sorted { $0.amount > $1.amount }
    }
    /// Starting amounts of the included groups.
    func comboStarts(_ c: ComboSettings) -> (stock: Double, etf: Double) {
        let lines = comboLines(c)
        let stock = c.includeStocks ? lines.filter(\.isStock).reduce(0) { $0 + $1.amount } : 0
        let etf = c.includeETFs ? lines.filter { !$0.isStock }.reduce(0) { $0 + $1.amount } : 0
        return (stock, etf)
    }
    func comboStockShare(_ c: ComboSettings) -> Double {
        if let percent = c.stockPercent { return min(max(percent, 0), 100) / 100 }
        let starts = comboStarts(c), total = starts.stock + starts.etf
        return total > 0 ? (starts.stock / total * 100).rounded() / 100 : 0.4
    }
    /// The holdings' last-year cash dividends as a yield once the records cover that year, else 2% for stocks and 4% for ETFs.
    func comboDefaultYields(_ c: ComboSettings) -> (stock: Double, etf: Double) {
        let lines = comboLines(c)
        func weighted(_ items: [ComboLine], perShare: (String) -> Double) -> Double? {
            var weight = 0.0, total = 0.0
            for line in items {
                guard let price = quote(line.symbol)?.price, price > 0 else { continue }
                let yield = perShare(line.symbol) / price * 100
                if yield > 0 { total += yield * line.amount; weight += line.amount }
            }
            return weight > 0 ? total / weight : nil
        }
        let stock = weighted(lines.filter(\.isStock)) { StockSnapshot.bundled?.trailingCash($0) ?? 0 }
        let etf = weighted(lines.filter { !$0.isStock }) { official.trailingAmount($0) ?? 0 }
        return (((stock ?? 2) * 100).rounded() / 100, ((etf ?? 4) * 100).rounded() / 100)
    }
    /// Copies the current holdings into the simulated mix, so it can be edited without touching real holdings.
    func comboWithSimulation(_ c: ComboSettings) -> ComboSettings {
        var next = c
        if next.source == 0 {
            var holdingsMix = c; holdingsMix.excluded = []
            next.simulated = comboLines(holdingsMix).map { ComboItem(symbol: $0.symbol, amount: $0.amount.rounded()) }
            next.source = 1
            if next.snapshotAt == nil { next.snapshotAt = Date() }
        }
        return next
    }
}
private func scenarioLabel(_ c: ComboSettings, _ scenario: ComboScenario) -> String {
    if scenario == .stress { return "第 1 年 −30%" }
    let stock = scenario.rate(c.stockReturn), etf = scenario.rate(c.etfReturn)
    return stock == etf ? "\(decimal(stock))%" : "個股 \(decimal(stock))%／ETF \(decimal(etf))%"
}
private let stockColors: [Color] = [Color(red: 1, green: 0.35, blue: 0.54), Color(red: 0.12, green: 0.78, blue: 0.71), Color(red: 1, green: 0.69, blue: 0.13), Color(red: 1, green: 0.48, blue: 0.27), Color(red: 0.78, green: 0.42, blue: 0.98)]
private let etfColors: [Color] = [Palette.blue, Color(red: 0.37, green: 0.64, blue: 1), Palette.teal, Palette.purple, Color(red: 0.22, green: 0.76, blue: 0.45)]

struct ComboView: View {
    @EnvironmentObject var store: PortfolioStore
    /// A stock or ETF to put into the simulated mix when the screen opens (from a detail page's 加入試算).
    var addSymbol: String? = nil
    @State private var added = false
    @AppStorage("hideAmounts") private var hidden = false
    @State private var editing: ComboItem?
    @State private var adding: Bool?
    var body: some View {
        let c = store.combo, lines = store.comboLines(c)
        let stocks = lines.filter(\.isStock), etfs = lines.filter { !$0.isStock }
        let starts = store.comboStarts(c)
        Page {
            SegmentBar(items: ["我的持有", "模擬組合"], selection: Binding(get: { c.source }, set: { value in var next = c; next.source = value; store.saveCombo(next) }), pill: true, filled: true)
            heroCard(c)
            if c.source == 0 && store.data.holdings.isEmpty {
                Card { ContentUnavailableView("還沒有持有", systemImage: "bag", description: Text("先新增持有，或切換到「模擬組合」自己加入股票與 ETF。")) }
            }
            group(title: "個股", icon: "chart.line.uptrend.xyaxis", tint: Palette.pink, lines: stocks, included: c.includeStocks, total: stocks.reduce(0) { $0 + $1.amount }, isStock: true, colors: stockColors)
            group(title: "ETF", icon: "chart.bar.fill", tint: Palette.blue, lines: etfs, included: c.includeETFs, total: etfs.reduce(0) { $0 + $1.amount }, isStock: false, colors: etfColors)
            HStack {
                VStack(alignment: .leading, spacing: 2) { Text("試算總資產").font(.headline); Text("(個股＋ETF)").font(.caption).opacity(0.85) }
                Spacer()
                Text(shown(money(starts.stock + starts.etf), hidden: hidden)).font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
            }
            .foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 14)
            .background(Palette.hero, in: RoundedRectangle(cornerRadius: 20))
            Label("試算不修改實際持有，只用於模擬計算", systemImage: "info.circle").font(.caption.bold()).foregroundStyle(Palette.pink)
                .frame(maxWidth: .infinity).padding(10).background(Palette.pink.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            NavigationLink(value: AppRoute.comboSettings) { PrimaryButtonLabel(title: "設定試算", icon: "arrow.right") }.buttonStyle(.plain).accessibilityIdentifier("combo-settings")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { VStack(spacing: 0) { Text("組合試算").font(.headline).foregroundStyle(Palette.ink); Text("個股＋ETF 一起試算").font(.caption2).foregroundStyle(Palette.muted) } } }
        .onAppear { if let addSymbol, !added { added = true; add(addSymbol) } }
        .sheet(item: $editing) { item in ComboItemSheet(existing: item, isStock: store.isStock(item.symbol)) }
        .sheet(isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) { ComboItemSheet(existing: nil, isStock: adding ?? true) }
    }
    private func heroCard(_ c: ComboSettings) -> some View {
        let at = c.snapshotAt ?? Date()
        return Card(padding: 16) {
            HStack(spacing: 12) {
                Artwork(name: "tool-compound", size: 92)
                VStack(alignment: .leading, spacing: 6) {
                    Text("個股＋ETF 一起試算").font(.headline).foregroundStyle(Palette.ink)
                    Text("結合你的持有標的，輕鬆預估未來資產變化").font(.caption).foregroundStyle(Palette.muted)
                    Button { importHoldings(c) } label: { Label("帶入目前持有", systemImage: "square.and.arrow.up").font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 8).overlay(Capsule().stroke(Palette.blue, lineWidth: 1.2)) }
                        .buttonStyle(.plain).foregroundStyle(Palette.blue)
                }
            }
            Text("估值快照：\(ymdText(at)) \(at.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 8)
        }
    }
    private func importHoldings(_ c: ComboSettings) {
        var next = c
        next.excluded = []; next.snapshotAt = Date()
        if next.source == 1 { next.source = 0; next = store.comboWithSimulation(next) }
        store.saveCombo(next)
        store.message = store.data.holdings.isEmpty ? "還沒有持有可以帶入。" : "已帶入目前持有與市值。"
    }
    private func group(title: String, icon: String, tint: Color, lines: [ComboLine], included: Bool, total: Double, isStock: Bool, colors: [Color]) -> some View {
        let c = store.combo
        return Card(padding: 12) {
            HStack(spacing: 10) {
                Button {
                    var next = c
                    if isStock { next.includeStocks.toggle() } else { next.includeETFs.toggle() }
                    store.saveCombo(next)
                } label: {
                    Image(systemName: included ? "checkmark.square.fill" : "square").font(.title2).foregroundStyle(Palette.blue)
                }.buttonStyle(.plain).accessibilityLabel(included ? "不納入\(title)" : "納入\(title)")
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                Text("(\(lines.count) 檔)").font(.caption).foregroundStyle(Palette.muted)
                Spacer()
                Text(shown(money(total), hidden: hidden)).font(.title3.bold()).monospacedDigit().foregroundStyle(Palette.ink)
            }
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                Divider().padding(.vertical, 6)
                lineRow(line, color: colors[index % colors.count], source: c.source)
            }
            Button {
                if c.source == 0 { store.saveCombo(store.comboWithSimulation(c)); store.message = "已切換到模擬組合，可以自由增減，不影響實際持有。" }
                adding = isStock
            } label: {
                Label(isStock ? "新增個股" : "新增 ETF", systemImage: "plus").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 10).background(Palette.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).foregroundStyle(Palette.blue).padding(.top, 8)
        }
    }
    private func lineRow(_ line: ComboLine, color: Color, source: Int) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5).fill(color).frame(width: 18, height: 18)
            Button { if source == 1 { editing = ComboItem(symbol: line.symbol, amount: line.amount) } } label: {
                HStack(spacing: 8) {
                    Text(line.symbol).font(.subheadline.bold()).monospacedDigit()
                    Text(store.name(for: line.symbol)).font(.subheadline).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(shown(money(line.amount), hidden: false)).font(.subheadline.bold()).monospacedDigit()
                }.foregroundStyle(Palette.ink).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { remove(line.symbol) } label: { Image(systemName: "xmark").font(.caption).foregroundStyle(Palette.muted).frame(width: 26, height: 30) }.buttonStyle(.plain).accessibilityLabel("從試算移除 \(line.symbol)")
            SymbolLink(symbol: line.symbol) { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted).frame(width: 20, height: 30) }
        }
    }
    private func add(_ symbol: String) {
        var next = store.comboWithSimulation(store.combo)
        if !next.simulated.contains(where: { $0.symbol == symbol }) {
            let price = store.quote(symbol)?.price ?? 0
            let shares: Double = price > 500 ? 10 : 1000
            next.simulated.append(ComboItem(symbol: symbol, amount: price > 0 ? (price * shares).rounded() : 10000))
        }
        store.saveCombo(next)
    }
    private func remove(_ symbol: String) {
        var next = store.combo
        if next.source == 1 { next.simulated.removeAll { $0.symbol == symbol } } else if !next.excluded.contains(symbol) { next.excluded.append(symbol) }
        store.saveCombo(next)
    }
}
struct ComboItemSheet: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.dismiss) private var dismiss
    let existing: ComboItem?
    let isStock: Bool
    @State private var symbol = ""
    @State private var amount = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if let existing {
                    Text("\(existing.symbol) \(store.name(for: existing.symbol))").font(.headline)
                } else {
                    TextField(isStock ? "股票代號，例如 2330" : "ETF 代號，例如 0050", text: $symbol).textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("combo-symbol")
                    let code = symbol.trimmingCharacters(in: .whitespaces).uppercased()
                    if !code.isEmpty { Text(store.name(for: code) == code ? "清單沒有這個代號" : store.name(for: code)).font(.caption).foregroundStyle(Palette.muted) }
                }
                HStack { TextField("試算金額", text: $amount).keyboardType(.decimalPad).accessibilityIdentifier("combo-amount"); Text("元").foregroundStyle(Palette.muted) }
                if let error { Text(error).font(.caption).foregroundStyle(Palette.red) }
                if let existing { Button("從模擬組合移除", role: .destructive) { var next = store.combo; next.simulated.removeAll { $0.symbol == existing.symbol }; store.saveCombo(next); dismiss() } }
            }
            .navigationTitle(existing != nil ? "調整試算金額" : (isStock ? "新增個股" : "新增 ETF")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { save() } }
            }
            .onAppear { if let existing { amount = String(Int(existing.amount.rounded())) } }
        }
        .presentationDetents([.medium])
    }
    private func save() {
        let code = existing?.symbol ?? symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let value = Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0
        if existing == nil {
            guard DataChecks.code(code), store.name(for: code) != code else { error = "找不到這個代號，請確認。"; return }
            guard store.isStock(code) == isStock else { error = isStock ? "這是 ETF，請用「新增 ETF」。" : "這是個股，請用「新增個股」。"; return }
        }
        guard value > 0, value <= 1e12 else { error = "請填寫大於 0 的試算金額。"; return }
        var next = store.combo
        if let i = next.simulated.firstIndex(where: { $0.symbol == code }) { next.simulated[i].amount = value } else { next.simulated.append(ComboItem(symbol: code, amount: value)) }
        store.saveCombo(next)
        dismiss()
    }
}
struct ComboSettingsView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var monthly = ""
    @State private var stockPercent = ""
    @State private var stockReturn = ""
    @State private var etfReturn = ""
    @State private var stockYield = ""
    @State private var etfYield = ""
    @State private var startOfMonth = false
    @State private var years = 5
    @State private var reinvest = true
    @State private var buyFee = false
    @State private var scenario = ComboScenario.base
    @State private var loaded = false
    @State private var error: String?
    @State private var showResult = false
    var body: some View {
        let c = store.combo, starts = store.comboStarts(c)
        Page {
            Card(padding: 14) {
                NumberedHeading(number: 1, title: "基本設定")
                FieldRow(title: "目前資產（估值快照）", bar: true) { HStack { Spacer(); Text(money(starts.stock + starts.etf)).font(.headline).monospacedDigit() } }.padding(.top, 6)
                FieldRow(title: "每月投資金額", bar: true) { UnitField(placeholder: "10,000", text: $monthly, unit: "元", identifier: "combo-monthly") }
            }
            Card(padding: 14) {
                HStack { NumberedHeading(number: 2, title: "投資配置"); Spacer(); Text("每月投入的個股＋ETF 比例").font(.caption2).foregroundStyle(Palette.muted) }
                HStack(spacing: 10) {
                    allocationBox(title: "個股", tint: Palette.pink, text: Binding(get: { stockPercent }, set: { stockPercent = $0; if let v = Double($0) { etfPercentText = String(Int(100 - min(max(v, 0), 100))) } }))
                    allocationBox(title: "ETF", tint: Palette.blue, text: Binding(get: { etfPercentText }, set: { etfPercentText = $0; if let v = Double($0) { stockPercent = String(Int(100 - min(max(v, 0), 100))) } }))
                }.padding(.top, 10)
            }
            Card(padding: 14) {
                NumberedHeading(number: 3, title: "投資條件")
                FieldRow(title: "每月投入時間", bar: true) { Picker("每月投入時間", selection: $startOfMonth) { Text("月底").tag(false); Text("月初").tag(true) }.pickerStyle(.segmented) }.padding(.top, 6)
                FieldRow(title: "試算年數", bar: true) { Picker("試算年數", selection: $years) { Text("3年").tag(3); Text("5年").tag(5); Text("10年").tag(10) }.pickerStyle(.segmented) }
            }
            Card(padding: 14) {
                HStack { NumberedHeading(number: 4, title: "報酬與其他假設"); Spacer(); Text("預設值，可調整").font(.caption2).foregroundStyle(Palette.muted) }
                FieldRow(title: "個股年總報酬", bar: true) { UnitField(placeholder: "5", text: $stockReturn, unit: "%", identifier: "combo-stock-return") }.padding(.top, 6)
                FieldRow(title: "ETF 年總報酬", bar: true) { UnitField(placeholder: "5", text: $etfReturn, unit: "%", identifier: "combo-etf-return") }
                Toggle(isOn: $reinvest) { Text("股息再投入").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink) }.padding(.vertical, 6)
                if !reinvest {
                    FieldRow(title: "個股現金殖利率", bar: true) { UnitField(placeholder: "2", text: $stockYield, unit: "%") }
                    FieldRow(title: "ETF 現金殖利率", bar: true) { UnitField(placeholder: "4", text: $etfYield, unit: "%") }
                    Text("預設依持有標的近一年現金股利，沒有資料時個股 2%、ETF 4%。股息每月提出為現金，不再複利。").font(.caption2).foregroundStyle(Palette.muted)
                }
                FieldRow(title: "費用與稅務假設", bar: true) { Picker("費用與稅務假設", selection: $buyFee) { Text("本例未計費稅").tag(false); Text("計入買進手續費").tag(true) }.pickerStyle(.menu) }
            }
            Card(padding: 14) {
                HStack { NumberedHeading(number: 5, title: "情境設定"); Spacer(); Text("情境假設，非機率區間").font(.caption2).foregroundStyle(Palette.muted) }
                HStack(spacing: 8) { ForEach([ComboScenario.conservative, .base, .optimistic]) { item in scenarioButton(item, current: draft) } }.padding(.top, 10)
            }
            if let error { Text(error).font(.caption).foregroundStyle(Palette.red) }
            Button { run() } label: { PrimaryButtonLabel(title: "開始試算", icon: "arrow.right") }.buttonStyle(.plain).accessibilityIdentifier("combo-run")
        }
        .navigationTitle("試算設定").navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .navigationDestination(isPresented: $showResult) { ComboResultView(fromSettings: true).tabBarSpace() }
    }
    @State private var etfPercentText = ""
    private var draft: ComboSettings {
        var c = store.combo
        c.stockReturn = Double(stockReturn) ?? c.stockReturn; c.etfReturn = Double(etfReturn) ?? c.etfReturn
        return c
    }
    private func load() {
        guard !loaded else { return }; loaded = true
        let c = store.combo, yields = store.comboDefaultYields(c)
        monthly = String(Int(c.monthly)); let share = Int((store.comboStockShare(c) * 100).rounded())
        stockPercent = String(share); etfPercentText = String(100 - share)
        stockReturn = decimal(c.stockReturn); etfReturn = decimal(c.etfReturn)
        stockYield = decimal(c.stockYield ?? yields.stock); etfYield = decimal(c.etfYield ?? yields.etf)
        startOfMonth = c.startOfMonth; years = c.years; reinvest = c.reinvest; buyFee = c.buyFee; scenario = c.scenario == .stress ? .base : c.scenario
    }
    private func allocationBox(title: String, tint: Color, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill").foregroundStyle(tint)
            Text(title).font(.subheadline.bold()).foregroundStyle(Palette.ink)
            TextField("0", text: text).keyboardType(.numberPad).multilineTextAlignment(.trailing).font(.title3.bold()).monospacedDigit()
            Text("%").font(.subheadline.bold())
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
    }
    private func scenarioButton(_ item: ComboScenario, current: ComboSettings) -> some View {
        let on = scenario == item
        return Button { scenario = item } label: {
            VStack(spacing: 2) { Text(item.rawValue).font(.subheadline.bold()); Text(scenarioLabel(current, item)).font(.caption2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7) }
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .foregroundStyle(on && item == .base ? Color.white : item.color)
                .background(on && item == .base ? AnyShapeStyle(Palette.hero) : AnyShapeStyle(item.color.opacity(0.1)), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(on && item != .base ? item.color : Color.clear, lineWidth: 1.5))
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }
    private func run() {
        error = nil
        func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) }
        guard let m = number(monthly), m >= 0, m <= 1e9 else { error = "每月投資金額請填 0 以上的金額。"; return }
        guard let sp = number(stockPercent), sp >= 0, sp <= 100 else { error = "投資配置請填 0–100%。"; return }
        guard let rs = number(stockReturn), let re = number(etfReturn), abs(rs) < 50, abs(re) < 50 else { error = "年總報酬請填 −50% 到 50% 之間。"; return }
        var next = store.combo
        if !reinvest {
            guard let ys = number(stockYield), let ye = number(etfYield), ys >= 0, ys < 30, ye >= 0, ye < 30 else { error = "現金殖利率請填 0–30%。"; return }
            next.stockYield = ys; next.etfYield = ye
        }
        next.monthly = m; next.stockPercent = sp; next.stockReturn = rs; next.etfReturn = re
        next.startOfMonth = startOfMonth; next.years = years; next.reinvest = reinvest; next.buyFee = buyFee; next.scenario = scenario
        store.saveCombo(next)
        showResult = true
    }
}
struct ComboResultView: View {
    @EnvironmentObject var store: PortfolioStore
    /// Opened from the settings page (調整假設 goes back) rather than straight from the home page.
    var fromSettings = false
    @Environment(\.dismiss) private var dismiss
    @State private var scenario: ComboScenario?
    @State private var part: Int?
    var body: some View {
        let c = store.combo, starts = store.comboStarts(c), share = store.comboStockShare(c)
        let current = scenario ?? c.scenario
        let rows = [3, 5, 10].map { years in (years, ComboMath.project(stockStart: starts.stock, etfStart: starts.etf, settings: c, stockShare: share, years: years, scenario: current)) }
        Page {
            Text(current == .stress ? "壓力測試・第 1 年 −30%，之後 \(scenarioLabel(c, .base))" : "\(current.rawValue)情境・假設年總報酬 \(scenarioLabel(c, current))")
                .font(.headline).foregroundStyle(Palette.deepBlue).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(LinearGradient(colors: [Palette.blue.opacity(0.14), Palette.card], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16))
            Card(padding: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("目前資產").font(.headline).foregroundStyle(Palette.ink)
                        Text("（估值快照）").font(.caption).foregroundStyle(Palette.muted)
                        Text(money(starts.stock + starts.etf)).font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1)
                    }
                    Spacer()
                    Artwork(name: "div-coins", size: 96)
                }
            }
            Card(padding: 10) {
                resultHeader(c)
                ForEach(rows, id: \.0) { years, result in resultRow(years: years, invested: result.invested, end: result.end, selected: years == c.years) }
            }
            HStack(spacing: 10) {
                partButton(0, title: "個股結果", tint: Palette.pink)
                partButton(1, title: "ETF 結果", tint: Palette.blue)
            }
            if let part {
                Card(padding: 10) {
                    resultHeader(c, part: true)
                    ForEach(rows, id: \.0) { years, result in
                        let p = part == 0 ? result.stock : result.etf
                        resultRow(years: years, invested: p.invested, end: p.end, selected: years == c.years)
                    }
                }
            }
            HStack { Text("情境切換").font(.headline).foregroundStyle(Palette.ink); Spacer(); Label("可為負報酬，不保證獲利", systemImage: "info.circle").font(.caption2).foregroundStyle(Palette.muted) }
            HStack(spacing: 8) { ForEach(ComboScenario.allCases) { item in scenarioChip(item, current: current, settings: c) } }
            Card(padding: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.text").font(.title3).foregroundStyle(Palette.blue).frame(width: 40, height: 40).background(Palette.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("試算方法").font(.headline).foregroundStyle(Palette.ink)
                        bullet("逐月複利，\(c.startOfMonth ? "月初" : "月底")投入；每月投入依個股 \(Int((share * 100).rounded()))%／ETF \(100 - Int((share * 100).rounded()))% 分配")
                        bullet(c.reinvest ? "總報酬包含股息，不重複加計" : "股息不再投入：依殖利率每月提出為現金，計入期末資產")
                        bullet(c.buyFee ? "每月投入扣除買進手續費 0.1425%；未計證交稅與股利所得稅" : "本例未計手續費、證交稅與股利所得稅")
                        bullet("保守＝基準 −7 個百分點，樂觀＝基準 +3 個百分點；壓力測試＝第 1 年 −30% 後回到基準")
                    }
                    Spacer(minLength: 0)
                }
                Group {
                    if fromSettings { Button("調整假設") { dismiss() } }
                    else { NavigationLink(value: AppRoute.comboSettings) { Text("調整假設") }.buttonStyle(.plain).foregroundStyle(Palette.blue) }
                }.font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 10).overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.blue, lineWidth: 1.2)).padding(.top, 10)
            }
            Text("這是依你設定的假設計算的情境，不是預測或保證；個股風險集中在單一公司，實際報酬可能為負。").font(.caption).foregroundStyle(Palette.muted)
        }
        .navigationTitle("試算結果").navigationBarTitleDisplayMode(.inline)
    }
    private func resultHeader(_ c: ComboSettings, part: Bool = false) -> some View {
        HStack {
            Text("試算期間").frame(maxWidth: .infinity)
            VStack(spacing: 1) { Text("新增投入金額"); Text(part ? "依配置比例" : "（每月 \(money(c.monthly))）").font(.caption2).foregroundStyle(Palette.muted) }.frame(maxWidth: .infinity)
            VStack(spacing: 1) { Text("期末資產"); Text("（含原資產與新增投入）").font(.caption2).foregroundStyle(Palette.muted) }.frame(maxWidth: .infinity)
        }
        .font(.caption.bold()).foregroundStyle(Palette.ink).padding(.vertical, 8)
        .background(Palette.cardSoft, in: RoundedRectangle(cornerRadius: 12))
    }
    private func resultRow(years: Int, invested: Double, end: Double, selected: Bool) -> some View {
        HStack {
            Text("\(years) 年").frame(maxWidth: .infinity)
            Text(money(invested)).frame(maxWidth: .infinity)
            Text(money(end)).frame(maxWidth: .infinity)
        }
        .font(selected ? Font.headline : Font.subheadline.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        .foregroundStyle(selected ? Color.white : Palette.ink)
        .padding(.vertical, 11)
        .background(selected ? AnyShapeStyle(Palette.hero) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
    private func partButton(_ index: Int, title: String, tint: Color) -> some View {
        Button { part = part == index ? nil : index } label: {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill").foregroundStyle(tint).frame(width: 34, height: 34).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.bold()).foregroundStyle(Palette.ink); Text("按各組假設分別計算").font(.caption2).foregroundStyle(Palette.muted) }
                Spacer(minLength: 0)
                Image(systemName: part == index ? "chevron.down" : "chevron.right").font(.caption).foregroundStyle(Palette.muted)
            }
            .padding(12).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(part == index ? Palette.blue : Color.clear, lineWidth: 1.5))
        }.buttonStyle(.plain)
    }
    private func scenarioChip(_ item: ComboScenario, current: ComboScenario, settings: ComboSettings) -> some View {
        let on = item == current
        return Button { scenario = item } label: {
            VStack(spacing: 2) {
                Text(item.rawValue).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
                if item != .stress { Text(scenarioLabel(settings, item)).font(.caption2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6) }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .foregroundStyle(on && item == .base ? Color.white : item.color)
            .background(on && item == .base ? AnyShapeStyle(Palette.hero) : AnyShapeStyle(item.color.opacity(0.1)), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(on && item != .base ? item.color : Color.clear, lineWidth: 1.5))
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•"); Text(text).fixedSize(horizontal: false, vertical: true) }.font(.caption).foregroundStyle(Palette.ink)
    }
}
