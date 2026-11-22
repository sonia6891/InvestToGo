import XCTest
@testable import ETFToGo

/// A notification center whose adds can be held in flight, so two syncs interleave as they can on a phone.
@MainActor private final class FakeReminderCenter: ReminderCenter {
    /// Pending id → body.
    var pending: [String: String] = [:]
    var holdAdds = false
    private var held: [CheckedContinuation<Void, Never>] = []
    var heldCount: Int { held.count }

    func pendingIDs() async -> [String] { Array(pending.keys) }
    func remove(_ ids: [String]) { for id in ids { pending[id] = nil } }
    func add(_ request: DCAReminderRequest) async {
        if holdAdds { await withCheckedContinuation { held.append($0) } }
        // Lands after the wait, as a slow `UNUserNotificationCenter.add` does.
        pending[request.id] = request.body
    }
    func release() {
        holdAdds = false
        let waiting = held
        held = []
        waiting.forEach { $0.resume() }
    }
}

final class DCAReminderSyncTests: XCTestCase {
    private let now = GameRules.taipei.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 12))!

    private func inputs(dayBefore: Bool = true, showAmount: Bool = true, logged: Bool = false) -> DCAReminderInputs {
        DCAReminderInputs(day: 6, minutes: 540, dayBefore: dayBefore, showAmount: showAmount, amount: 5000, symbol: "0050",
                          month: YearMonth(now, calendar: GameRules.taipei).key, loggedThisMonth: logged)
    }
    private func plan(_ inputs: DCAReminderInputs) -> [String: String] {
        Dictionary(uniqueKeysWithValues: DCAReminderPlan.requests(inputs, now: now).map { ($0.id, $0.body) })
    }
    @MainActor private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "Timed out")
    }

    /// One sync: the old repeating ids and any stale month go, other notifications stay, the plan is pending.
    @MainActor func testSyncReplacesOwnIDsOnly() async {
        let center = FakeReminderCenter()
        center.pending = ["dca-reminder": "舊", "dca-reminder-eve": "舊", "dca-reminder-2026-10": "舊", "dividend-ABC": "配息", "price-alert-1": "到價"]
        let sync = DCAReminderSync(center: center, now: { self.now })
        await sync.sync(inputs())
        var expected = plan(inputs())
        expected["dividend-ABC"] = "配息"
        expected["price-alert-1"] = "到價"
        XCTAssertEqual(center.pending, expected)
        XCTAssertEqual(center.pending.keys.filter { $0.hasPrefix("dca-reminder") }.count, 24, "Twelve months, each with its eve")
    }

    /// A second sync starts while the first one's add is still in flight: what is pending at the end is the second
    /// one's plan only. No 前一天 id survives 「前一天也提醒」 off, and no body shows the amount once 「通知顯示金額」 is off.
    @MainActor func testOverlappingSyncsEndWithTheLatestInputs() async {
        let center = FakeReminderCenter()
        center.holdAdds = true
        let sync = DCAReminderSync(center: center, now: { self.now })
        let older = inputs(dayBefore: true, showAmount: true), newer = inputs(dayBefore: false, showAmount: false)
        let first = Task { await sync.sync(older) }
        await waitUntil { center.heldCount == 1 }
        let second = Task { await sync.sync(newer) }
        await waitUntil { sync.latest == newer }
        center.release()
        await first.value
        await second.value
        XCTAssertEqual(center.pending, plan(newer))
        XCTAssertFalse(center.pending.keys.contains { $0.contains("-eve-") }, "No 前一天 reminder after it was turned off")
        XCTAssertFalse(center.pending.values.contains { $0.contains("5,000") || $0.contains("0050") }, "No amount after 通知顯示金額 was turned off")
    }

    /// Logged this month, or turned off, while an older sync is in flight: this month's reminder is not put back, and
    /// once off nothing of the reminder stays.
    @MainActor func testLoggedThenTurnedOffWhileInFlight() async {
        let center = FakeReminderCenter()
        center.pending = ["dividend-ABC": "配息"]
        center.holdAdds = true
        let sync = DCAReminderSync(center: center, now: { self.now })
        // Day 25: this month's debit day is still ahead, so the unlogged plan has it and the logged one does not.
        var unlogged = inputs(), logged = inputs(logged: true)
        unlogged.day = 25; logged.day = 25
        XCTAssertNotNil(plan(unlogged)["dca-reminder-2026-11"])
        XCTAssertNil(plan(logged)["dca-reminder-2026-11"])
        let first = Task { await sync.sync(unlogged) }
        await waitUntil { center.heldCount == 1 }
        let second = Task { await sync.sync(logged) }
        await waitUntil { sync.latest == logged }
        center.release()
        await first.value; await second.value
        var expected = plan(logged)
        expected["dividend-ABC"] = "配息"
        XCTAssertEqual(center.pending, expected, "This month is not reminded once it is logged")

        center.holdAdds = true
        let third = Task { await sync.sync(unlogged) }
        await waitUntil { center.heldCount == 1 }
        let off = Task { await sync.sync(nil) }
        await waitUntil { sync.latest == nil }
        center.release()
        await third.value; await off.value
        XCTAssertEqual(center.pending, ["dividend-ABC": "配息"], "Turned off: no debit-day reminder stays")
    }
}
