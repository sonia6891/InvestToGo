import Foundation
import UserNotifications

/// The pending-notification calls the debit-day reminder makes: the system's center in the app, a fake in tests.
@MainActor protocol ReminderCenter: AnyObject {
    func pendingIDs() async -> [String]
    func remove(_ ids: [String])
    func add(_ request: DCAReminderRequest) async
}

/// `UNUserNotificationCenter`, one one-shot calendar notification per planned request.
@MainActor final class SystemReminderCenter: ReminderCenter {
    private var center: UNUserNotificationCenter { .current() }

    func pendingIDs() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func remove(_ ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func add(_ request: DCAReminderRequest) async {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.userInfo = request.userInfo
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: request.fire)
        try? await center.add(UNNotificationRequest(identifier: request.id, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }
}

/// Replaces the pending debit-day reminders with the plan for the latest inputs, one run at a time (final review I1).
///
/// Every call stores its inputs as the latest and joins the run in progress, or starts one. The run checks for newer
/// inputs after every await and starts over when it finds some, so a run for older inputs never adds its requests
/// after a newer one has planned: no 前一天 reminder after 「前一天也提醒」 is turned off, no reminder for a month
/// already logged, none after the reminder is turned off, and no amount after 「通知顯示金額」 is turned off. Once
/// the plan is added it reads the pending list once more and removes any own id the plan does not have.
///
/// A caller whose task is cancelled (`.task(id:)` with new inputs) only stops waiting: the run carries on toward the
/// latest inputs, which the newer call has already stored.
@MainActor final class DCAReminderSync {
    static let shared = DCAReminderSync(center: SystemReminderCenter())

    private let center: ReminderCenter
    private let now: () -> Date
    /// What the pending reminders must end up as; nil: none.
    private(set) var latest: DCAReminderInputs?
    /// Bumped by every call, so a run can tell its inputs were replaced while it waited.
    private(set) var generation = 0
    private var running: Task<Void, Never>?

    init(center: ReminderCenter, now: @escaping () -> Date = Date.init) {
        self.center = center
        self.now = now
    }

    /// Returns once the pending reminders match the latest inputs (these, unless a newer call came meanwhile).
    func sync(_ inputs: DCAReminderInputs?) async {
        latest = inputs
        generation += 1
        let run: Task<Void, Never>
        if let running {
            run = running
        } else {
            run = Task { [weak self] in
                await self?.run()
                self?.running = nil
            }
            running = run
        }
        await run.value
    }

    private func run() async {
        while true {
            let started = generation, inputs = latest
            let plan = inputs.map { DCAReminderPlan.requests($0, now: now()) } ?? []
            let pending = await center.pendingIDs()
            guard started == generation else { continue }
            center.remove(DCAReminders.ownIDs(in: pending))
            var replaced = false
            for request in plan {
                guard started == generation else { replaced = true; break }
                await center.add(request)
            }
            if replaced || started != generation { continue }
            // Anything another run left behind, or an add that landed late: not in the plan, so not pending.
            let wanted = Set(plan.map(\.id))
            let after = await center.pendingIDs()
            guard started == generation else { continue }
            let stale = DCAReminders.ownIDs(in: after).filter { !wanted.contains($0) }
            if !stale.isEmpty { center.remove(stale) }
            return
        }
    }
}
