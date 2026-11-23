import SwiftUI
import WidgetKit

// The 「連續定投」 widget's views. This file is compiled into the app (the in-app preview and the tests) and into the
// widget extension. System fonts only, in the skin's colours. No amount appears anywhere.

private extension Color {
    /// 0xRRGGBB as the skins store it (the app's own `Color(rgb:)` is in SkinStore.swift, outside the extension).
    init(widgetRGB value: UInt32) {
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

/// The skin's page colour with a 6 pt band of its main colour along the top edge. The accent is only ever a fill,
/// never text (on sketch it is a 1.4:1 highlighter).
struct StreakWidgetBackground: View {
    let skin: Skin
    var body: some View {
        ZStack(alignment: .top) {
            Color(widgetRGB: skin.colors.page)
            Rectangle().fill(Color(widgetRGB: skin.colors.accent)).frame(height: 6)
        }
    }
}

/// The big number and the words around it. The medium tile, which has the room, also shows the best run after a
/// break (「最長紀錄 5 個月」).
struct StreakSmallView: View {
    let snapshot: WidgetSnapshot
    let skin: Skin
    var showsRecord = false
    var body: some View {
        let hero = WidgetHero.of(snapshot)
        VStack(alignment: .leading, spacing: 0) {
            Text(hero.top)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(widgetRGB: skin.colors.sub))
                .lineLimit(1)
            Text("\(hero.value)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(Color(widgetRGB: skin.colors.ink))
            Text(hero.bottom)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(widgetRGB: skin.colors.sub))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if showsRecord, let record = hero.record {
                Text(record)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(widgetRGB: skin.colors.sub))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// The small block on the left and this month's quests on the right.
struct StreakMediumView: View {
    let snapshot: WidgetSnapshot
    let skin: Skin
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            StreakSmallView(snapshot: snapshot, skin: skin, showsRecord: true).frame(width: 116)
            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.questLine)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(widgetRGB: skin.colors.sub))
                    .lineLimit(1)
                ForEach(Array(snapshot.quests.prefix(3).enumerated()), id: \.offset) { _, quest in
                    HStack(spacing: 6) {
                        Image(systemName: quest.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(widgetRGB: quest.done ? skin.colors.ink : skin.colors.sub))
                        Text(quest.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(widgetRGB: skin.colors.ink))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// What the widget draws for a family: the content, what VoiceOver says, the tap target and the background.
struct StreakWidgetView: View {
    let snapshot: WidgetSnapshot
    let skin: Skin
    let family: WidgetFamily
    /// The widget could not read the app's file yet (`StreakWidgetLoad.unreadable`): the tile is drawn as a redacted
    /// placeholder and VoiceOver says only the widget's name, so no made-up number is shown or spoken.
    var redacted = false

    var body: some View {
        content
            .redacted(reason: redacted ? .placeholder : [])
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(redacted ? Self.placeholderLabel : Self.spoken(snapshot, family: family))
            .widgetURL(AppURL.lobby)
            .containerBackground(for: .widget) { StreakWidgetBackground(skin: skin) }
    }

    @ViewBuilder private var content: some View {
        if family == .systemMedium { StreakMediumView(snapshot: snapshot, skin: skin) } else { StreakSmallView(snapshot: snapshot, skin: skin) }
    }

    /// What VoiceOver says for the redacted placeholder.
    static let placeholderLabel = "連續定投"

    /// 「連續定投 12 個月」 or 「第 1 個月，今天開始」 (the lobby's words); after a break the medium widget, which shows
    /// it, adds 「，最長紀錄 5 個月」, and the medium widget always ends with 「，本月任務 2/3」.
    static func spoken(_ s: WidgetSnapshot, family: WidgetFamily) -> String {
        let hero = WidgetHero.of(s)
        let medium = family == .systemMedium
        var line: String
        if s.streak > 0 { line = "\(hero.top) \(hero.value) \(hero.bottom)" }
        else { line = [hero.bottom, hero.top, medium ? hero.record : nil].compactMap { $0 }.joined(separator: "，") }
        if medium { line += "，\(s.questLine)" }
        return line
    }
}

extension WidgetSnapshot {
    /// A made-up snapshot for the gallery, the in-app preview and the tests: DCA quests of `now`'s month, the first
    /// `done` of them ticked.
    static func sample(streak: Int, longest: Int? = nil, done: Int, isNewbie: Bool = false, skinID: String = "blackgold", now: Date) -> WidgetSnapshot {
        let month = YearMonth(now)
        let quests = Quests.forMonth(month, habit: .dca, isNewbie: isNewbie).enumerated().map { WidgetQuest(id: $1.id, title: $1.title, done: $0 < done) }
        return WidgetSnapshot(version: version, writtenAt: now, month: month.key, streak: streak, longestStreak: longest ?? streak,
                              isNewbie: isNewbie, habit: .dca, dcaMonths: [], quests: quests, skinID: skinID)
    }
}
