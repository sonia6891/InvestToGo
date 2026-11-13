import SwiftUI

/// The gate of every 口袋會員 screen: a member sees `content`; anyone else sees `preview` (dimmed, not touchable, hidden
/// from VoiceOver) under a card that names the feature and opens 會員.
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
            ZStack(alignment: .top) {
                preview
                    .opacity(0.35)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                lockCard.padding(16)
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
