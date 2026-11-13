import SwiftUI

/// 定投紀錄 (spec 4.1, opened from the lobby's numeral): every month from the first recorded DCA (or this year's
/// January) to now as a check, by year, newest first, with the current run and the best run.
struct DCAHistoryView: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.skin) private var skin

    var body: some View {
        let game = store.data.game ?? GameState(), now = Date()
        let years = Self.years(game, now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DCA×\(String(format: "%03d", game.dcaMonths.count))").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
                    Text("定投紀錄").skinFont(.title(30)).skinForeground(\.ink)
                }
                HStack(spacing: 10) {
                    SkinTag("目前連續 \(game.streak(now: now)) 個月")
                    SkinTag("最長紀錄 \(game.longestStreak) 個月")
                }
                ForEach(years, id: \.self) { year in
                    SkinCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(String(year)).skinFont(.big(22))
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 12) {
                                ForEach(1...12, id: \.self) { month in
                                    let ym = YearMonth(year: year, month: month)
                                    let future = ym > YearMonth(now)
                                    VStack(spacing: 4) {
                                        SkinCheck(done: game.dcaMonths.contains(ym), size: 24)
                                        Text("\(month)月").skinFont(.mono(11)).skinForeground(\.sub)
                                    }
                                    .opacity(future ? 0.35 : 1)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("\(year) 年 \(month) 月，\(game.dcaMonths.contains(ym) ? "已定投" : "未定投")")
                                }
                            }
                        }
                    }
                }
                if game.isNewbie {
                    Text("記下第一筆定期定額，這裡就會打上第一個勾。").skinFont(.body(13)).skinForeground(\.sub)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
        }
        .background(skin.color(\.page).ignoresSafeArea())
        .navigationTitle("定投紀錄").navigationBarTitleDisplayMode(.inline)
    }

    /// Years from the first recorded month (or this year) to this year, newest first.
    static func years(_ game: GameState, now: Date) -> [Int] {
        let this = YearMonth(now).year
        let first = min(game.dcaMonths.map(\.year).min() ?? this, this)
        return Array((first...this).reversed())
    }
}
