import Foundation
import WidgetKit

/// Keeps `widget.json` in the App Group up to date: the small, amount-free file the 「連續定投」 widget reads.
/// It is written after every save, on every return to the foreground and on every skin change, and only when
/// what the widget shows would differ (`writtenAt` is ignored in the comparison). The name and the folder are
/// `WidgetFile`'s, which the widget compiles too.
@MainActor final class WidgetSync {
    static let shared = WidgetSync(directory: WidgetFile.groupDirectory(),
                                   reload: { WidgetCenter.shared.reloadAllTimelines() },
                                   skinID: { SkinStore.shared.skin.id },
                                   locked: { true },
                                   report: WidgetSync.reportInRelease)

    private let directory: URL?
    private let reload: () -> Void
    private let skinID: () -> String
    private let now: () -> Date
    private let report: (WidgetSyncError) -> Void
    /// True while the records cannot be trusted: iOS will not let the app read them yet (a locked phone), or they
    /// could not be read at all (a damaged file, `PortfolioStore.readFailed`). A locked store never writes a newbie
    /// snapshot over a real one. `shared` starts locked, so nothing is written before the store exists.
    var locked: () -> Bool
    private(set) var writes = 0
    /// The last snapshot written (or read once from the file), without its time.
    private var last: WidgetSnapshot?
    private var lastLoaded = false
    private var reportedNoContainer = false

    init(directory: URL?, reload: @escaping () -> Void, skinID: @escaping () -> String, locked: @escaping () -> Bool,
         now: @escaping () -> Date = Date.init, report: @escaping (WidgetSyncError) -> Void = { _ in }) {
        self.directory = directory
        self.reload = reload
        self.skinID = skinID
        self.locked = locked
        self.now = now
        self.report = report
    }

    /// The gate the app installs: locked while `store` is gone, its records are locked, or they failed to read.
    static func locked(by store: PortfolioStore) -> () -> Bool {
        { [weak store] in
            guard let store else { return true }
            return store.recordsLocked || store.readFailed
        }
    }

    /// A missing container or a failed write, sent to Sentry in a Release build: the only sign from the field that a
    /// build lacks its App Group. The error carries no snapshot content, only what failed. Sentry is off in Debug
    /// builds (and so in the simulator CI, where an unsigned build may have no container).
    private static let reportInRelease: (WidgetSyncError) -> Void = { error in
        #if !DEBUG
        CrashReporting.capture(error, context: error.context, offline: false)
        #endif
    }

    func sync(_ p: Portfolio) {
        guard !locked() else { return }
        guard let directory else {
            if !reportedNoContainer { reportedNoContainer = true; report(.noContainer) }
            return
        }
        let url = directory.appendingPathComponent(WidgetFile.name)
        let snapshot = WidgetSnapshot.of(p, skinID: skinID(), now: now())
        if !lastLoaded {
            lastLoaded = true
            if case .snapshot(let onFile) = StreakWidgetLoad.load(directory: directory, now: now()) { last = onFile.unchanged }
        }
        if last == snapshot.unchanged { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            let ns = error as NSError
            report(.writeFailed(domain: ns.domain, code: ns.code))
            return
        }
        last = snapshot.unchanged
        writes += 1
        reload()
    }

    /// On every return to the foreground: `sync`, and the widget is asked to read its file again even when nothing
    /// was written. A timeline drawn before the first unlock after a restart (the file unreadable then) is replaced
    /// as soon as the app is opened; reloads asked for in the foreground do not count against the widget's budget.
    func returned(_ p: Portfolio) {
        let before = writes
        sync(p)
        if writes == before { reload() }
    }
}

/// What `WidgetSync` reports. Never the snapshot or the file's path: only which step failed and the system's code.
enum WidgetSyncError: Error, Equatable, CustomNSError {
    /// The build has no App Group container (its entitlements lack the group).
    case noContainer
    /// Writing `widget.json` threw.
    case writeFailed(domain: String, code: Int)

    var context: String {
        switch self {
        case .noContainer: return "widget-container"
        case .writeFailed: return "widget-write"
        }
    }

    static var errorDomain: String { "ETFToGo.WidgetSync" }
    var errorCode: Int {
        switch self {
        case .noContainer: return 1
        case .writeFailed: return 2
        }
    }
    var errorUserInfo: [String: Any] {
        switch self {
        case .noContainer: return [:]
        case .writeFailed(let domain, let code): return ["underlyingDomain": domain, "underlyingCode": code]
        }
    }
}
