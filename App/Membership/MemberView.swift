import SwiftUI
import StoreKit

/// The App Store product ids of the paid plans. Neither design document names them yet (2026-11-11 文件第 7 節 lists
/// the plans and D10 leaves the yearly price open), so they live here, in one place, until App Store Connect has them.
enum MembershipProducts {
    static let pocketMonthly = "tw.sonia.etftogo.member.pocket.monthly"
    /// 會員＋AI: not sold in this build (its features are not in the app yet, ruling R33). Kept so a purchase already on
    /// the Apple ID still counts, and so selling it again is adding it to `sold`.
    static let aiMonthly = "tw.sonia.etftogo.member.ai.monthly"
    /// Every plan that makes a member.
    static let all = [pocketMonthly, aiMonthly]
    /// The plans this build offers for sale; only their prices are asked of the App Store.
    static let sold = [pocketMonthly]
}

/// What a plan's price slot says.
enum PlanPrice {
    /// The price the App Store screenshots show for 口袋會員 where StoreKit has no product to ask (the CI simulator): the
    /// one set for Taiwan in App Store Connect. Only `--demo-store` ever shows it.
    static let demoStore = "NT$120 / 月"
    /// `product` is the App Store's own price and period, nil until it has answered. Without one a real launch shows
    /// 「…」 while asking and 「—」 after; `--demo-store` shows the screenshots' price instead.
    static func text(product: String?, loading: Bool, demoStore: Bool) -> String {
        if let product { return product }
        if demoStore { return Self.demoStore }
        return loading ? "…" : "—"
    }
}

/// Prices from the App Store and whether this Apple ID has a membership. Prices are never written into the app: until
/// the App Store answers, a plan shows 「—」 and 「再試一次」.
@MainActor final class MembershipStore: ObservableObject {
    static let shared = MembershipStore()
    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var loading = false
    /// The App Store did not answer, or answered without the plans.
    @Published private(set) var failed = false
    /// The paid plans this Apple ID holds, current and not refunded (StoreKit's own record of its purchases).
    @Published private(set) var owned: Set<String> = []
    var isMember: Bool { !owned.isEmpty }
    /// `--ui-testing --demo-member` (or `--demo-store`, which implies it): every member feature open without a purchase
    /// (UI tests, screenshots).
    var demoMember = MembershipStore.demoMember(from: ProcessInfo.processInfo.arguments)
    /// Whether this person may use a member feature. Reads `owned`, so views observing the store redraw on a change.
    func has(_ feature: MemberFeature) -> Bool { isMember || demoMember }
    nonisolated static func demoMember(from args: [String]) -> Bool { DemoArguments.has("--demo-member", in: args) }
    @Published var message: String?
    private var updates: Task<Void, Never>?
    /// One App Store request at a time: a second caller waits for the first instead of clearing the spinner early.
    private var loadTask: Task<Void, Never>?
    /// The player's level, for the level skins a non-member may still wear; set at launch.
    var level: () -> Int = { 1 }
    /// Where the 「會員已到期」 notice goes (the root toast); set at launch.
    var onLapse: (String) -> Void = { _ in }
    /// The skin store whose worn skin is checked; the app's own outside tests.
    var skins: SkinStore?
    /// Off in UI tests, which wear member skins with `--skin` and no purchase, and in the unit-test host (the tests
    /// switch it on for their own store).
    var checksWornSkin = !ProcessInfo.processInfo.arguments.contains("--ui-testing")
        && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    static let lapseNotice = "會員已到期，已換回黑金"

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
        if let loadTask { await loadTask.value; return }
        let task = Task { await self.fetchProducts() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func fetchProducts() async {
        loading = true; failed = false
        defer { loading = false }
        do {
            let found = try await Product.products(for: MembershipProducts.sold)
            products = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            failed = products.count < MembershipProducts.sold.count
        } catch {
            failed = true
        }
    }

    func refreshMembership() async {
        var held: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, MembershipProducts.all.contains(transaction.productID), transaction.revocationDate == nil {
                held.insert(transaction.productID)
            }
        }
        apply(held)
    }

