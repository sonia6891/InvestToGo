import SwiftUI

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
