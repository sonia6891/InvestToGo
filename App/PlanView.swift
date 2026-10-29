import SwiftUI
import Charts

struct PlanYear: Identifiable {
    let year: Int
    let invested: Double
    let cash: Double
    let contributed: Double
    var dividends: Double = 0
    var id: Int { year }
    var total: Double { invested + cash }
}
enum PlanMath {
    static func project(_ plan: LegacyPlan) throws -> [PlanYear] {
        try plan.validate()
        let monthlyRate = exp(log1p(plan.totalReturn) / 12) - 1
        var invested = plan.principal, cash = 0.0, contributed = plan.principal, dividends = 0.0
        var rows = [PlanYear(year: 0, invested: invested, cash: cash, contributed: contributed)]
        for month in 1...(plan.years * 12) {
            invested *= 1 + monthlyRate
            if month % (12 / plan.frequency) == 0 {
                let gross = invested * plan.distributionRate / Double(plan.frequency)
                let net = gross * (1 - plan.deductionRate)
                dividends += net
                invested -= gross
                invested += net * plan.reinvest
                cash += net * (1 - plan.reinvest)
            }
            invested += plan.monthly; contributed += plan.monthly
            if month % 12 == 0 { rows.append(PlanYear(year: month / 12, invested: invested, cash: cash, contributed: contributed, dividends: dividends)) }
        }
        return rows
    }
}
/// 股息複利試算: the design's form on top of the legacy plan model (monthly compounding, distributions paid out of the position).
struct PlanView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var plan = LegacyPlan(principal: 300000, monthly: 10000, years: 20, totalReturn: 0.06, distributionRate: 0.04, frequency: 4, reinvest: 1, deductionRate: 0)
    @State private var principal = "300000"
    @State private var monthly = "10000"
    @State private var years = "20"
    @State private var returnPercent = "6"
    @State private var yieldPercent = "4"
    @State private var deductionPercent = "0"
    @State private var reinvest = true
    @State private var message: String?
    @State private var loaded = false
    var body: some View {
        Page {
            Card {
                FieldRow(title: "初始投入金額", bar: true) { UnitField(placeholder: "金額", text: $principal, unit: "元") }
                FieldRow(title: "每月定期投入", bar: true) { UnitField(placeholder: "金額", text: $monthly, unit: "元") }
                FieldRow(title: "投資年期", bar: true) { UnitField(placeholder: "年", text: $years, unit: "年") }
                FieldRow(title: "預估年化報酬率", bar: true) { UnitField(placeholder: "%", text: $returnPercent, unit: "%") }
                FieldRow(title: "股息再投入", bar: true) { Toggle("將領到的股息自動再投入", isOn: $reinvest).font(.caption).tint(Palette.blue) }
                DisclosureGroup("進階：配息假設") {
                    FieldRow(title: "預估殖利率") { UnitField(placeholder: "%", text: $yieldPercent, unit: "%") }
                    FieldRow(title: "每年配息次數") { Picker("每年配息次數", selection: $plan.frequency) { ForEach([1, 2, 4, 12], id: \.self) { Text("\($0) 次").tag($0) } }.labelsHidden() }
                    FieldRow(title: "配息扣費比例") { UnitField(placeholder: "%", text: $deductionPercent, unit: "%") }
                }.font(.caption.bold()).foregroundStyle(Palette.muted).padding(.top, 6)
            }
            Button { run() } label: { PrimaryButtonLabel(title: "開始試算", icon: "function") }.buttonStyle(.plain)
            if let rows = try? PlanMath.project(plan), let last = rows.last {
                Card {
                    HStack { Label("試算結果", systemImage: "target").font(.headline).foregroundStyle(Palette.ink); Spacer(); TintPill(title: "假設試算") }
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 2) { Text("最終資產").font(.caption).foregroundStyle(Palette.muted); Text(money(last.total)).font(.system(size: 28, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Palette.blue).minimumScaleFactor(0.6).lineLimit(1); Text("元").font(.caption).foregroundStyle(Palette.blue) }.frame(maxWidth: .infinity)
                        VStack(spacing: 8) {
                            LabeledContent("總投入金額", value: money(last.contributed))
                            LabeledContent("累積股息", value: money(last.dividends))
                            LabeledContent("報酬率（年化）", value: "\(decimal(plan.totalReturn * 100))%")
                        }.font(.caption).frame(maxWidth: .infinity)
                    }.padding(.top, 10)
                    Chart(rows) { row in
                        AreaMark(x: .value("年", row.year), y: .value("資產", row.total)).foregroundStyle(LinearGradient(colors: [Palette.blue.opacity(0.25), Palette.blue.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("年", row.year), y: .value("資產", row.total)).foregroundStyle(Palette.blue)
                    }.chartYAxis(.hidden).frame(height: 100).padding(.top, 10)
                    Text(plan.reinvest > 0 ? "股息全部再投入。" : "股息不再投入，期末累計保留現金 \(money(last.cash)) 元已含在最終資產中。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 6)
                }
            } else { Text("輸入超出範圍，請檢查金額、年數（1–50 年）與比率。").font(.subheadline).foregroundStyle(Palette.red) }
            if let message { Text(message).font(.caption).foregroundStyle(Palette.muted) }
            Text("年化報酬率換算月複利，配息從投資部位扣除，扣費後依設定再投入或保留現金，每月底追加投入。配息不是額外報酬；這是情境試算，不是歷史績效或保證收益。").font(.caption).foregroundStyle(Palette.muted)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { VStack(spacing: 0) { Text("股息複利試算").font(.headline).foregroundStyle(Palette.ink); Text("模擬長期投入與股息再投入的複利效果").font(.caption2).foregroundStyle(Palette.muted) } } }
        .onAppear {
            guard !loaded else { return }; loaded = true
            if let saved = store.data.legacyPlan { plan = saved }
            principal = String(Int(plan.principal)); monthly = String(Int(plan.monthly)); years = String(plan.years)
            returnPercent = decimal(plan.totalReturn * 100); yieldPercent = decimal(plan.distributionRate * 100); deductionPercent = decimal(plan.deductionRate * 100); reinvest = plan.reinvest > 0
        }
    }
    private func run() {
        var next = plan
        next.principal = Double(principal.replacingOccurrences(of: ",", with: "")) ?? -1
        next.monthly = Double(monthly.replacingOccurrences(of: ",", with: "")) ?? -1
        next.years = Int(years) ?? 0
        next.totalReturn = (Double(returnPercent) ?? 0) / 100
        next.distributionRate = (Double(yieldPercent) ?? 0) / 100
        next.deductionRate = (Double(deductionPercent) ?? 0) / 100
        next.reinvest = reinvest ? 1 : 0
        do {
            try next.validate()
            plan = next
            var data = store.data; data.legacyPlan = next; try store.commit(data); message = "已試算並儲存設定。"
        } catch { message = error.localizedDescription }
    }
}
