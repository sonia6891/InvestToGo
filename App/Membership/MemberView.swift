import SwiftUI
import StoreKit

/// The App Store product ids of the paid plans. Neither design document names them yet (2026-11-11 文件第 7 節 lists
/// the plans and D10 leaves the yearly price open), so they live here, in one place, until App Store Connect has them.
enum MembershipProducts {
    static let pocketMonthly = "tw.sonia.etftogo.member.pocket.monthly"
    static let aiMonthly = "tw.sonia.etftogo.member.ai.monthly"
    static let all = [pocketMonthly, aiMonthly]
}

/// Prices from the App Store and whether this Apple ID has a membership. Prices are never written into the app: until
/// the App Store answers, a plan shows 「—」 and 「再試一次」.
@MainActor final class MembershipStore: ObservableObject {
    static let shared = MembershipStore()
    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var loading = false
    /// The App Store did not answer, or answered without the plans.
    @Published private(set) var failed = false
    /// Any paid plan, current and not refunded (StoreKit's own record of this Apple ID's purchases).
    @Published private(set) var isMember = false
    @Published var message: String?
    private var updates: Task<Void, Never>?

    /// Reads the prices and the membership, and follows purchases made elsewhere (renewals, Ask to Buy, refunds).
    func start() async {
        if updates == nil {
            updates = Task { [weak self] in
                for await result in Transaction.updates {
                    if case .verified(let transaction) = result { await transaction.finish() }
                    await self?.refreshMembership()
                }
            }
        }
        await refreshMembership()
        if products.isEmpty { await loadProducts() }
    }

    func loadProducts() async {
        loading = true; failed = false
        defer { loading = false }
        do {
            let found = try await Product.products(for: MembershipProducts.all)
            products = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            failed = products.count < MembershipProducts.all.count
        } catch {
            failed = true
        }
    }

    func refreshMembership() async {
        var member = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, MembershipProducts.all.contains(transaction.productID), transaction.revocationDate == nil {
                member = true
            }
        }
        isMember = member
    }

    /// The App Store's own purchase sheet; the full flow (server confirmation, 2026-11-11 文件 5.5) is a later task.
    func purchase(_ id: String) async {
        guard let product = products[id] else { return }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification { await transaction.finish() }
                await refreshMembership()
            case .pending: message = "購買等待確認中，完成後會自動解鎖。"
            case .userCancelled: break
            @unknown default: break
            }
        } catch {
            message = "購買沒有完成，請稍後再試一次。"
        }
    }

    func restore() async {
        do { try await AppStore.sync() } catch { message = "恢復購買沒有完成，請稍後再試一次。" }
        await refreshMembership()
        if !isMember && message == nil { message = "這個 Apple ID 沒有可恢復的會員方案。" }
    }
}

/// 會員 (spec 5.10): the crown on its stage, 口袋會員, three plans, the main button, restore, terms and 隨時可取消.
/// 換膚 opens from here too, since membership is what unlocks the skins.
struct MemberView: View {
    @ObservedObject private var membership = MembershipStore.shared
    @ObservedObject private var skins = SkinStore.shared
    @Environment(\.skin) private var skin
    @State private var plan: Plan = .pocket
    /// Apple's standard licence agreement, the terms auto-renewing plans are sold under until the app has its own.
    private static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    enum Plan: String, CaseIterable, Identifiable {
        case free, pocket, ai
        var id: String { rawValue }
        var title: String {
            switch self {
            case .free: return "免費"
            case .pocket: return "口袋會員"
            case .ai: return "會員＋AI"
            }
        }
        var detail: String {
            switch self {
            case .free: return "記帳、1 個習慣、基本提醒"
            case .pocket: return "無限持股・全部皮膚・券商匯入"
            case .ai: return "再加 AI 問答與月報"
            }
        }
        var product: String? {
            switch self {
            case .free: return nil
            case .pocket: return MembershipProducts.pocketMonthly
            case .ai: return MembershipProducts.aiMonthly
            }
        }
    }

