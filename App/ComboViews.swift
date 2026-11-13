import SwiftUI


extension ComboScenario {
    var color: Color {
        switch self { case .conservative: return Palette.pink; case .base: return Palette.blue; case .optimistic: return Palette.green; case .stress: return Palette.deepBlue }
    }
}
extension PortfolioStore {
    var combo: ComboSettings { data.combo ?? ComboSettings() }
    func saveCombo(_ value: ComboSettings) {
        var next = data; next.combo = value
        do { try commit(next) } catch { message = error.localizedDescription }
    }
    /// ETF lines only: records of other codes kept from older versions are left out.
    func comboLines(_ c: ComboSettings) -> [ComboLine] {
        if c.source == 1 { return c.simulated.filter { isETF($0.symbol) }.map { ComboLine(symbol: $0.symbol, amount: $0.amount, isStock: false) } }
        var totals: [String: Double] = [:]
        for holding in data.holdings where isETF(holding.symbol) { totals[holding.symbol, default: 0] += marketValue(of: holding) ?? holding.cost }
        return totals.filter { !c.excluded.contains($0.key) }.map { ComboLine(symbol: $0.key, amount: $0.value, isStock: false) }.sorted { $0.amount > $1.amount }
    }
    /// Starting amount of the ETFs in the mix.
    func comboStart(_ c: ComboSettings) -> Double { comboLines(c).reduce(0) { $0 + $1.amount } }
    /// The holdings' last-year distributions as a yield once the records cover that year, else 4%.
    func comboDefaultYield(_ c: ComboSettings) -> Double {
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
        let etf = weighted(lines) { official.trailingAmount($0) ?? 0 }
        return ((etf ?? 4) * 100).rounded() / 100
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
    return "\(decimal(scenario.rate(c.etfReturn)))%"
}
private let etfColors: [Color] = [Palette.blue, Color(red: 0.37, green: 0.64, blue: 1), Palette.teal, Palette.purple, Color(red: 0.22, green: 0.76, blue: 0.45)]

struct ComboView: View {
    @EnvironmentObject var store: PortfolioStore
    /// An ETF to put into the simulated mix when the screen opens (from a detail page's 加入試算).
    var addSymbol: String? = nil
    @State private var added = false
    @AppStorage("hideAmounts") private var hidden = false
    @State private var editing: ComboItem?
    @State private var adding = false
    var body: some View {
        let c = store.combo, etfs = store.comboLines(c)
        let start = store.comboStart(c)
        Page {
            SegmentBar(items: ["我的持有", "模擬組合"], selection: Binding(get: { c.source }, set: { value in var next = c; next.source = value; store.saveCombo(next) }), pill: true, filled: true)
            heroCard(c)
            if c.source == 0 && store.data.holdings.isEmpty {
                Card { ContentUnavailableView("還沒有持有", systemImage: "bag", description: Text("先新增持有，或切換到「模擬組合」自己加入 ETF。")) }
            }
            group(title: "ETF", icon: "chart.bar.fill", tint: Palette.blue, lines: etfs, total: start, colors: etfColors)
            HStack {
                Text("試算總資產").font(.headline)
                Spacer()
                Text(shown(money(start), hidden: hidden)).font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
            }
            .foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 14)
            .background(Palette.hero, in: RoundedRectangle(cornerRadius: 20))
            Label("試算不修改實際持有，只用於模擬計算", systemImage: "info.circle").font(.caption.bold()).foregroundStyle(Palette.pink)
                .frame(maxWidth: .infinity).padding(10).background(Palette.pink.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            NavigationLink(value: AppRoute.comboSettings) { PrimaryButtonLabel(title: "設定試算", icon: "arrow.right") }.buttonStyle(.plain).accessibilityIdentifier("combo-settings")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { VStack(spacing: 0) { Text("組合試算").font(.headline).foregroundStyle(Palette.ink); Text("ETF 組合一起試算").font(.caption2).foregroundStyle(Palette.muted) } } }
        .onAppear { if let addSymbol, !added { added = true; add(addSymbol) } }
        .sheet(item: $editing) { item in ComboItemSheet(existing: item).silencesScrollTop() }
        .sheet(isPresented: $adding) { ComboItemSheet(existing: nil).silencesScrollTop() }
    }
    private func heroCard(_ c: ComboSettings) -> some View {
        let at = c.snapshotAt ?? Date()
        return Card(padding: 16) {
            HStack(spacing: 12) {
                Artwork(name: "tool-compound", size: 92)
                VStack(alignment: .leading, spacing: 6) {
                    Text("ETF 組合一起試算").font(.headline).foregroundStyle(Palette.ink)
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
    private func group(title: String, icon: String, tint: Color, lines: [ComboLine], total: Double, colors: [Color]) -> some View {
        let c = store.combo
        return Card(padding: 12) {
            HStack(spacing: 10) {
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
                adding = true
            } label: {
                Label("新增 ETF", systemImage: "plus").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 10).background(Palette.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
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
    @State private var symbol = ""
    @State private var amount = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if let existing {
                    Text("\(existing.symbol) \(store.name(for: existing.symbol))").font(.headline)
                } else {
                    TextField("ETF 代號，例如 0050", text: $symbol).textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("combo-symbol")
                    let code = symbol.trimmingCharacters(in: .whitespaces).uppercased()
                    if !code.isEmpty { Text(store.name(for: code) == code ? "清單沒有這個代號" : store.name(for: code)).font(.caption).foregroundStyle(Palette.muted) }
                }
                HStack { TextField("試算金額", text: $amount).keyboardType(.decimalPad).accessibilityIdentifier("combo-amount"); Text("元").foregroundStyle(Palette.muted) }
                if let error { Text(error).font(.caption).foregroundStyle(Palette.red) }
                if let existing { Button("從模擬組合移除", role: .destructive) { var next = store.combo; next.simulated.removeAll { $0.symbol == existing.symbol }; store.saveCombo(next); dismiss() } }
            }
            .navigationTitle(existing != nil ? "調整試算金額" : "新增 ETF").navigationBarTitleDisplayMode(.inline)
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
            guard store.isETF(code) else { error = "這不是 ETF，試算只收 ETF。"; return }
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
    @State private var etfReturn = ""
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
        let c = store.combo, start = store.comboStart(c)
        Page {
            Card(padding: 14) {
                NumberedHeading(number: 1, title: "基本設定")
                FieldRow(title: "目前資產（估值快照）", bar: true) { HStack { Spacer(); Text(money(start)).font(.headline).monospacedDigit() } }.padding(.top, 6)
                FieldRow(title: "每月投資金額", bar: true) { UnitField(placeholder: "10,000", text: $monthly, unit: "元", identifier: "combo-monthly") }
            }
            Card(padding: 14) {
                NumberedHeading(number: 2, title: "投資條件")
                FieldRow(title: "每月投入時間", bar: true) { Picker("每月投入時間", selection: $startOfMonth) { Text("月底").tag(false); Text("月初").tag(true) }.pickerStyle(.segmented) }.padding(.top, 6)
                FieldRow(title: "試算年數", bar: true) { Picker("試算年數", selection: $years) { Text("3年").tag(3); Text("5年").tag(5); Text("10年").tag(10) }.pickerStyle(.segmented) }
            }
            Card(padding: 14) {
                HStack { NumberedHeading(number: 3, title: "報酬與其他假設"); Spacer(); Text("預設值，可調整").font(.caption2).foregroundStyle(Palette.muted) }
                FieldRow(title: "ETF 年總報酬", bar: true) { UnitField(placeholder: "5", text: $etfReturn, unit: "%", identifier: "combo-etf-return") }.padding(.top, 6)
                Toggle(isOn: $reinvest) { Text("股息再投入").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink) }.padding(.vertical, 6)
                if !reinvest {
                    FieldRow(title: "ETF 現金殖利率", bar: true) { UnitField(placeholder: "4", text: $etfYield, unit: "%") }
                    Text("預設依持有 ETF 近一年配息，沒有資料時 4%。股息每月提出為現金，不再複利。").font(.caption2).foregroundStyle(Palette.muted)
                }
                FieldRow(title: "費用與稅務假設", bar: true) { Picker("費用與稅務假設", selection: $buyFee) { Text("本例未計費稅").tag(false); Text("計入買進手續費").tag(true) }.pickerStyle(.menu) }
            }
            Card(padding: 14) {
                HStack { NumberedHeading(number: 4, title: "情境設定"); Spacer(); Text("情境假設，非機率區間").font(.caption2).foregroundStyle(Palette.muted) }
                HStack(spacing: 8) { ForEach([ComboScenario.conservative, .base, .optimistic]) { item in scenarioButton(item, current: draft) } }.padding(.top, 10)
            }
            if let error { Text(error).font(.caption).foregroundStyle(Palette.red) }
            Button { run() } label: { PrimaryButtonLabel(title: "開始試算", icon: "arrow.right") }.buttonStyle(.plain).accessibilityIdentifier("combo-run")
        }
        .navigationTitle("試算設定").navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .navigationDestination(isPresented: $showResult) { ComboResultView(fromSettings: true).gameBarSpace().silencesScrollTop() }
    }
    private var draft: ComboSettings {
        var c = store.combo
        c.etfReturn = Double(etfReturn) ?? c.etfReturn
        return c
    }
    private func load() {
        guard !loaded else { return }; loaded = true
        let c = store.combo
        monthly = String(Int(c.monthly))
        etfReturn = decimal(c.etfReturn)
        etfYield = decimal(c.etfYield ?? store.comboDefaultYield(c))
        startOfMonth = c.startOfMonth; years = c.years; reinvest = c.reinvest; buyFee = c.buyFee; scenario = c.scenario == .stress ? .base : c.scenario
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
        guard let re = number(etfReturn), abs(re) < 50 else { error = "年總報酬請填 −50% 到 50% 之間。"; return }
        var next = store.combo
        if !reinvest {
            guard let ye = number(etfYield), ye >= 0, ye < 30 else { error = "現金殖利率請填 0–30%。"; return }
            next.etfYield = ye
        }
        next.monthly = m; next.stockPercent = 0; next.etfReturn = re
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
    var body: some View {
        let c = store.combo, start = store.comboStart(c)
        let current = scenario ?? c.scenario
        let rows = [3, 5, 10].map { years in (years, ComboMath.project(stockStart: 0, etfStart: start, settings: c, stockShare: 0, years: years, scenario: current)) }
        Page {
            Text(current == .stress ? "壓力測試・第 1 年 −30%，之後 \(scenarioLabel(c, .base))" : "\(current.rawValue)情境・假設年總報酬 \(scenarioLabel(c, current))")
                .font(.headline).foregroundStyle(Palette.deepBlue).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(LinearGradient(colors: [Palette.blue.opacity(0.14), Palette.card], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16))
            Card(padding: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("目前資產").font(.headline).foregroundStyle(Palette.ink)
                        Text("（估值快照）").font(.caption).foregroundStyle(Palette.muted)
                        Text(money(start)).font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1)
                    }
                    Spacer()
                    Artwork(name: "div-coins", size: 96)
                }
            }
            Card(padding: 10) {
                resultHeader(c)
                ForEach(rows, id: \.0) { years, result in resultRow(years: years, invested: result.invested, end: result.end, selected: years == c.years) }
            }
            HStack { Text("情境切換").font(.headline).foregroundStyle(Palette.ink); Spacer(); Label("可為負報酬，不保證獲利", systemImage: "info.circle").font(.caption2).foregroundStyle(Palette.muted) }
            HStack(spacing: 8) { ForEach(ComboScenario.allCases) { item in scenarioChip(item, current: current, settings: c) } }
            Card(padding: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.text").font(.title3).foregroundStyle(Palette.blue).frame(width: 40, height: 40).background(Palette.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("試算方法").font(.headline).foregroundStyle(Palette.ink)
                        bullet("逐月複利，\(c.startOfMonth ? "月初" : "月底")投入，全數投入 ETF")
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
            Text("這是依你設定的假設計算的情境，不是預測或保證；實際報酬可能為負。").font(.caption).foregroundStyle(Palette.muted)
        }
        .navigationTitle("試算結果").navigationBarTitleDisplayMode(.inline)
    }
    private func resultHeader(_ c: ComboSettings) -> some View {
        HStack {
            Text("試算期間").frame(maxWidth: .infinity)
            VStack(spacing: 1) { Text("新增投入金額"); Text("（每月 \(money(c.monthly))）").font(.caption2).foregroundStyle(Palette.muted) }.frame(maxWidth: .infinity)
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
