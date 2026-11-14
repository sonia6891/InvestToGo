import SwiftUI

extension PortfolioStore {
    /// The active ETFs among what is held or in the favourites, by code (主動式追蹤 follows these).
    var trackedActiveFunds: [Fund] {
        Set(data.holdings.map(\.symbol)).union(data.favorites).sorted()
            .filter { isETF($0) }
            .map { dexFund($0) }
            .filter(\.isActive)
    }
}

/// What changed between two days of an ETF's holdings: the two days said plainly, then 新增, 剔除 and 權重變化.
struct HoldingChangeList: View {
    let change: SnapshotChange

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(change.title).font(.subheadline.bold()).foregroundStyle(Palette.ink)
            if change.isEmpty {
                Text("這兩次公布的持股沒有變化。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 6)
            }
            if !change.added.isEmpty {
                heading("新增 \(change.added.count) 檔")
                ForEach(change.added) { row($0, value: "\(decimal($0.weight))%", note: "目前權重") }
            }
            if !change.removed.isEmpty {
                heading("剔除 \(change.removed.count) 檔")
                ForEach(change.removed) { row($0, value: "\(decimal($0.weight))%", note: "原本權重") }
            }
            if !change.changed.isEmpty {
                heading(change.changedCut ? "權重變化（變動最大的前 \(SnapshotDiff.limit) 檔）" : "權重變化")
                ForEach(change.changed.indices, id: \.self) { i in
                    row(change.changed[i].component, value: "\(signed(change.changed[i].delta, decimal)) 個百分點",
                        note: "目前 \(decimal(change.changed[i].component.weight))%")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.caption.bold()).foregroundStyle(Palette.blue).padding(.top, 14)
    }

    private func row(_ component: FundComponent, value: String, note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(component.name ?? component.symbol).font(.subheadline.bold()).foregroundStyle(Palette.ink)
                Text(component.symbol).font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.ink)
                Text(note).font(.caption).monospacedDigit().foregroundStyle(Palette.muted)
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

/// 主動式追蹤 (spec 5.3, 口袋會員): the active ETFs that are held or in the favourites, each with what changed between
/// the two newest days of holdings kept on the phone.
struct ActiveTrackingView: View {
    @EnvironmentObject private var store: PortfolioStore
    @State private var busy = false
    /// What went wrong for an ETF in the last 更新, by code.
    @State private var errors: [String: String] = [:]
    @State private var task: Task<Void, Never>?

    var body: some View {
        Page {
            MemberLock(.activeTracking) { tracking } preview: { preview }
            VStack(alignment: .leading, spacing: 4) {
                Text("資料來自各投信官網公開的持股，更新時間依投信而定。")
                Text("這裡只整理公開持股的變動，不是投資建議。")
            }
            .font(.caption).foregroundStyle(Palette.muted)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { VStack(spacing: 0) { Text("主動式追蹤").font(.headline).foregroundStyle(Palette.ink); Text("主動式 ETF 前後兩次持股的變化").font(.caption2).foregroundStyle(Palette.muted) } } }
        .onDisappear { task?.cancel(); task = nil; busy = false }
    }

    // MARK: Member

    @ViewBuilder private var tracking: some View {
        let funds = store.trackedActiveFunds
        if funds.isEmpty {
            Card {
                Text("你持有或收藏的 ETF 裡還沒有主動式 ETF。").font(.subheadline.bold()).foregroundStyle(Palette.ink)
                    .accessibilityIdentifier("active-tracking-empty")
                Text("把主動式 ETF 加進收藏或持有，就會出現在這裡。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 6)
            }
        } else {
            Card {
                Button(busy ? "更新中…" : "更新") { task?.cancel(); task = Task { await refresh(funds.map(\.id)) } }
                    .buttonStyle(.borderedProminent).disabled(busy)
                    .accessibilityIdentifier("active-tracking-refresh")
                Text("每檔一天更新一次；變化是最新兩次持股的比較。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 10)
            }
            ForEach(funds) { card($0) }
        }
    }

    @ViewBuilder private func card(_ fund: Fund) -> some View {
        let history = store.componentHistory(for: fund.id)
        // Holdings saved before the history was kept are still the latest day known.
        let latest = history.first ?? store.data.components?[fund.id]
        Card {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fund.name).font(.headline).foregroundStyle(Palette.ink)
                    Text(fund.id).font(.caption).monospacedDigit().foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                if let latest {
                    Text("最新資料 \(SnapshotDiff.shortDay(latest.date))").font(.caption).monospacedDigit().foregroundStyle(Palette.muted)
                }
            }
            if let message = errors[fund.id] {
                Text(message).font(.caption).foregroundStyle(Palette.red).padding(.top, 8)
            }
            if let change = SnapshotDiff.latest(history) {
                HoldingChangeList(change: change).padding(.top, 12)
            } else if latest != nil {
                Text("下次更新後就能看到變化").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 12)
            } else {
                Text("還沒有這檔的持股資料，按「更新」取得。").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 12)
            }
        }
    }

    /// One ETF after another (`HoldingsClient` spaces the requests and asks each company once a day). An ETF that
    /// fails keeps what was saved and says why on its own card; leaving the screen stops the rest.
    private func refresh(_ symbols: [String]) async {
        busy = true; errors = [:]
        for symbol in symbols {
            do {
                try await store.refreshComponents(symbol)
            } catch {
                if Task.isCancelled || error is CancellationError { return }
                errors[symbol] = error.localizedDescription
            }
            if Task.isCancelled { return }
        }
        busy = false
    }

    // MARK: Preview behind the lock

    /// Made-up names and numbers: what the screen looks like, never anyone's holdings.
    private static let sample = SnapshotChange(
        from: "2026-11-11", to: "2026-11-13",
        added: [FundComponent(symbol: "1001", name: "範例股票 A", weight: 3.2)],
        removed: [FundComponent(symbol: "1002", name: "範例股票 B", weight: 1.8)],
        changed: [(component: FundComponent(symbol: "1003", name: "範例股票 C", weight: 12.4), delta: 2.1),
                  (component: FundComponent(symbol: "1004", name: "範例股票 D", weight: 4.6), delta: -1.2)])

    private var preview: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("範例主動式 ETF").font(.headline).foregroundStyle(Palette.ink)
                    Text("00000A").font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Text("最新資料 11/13").font(.caption).foregroundStyle(Palette.muted)
            }
            HoldingChangeList(change: Self.sample).padding(.top, 12)
        }
    }
}

/// 「持股變化」 on an active ETF's 成分 tab. A member sees what changed between the two newest days; anyone else sees
/// one line that opens 會員, and none of the data. The holdings themselves stay free above and below it.
struct HoldingChangesSection: View {
    @EnvironmentObject private var store: PortfolioStore
    @ObservedObject private var membership = MembershipStore.shared
    @Environment(\.lobbyNavigation) private var navigation
    let symbol: String

    var body: some View {
        SkinPanel {
            SectionHeading(title: "持股變化")
            if membership.has(.activeTracking) {
                if let change = SnapshotDiff.latest(store.componentHistory(for: symbol)) {
                    HoldingChangeList(change: change).padding(.top, 12)
                } else {
                    Text("下次更新後就能看到變化").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 12)
                }
            } else {
                Button { navigation.push(.member) } label: {
                    HStack(spacing: 8) {
                        MemberCrown().frame(width: 18, height: 18)
                        Text("口袋會員可以看前後兩次持股的變化").font(.subheadline).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Text("›").font(.headline).foregroundStyle(Palette.muted).accessibilityHidden(true)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("holding-changes-lock")
                .padding(.top, 4)
            }
        }
    }
}
