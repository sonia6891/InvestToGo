import SwiftUI

/// 開機 (spec 5.1): the skin's rays around the stage with the 3D 「$」, the skin's code and name, the line
/// 「存 ETF，也存下好習慣。」 and 「→ 輕點開始 ←」. A tap anywhere starts.
struct SplashView: View {
    let onStart: () -> Void
    @Environment(\.skin) private var skin

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 16)
            SkinStage(size: 220) { SkinImage(.heroDollar).padding(42) }
                .background { SkinDecor(page: .splash).frame(width: 390, height: 320).allowsHitTesting(false) }
                .accessibilityHidden(true)
                .padding(.bottom, 22)
            Text(skin.code.replacingOccurrences(of: " ", with: "×")).skinFont(.mono(12)).tracking(2).foregroundStyle(skin.color(\.sub))
            Text("ETF 袋著走").skinFont(.title(34)).foregroundStyle(skin.color(\.ink))
            SkinTag(skin.name)
            Text("存 ETF，也存下好習慣。").skinFont(.body(15)).foregroundStyle(skin.color(\.sub)).padding(.top, 4)
            Spacer(minLength: 16)
            Button(action: onStart) {
                Text("→ 輕點開始 ←").skinFont(.mono(13)).foregroundStyle(skin.color(\.dim))
                    .frame(minWidth: 200, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("輕點開始")
            .accessibilityIdentifier("splash")
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onStart)
        .background(skin.color(\.page).ignoresSafeArea())
    }
}
