import SwiftUI
import WidgetKit

struct StreakEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Reads the app's `widget.json` from the App Group; makes no network request. Without the file (an unsigned build,
/// a first launch, a locked phone) it shows the newbie state.
struct StreakProvider: TimelineProvider {
    /// The same name the app writes (`WidgetSync.fileName`).
    private static let fileName = "widget.json"

    static func load(now: Date) -> WidgetSnapshot {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "ETFAppGroup") as? String, !id.isEmpty, !id.contains("$("),
              let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id),
              let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)),
              let snapshot = WidgetSnapshot.decode(data) else { return .newbie(now: now) }
        return snapshot
    }

    private static func sample(_ now: Date) -> WidgetSnapshot { .sample(streak: 12, done: 2, now: now) }

    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), snapshot: Self.sample(Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        let now = Date()
        completion(StreakEntry(date: now, snapshot: context.isPreview ? Self.sample(now) : Self.load(now: now).display(at: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let now = Date()
        let next = WidgetSnapshot.nextMonthStart(after: now)
        let snapshot = Self.load(now: now)
        let entries = [now, next].map { StreakEntry(date: $0, snapshot: snapshot.display(at: $0)) }
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

struct StreakEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry
    var body: some View {
        StreakWidgetView(snapshot: entry.snapshot, skin: Skins.named(entry.snapshot.skinID), family: family)
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
