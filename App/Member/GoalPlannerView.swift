import SwiftUI

/// 存錢目標反推 (spec 5.x, 口袋會員): from a target amount back to the monthly amount, in three scenarios.
struct GoalPlannerView: View {
    @State private var targetText = "3000000"
    @State private var yearsText = "10"
    @State private var currentText = "0"
    @State private var returnText = "6"

    private func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: "")) }

    var body: some View {
        Page {
            MemberLock(.goalPlanner) { planner } preview: { preview }
            Text("情境試算，不是預測或保證。").font(.caption).foregroundStyle(Palette.muted)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { VStack(spacing: 0) { Text("存錢目標反推").font(.headline).foregroundStyle(Palette.ink); Text("設定目標，算出每月要投多少").font(.caption2).foregroundStyle(Palette.muted) } } }
    }

    @ViewBuilder private var planner: some View {
        Card {
            FieldRow(title: "目標金額", bar: true) { UnitField(placeholder: "目標", text: $targetText, unit: "元") }
            FieldRow(title: "年數", bar: true) { UnitField(placeholder: "年", text: $yearsText, unit: "年") }
            FieldRow(title: "目前已有", bar: true) { UnitField(placeholder: "已有", text: $currentText, unit: "元") }
            FieldRow(title: "假設年報酬", bar: true) { UnitField(placeholder: "%", text: $returnText, unit: "%") }
        }
        let target = number(targetText), years = Int(yearsText), current = number(currentText) ?? 0, annual = number(returnText)
        if let target, let years, let annual, target > 0, (1...60).contains(years), current >= 0, abs(annual) <= 30 {
            let rows = GoalPlanner.scenarios(target: target, years: years, current: current, annualReturn: annual)
            let base = rows[1].monthly
            Card {
                Text("每月需投入").font(.caption).foregroundStyle(Palette.muted)
                Text("\(money(base)) 元").font(.title.bold()).monospacedDigit().foregroundStyle(Palette.ink)
                    .accessibilityIdentifier("goal-planner-monthly")
                Text("基準情境，年報酬 \(decimal(rows[1].annualReturn))%").font(.caption).foregroundStyle(Palette.muted)
                ForEach(rows.indices, id: \.self) { i in
                    HStack {
                        Text(rows[i].scenario.rawValue).font(.subheadline.bold()).foregroundStyle(Palette.ink)
                        Text("年報酬 \(decimal(rows[i].annualReturn))%").font(.caption).foregroundStyle(Palette.muted)
                        Spacer()
                        Text("\(money(rows[i].monthly)) 元／月").font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink)
                    }.padding(.top, 10)
                }
            }
        } else {
            Card { Text("請輸入目標金額、1–60 年、目前已有金額與 −30 到 30 之間的年報酬。").font(.subheadline).foregroundStyle(Palette.muted) }
        }
    }

    private var preview: some View {
        Card {
            Text("每月需投入").font(.caption).foregroundStyle(Palette.muted)
            Text("18,465 元").font(.title.bold()).foregroundStyle(Palette.ink)
            ForEach([("樂觀", "9", "15,813"), ("基準", "6", "18,465"), ("保守", "-1", "26,266")], id: \.0) { row in
                HStack {
                    Text(row.0).font(.subheadline.bold()).foregroundStyle(Palette.ink)
                    Text("年報酬 \(row.1)%").font(.caption).foregroundStyle(Palette.muted)
                    Spacer()
                    Text("\(row.2) 元／月").font(.subheadline).foregroundStyle(Palette.ink)
                }.padding(.top, 10)
            }
        }
    }
}