    var body: some View {
        Page {
            Text("MBR×001").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
            SkinStage(size: 230) { SkinImage(.crown).frame(width: 190, height: 190) }
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity)
            VStack(spacing: 8) {
                Text("口袋會員").skinFont(.title(30)).skinForeground(\.ink)
                SkinTag(membership.isMember ? "你是會員・全部解鎖" : "解鎖全部功能")
            }
            .frame(maxWidth: .infinity)
            skinsEntry
            VStack(spacing: 10) { ForEach(Plan.allCases) { planCard($0) } }
            if membership.failed && !membership.loading {
                Button { Task { await membership.loadProducts() } } label: { Text("再試一次") }
                    .buttonStyle(SkinButtonStyle(primary: false, seed: 3))
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("member-retry")
            }
            VStack(spacing: 14) {
                Button { if let id = plan.product { Task { await membership.purchase(id) } } } label: { Text(buyTitle) }
                    .buttonStyle(SkinButtonStyle(primary: true, seed: 7))
                    .disabled(plan.product.map { membership.products[$0] == nil } ?? true)
                    .accessibilityIdentifier("member-buy")
                HStack(spacing: 6) {
                    Button { Task { await membership.restore() } } label: { Text("恢復購買").frame(minHeight: 44).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityIdentifier("member-restore")
                    Text("·").accessibilityHidden(true)
                    Link(destination: Self.terms) { Text("條款").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityIdentifier("member-terms")
                    Text("·").accessibilityHidden(true)
                    Text("隨時可取消")
                }
                .skinFont(.mono(12)).skinForeground(\.sub)
                Text("訂閱會自動續訂，可隨時在 App Store 的訂閱設定取消；價格以 App Store 顯示為準。")
                    .skinFont(.body(11)).skinForeground(\.sub).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await membership.start() }
        .alert("口袋會員", isPresented: Binding(get: { membership.message != nil }, set: { if !$0 { membership.message = nil } })) {
            Button("知道了", role: .cancel) { membership.message = nil }
        } message: { Text(membership.message ?? "") }
    }

    private var buyTitle: String { plan == .free ? "目前使用免費版" : "選這個方案" }

    /// 換膚: the current skin's badge and name.
    private var skinsEntry: some View {
        NavigationLink(value: AppRoute.skins) {
            SkinCard {
                HStack(spacing: 12) {
                    SkinImage(.badge).frame(width: 44, height: 44).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("換膚").skinFont(.title(16))
                        Text("目前：\(skins.skin.name)・四套世界任你換").skinFont(.body(12)).skinForeground(\.sub)
                    }
                    Spacer(minLength: 0)
                    Text("›").skinFont(.title(20)).skinForeground(\.sub).accessibilityHidden(true)
                }
                .frame(minHeight: 44)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("member-skins")
    }

    private func planCard(_ item: Plan) -> some View {
        let selected = plan == item
        return Button { plan = item; Haptics.tick() } label: {
            HStack(spacing: 12) {
                SkinCheck(done: selected)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).skinFont(.title(15)).skinForeground(\.ink)
                    Text(item.detail).skinFont(.body(11)).skinForeground(\.sub).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                price(item)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(PlanBackground(selected: selected))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("member-plan-\(item.rawValue)")
    }

    @ViewBuilder private func price(_ item: Plan) -> some View {
        Group {
            if let id = item.product {
                if let product = membership.products[id] {
                    Text("\(product.displayPrice) / 月")
                } else {
                    Text(membership.loading ? "…" : "—").accessibilityLabel(membership.loading ? "價格讀取中" : "價格暫時無法取得")
                }
            } else {
                Text("免費")
            }
        }
        .skinFont(.mono(12)).skinForeground(\.sub).lineLimit(1)
    }
}

/// A plan card: the skin's card, and the chosen one outlined in the accent colour.
private struct PlanBackground: View {
    @Environment(\.skin) private var skin
    let selected: Bool
    var body: some View {
        let accent = skin.color(\.accent), card = skin.color(\.card)
        switch skin.style.button {
        case .hex:
            RoundedRectangle(cornerRadius: 22).fill(card)
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(accent, lineWidth: selected ? 3 : 0))
        case .pixelBlock:
            Rectangle().fill(card).hardShadow(skin.extra(2, or: \.line))
                .overlay(Rectangle().strokeBorder(accent, lineWidth: selected ? 3 : 0))
        case .paperStitch:
            RoundedRectangle(cornerRadius: 14).fill(card).paperShadow()
                .overlay(StitchSeam(color: selected ? accent : skin.color(\.dim), cornerRadius: 14, inset: 5, lineWidth: selected ? 2.5 : 1.5))
        case .sketchBox:
            SketchBoxShape(seed: 11, overshoot: false).fill(card)
                .overlay(SketchBoxShape(seed: 11).stroke(selected ? skin.color(\.ink) : skin.color(\.line), style: StrokeStyle(lineWidth: selected ? 2.5 : 1.5, lineCap: .round)))
        }
    }
}
