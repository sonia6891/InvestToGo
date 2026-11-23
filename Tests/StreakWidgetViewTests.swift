import XCTest
import SwiftUI
import WidgetKit
@testable import ETFToGo

@MainActor final class StreakWidgetViewTests: XCTestCase {
    private let now = GameRules.taipei.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 12))!

    func testRendersInEverySkinAndFamily() {
        let sizes: [(WidgetFamily, CGSize)] = [(.systemSmall, CGSize(width: 158, height: 158)), (.systemMedium, CGSize(width: 338, height: 158))]
        let snapshots = [WidgetSnapshot.sample(streak: 12, done: 2, now: now), .sample(streak: 0, longest: 5, done: 0, now: now), .newbie(now: now)]
        for skin in Skins.all {
            for (family, size) in sizes {
                for snapshot in snapshots {
                    for redacted in [false, true] {
                        let view = StreakWidgetView(snapshot: snapshot, skin: skin, family: family, redacted: redacted).frame(width: size.width, height: size.height)
                        let renderer = ImageRenderer(content: view)
                        renderer.scale = 1
                        XCTAssertNotNil(renderer.uiImage, "\(skin.id) \(family) redacted \(redacted) did not render")
                    }
                }
            }
        }
    }

    func testSpokenLabels() {
        let running12 = WidgetSnapshot.sample(streak: 12, done: 0, now: now)
        let running12with2of3 = WidgetSnapshot.sample(streak: 12, done: 2, now: now)
        let broken5 = WidgetSnapshot.sample(streak: 0, longest: 5, done: 0, now: now)
        XCTAssertEqual(StreakWidgetView.spoken(running12, family: .systemSmall), "連續定投 12 個月")
        XCTAssertEqual(StreakWidgetView.spoken(running12with2of3, family: .systemMedium), "連續定投 12 個月，本月任務 2/3")
        // The lobby's words (「第 1 個月，今天開始」); only the medium tile, which shows the best run, says it.
        XCTAssertEqual(StreakWidgetView.spoken(broken5, family: .systemSmall), "第 1 個月，今天開始")
        XCTAssertEqual(StreakWidgetView.spoken(broken5, family: .systemMedium), "第 1 個月，今天開始，最長紀錄 5 個月，本月任務 0/3")
        XCTAssertEqual(StreakWidgetView.spoken(.newbie(now: now), family: .systemSmall), "第 1 個月，今天開始")
        XCTAssertEqual(StreakWidgetView.spoken(.newbie(now: now), family: .systemMedium), "第 1 個月，今天開始，本月任務 0/\(WidgetSnapshot.newbie(now: now).quests.count)")
        XCTAssertEqual(StreakWidgetView.placeholderLabel, "連續定投")
    }
}
