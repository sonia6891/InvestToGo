import SwiftUI

/* ---------- 口袋 (spec 5.7) ---------- */
/// Opens 找 ETF, optionally with the search field focused. Sent by the pocket page.
struct DiscoverRequest: Equatable {
    var search: Bool
    let id = UUID()
}

/// 口袋: the skin's pocket, 「我的口袋 · N 檔」, the total value in the big face, the total gain or loss as a tag, the
/// allocation bar, a row per holding and 「＋ 加一檔」. An empty pocket is the object, one sentence and one button —
/// never an NT$ 0 (ruling R15). The lobby now carries the market, watchlist and dividend teasers the old home page
/// had; search, watchlist, notices and settings stay as small icons along the top.
struct HomeView: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.skin) private var skin
    @Environment(\.lobbyNavigation) private var navigation
    @AppStorage("hideAmounts") private var hidden = false
    @AppStorage("readNotices") private var readNotices = ""

    var body: some View {
        let holdings = store.data.holdings
        let summary = PocketSummary.of(holdings) { store.marketValue(of: $0) }
        let count = Set(holdings.map(\.symbol)).count
        Page {
            topBar(count: count, filled: !holdings.isEmpty)
            if holdings.isEmpty {
                newbie
            } else {
                hero(summary, count: count)
                list(summary)
                more(holdings)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // Pulling down refreshes prices, so 口袋 has no pull-to-lobby (ruling R21).
        .refreshable {
            await store.refreshIndices()
            let symbols = store.data.holdings.map(\.symbol) + store.data.favorites.sorted()
            if !symbols.isEmpty { await store.refresh(symbols: symbols) }
        }
    }

    // MARK: Top bar

    private func topBar(count: Int, filled: Bool) -> some View {
        let read = Set(readNotices.split(separator: ",").map(String.init))
        let unread = AppNotice.all(store).filter { !read.contains($0.id) }.count
        return HStack(spacing: 0) {
            Text("PKT×\(String(format: "%03d", count))").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
            Spacer(minLength: 8)
            Button { openDiscover(search: true) } label: { glyph("magnifyingglass") }
                .buttonStyle(.plain).accessibilityLabel("搜尋 ETF").accessibilityIdentifier("home-search")
            NavigationLink(value: AppRoute.watchlist) { glyph("star") }
                .buttonStyle(.plain).accessibilityLabel("我的自選").accessibilityIdentifier("home-watchlist")
            if filled {
                Button { hidden.toggle() } label: { glyph(hidden ? "eye.slash" : "eye") }
                    .buttonStyle(.plain).accessibilityLabel(hidden ? "顯示金額" : "隱藏金額")
            }
            NavigationLink(value: AppRoute.notices) {
                glyph("bell").overlay(alignment: .topTrailing) {
                    if unread > 0 { Circle().fill(skin.color(\.accent)).frame(width: 8, height: 8).padding(10).accessibilityHidden(true) }
                }
            }
            .buttonStyle(.plain).accessibilityLabel(unread > 0 ? "通知中心，\(unread) 則未讀" : "通知中心")
            NavigationLink(value: AppRoute.settings) { glyph("gearshape") }
                .buttonStyle(.plain).accessibilityLabel("設定")
        }
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 15, weight: .semibold)).foregroundStyle(skin.color(\.sub))
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }

    private func openDiscover(search: Bool) {
        store.discoverRequest = DiscoverRequest(search: search)
        navigation.open(.find)
    }

    // MARK: Newbie

    /// The pocket, one sentence and one button: nothing to add up yet, so no number at all.
    private var newbie: some View {
        VStack(spacing: 18) {
            SkinImage(.pocket).frame(width: 220, height: 220)
                .accessibilityElement().accessibilityLabel("空的口袋")
            Text("口袋還是空的，放進第一檔 ETF 開始追蹤。")
                .skinFont(.body(15)).skinForeground(\.ink).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pocket-newbie")
            NavigationLink(value: AppRoute.holdingForm(id: nil, symbol: nil)) { Text("＋ 加一檔") }
                .buttonStyle(SkinButtonStyle(primary: true, seed: SkinSeed.of("＋ 加一檔")))
                .accessibilityIdentifier("pocket-add")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // MARK: Hero

    private func hero(_ summary: PocketSummary, count: Int) -> some View {
        VStack(spacing: 8) {
            // The 3D pocket is read as what it holds.
            SkinImage(.pocket).frame(width: 200, height: 200)
                .accessibilityElement().accessibilityLabel("我的口袋，\(count) 檔 ETF")
            Text("我的口袋 · \(count) 檔").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
            Text(summary.total.map { "NT$ \(shown(money($0), hidden: hidden))" } ?? "NT$ —")
                .skinFont(.big(42)).skinForeground(\.ink)
                .lineLimit(1).minimumScaleFactor(0.4)
                .accessibilityIdentifier("portfolio-value")
            gainTag(summary)
            if summary.missing > 0 {
                Text("另有 \(summary.missing) 筆還沒有台幣報價，未計入總市值").skinFont(.body(11)).skinForeground(\.sub)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The total gain or loss, honestly in the skin's up or down colour with its arrow, and nothing more: a loss gets
    /// no animation and no words of its own.
    @ViewBuilder private func gainTag(_ summary: PocketSummary) -> some View {
        if let percent = summary.gainPercent {
            if hidden {
                SkinTag("損益 ＊＊＊＊").accessibilityLabel("總損益已隱藏")
            } else {
                SkinTag(SkinChange.text(percent: percent, amount: summary.gain, format: money), tint: skin.color(SkinChange.tone(percent)))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("總損益 " + SkinChange.spoken(percent: percent, amount: summary.gain, format: money))
                    .accessibilityIdentifier("portfolio-gain")
            }
        }
    }

    // MARK: Holdings

    private func list(_ summary: PocketSummary) -> some View {
        let colors = skin.allocationColors
        let rows = Array(summary.rows.enumerated())
        return VStack(spacing: 0) {
            AllocationBar(parts: rows.compactMap { i, row in row.share.map { (share: $0, color: colors[i % colors.count]) } })
                .padding(.bottom, 6)
            ForEach(rows, id: \.element.id) { i, row in
                NavigationLink(value: AppRoute.holdingDetail(row.holding.id)) {
                    PocketHoldingRow(row: row, color: colors[i % colors.count], hidden: hidden)
                }
                .buttonStyle(.plain)
                Rectangle().fill(skin.color(\.line)).frame(height: 1).accessibilityHidden(true)
            }
            NavigationLink(value: AppRoute.holdingForm(id: nil, symbol: nil)) { Text("＋ 加一檔") }
                .buttonStyle(SkinButtonStyle(primary: false, seed: SkinSeed.of("＋ 加一檔")))
                .accessibilityIdentifier("pocket-add")
                .padding(.top, 18)
        }
    }

    // MARK: More

    /// The pocket's own records and tools, below the holdings.
    private func more(_ holdings: [Holding]) -> some View {
        let dates = holdings.compactMap { store.quote($0.symbol)?.date }.sorted()
        return VStack(alignment: .leading, spacing: 10) {
            SkinCard {
                VStack(spacing: 0) {
                    NavigationLink(value: AppRoute.overview) { SkinLinkRow(title: "資產總覽", subtitle: "報酬、配息與配置一次看") }
                        .buttonStyle(.plain).accessibilityIdentifier("home-overview")
                    divider
                    NavigationLink(value: AppRoute.trades) { SkinLinkRow(title: "交易紀錄", subtitle: "買進、賣出、調整與匯入") }
                        .buttonStyle(.plain).accessibilityIdentifier("holdings-trades")
                    divider
                    NavigationLink(value: AppRoute.allocation) { SkinLinkRow(title: "資產配置", subtitle: "類型、產業分佈與券商帳戶") }
                        .buttonStyle(.plain).accessibilityIdentifier("holdings-allocation")
                    divider
                    NavigationLink(value: AppRoute.combo) { SkinLinkRow(title: "ETF 組合試算", subtitle: "3、5、10 年資產預估") }
                        .buttonStyle(.plain).accessibilityIdentifier("home-combo")
                }
            }
            Text("報價日期 \(dates.last?.replacingOccurrences(of: "-", with: "/") ?? "—") · 下拉更新 · 行情更新不等於券商持股同步")
                .skinFont(.mono(10)).skinForeground(\.sub).fixedSize(horizontal: false, vertical: true)
            if SellCosts.enabled, holdings.contains(where: { !SellCosts.isSet(for: $0.broker) }) {
                NavigationLink(value: AppRoute.settings) {
                    Text("市值目前用原價手續費估算，到設定填入你的券商折扣會更準 ›")
                        .skinFont(.body(11)).skinForeground(\.sub).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private var divider: some View { Rectangle().fill(skin.color(\.line)).frame(height: 1).accessibilityHidden(true) }
}
