import Foundation

/// Bundled data files: the package's resource bundle when built with SwiftPM (Linux tests), the app bundle when these
/// sources are compiled into the iOS app target.
enum CoreBundle {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }
}
