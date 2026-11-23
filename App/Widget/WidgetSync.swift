import Foundation
import WidgetKit

/// Keeps `widget.json` in the App Group up to date: the small, amount-free file the 「連續定投」 widget reads.
/// It is written after every save, on every return to the foreground and on every skin change, and only when
/// what the widget shows would differ (`writtenAt` is ignored in the comparison).
@MainActor final class WidgetSync {
    static let fileName = "widget.json"
    static let shared = WidgetSync(directory: WidgetSync.groupDirectory(),
                                   reload: { WidgetCenter.shared.reloadAllTimelines() },
                                   skinID: { SkinStore.shared.skin.id },
                                   locked: { true })

    private let directory: URL?
    private let reload: () -> Void
    private let skinID: () -> String
    private let now: () -> Date
    /// True while iOS will not let the app read the records: a locked store never writes a newbie snapshot over a
    /// real one. `shared` starts locked, so nothing is written before the store exists.
    var locked: () -> Bool
    private(set) var writes = 0
    /// The last snapshot written (or read once from the file), without its time.
    private var last: WidgetSnapshot?
    private var lastLoaded = false

    init(directory: URL?, reload: @escaping () -> Void, skinID: @escaping () -> String, locked: @escaping () -> Bool,
         now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.reload = reload
        self.skinID = skinID
        self.locked = locked
        self.now = now
    }

    /// The App Group's folder; nil when the build is unsigned (the simulator CI), where nothing is written.
    nonisolated static func groupDirectory() -> URL? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "ETFAppGroup") as? String, !id.isEmpty, !id.contains("$(") else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    func sync(_ p: Portfolio) {
        guard let directory, !locked() else { return }
        let url = directory.appendingPathComponent(Self.fileName)
        let snapshot = WidgetSnapshot.of(p, skinID: skinID(), now: now())
        if !lastLoaded {
            lastLoaded = true
            if let data = try? Data(contentsOf: url) { last = WidgetSnapshot.decode(data)?.unchanged }
        }
        if last == snapshot.unchanged { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { return }
        last = snapshot.unchanged
        writes += 1
        reload()
    }
}
