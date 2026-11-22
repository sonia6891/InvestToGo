import SwiftUI

// 口袋會員前 7 天全開 (docs/superpowers/specs/2026-11-22-member-open-7-days-design.md), as the lobby shows it, after
// the meow-work app's assets/meow-v4-proopen.js:
//   · the lobby: one line 「口袋會員全開中・11/29（日）14:30 結束・還剩 N 天」 on every day of the 7, which opens 會員;
//   · day 1: one note that the 7 days have started, when they end and that every record stays afterwards;
//   · day 5: one gentle note of what stays free afterwards;
//   · after day 7, to a non-member: one sheet of what was used, the App Store's price and 「訂閱口袋會員」;
//   · 3 days later, once, if still not a member: 「要不要再考慮一下口袋會員？」. Nothing after that.
// The notes come up only over the lobby, once nothing else is over it: never over the opening, onboarding or the lock
// screen (the lobby is built after them, and the lock is checked again here), LEVEL×UP, a sheet, a purchase or a
// keyboard (all of which live on other screens). Each is marked seen as it comes up.

/// To 會員 the way `--open member` stacks it: above 工具, so the bottom bar's 「‹ 大廳」 leads back.
enum MemberOpenRoute {
    static func toMember(_ navigation: LobbyNavigation) {
        navigation.open(.tools)
        navigation.push(.member)
    }
}

/// UI tests: StoreKit's answer is not waited for (the simulator may never give one).
private let memberOpenTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")

/// The lobby's line on every day of the 7.
struct MemberOpenBanner: View {
    @ObservedObject private var membership = MembershipStore.shared
    @Environment(\.lobbyNavigation) private var navigation

