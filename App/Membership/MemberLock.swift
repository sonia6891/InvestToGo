import SwiftUI

/// The gate of every 口袋會員 screen: a member sees `content`; anyone else sees a card that names the feature and opens
/// 會員, and below it the whole `preview` (dimmed, not touchable, hidden from VoiceOver). The card sits above the
/// preview, not over it: however tall the preview is, none of it is half covered.
struct MemberLock<Content: View, Preview: View>: View {
    @ObservedObject private var membership = MembershipStore.shared
    @Environment(\.lobbyNavigation) private var navigation
    let feature: MemberFeature
    private let content: Content
    private let preview: Preview

    init(_ feature: MemberFeature, @ViewBuilder content: () -> Content, @ViewBuilder preview: () -> Preview) {
        self.feature = feature
        self.content = content()
        self.preview = preview()
    }

    var body: some View {
        if membership.has(feature) {
            content
        } else {
            VStack(spacing: 14) {
                lockCard
                VStack(spacing: 14) { preview }
                    .opacity(0.35)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("member-lock-\(feature.rawValue)")
        }
    }

    private var lockCard: some View {
        SkinCard {
            VStack(spacing: 10) {
                MemberCrown().frame(width: 36, height: 36)
                Text("口袋會員專屬").skinFont(.mono(12)).skinForeground(\.sub)
                Text(feature.title).skinFont(.title(20)).skinForeground(\.ink)
                Text(feature.pitch).skinFont(.body(13)).skinForeground(\.sub)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button { navigation.push(.member) } label: { Text("看看口袋會員") }
                    .buttonStyle(SkinButtonStyle(primary: true, seed: 7))
                    .accessibilityIdentifier("member-lock-open")
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// The small crown on a member tile or lock card.
struct MemberCrown: View {
    var body: some View {
        SkinImage(.crown).accessibilityHidden(true)
    }
}