    /// StoreKit's answer about this Apple ID. Only now, never before the first answer (members would flash to black-gold
    /// at every launch), is the worn skin checked: one the player may no longer wear goes back to black-gold, with a
    /// notice (final review I1).
    func apply(_ held: Set<String>) {
        owned = held
        guard checksWornSkin else { return }
        if (skins ?? SkinStore.shared).takeOffLocked(level: level(), member: isMember) { onLapse(Self.lapseNotice) }
    }

    /// The App Store's own purchase sheet; the full flow (server confirmation, 2026-11-11 文件 5.5) is a later task.
    func purchase(_ id: String) async {
        guard let product = products[id] else { return }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refreshMembership()
            case .success(.unverified):
                message = "購買未能驗證，請稍後按「恢復購買」再試一次。"
            case .pending: message = "購買等待確認中，完成後會自動解鎖。"
            case .userCancelled: break
            @unknown default: break
            }
        } catch {
            message = "購買沒有完成，請稍後再試一次。"
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return  // The person closed the App Store sign-in themselves: nothing to report.
        } catch {
            message = "恢復購買沒有完成，請稍後再試一次。"
        }
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
    /// The height of the buy button's block at the bottom, which the first screenful stops above.
    @State private var footer: CGFloat = 0
    private static let demoStore = DemoArguments.has("--demo-store", in: ProcessInfo.processInfo.arguments)
    /// The crown's stage gives way, down to the smaller size, so that the three plans fit above the buy button.
    static let stageSizes: ClosedRange<CGFloat> = 110...180
    /// Apple's standard licence agreement, the terms auto-renewing plans are sold under until the app has its own.
    private static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// The privacy policy, linked beside 條款 (guideline 3.1.2 asks for both on a subscription screen).
    // TODO(user): confirm URL — the page must be published there before App Review.
    static let privacy = URL(string: "https://sonia6891.github.io/etftogo/privacy")!

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
        /// Only what this build delivers (ruling R33): the free card names no limit the app does not enforce, and
        /// 口袋會員 only what membership really gates (`Skins.isUnlocked`).
        var detail: String {
            switch self {
            case .free: return "記帳、配息、提醒、圖鑑"
            case .pocket: return "成分重疊・回測・目標反推・到價提醒・月報年報・全部皮膚"
            case .ai: return "AI 問答與月報"
            }
        }
        /// Shown, but not for sale yet: no price, no buy button.
        var comingSoon: Bool { self == .ai }
        var product: String? {
            switch self {
            case .free: return nil
            case .pocket: return MembershipProducts.pocketMonthly
            case .ai: return MembershipProducts.aiMonthly
            }
        }
    }

    var body: some View {
        // Measured from outside the page: the room between the status bar and the bottom bar.
        GeometryReader { screen in page(height: screen.size.height) }
        .toolbar(.hidden, for: .navigationBar)
        .task { await membership.start() }
        .alert("口袋會員", isPresented: Binding(get: { membership.message != nil }, set: { if !$0 { membership.message = nil } })) {
            Button("知道了", role: .cancel) { membership.message = nil }
        } message: { Text(membership.message ?? "") }
    }

    /// How tall the page's first block (the crown down to the last plan) is made at least, so that it ends just above
    /// the buy button and what follows starts below it: the page's own top padding and a little air are taken off.
    static func firstScreen(height: CGFloat, footer: CGFloat) -> CGFloat { max(0, height - footer - 8 - 14) }

    private func page(height: CGFloat) -> some View {
        Page {
            // The first screenful: with room to spare the stage is full size and the rest stays empty; on a shorter
            // screen the stage shrinks first, so 會員＋AI is whole above the button rather than cut by it.
            VStack(alignment: .leading, spacing: 18) {
                Text("MBR×001").skinFont(.mono(11)).tracking(1.5).skinForeground(\.sub)
                GeometryReader { room in
                    let size = min(Self.stageSizes.upperBound, max(Self.stageSizes.lowerBound, room.size.height))
                    SkinStage(size: size) { SkinImage(.crown).frame(width: size * 5 / 6, height: size * 5 / 6) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minHeight: Self.stageSizes.lowerBound, maxHeight: Self.stageSizes.upperBound)
                .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text("口袋會員").skinFont(.title(30)).skinForeground(\.ink)
                    SkinTag(membership.isMember ? "你是會員・全部皮膚已解鎖" : "看懂・規劃・回顧")
                }
                .frame(maxWidth: .infinity)
                // Only the stage gives way: the cards have a least height (44) they would otherwise be pressed down
                // to before it, with their text spilling over the edges.
                skinsEntry.fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 10) { ForEach(Plan.allCases) { planCard($0) } }.fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: Self.firstScreen(height: height, footer: footer), alignment: .top)
            if membership.failed && !membership.loading {
                Button { Task { await membership.loadProducts() } } label: { Text("再試一次") }
                    .buttonStyle(SkinButtonStyle(primary: false, seed: 3))
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("member-retry")
            }
            Text("訂閱會自動續訂，可隨時在 App Store 的訂閱設定取消；價格以 App Store 顯示為準。")
                .skinFont(.body(11)).skinForeground(\.sub).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        // The main button stays on screen above the bottom bar, whatever the phone's height (spec 5.10).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 2) {
                Button { if let id = plan.product { Task { await membership.purchase(id) } } } label: { Text(buyTitle) }
                    .buttonStyle(SkinButtonStyle(primary: true, seed: 7))
                    .disabled(buyDisabled)
                    .accessibilityIdentifier("member-buy")
                HStack(spacing: 6) {
                    Button { Task { await membership.restore() } } label: { Text("恢復購買").frame(minHeight: 44).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityIdentifier("member-restore")
                    Text("·").accessibilityHidden(true)
                    Link(destination: Self.terms) { Text("條款").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityIdentifier("member-terms")
                    Text("·").accessibilityHidden(true)
                    Link(destination: Self.privacy) { Text("隱私權").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityIdentifier("member-privacy")
                    Text("·").accessibilityHidden(true)
                    Text("隨時可取消")
                }
                .skinFont(.mono(12)).skinForeground(\.sub)
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity)
            .background(skin.color(\.page))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footer = $0 }
        }
    }

    /// The selected plan is already this Apple ID's.
    private var ownsPlan: Bool { plan.product.map { membership.owned.contains($0) } ?? !membership.isMember }
    private var buyTitle: String {
        if plan == .free { return membership.isMember ? "免費版" : "目前使用免費版" }
        return ownsPlan ? "目前方案" : "選這個方案"
    }
    private var buyDisabled: Bool {
        guard let id = plan.product else { return true }
        return ownsPlan || membership.products[id] == nil
    }

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
        if item.comingSoon { return AnyView(comingSoonCard(item)) }
        return AnyView(sellableCard(item))
    }

    /// 會員＋AI: the plan as a plain card with 「即將推出」, never selectable and never sold.
    private func comingSoonCard(_ item: Plan) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).skinFont(.title(15)).skinForeground(\.sub)
                detailText(item).skinFont(.body(11)).skinForeground(\.sub)
            }
            Spacer(minLength: 8)
            SkinTag("即將推出")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(PlanBackground(selected: false).opacity(0.6))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("member-plan-\(item.rawValue)")
    }

    private func sellableCard(_ item: Plan) -> some View {
        let selected = plan == item
        // 選中的反白並打勾: the chosen card is filled with the main colour, its text in whichever of page or ink reads on it.
        let text = selected ? skin.onFill(skin.colors.accent) : skin.color(\.ink)
        let detail = selected ? skin.onFill(skin.colors.accent) : skin.color(\.sub)
        return Button { plan = item; Haptics.tick() } label: {
            HStack(spacing: 12) {
                SkinCheck(done: selected)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).skinFont(.title(15)).foregroundStyle(text)
                    detailText(item).skinFont(.body(11)).foregroundStyle(detail)
                }
                Spacer(minLength: 8)
                price(item).foregroundStyle(detail)
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
                let known = membership.products[id].map { "\($0.displayPrice) / \(Self.period($0))" }
                let text = Text(PlanPrice.text(product: known, loading: membership.loading, demoStore: Self.demoStore))
                // The two placeholders are read out as what they mean.
                if known != nil || Self.demoStore { text } else { text.accessibilityLabel(membership.loading ? "價格讀取中" : "價格暫時無法取得") }
            } else {
                Text("免費")
            }
        }
        .skinFont(.mono(12)).lineLimit(1)
    }

    static let detailSeparator = "・"

    /// A plan's detail cut after a 「・」 into `count` lines (two or three) whose longest is as short as can be; the
    /// detail whole when it has too few parts to cut.
    static func detailLines(_ detail: String, count: Int) -> [String] {
        let terms = detail.components(separatedBy: detailSeparator)
        guard (2...3).contains(count), terms.count >= count else { return [detail] }
        func line(_ range: Range<Int>) -> String {
            terms[range].joined(separator: detailSeparator) + (range.upperBound < terms.count ? detailSeparator : "")
        }
        var best = [detail], width = Int.max
        for first in 1..<terms.count {
            let seconds = count == 2 ? [terms.count] : Array((first + 1)..<terms.count)
            for second in seconds {
                let lines = count == 2 ? [line(0..<first), line(first..<second)] : [line(0..<first), line(first..<second), line(second..<terms.count)]
                let longest = lines.map(\.count).max() ?? 0
                if longest < width { best = lines; width = longest }
            }
        }
        return best
    }

    /// The detail on one line when the card is wide enough, else on two or three lines that each end at a 「・」: a
    /// line never breaks inside a word, so no 「部皮膚」 is left alone on the last one.
    @ViewBuilder private func detailText(_ item: Plan) -> some View {
        if item.detail.contains(Self.detailSeparator) {
            ViewThatFits(in: .horizontal) {
                Text(item.detail).lineLimit(1)
                VStack(alignment: .leading, spacing: 1) { ForEach(Self.detailLines(item.detail, count: 2), id: \.self) { Text($0).lineLimit(1) } }
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Self.detailLines(item.detail, count: 3), id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
                }
            }
        } else {
            Text(item.detail).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 「月」, 「年」, 「3 個月」…: the billing period as the App Store states it, never assumed.
    static func period(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "次" }
        let unit: String
        switch period.unit {
        case .day: unit = "天"
        case .week: unit = "週"
        case .month: unit = period.value == 1 ? "月" : "個月"
        case .year: unit = "年"
        @unknown default: unit = "期"
        }
        return period.value == 1 ? unit : "\(period.value) \(unit)"
    }
}

/// A plan card: the skin's card; the chosen one filled with the main colour (反白).
private struct PlanBackground: View {
    @Environment(\.skin) private var skin
    let selected: Bool
    var body: some View {
        let fill = selected ? skin.color(\.accent) : skin.color(\.card)
        switch skin.style.button {
        case .hex:
            RoundedRectangle(cornerRadius: 22).fill(fill)
        case .pixelBlock:
            Rectangle().fill(fill).hardShadow(skin.extra(2, or: \.line))
        case .paperStitch:
            RoundedRectangle(cornerRadius: 14).fill(fill).paperShadow()
                .overlay(StitchSeam(color: selected ? skin.color(\.card) : skin.color(\.dim), cornerRadius: 14, inset: 5, lineWidth: 1.5))
        case .sketchBox:
            SketchBoxShape(seed: 11, overshoot: false).fill(fill)
                .overlay(SketchBoxShape(seed: 11).stroke(selected ? skin.color(\.ink) : skin.color(\.line), style: StrokeStyle(lineWidth: selected ? 2.5 : 1.5, lineCap: .round)))
        }
    }
}
