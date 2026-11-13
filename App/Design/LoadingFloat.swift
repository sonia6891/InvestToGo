import SwiftUI

/// Loading (spec 9 載入中): the skin's object floating gently with 「讀取中」 in the mono face, in place of a spinner.
/// With Reduce Motion the object stays still.
struct LoadingFloat: View {
    var art: SkinArtName = .pocketIcon
    var text = "讀取中"
    var size: CGFloat = 36
    @Environment(\.motionReduced) private var reduceMotion
    @State private var up = false

    var body: some View {
        HStack(spacing: 10) {
            SkinImage(art).frame(width: size, height: size)
                .offset(y: reduceMotion ? 0 : (up ? -4 : 4))
                .accessibilityHidden(true)
            Text(text).skinFont(.mono(12)).skinForeground(\.sub)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("loading-float")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { up = true }
        }
    }
}
