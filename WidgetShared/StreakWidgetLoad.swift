import Foundation

/// Where the 「連續定投」 widget's file lives. The app (`WidgetSync`, the writer) and the widget extension
/// (`StreakProvider`, the reader) both compile this file, so they cannot disagree on the name or the folder.
enum WidgetFile {
    static let name = "widget.json"

    /// The App Group's folder, from the target's own Info.plist key `ETFAppGroup` (`$(APP_GROUP_ID)`). Nil when the
    /// key is missing or unresolved, or when iOS gives no container. On an unsigned build (the simulator CI) the
    /// container *may* be nil: the simulator does not reliably enforce group entitlements, so it may also be a folder.
    static func groupDirectory(bundle: Bundle = .main) -> URL? {
        guard let id = bundle.object(forInfoDictionaryKey: "ETFAppGroup") as? String, !id.isEmpty, !id.contains("$(") else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }
}

/// What the widget found when it looked for the app's file. "No file" and "a file it could not read" are told apart:
/// the first is a newbie (or an unsigned build) and lasts until the month turns; the second is usually a phone that has
/// not been unlocked since it restarted (the file is protected until then), so the widget draws a redacted
/// placeholder and asks again in 15 minutes, never 「今天開始」 over a real streak.
enum StreakWidgetLoad: Equatable {
    /// No App Group folder, or no file in it.
    case missing
    /// The file is there but cannot be opened yet, or does not decode (damaged, or from a newer app).
    case unreadable
    case snapshot(WidgetSnapshot)

    /// How soon an unreadable file is tried again.
    static let retryInterval: TimeInterval = 15 * 60

    static func load(directory: URL?, now: Date) -> StreakWidgetLoad {
        guard let directory else { return .missing }
        let url = directory.appendingPathComponent(WidgetFile.name)
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url), let snapshot = WidgetSnapshot.decode(data) else { return .unreadable }
        return .snapshot(snapshot)
    }

    /// When WidgetKit should ask for the next timeline: the next Taipei month start, or in 15 minutes for an
    /// unreadable file.
    func reloadDate(after now: Date) -> Date {
        if case .unreadable = self { return now.addingTimeInterval(Self.retryInterval) }
        return WidgetSnapshot.nextMonthStart(after: now)
    }

    /// True when the widget should draw its placeholder, redacted, instead of a snapshot.
    var redacted: Bool { self == .unreadable }

    /// The snapshot the widget draws: the file's, the newbie state for no file, or a sample (drawn redacted) for an
    /// unreadable one.
    func snapshot(now: Date) -> WidgetSnapshot {
        switch self {
        case .missing: return .newbie(now: now)
        case .unreadable: return .sample(streak: 12, done: 2, now: now)
        case .snapshot(let s): return s
        }
    }
}