    var body: some View {
        if membership.openNow, !membership.isMember, !membership.demoMember, membership.answered || memberOpenTesting,
           let text = MemberOpenCopy.banner(membership.open) {
            Button { MemberOpenRoute.toMember(navigation) } label: {
                SkinCard {
                    HStack(spacing: 10) {
                        MemberCrown().frame(width: 22, height: 22)
                        lines(text).skinFont(.title(13))
                        Spacer(minLength: 4)
                        Text("›").skinFont(.title(18)).skinForeground(\.sub).accessibilityHidden(true)
                    }
                    .frame(minHeight: 28)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text)
            .accessibilityHint("打開口袋會員")
            .accessibilityIdentifier("member-open-banner")
        }
    }

    /// The line breaks only at a 「・」, so no piece of it (「結」/「束」) is split over two lines on a narrow phone.
    private func lines(_ text: String) -> some View {
        ViewThatFits(in: .horizontal) {
            Text(text).lineLimit(1)
            VStack(alignment: .leading, spacing: 1) { ForEach(MemberView.detailLines(text, count: 2), id: \.self) { Text($0).lineLimit(1) } }
            VStack(alignment: .leading, spacing: 1) {
                ForEach(MemberView.detailLines(text, count: 3), id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

/// The four notes, over the lobby. `ready`: the lobby is on screen with nothing over it (no LEVEL×UP up or due, no
/// replay playing, the records read).
struct MemberOpenNotes: ViewModifier {
    let ready: Bool
    @ObservedObject private var membership = MembershipStore.shared
    @ObservedObject private var lock = AppLock.shared
    @ObservedObject private var skins = SkinStore.shared
    @Environment(\.lobbyNavigation) private var navigation
    @Environment(\.scenePhase) private var phase
    @State private var note: MemberOpenNote?
    /// The note's button went to 會員: it opens once the sheet has gone.
    @State private var toMember = false

    /// Nothing stands in the way of a note, and none is up.
    private var clear: Bool {
        ready && note == nil && phase == .active && !lock.locked && !lock.covered && (membership.answered || memberOpenTesting)
    }

    private struct Moment: Equatable {
        var clear: Bool, day: Int, ended: Bool, member: Bool
    }

    func body(content: Content) -> some View {
        content
            .onAppear { membership.refreshOpen() }
            .onChange(of: phase) { _, value in if value == .active { membership.refreshOpen() } }
            // Asked again whenever the way clears or the days move on; a short wait first, so the lobby has settled
            // (its entrance, a replay that is about to start) and the note never pops up in the middle of something.
            .task(id: Moment(clear: clear, day: membership.open.day, ended: membership.open.ended, member: membership.isMember)) {
                guard clear else { return }
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled, clear,
                      let due = membership.memberOpen.due(member: membership.isMember || membership.demoMember) else { return }
                membership.memberOpen.markSeen(due)
                note = due
            }
            .sheet(item: $note, onDismiss: {
                guard toMember else { return }
                toMember = false
                MemberOpenRoute.toMember(navigation)
            }) { item in
                MemberOpenNoteSheet(note: item) { goes in
                    toMember = goes
                    note = nil
                }
                .environment(\.skin, skins.skin)
                .preferredColorScheme(skins.colorScheme)
            }
    }
}

/// One note. `done(true)`: its button goes to 會員.
struct MemberOpenNoteSheet: View {
    let note: MemberOpenNote
    let done: (Bool) -> Void
    @ObservedObject private var membership = MembershipStore.shared
    @Environment(\.skin) private var skin
    private static let demoStore = DemoArguments.has("--demo-store", in: ProcessInfo.processInfo.arguments)

    /// The summary and 「再考慮」 sell the plan: they show its price and period, the renewal line and the terms and
    /// privacy links, as the 會員 page does (App Review 3.1.2).
    private var sells: Bool { note == .ended || note == .again }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()
                    Button { done(false) } label: {
                        Text("×").skinFont(.title(22)).skinForeground(\.sub).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(MemberOpenCopy.close)
                }
                MemberCrown().frame(width: 44, height: 44).frame(maxWidth: .infinity)
                Text(title).skinFont(.title(22)).skinForeground(\.ink)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                content(for: note)
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .background(skin.color(\.page).ignoresSafeArea())
        // The buttons stay at the bottom however long the list is; the note scrolls.
        .safeAreaInset(edge: .bottom, spacing: 0) { buttons }
        .presentationDetents(sells ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(note == .ended ? "member-open-summary" : "member-open-note")
        .task { if sells && membership.products.isEmpty { await membership.loadProducts() } }
    }

    private var title: String {
        switch note {
        case .day1: return MemberOpenCopy.day1Title
        case .day5: return MemberOpenCopy.day5Title(membership.open.daysLeft)
        case .ended: return MemberOpenCopy.endedTitle
        case .again: return MemberOpenCopy.againTitle
        }
    }

    @ViewBuilder private func content(for note: MemberOpenNote) -> some View {
        switch note {
        case .day1:
            if let end = membership.open.end {
                Text(MemberOpenCopy.day1Ends(MemberOpenCopy.endText(end))).skinFont(.title(16)).skinForeground(\.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            lead(MemberOpenCopy.noPayment)
            lead(MemberOpenCopy.day1Lead)
            lead(MemberOpenCopy.day1After)
        case .day5:
            lead(MemberOpenCopy.day5Lead)
            list(MemberOpenCopy.free.map { Row(title: $0, detail: nil) })
            lead(MemberOpenCopy.day5After)
        case .ended:
            priceLine
            let used = membership.memberOpen.usedFeatures()
            if used.isEmpty {
                lead(MemberOpenCopy.endedNone)
            } else {
                lead(MemberOpenCopy.endedUsed)
                list(used.map { Row(title: $0.title, detail: $0.pitch) })
            }
            lead(MemberOpenCopy.endedKept)
            terms
        case .again:
            priceLine
            lead(MemberOpenCopy.againLead)
            let used = membership.memberOpen.usedFeatures()
            list((used.isEmpty ? MemberOpenCopy.againDefault : used).map { Row(title: $0.title, detail: $0.pitch) })
            lead(MemberOpenCopy.againKept)
            terms
        }
    }

    private func lead(_ text: String) -> some View {
        Text(text).skinFont(.body(14)).skinForeground(\.sub)
            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Row: Identifiable {
        let title: String
        let detail: String?
        var id: String { title }
    }

    private func list(_ rows: [Row]) -> some View {
        SkinCard {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 10) {
                        SkinCheck(done: true, size: 18).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).skinFont(.title(14)).skinForeground(\.ink)
                            if let sub = row.detail { Text(sub).skinFont(.body(12)).skinForeground(\.sub).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// The App Store's own price and period, once it has answered (the screenshots' price under `--demo-store`). Before
    /// that no price is said: 「訂閱口袋會員」 opens the 會員 page, which shows it.
    @ViewBuilder private var priceLine: some View {
        if let price {
            Text("口袋會員 \(price)").skinFont(.title(16)).skinForeground(\.ink)
                .frame(maxWidth: .infinity)
        }
    }

    private var price: String? {
        if let product = membership.products[MembershipProducts.pocketMonthly] { return "\(product.displayPrice) / \(MemberView.period(product))" }
        return Self.demoStore ? PlanPrice.demoStore : nil
    }

    private var terms: some View {
        VStack(spacing: 2) {
            Text(MemberOpenCopy.renews).skinFont(.body(11)).skinForeground(\.sub)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Link(destination: MemberView.terms) { Text("條款").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                Text("·").accessibilityHidden(true)
                Link(destination: MemberView.privacy) { Text("隱私權").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
            }
            .skinFont(.mono(12)).skinForeground(\.sub)
        }
        .frame(maxWidth: .infinity)
    }

    private var buttons: some View {
        let (main, mainGoes, other, otherGoes): (String, Bool, String, Bool) = {
            switch note {
            case .day1: return (MemberOpenCopy.start, false, MemberOpenCopy.look, true)
            case .day5: return (MemberOpenCopy.look, true, MemberOpenCopy.gotIt, false)
            case .ended: return (MemberOpenCopy.subscribe, true, MemberOpenCopy.stayFree, false)
            case .again: return (MemberOpenCopy.subscribe, true, MemberOpenCopy.noThanks, false)
            }
        }()
        return VStack(spacing: 8) {
            if sells {
                Button { done(mainGoes) } label: { Text(main).frame(maxWidth: .infinity) }
                    .buttonStyle(SkinButtonStyle(primary: true, seed: 7))
                    .accessibilityIdentifier("member-open-subscribe")
            } else {
                Button { done(mainGoes) } label: { Text(main).frame(maxWidth: .infinity) }
                    .buttonStyle(SkinButtonStyle(primary: true, seed: 7))
            }
            Button { done(otherGoes) } label: { Text(other).frame(maxWidth: .infinity) }
                .buttonStyle(SkinButtonStyle(primary: false, seed: 3))
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(skin.color(\.page))
    }
}
