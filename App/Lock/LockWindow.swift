import SwiftUI
import UIKit
import Combine

/// The lock screen and the privacy cover, in a window of their own above the app's: they cover every sheet,
/// full-screen cover (LEVEL×UP) and alert as well, which a view inside the app's window could not. Hidden, it takes no
/// touches; shown with the lock, it is the key window, so VoiceOver reads only the lock screen.
@MainActor final class LockWindow {
    static let shared = LockWindow()
    private var window: UIWindow?
    private var watching: AnyCancellable?
    private var hiding: DispatchWorkItem?

    /// Called once the app's window is in its scene (`LockWindowAnchor`).
    func attach(to scene: UIWindowScene) {
        guard window?.windowScene !== scene else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let host = UIHostingController(rootView: LockOverlay())
        host.view.backgroundColor = .clear
        host.view.accessibilityViewIsModal = true
        window.rootViewController = host
        window.backgroundColor = .clear
        window.isHidden = true
        self.window = window
        let lock = AppLock.shared
        // @Published sends the new values as they change; the first pair is the state now.
        watching = Publishers.CombineLatest(lock.$locked, lock.$covered)
            .sink { [weak self] locked, covered in self?.show(locked: locked, covered: covered) }
    }

    private func show(locked: Bool, covered: Bool) {
        guard let window else { return }
        if locked || covered {
            hiding?.cancel()
            hiding = nil
            if window.isHidden { window.isHidden = false }
            if locked, !window.isKeyWindow { window.makeKey() }
        } else {
            // After the lock screen's fade.
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            hiding = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    private func hide() {
        guard let window else { return }
        hiding = nil
        window.isHidden = true
        window.windowScene?.windows.first { $0 !== window && !$0.isHidden && $0.windowLevel == .normal }?.makeKey()
    }
}

/// Finds the app's window scene for `LockWindow`. Invisible, takes no touches.
struct LockWindowAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }
    func updateUIView(_ view: AnchorView, context: Context) {}

    final class AnchorView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scene = window?.windowScene { LockWindow.shared.attach(to: scene) }
        }
    }
}

/// What the lock window shows: the lock screen, or the cover while the app is away from the front.
struct LockOverlay: View {
    @ObservedObject private var lock = AppLock.shared
    @ObservedObject private var skins = SkinStore.shared

    var body: some View {
        ZStack {
            if lock.locked {
                AppLockScreen().transition(.opacity)
            } else if lock.covered {
                LockCover()
            } else {
                Color.clear
            }
        }
        .environment(\.skin, skins.skin)
        .preferredColorScheme(skins.colorScheme)
    }
}
