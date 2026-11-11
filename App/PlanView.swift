import SwiftUI
import PocketCore

struct PlanView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var plan = LegacyPlan(principal: 100000, monthly: 5000, years: 10, totalReturn: 0.06, distributionRate: 0.04, frequency: 4, reinvest: 1, deductionRate: 0)
    @State private var message: String?
    var body: some View { Form {
        Section("投入計畫") {
            number("起始本金", value: $plan.principal)
            number("每月底投入", value: $plan.monthly)
            Stepper("累積 \(plan.years) 年", value: $plan.years, in: 1...50)
            percent("假設年總報酬率", value: $plan.totalReturn, range: -0.9...0.5)
        }
        Section("配息與再投入") {
            percent("假設年配息率", value: $plan.distributionRate, range: 0...0.3)
            Picker("每年配息次數", selection: $plan.frequency) { ForEach([1,2,4,12], id: \.self) { Text("\($0) 次").tag($0) } }
            percent("配息再投入比例", value: $plan.reinvest, range: 0...1)
            percent("配息扣費比例", value: $plan.deductionRate, range: 0...0.2)
        }
        if let rows = try? PlanMath.project(plan), let last = rows.last {
            Section("第 \(plan.years) 年試算") {
                LabeledContent("累計投入", value: "$\(money(last.contributed))")
                LabeledContent("投資部位", value: "$\(money(last.invested))")
                LabeledContent("累計保留現金", value: "$\(money(last.cash))")
                LabeledContent("合計資產", value: "$\(money(last.total))").foregroundStyle(Palette.blue)
            }
            Section("逐年試算") { ForEach(rows.dropFirst()) { row in LabeledContent("第 \(row.year) 年", value: "$\(money(row.total))") } }
        } else { Section { Text("輸入超出範圍，請檢查金額與比例。").foregroundStyle(.red) } }
        Section { Button("儲存試算設定") { do { try plan.validate(); var next = store.data; next.legacyPlan = plan; try store.commit(next); message = "已儲存。" } catch { message = error.localizedDescription } }; if let message { Text(message) } }
        Section { Text("沿用舊版模型：年總報酬率換算月複利，配息從投資部位扣除，扣費後再分為再投入及保留現金，每月底追加投入。配息不是額外報酬；假設固定報酬與配息率，未計通膨或交易成本。這是情境試算，不是歷史績效或保證收益。").font(.footnote).foregroundStyle(.secondary) }
    }.navigationTitle("配息再投入試算").navigationBarTitleDisplayMode(.inline)
        .onAppear { if let saved = store.data.legacyPlan { plan = saved } }
    }
    private func number(_ title: String, value: Binding<Double>) -> some View { HStack { Text(title); TextField(title, value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) } }
    private func percent(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View { VStack(alignment: .leading) { Text("\(title) \(decimal(value.wrappedValue * 100))%"); Slider(value: value, in: range, step: 0.005) } }
}
