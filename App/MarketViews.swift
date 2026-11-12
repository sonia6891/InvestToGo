import SwiftUI
import Charts

/* ---------- shared pieces for ETF rows ---------- */
/// Rounded square with the ETF code.
struct SymbolAvatar: View {
    let symbol: String
    var size: CGFloat = 42
    var body: some View {
        Text(symbol)
            .font(.system(size: symbol.count > 5 ? size * 0.24 : size * 0.29, weight: .heavy, design: .rounded))
            .lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Palette.blue.opacity(0.65), Palette.blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}
/// 上市 / 上櫃 for the fund's market.
struct MarketBadge: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    var body: some View {
        let tpex = store.funds.first { $0.id == symbol }?.market == "TPEx"
        TintPill(title: tpex ? "上櫃 ETF" : "ETF", color: tpex ? Palette.teal : Palette.orange)
    }
}
/// Opens the ETF page.
struct SymbolLink<Label: View>: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    @ViewBuilder var label: Label
    var body: some View {
        NavigationLink(value: store.funds.first { $0.id == symbol } ?? Fund(id: symbol, name: store.name(for: symbol), strategy: .unclassified)) { label }.buttonStyle(.plain)
    }
}
/// Avatar, code and name, market badge, price and change, watchlist star.
struct SymbolRow: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    var subtitle: String? = nil
    var body: some View {
        let quote = store.quote(symbol), on = store.data.favorites.contains(symbol)
        HStack(spacing: 6) {
            SymbolLink(symbol: symbol) {
                HStack(spacing: 10) {
                    SymbolAvatar(symbol: symbol)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) { Text(symbol).font(.subheadline.bold()).monospacedDigit(); Text(store.name(for: symbol)).font(.subheadline.bold()).lineLimit(1) }.foregroundStyle(Palette.ink)
                        HStack(spacing: 6) { MarketBadge(symbol: symbol); if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(Palette.muted).lineLimit(1) } }
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(quote.map { priceText($0.price) } ?? "—").font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.ink)
                            .contentTransition(.numericText(value: quote?.price ?? 0)).animation(.snappy, value: quote?.price)
                        QuoteChange(quote: quote, font: .caption2)
                    }
                }.contentShape(Rectangle())
            }
            Button { store.favorite(symbol) } label: {
                Image(systemName: on ? "star.fill" : "star").foregroundStyle(on ? Palette.orange : Palette.muted.opacity(0.5)).frame(width: 32, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(on ? "取消自選 \(symbol)" : "加入自選 \(symbol)")
        }
        .padding(.vertical, 6)
    }
}

struct TintedIconLabel: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon.foregroundStyle(tint); configuration.title }
    }
}

/* ---------- skin pieces for 找 ETF, the ETF page and the dex card ---------- */
/// A day's move in the skin's 紅漲綠跌 colours, never colour alone: "▲ 0.75%", "▼ 0.27%", "－ 0.00%" when unchanged;
/// with `withAmount`, "▲ 1.25 (+0.75%)". Without a change figure it shows "—" and invents nothing.
struct SkinChange: View {
    @Environment(\.skin) private var skin
    let quote: Quote?
    var size: CGFloat = 11
    var withAmount = false
    var body: some View {
        if let quote, quote.trial != true, let percent = quote.changePercent, percent.isFinite {
            let rounded = (percent * 100).rounded() / 100
            Text(Self.text(percent: percent, amount: withAmount ? quote.changeAmount : nil))
                .skinFont(.mono(size)).lineLimit(1)
                .foregroundStyle(rounded > 0 ? skin.color(\.up) : (rounded < 0 ? skin.color(\.down) : skin.color(\.sub)))
        } else {
            Text(quote?.trial == true ? "試撮中" : "—").skinFont(.mono(size)).skinForeground(\.sub)
        }
    }
    /// The arrow follows the percentage as shown (two decimals), so a move that rounds to 0.00% reads as unchanged.
    static func text(percent: Double, amount: Double?) -> String {
        let rounded = (percent * 100).rounded() / 100
        let arrow = rounded > 0 ? "▲" : (rounded < 0 ? "▼" : "－")
        guard let amount, amount.isFinite else { return "\(arrow) \(String(format: "%.2f", abs(rounded)))%" }
        return "\(arrow) \(priceText(abs(amount))) (\(String(format: "%+.2f", rounded))%)"
    }
}

/// The price line in the skin's chart style (spec 7.1): smooth gold (black-gold), stepped (pixel), plain red (stitch),
/// black pencil (sketch). No axes; the caller labels the range and the data date.
struct SkinTrendLine: View {
    @Environment(\.skin) private var skin
    let points: [ValuePoint]
    var height: CGFloat = 150
    var body: some View {
        let style = skin.style.chart
        let shown = style == .stepped ? Self.thinned(points, to: 32) : points
        let values = shown.map(\.value)
        let low = values.min() ?? 0, high = values.max() ?? 1
        let pad = max((high - low) * 0.12, abs(high) * 0.002, 0.01)
        let base = low - pad
        Chart(shown) { point in
            if let fill = fillOpacity(style) {
                AreaMark(x: .value("日期", point.date), yStart: .value("基準", base), yEnd: .value("價格", point.value))
                    .foregroundStyle(lineColor(style).opacity(fill))
                    .interpolationMethod(interpolation(style))
            }
            LineMark(x: .value("日期", point.date), y: .value("價格", point.value))
                .foregroundStyle(lineColor(style))
                .lineStyle(stroke(style))
                .interpolationMethod(interpolation(style))
        }
        .chartYScale(domain: base...(high + pad))
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("價格走勢")
        .accessibilityValue(summary)
    }
    private var summary: String {
        guard let first = points.first, let last = points.last, first.value > 0 else { return "" }
        let move = SkinChange.text(percent: (last.value / first.value - 1) * 100, amount: nil)
        return "從 \(priceText(first.value)) 到 \(priceText(last.value))，\(move)"
    }
    private func lineColor(_ style: SkinStyle.ChartKind) -> Color {
        switch style {
        case .smooth, .stepped, .plain: return skin.color(\.accent)
        case .pencil: return skin.color(\.ink)
        }
    }
    private func fillOpacity(_ style: SkinStyle.ChartKind) -> Double? {
        switch style {
        case .smooth: return 0.16
        case .stepped: return nil
        case .plain: return 0.18
        case .pencil: return 0.1
        }
    }
    private func interpolation(_ style: SkinStyle.ChartKind) -> InterpolationMethod {
        switch style {
        case .smooth: return .monotone
        case .stepped: return .stepEnd
        case .plain, .pencil: return .linear
        }
    }
    private func stroke(_ style: SkinStyle.ChartKind) -> StrokeStyle {
        switch style {
        case .smooth: return StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        case .stepped: return StrokeStyle(lineWidth: 4, lineCap: .square, lineJoin: .miter)
        case .plain: return StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        case .pencil: return StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        }
    }
    /// Pixel steps read as steps only when there are few of them: evenly spaced samples, always keeping the last day.
    static func thinned(_ points: [ValuePoint], to count: Int) -> [ValuePoint] {
        guard points.count > count, count > 1 else { return points }
        let step = Double(points.count - 1) / Double(count - 1)
        return (0..<count).map { points[Int((Double($0) * step).rounded())] }
    }
}

/// `SkinCard` holding a leading-aligned stack: the panels of the ETF page's tabs.
struct SkinPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { SkinCard { VStack(alignment: .leading, spacing: 0) { content } } }
}
