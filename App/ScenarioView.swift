import SwiftUI

struct ScenarioRate: Identifiable {
    let name: String
    let rate: Double
    var id: String { name }
}
struct ScenarioPlan: Codable, Equatable {
    var conservative = 0.03
    var balanced = 0.05
    var aggressive = 0.07
    var monthly = 0.0
    static let range = -0.1...0.2
    var rates: [ScenarioRate] { [.init(name: "保守", rate: conservative), .init(name: "平衡", rate: balanced), .init(name: "積極", rate: aggressive)] }
    func validate() throws {
        guard [conservative, balanced, aggressive].allSatisfy({ $0.isFinite && Self.range.contains($0) }), monthly.isFinite, (0...1e9).contains(monthly) else { throw AppDataError("年報酬率須介於 -10% 與 20%，每月加碼不可為負數。") }
        guard conservative <= balanced, balanced <= aggressive else { throw AppDataError("請讓保守 ≤ 平衡 ≤ 積極，情境名稱才有意義。") }
    }
}
struct ScenarioPosition: Identifiable {
    var symbol: String
    var name: String
    var value: Double
    var quoted: Bool
    var id: String { symbol }
}
enum ScenarioMath {
    static let horizons = [3, 5, 10, 20, 30, 50]
    /// `annual` is an effective yearly return; contributions are added at each month end.
    static func value(start: Double, monthly: Double, annual: Double, years: Int) -> Double {
        let rate = exp(log1p(annual) / 12) - 1
        var total = start
        for _ in 0..<(max(years, 0) * 12) { total = total * (1 + rate) + monthly }
        return total
    }
    /// One row per code across brokers; TWD quotes give market value, otherwise the cost is used and marked.
    static func positions(_ portfolio: Portfolio) -> [ScenarioPosition] {
        var result: [String: ScenarioPosition] = [:]
        for h in portfolio.holdings {
            let quote = portfolio.quotes[h.symbol].flatMap { $0.isTWD ? $0 : nil }
            var row = result[h.symbol] ?? ScenarioPosition(symbol: h.symbol, name: h.name, value: 0, quoted: quote != nil)
            row.value += quote.map { $0.price * h.shares } ?? h.cost; result[h.symbol] = row
        }
        return result.values.sorted { $0.value == $1.value ? $0.symbol < $1.symbol : $0.value > $1.value }
    }
    /// Value-weighted adjusted-price annualized return over the positions that have at least a year of history.
    static func historical(_ portfolio: Portfolio, positions: [ScenarioPosition]) -> (rate: Double, coverage: Double)? {
        let total = positions.reduce(0) { $0 + $1.value }
        var covered = 0.0, weighted = 0.0
        for p in positions {
            guard let history = portfolio.histories?[p.symbol], let annual = (try? PerformanceStats(history))?.annualized else { continue }
            covered += p.value; weighted += p.value * annual
        }
        guard total > 0, covered > 0 else { return nil }
        return (weighted / covered, covered / total)
    }
}
struct ScenarioView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var plan = ScenarioPlan()
    @State private var message: String?
    private var positions: [ScenarioPosition] { ScenarioMath.positions(store.data) }
    private var start: Double { positions.reduce(0) { $0 + $1.value } }
    private var planError: String? { do { try plan.validate(); return nil } catch { return error.localizedDescription } }
    var body: some View { Form {
        Section("起點：目前持有") {
            LabeledContent("試算起始金額", value: "$\(money(start))")
            let costOnly = positions.filter { !$0.quoted }.count
            if positions.isEmpty { Text("尚無持有，請先在「我的持有」新增 ETF 或個股。").foregroundStyle(.secondary) }
            else { Text(costOnly == 0 ? "全部以已取得的台幣報價市值計算。" : "\(costOnly) 檔尚無台幣報價，暫以投入成本計算；到首頁更新行情後會改用市值。").font(.caption).foregroundStyle(.secondary) }
        }
        Section("三種情境的年報酬率") {
            percent("保守", value: $plan.conservative)
            percent("平衡", value: $plan.balanced)
            percent("積極", value: $plan.aggressive)
            HStack { Text("每月底加碼（元）"); TextField("每月底加碼", value: $plan.monthly, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            Button { plan = ScenarioPlan(monthly: plan.monthly) } label: { Text(verbatim: "恢復預設 3%／5%／7%") }
            if let planError { Text(planError).foregroundStyle(.red) }
        }
        Section("試算結果") {
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 12) {
                // Style each cell: a modified GridRow would no longer lay out as a row.
                GridRow { heading("期間").gridColumnAlignment(.leading); ForEach(plan.rates) { heading("\($0.name) \(decimal($0.rate * 100))%") } }
                Divider()
                ForEach(ScenarioMath.horizons, id: \.self) { years in
                    GridRow {
                        VStack(alignment: .leading, spacing: 3) { Text("\(years) 年").font(.subheadline.bold()); if plan.monthly > 0 { Text("投入 \(wan(start + plan.monthly * 12 * Double(years)))").font(.caption2).foregroundStyle(.secondary) } }
                        ForEach(plan.rates) { item in Text(wan(ScenarioMath.value(start: start, monthly: plan.monthly, annual: item.rate, years: years))).font(.subheadline).monospacedDigit().foregroundStyle(item.name == "平衡" ? Palette.blue : Palette.ink) }
                    }
                }
            }.padding(.vertical, 6)
        }
        Section {
            ForEach(positions) { p in
                NavigationLink { HistoryView(symbol: p.symbol) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) { Text("\(p.symbol) \(p.name)").font(.subheadline); Text("\(store.isETF(p.symbol) ? "ETF" : "個股") · 佔 \(decimal(p.value / max(start, 1) * 100))%\(historyPeriod(p.symbol))").font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Text(historyRate(p.symbol)).font(.subheadline.bold()).foregroundStyle(Palette.ink)
                    }
                }
            }
            if let weighted = ScenarioMath.historical(store.data, positions: positions) {
                LabeledContent("持有加權歷史年化", value: "\(decimal(weighted.rate * 100))%")
                if weighted.coverage < 0.999 { Text("只涵蓋 \(decimal(weighted.coverage * 100))% 的部位；其餘尚無一年以上的歷史資料。").font(.caption).foregroundStyle(.secondary) }
            }
        } header: { Text("各檔歷史年化（參考）") } footer: { Text("點選一檔可用富果還原價格取得歷史績效。各檔期間不同，不能直接比較，也不代表未來；單一個股的過去高報酬不宜直接拿來推算數十年。") }
        Section { Button("儲存情境設定") { do { try plan.validate(); var next = store.data; next.scenarioPlan = plan; try store.commit(next); message = "已儲存。" } catch { message = error.localizedDescription } }; if let message { Text(message) } }
        Section { Text("情境報酬率是你設定的假設，不是預測或保證。年報酬率換算為月複利，每月底加碼；未計通膨、稅費、交易成本與配息扣費。時間越長，三種情境的差距越大，建議每年對照實際報酬調整。").font(.footnote).foregroundStyle(.secondary) }
    }.navigationTitle("三種情境試算").navigationBarTitleDisplayMode(.inline)
        .onAppear { if let saved = store.data.scenarioPlan { plan = saved } }
    }
    private func percent(_ title: String, value: Binding<Double>) -> some View { VStack(alignment: .leading) { Text("\(title) \(decimal(value.wrappedValue * 100))%"); Slider(value: value, in: ScenarioPlan.range, step: 0.005) } }
    private func wan(_ value: Double) -> String { value >= 1e8 ? "\(decimal(value / 1e8)) 億" : "\((value / 1e4).formatted(.number.precision(.fractionLength(value < 1e6 ? 1 : 0)))) 萬" }
    private func heading(_ text: String) -> some View { Text(text).font(.caption.bold()).foregroundStyle(.secondary) }
    private func stats(_ symbol: String) -> (history: PriceHistory, stats: PerformanceStats)? {
        guard let history = store.data.histories?[symbol], let stats = try? PerformanceStats(history) else { return nil }
        return (history, stats)
    }
    private func historyRate(_ symbol: String) -> String { stats(symbol)?.stats.annualized.map { "\(decimal($0 * 100))%" } ?? "尚無" }
    private func historyPeriod(_ symbol: String) -> String { stats(symbol).map { " · \($0.history.points[0].date.prefix(4))～\($0.history.points[$0.history.points.count - 1].date.prefix(4))" } ?? "" }
}
