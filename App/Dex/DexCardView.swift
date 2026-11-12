import SwiftUI

/// ETF 圖鑑卡 (spec 5.6): a light card with an accent edge, number and series, risk stars, the big code and the series
/// object, five block bars, the 特技 line; under it the series' collection progress, 「PK 比一比」 and 「加入口袋」.
/// Swiping left or right (or the ‹ › buttons) moves through the collected cards; with Reduce Motion cards fade.
struct DexCardView: View {
    let symbol: String
    @EnvironmentObject private var store: PortfolioStore
    @Environment(\.skin) private var skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lobbyNavigation) private var navigation
    /// The card on screen once the user has swiped; nil shows `symbol`.
    @State private var swiped: String?
    @State private var forward = true
    /// The catalogue's facts and unique funds, built once when the screen appears (they rank the whole catalogue, so
    /// they are not rebuilt on every swipe).
    @State private var ranking: (facts: DexFacts, funds: [Fund])?

    var body: some View {
        let current = swiped ?? symbol
        let deck = store.dexDeck(opened: symbol, showing: current)
        let fund = store.dexFund(current)
        let series = DexSeries.of(fund)
        let funds = ranking?.funds ?? []
        let progress = (store.data.game ?? GameState()).seriesProgress(series, funds: funds)
        Page {
            ZStack {
                if let ranking {
                    DexCard(fund: fund, facts: ranking.facts, among: ranking.funds)
                        .id(current)
                        .transition(transition)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200)
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 60, abs(dx) > abs(value.translation.height) else { return }
                move(dx < 0 ? 1 : -1, in: deck, from: current)
            })
            .accessibilityAction(named: "下一張") { move(1, in: deck, from: current) }
            .accessibilityAction(named: "上一張") { move(-1, in: deck, from: current) }
            pager(deck: deck, current: current)
            Text("\(series.rawValue)系列　已收集 \(progress.got) / \(progress.total)")
                .skinFont(.mono(12)).skinForeground(\.sub)
                .frame(maxWidth: .infinity)
            HStack(spacing: 12) {
                Button("PK 比一比") {
                    do { try store.appendToComparison(current); navigation.push(.comparison) } catch { store.message = error.localizedDescription }
                }
                .buttonStyle(SkinButtonStyle(primary: false, horizontal: 20, seed: SkinSeed.of("PK 比一比")))
                NavigationLink(value: AppRoute.holdingForm(id: nil, symbol: current)) { Text("加入口袋") }
                    .buttonStyle(SkinButtonStyle(primary: true, horizontal: 24, seed: SkinSeed.of("加入口袋")))
            }
            .frame(maxWidth: .infinity)
            Text("能力條把官方數據換算成 1–10 格：費用越低、上市越久，格數越多；規模與上市時間在全部 ETF 裡排，殖利率與波動在同類型裡排。缺資料顯示「—」。只描述事實，不是評分或推薦。")
                .skinFont(.body(11)).skinForeground(\.sub)
        }
        .task { if ranking == nil { ranking = (store.dexFacts(), store.dexFunds) } }
        .navigationTitle("ETF 圖鑑").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                           removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    private func move(_ step: Int, in deck: [String], from current: String) {
        guard let i = deck.firstIndex(of: current), deck.indices.contains(i + step) else { return }
        forward = step > 0
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .snappy(duration: 0.3)) { swiped = deck[i + step] }
    }

    private func pager(deck: [String], current: String) -> some View {
        let index = deck.firstIndex(of: current) ?? 0
        return HStack(spacing: 16) {
            pageButton("‹", label: "上一張", enabled: index > 0) { move(-1, in: deck, from: current) }
            Text("\(index + 1) / \(deck.count)").skinFont(.mono(12)).skinForeground(\.sub)
                .accessibilityLabel("第 \(index + 1) 張，共 \(deck.count) 張")
            pageButton("›", label: "下一張", enabled: index < deck.count - 1) { move(1, in: deck, from: current) }
        }
        .frame(maxWidth: .infinity)
    }

    private func pageButton(_ glyph: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).skinFont(.title(20)).foregroundStyle(skin.color(enabled ? \.ink : \.dim))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// The card itself. Its paper is the skin's light colour (ink on dark skins, card on light ones) and the 特技 box the
/// dark one, so the card reads as a printed card on every skin.
private struct DexCard: View {
    let fund: Fund
    let facts: DexFacts
    let among: [Fund]
    @Environment(\.skin) private var skin

    var body: some View {
        let series = DexSeries.of(fund)
        let stats = Dex.stats(for: fund, among: among, facts: facts)
        let number = among.filter { DexSeries.of($0) == series }.map(\.id).sorted().firstIndex(of: fund.id).map { $0 + 1 }
        let paper = skin.lightText ? skin.colors.ink : skin.colors.card
        let box = skin.lightText ? skin.colors.card : skin.colors.ink
        let text = skin.onFill(paper)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(number.map { "No.\(String(format: "%03d", $0))" } ?? "No.—").skinFont(.mono(11)).tracking(1.2)
                SkinTag(series.rawValue)
                Spacer(minLength: 4)
                stars(DexText.riskStars(fund), color: text)
            }
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fund.id).skinFont(.big(64)).lineLimit(1).minimumScaleFactor(0.5)
                        .accessibilityIdentifier("dex-code")
                    Text(fund.name).skinFont(.title(16)).lineLimit(2)
                }
                Spacer(minLength: 4)
                SkinImage(Self.art(series)).frame(width: 84, height: 84).accessibilityHidden(true)
            }
            VStack(spacing: 8) {
                ForEach(DexText.bars(stats, fund: fund, facts: facts)) { bar in row(bar, text: text) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("特技").skinFont(.title(12)).foregroundStyle(skin.color(\.accent))
                Text(DexText.skill(fund, fee: AnnualFeeCatalog.bundled?.records[fund.id])).skinFont(.body(13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(skin.onFill(box))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(rgb: box)))
            .accessibilityElement(children: .combine)
        }
        .foregroundStyle(text)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color(rgb: paper)))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(skin.color(\.accent), lineWidth: 3))
    }

    /// Neutral ink, never the accent: these stars are a risk level, and gold would read as "better".
    private func stars(_ count: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            Text("風險").skinFont(.mono(10)).padding(.trailing, 2)
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= count ? "star.fill" : "star").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(i <= count ? color : color.opacity(0.3))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("風險等級 \(fund.riskLevel)，依資產類型粗估，\(count) 顆星，共 5 顆")
    }

    private func row(_ bar: DexBar, text: Color) -> some View {
        HStack(spacing: 8) {
            Text(bar.title).skinFont(.body(12)).frame(minWidth: 60, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(0..<10, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < bar.blocks ? skin.color(\.accent) : text.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(text.opacity(0.3), lineWidth: 1))
                        .frame(maxWidth: .infinity).frame(height: 12)
                }
            }
            Text(bar.value).skinFont(.mono(11)).lineLimit(1).frame(minWidth: 52, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bar.blocks > 0 ? "\(bar.title) \(bar.blocks) 格，共 10 格" : "\(bar.title) 沒有資料")
        .accessibilityValue(bar.value)
        .accessibilityIdentifier("dex-bar-\(bar.id)")
    }

    /// The series' object, drawn in the current skin.
    static func art(_ series: DexSeries) -> SkinArtName {
        switch series {
        case .marketCap: return .pocketIcon
        case .highDividend: return .dividends
        case .bond: return .goal
        case .theme: return .badge
        }
    }
}
