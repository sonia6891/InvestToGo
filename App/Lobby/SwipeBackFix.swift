import UIKit

/// With the navigation bar hidden (lobby, pocket, tools), UIKit turns off the swipe from the left edge. This keeps
/// it on whenever there is a screen to go back to (spec 4.3: 左緣右滑回上一層).
///
/// Trade-off: it applies to every navigation controller in the app, not only the lobby's stack, and it replaces
/// UIKit's own delegate for the edge-swipe recogniser. UIKit's delegate also blocks the swipe while a push is still
/// animating; here only "is there a screen below" is checked. Remove this once SwiftUI keeps the swipe with a
/// hidden bar.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer == interactivePopGestureRecognizer ? viewControllers.count > 1 : true
    }
}
