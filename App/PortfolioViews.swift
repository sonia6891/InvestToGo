import SwiftUI

struct HoldingsView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var add = false
    @State private var editing: Holding?
    var brokers: [String] { Array(Set(store.data.holdings.map(\.broker))).sorted() }
    var body: some View {
        Page {
            HStack(alignment: .firstTextBaseline) { Text("\(store.data.holdings.count) 筆持有").foregroundStyle(.secondary); Spacer(); Text("投入 $\(money(store.data.cost))").font(.subheadline.bold()).foregroundStyle(Palette.ink) }
            Button { add = true } label: { Label("新增一筆持有", systemImage: "plus.circle.fill").frame(maxWidth: .infinity).padding(.vertical, 13) }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 16)).accessibilityIdentifier("add-holding")
            if brokers.isEmpty { Card { ContentUnavailableView("把你的 ETF 和個股放進口袋", systemImage: "wallet.bifold", description: Text("選擇 ETF 或輸入個股代碼，填入股數與成本，之後就能持續追蹤。")) } }
            else { NavigationLink { ScenarioView() } label: { Label("用目前持有試算三種情境", systemImage: "chart.line.uptrend.xyaxis").frame(maxWidth: .infinity).padding(.vertical, 11) }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 16)).accessibilityIdentifier("holding-scenarios") }
            ForEach(brokers, id: \.self) { broker in
                let items = store.data.holdings.filter { $0.broker == broker }
                HStack { Label(broker, systemImage: "building.columns").font(.headline); Spacer(); Text("\(items.count) 筆").font(.caption).foregroundStyle(.secondary) }
                VStack(spacing: 12) { ForEach(items) { holding in
                    Button { editing = holding } label: {
                        Card {
                            HStack { Text(holding.name).font(.headline); Spacer(); Image(systemName: "ellipsis").foregroundStyle(.secondary) }
                            HStack { Text(holding.symbol).font(.caption).foregroundStyle(.secondary); Text(store.isETF(holding.symbol) ? "ETF" : "個股").font(.caption2.weight(.medium)).padding(.horizontal, 7).padding(.vertical, 3).foregroundStyle(Palette.ink.opacity(0.7)).background(Palette.ink.opacity(0.06), in: Capsule()); Spacer(); StrategyPill(strategy: holding.strategy) }.padding(.bottom, 8)
                            HStack(alignment: .top) {
                                metric("持有股數", decimal(holding.shares)); Spacer(); metric("每股成本", decimal(holding.unitCost)); Spacer(); metric("目前市值", store.data.quotes[holding.symbol].flatMap { $0.isTWD ? money($0.price * holding.shares) : nil } ?? "尚無報價")
                            }
                            if let quote = store.data.quotes[holding.symbol], quote.isTWD {
                                let profit = quote.price * holding.shares - holding.cost
                                Divider().padding(.vertical, 9)
                                HStack { Text("未實現損益").font(.caption).foregroundStyle(.secondary); Spacer(); Text("\(profit >= 0 ? "+" : "")\(money(profit))").font(.subheadline.bold()).foregroundStyle(profit >= 0 ? Palette.red : Palette.green) }
                            }
                        }
                    }.buttonStyle(.plain)
                } }
            }
            Text("股數以「股」為單位，成本統一填台幣（可包含實際手續費）。未確認幣別或外幣報價不直接加總為台幣市值。").font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("我的持有").sheet(isPresented: $add) { HoldingEditor() }.sheet(item: $editing) { HoldingEditor(existing: $0) }
    }
    private func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.bold()).foregroundStyle(Palette.ink) } }
}
struct HoldingEditor: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.dismiss) var dismiss
    var existing: Holding?
    var fund: Fund?
    @State private var symbol = ""
    @State private var selectedFund = ""
    @State private var name = ""
    @State private var shares = ""
    @State private var cost = ""
    @State private var broker = ""
    @State private var strategy = Strategy.unclassified
    @State private var error: String?
    @State private var deletePrompt = false
    // Broker inventory pages show a total cost that already reflects each account's fee discount.
    @AppStorage("holding-cost-is-total") private var totalCost = true
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("1  選擇 ETF 或輸入個股").font(.headline).foregroundStyle(Palette.blue)
                    if existing == nil { Picker("快速選擇 ETF", selection: $selectedFund) { Text("手動輸入").tag(""); ForEach(store.funds) { Text("\($0.id) \($0.name)").tag($0.id) } }.onChange(of: selectedFund) { _, value in if let item = store.funds.first(where: { $0.id == value }) { symbol = item.id; name = item.name; strategy = item.strategy } } }
                    TextField("代碼（ETF 或個股）", text: $symbol).textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("holding-symbol")
                    TextField("名稱", text: $name).accessibilityIdentifier("holding-name")
                } footer: { Text("個股請直接輸入代碼與名稱，例如 2330 台積電。") }
                Section { Text("2  填入持有資料").font(.headline).foregroundStyle(Palette.blue)
                    TextField("持有股數（股）", text: $shares).keyboardType(.decimalPad).accessibilityIdentifier("holding-shares")
                    Picker("成本填法", selection: $totalCost) { Text("券商顯示的總成本").tag(true); Text("每股成本").tag(false) }.pickerStyle(.segmented)
                        .onChange(of: totalCost) { _, total in if let s = number(shares), s > 0, let c = number(cost) { cost = plain(total ? s * c : c / s) } }
                    TextField(totalCost ? "總成本（照券商庫存頁，元）" : "每股買入成本（元）", text: $cost).keyboardType(.decimalPad).accessibilityIdentifier("holding-cost")
                    TextField("券商名稱", text: $broker).accessibilityIdentifier("holding-broker")
                    Picker("策略分類", selection: $strategy) { ForEach(Strategy.allCases) { Text($0.rawValue).tag($0) } }
                } footer: { Text("輸入 1,000 股代表 1 張。總成本請直接照抄券商 App「庫存」頁的持有成本，已含你帳戶實際的手續費折扣，不必自己計算。策略可以日後調整。") }
                if let s = number(shares), let c = number(cost), s > 0, c > 0 { Section { if totalCost { LabeledContent("換算每股成本", value: (c / s).formatted(.number.precision(.fractionLength(0...4)))) } else { LabeledContent("這筆投入成本", value: "$\(money(s * c))") } } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if existing != nil { Section { Button("刪除這筆持有", role: .destructive) { deletePrompt = true } } }
            }.navigationTitle(existing == nil ? "新增持有" : "編輯持有").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("儲存") { save() }.fontWeight(.bold).accessibilityIdentifier("save-holding") } }
                .onAppear { if let h = existing { symbol = h.symbol; name = h.name; shares = plain(h.shares); cost = plain(totalCost ? h.cost : h.unitCost); broker = h.broker; strategy = h.strategy } else if let fund { symbol = fund.id; selectedFund = fund.id; name = fund.name; strategy = fund.strategy } }
                .confirmationDialog("刪除這筆持有？配息紀錄會保留。", isPresented: $deletePrompt, titleVisibility: .visible) { Button("確認刪除", role: .destructive) { do { if let existing { try store.remove(existing) }; dismiss() } catch { self.error = error.localizedDescription } } }
        }
    }
    func save() {
        guard DataChecks.code(symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) else { error = "代碼須為 4～6 位數字，可加一個英文字母，例如 2330、00631L。"; return }
        let s = number(shares) ?? 0, c = number(cost) ?? 0
        let h = Holding(id: existing?.id ?? UUID(), symbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), shares: s, unitCost: totalCost ? (s > 0 ? c / s : 0) : c, broker: broker.trimmingCharacters(in: .whitespacesAndNewlines), strategy: strategy, sourceAccount: existing?.sourceAccount)
        do { try store.save(h); dismiss() } catch { self.error = error.localizedDescription }
    }
    private func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) }
    private func plain(_ value: Double) -> String { value.formatted(.number.grouping(.never).precision(.fractionLength(0...6)).locale(Locale(identifier: "en_US_POSIX"))) }
}
struct DividendsView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    @State private var add = false
    @State private var deleting: Dividend?
    var entries: [Dividend] { store.data.dividends.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }.sorted { $0.date < $1.date } }
    var body: some View {
        Page {
            HStack { Button { change(-1) } label: { Image(systemName: "chevron.left").padding(12) }.accessibilityLabel("上一個月"); Spacer(); Text(month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_Hant_TW")))).font(.title3.bold()); Spacer(); Button { change(1) } label: { Image(systemName: "chevron.right").padding(12) }.accessibilityLabel("下一個月") }.background(.white, in: RoundedRectangle(cornerRadius: 16))
            Card {
                Label("本月已入帳", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Palette.green)
                Text("$\(money(entries.filter { $0.status == .paid }.reduce(0) { $0 + $1.amount }))").font(.system(size: 38, weight: .bold, design: .rounded)).padding(.vertical, 8)
                Divider().padding(.bottom, 12)
                HStack { VStack(alignment: .leading, spacing: 6) { Text("已公告").font(.caption).foregroundStyle(.secondary); Text("$\(money(entries.filter { $0.status == .announced }.reduce(0) { $0 + $1.amount }))").font(.headline) }; Spacer(); VStack(alignment: .trailing, spacing: 6) { Text("預估・尚未確認").font(.caption).foregroundStyle(.secondary); Text("$\(money(entries.filter { $0.status == .estimated }.reduce(0) { $0 + $1.amount }))").font(.headline) } }
            }
            Button { add = true } label: { Label("記錄一筆配息", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 12) }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 15))
            SectionHeading(title: "配息時間軸", subtitle: "已入帳、已公告與預估分開記錄")
            if entries.isEmpty { Card { ContentUnavailableView("這個月還沒有紀錄", systemImage: "calendar.badge.plus", description: Text("記下每筆股息，慢慢看見累積。")) } }
            ForEach(entries) { item in
                Card {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 3) { Text(String(Calendar.current.component(.day, from: item.date))).font(.title2.bold()).lineLimit(1); Text(item.date.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "zh_Hant_TW")))).font(.caption2) }.foregroundStyle(Palette.blue).frame(width: 48).padding(.vertical, 10).background(Palette.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 8) { Text(store.funds.first(where: { $0.id == item.symbol })?.name ?? store.data.holdings.first(where: { $0.symbol == item.symbol })?.name ?? item.symbol).font(.headline); Text("\(item.symbol) · \(item.status.rawValue)").font(.caption).foregroundStyle(.secondary); Text("$\(money(item.amount))").font(.title3.bold()).foregroundStyle(item.status == .paid ? Palette.green : Palette.ink) }
                        Spacer(); Image(systemName: item.status == .paid ? "checkmark.circle.fill" : "clock").foregroundStyle(item.status == .paid ? Palette.green : Palette.blue)
                    }
                }.contextMenu { Button("刪除紀錄", role: .destructive) { deleting = item } }
            }
            Text("此頁為你的配息紀錄，非交易所自動公告。長按紀錄可刪除。").font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("配息").sheet(isPresented: $add) { DividendEditor() }.confirmationDialog("刪除這筆配息紀錄？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) { Button("確認刪除", role: .destructive) { do { if let deleting { try store.removeDividend(deleting) } } catch { store.message = error.localizedDescription }; deleting = nil } }
    }
    func change(_ amount: Int) { month = Calendar.current.date(byAdding: .month, value: amount, to: month)! }
}
struct DividendEditor: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.dismiss) var dismiss
    @State private var symbol = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var status = DividendStatus.paid
    @State private var error: String?
    var body: some View { NavigationStack { Form {
        Section("配息資料") { TextField("代碼（ETF 或個股）", text: $symbol).textInputAutocapitalization(.characters); TextField("總金額（元）", text: $amount).keyboardType(.decimalPad); DatePicker("入帳／預計日期", selection: $date, displayedComponents: .date); Picker("狀態", selection: $status) { ForEach(DividendStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) } } }
        Section { Text("請輸入這次收到的總金額，不是每股配息。公告與預估不會計入已入帳股息。").font(.footnote).foregroundStyle(.secondary) }
        if let error { Text(error).foregroundStyle(.red) }
    }.navigationTitle("記錄配息").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("儲存") { guard !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let value = Double(amount), value.isFinite, value > 0 else { error = "請輸入代碼與大於 0 的配息總額。"; return }; do { try store.record(Dividend(symbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), date: date, amount: value, status: status)); dismiss() } catch { self.error = error.localizedDescription } } } } } }
}
