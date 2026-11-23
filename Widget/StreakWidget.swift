import SwiftUI
import WidgetKit

struct StreakEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// The file was there but could not be read (a phone not unlocked since it restarted): drawn as a placeholder.
    var redacted = false
}

/// Reads the app's `widget.json` from the App Group; makes no network request. Without the file (an unsigned build,
/// a first launch) it shows the newbie state until the month turns; with a file it cannot read yet, a redacted
/// placeholder that is tried again in 15 minutes (`StreakWidgetLoad`).
struct StreakProvider: TimelineProvider {
    private static func sample(_ now: Date) -> WidgetSnapshot { .sample(streak: 12, done: 2, now: now) }

    private static func load(now: Date) -> StreakWidgetLoad {
        StreakWidgetLoad.load(directory: WidgetFile.groupDirectory(), now: now)
    }

    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), snapshot: Self.sample(Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        let now = Date()
        if context.isPreview { return completion(StreakEntry(date: now, snapshot: Self.sample(now))) }
        let load = Self.load(now: now)
        completion(StreakEntry(date: now, snapshot: load.snapshot(now: now).display(at: now), redacted: load.redacted))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let now = Date()
        let load = Self.load(now: now)
        let reload = load.reloadDate(after: now)
        let snapshot = load.snapshot(now: now)
        // One entry now and, for a file read (or none), one at the next Taipei month start, where the timeline ends.
        let dates = load.redacted ? [now] : [now, reload]
        let entries = dates.map { StreakEntry(date: $0, snapshot: snapshot.display(at: $0), redacted: load.redacted) }
        completion(Timeline(entries: entries, policy: .after(reload)))
    }
}

struct StreakEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry
    var body: some View {
        StreakWidgetView(snapshot: entry.snapshot, skin: Skins.named(entry.snapshot.skinID), family: family, redacted: entry.redacted)
    }
}

struct StreakWidget: Widget {
    let kind = "StreakWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakProvider()) { entry in
            StreakEntryView(entry: entry)
        }
        .configurationDisplayName("連續定投")
        .description("連續定投的月數與本月任務")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main struct ETFToGoWidgets: WidgetBundle {
    var body: some Widget { StreakWidget() }
}
