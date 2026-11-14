import BackgroundTasks
import Foundation
import UserNotifications

extension PortfolioStore {
    /// 到價提醒, in the order they were added.
    var alerts: [PriceAlert] { data.alerts ?? [] }

    func addAlert(symbol: String, above: Bool, price: Double) throws {
        var next = data
        try next.addAlert(symbol: symbol, above: above, price: price)
        try commit(next)
    }

    /// Switches an alert on or off. One that fired keeps the time it fired when it is switched on again.
    func setAlert(_ id: UUID, enabled: Bool) throws {
        var next = data
        guard let i = next.alerts?.firstIndex(where: { $0.id == id }), next.alerts?[i].enabled != enabled else { return }
        next.alerts?[i].enabled = enabled
        try commit(next)
    }

    func removeAlert(_ id: UUID) throws {
        var next = data
        guard next.alerts?.contains(where: { $0.id == id }) == true else { return }
        next.alerts?.removeAll { $0.id == id }
        try commit(next)
    }

    /// The price an alert is judged on: the newest one known for the code (`quote`), unless it is a trial match or its
    /// trading day is over a week back. An old price (the one bundled with the app, or the last one fetched before a
    /// long time offline) must never fire an alert.
    func alertPrice(_ symbol: String, now: Date = Date()) -> Double? {
        guard let quote = quote(symbol), quote.trial != true, AlertEngine.isCurrent(day: quote.date, now: now) else { return nil }
        return quote.price
    }
}

/// Lets a 到價提醒 show as a banner while the app is open: the check on returning to the app is the one that runs most
/// often, and iOS shows nothing for a notification that arrives in the foreground unless the app says to. Every
/// other notification (配息提醒, 扣款日提醒) stays as it was: not shown over the open app.
final class PriceAlertPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(notification.request.identifier.hasPrefix(PriceAlertMonitor.notificationPrefix) ? [.banner, .list, .sound] : [])
    }
}

/// 到價提醒's checks (spec 5.7, 做法 A): when the app comes to the front, and when iOS runs the background refresh task.
/// Nothing leaves the phone but the codes whose prices are asked for, as for any quote refresh.
enum PriceAlertMonitor {
    /// The background task; the same string is in Info.plist's BGTaskSchedulerPermittedIdentifiers (project.yml).
    static let identifier = "tw.sonia.etftogo.alerts"
    static let notificationPrefix = "price-alert-"
    /// How long iOS is asked to wait before the next background check; it decides the real time itself.
    static let interval: TimeInterval = 3600

    @MainActor private static weak var store: PortfolioStore?
    /// The background task has its launch handler: only then may a request be submitted (iOS stops the app otherwise).
    @MainActor private static var registered = false
    @MainActor private static let presenter = PriceAlertPresenter()

    /// Once, from the app's `init`: iOS wants the task's handler registered before launch ends. With `testing`
    /// (`--ui-testing`) only the store is kept: no background task, no notifications.
    @MainActor static func start(_ store: PortfolioStore, testing: Bool) {
        self.store = store
        guard !testing, !registered else { return }
        UNUserNotificationCenter.current().delegate = presenter
        registered = registerTask()
    }

    /// iOS calls the handler on a queue of its own, so it is made here, outside the main actor; the work hops over.
    private static func registerTask() -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let work = Task { @MainActor in
                await runInBackground()
                task.setTaskCompleted(success: !Task.isCancelled)
            }
            // iOS is out of patience: the requests under way stop, and the task is still marked as finished above.
            task.expirationHandler = { work.cancel() }
        }
    }

    /// One background run: the check, then the request for the next run.
    @MainActor private static func runInBackground() async {
        // On a locked phone the records cannot be opened (see `PortfolioStore.reloadIfLocked`): nothing to check yet.
        if let store, store.reloadIfLocked() { await check() }
        scheduleNext()
    }

    /// The app's own store, checked with the real membership, quotes and notifications.
    @MainActor static func check() async {
        guard let store, !store.recordsLocked else { return }
        await check(store)
    }

    /// Refreshes the prices of the codes being watched, then fires what is due: each alert is switched off with the
    /// time it fired (saved first, so it can never fire twice), then its notification is posted. Membership is read
    /// here every time: a lapsed member's alerts stay in the list and are never fired.
    @MainActor static func check(_ store: PortfolioStore, now: Date = Date(),
                      isMember: () async -> Bool = { await PriceAlertMonitor.memberNow() },
                      refresh: (PortfolioStore, [String]) async -> Void = { await $0.refresh(symbols: $1, quiet: true) },
                      notify: (PriceAlert, Double) async -> Void = { await PriceAlertMonitor.post($0, price: $1) }) async {
        let watched = Set(store.alerts.filter(\.enabled).map(\.symbol))
        guard !watched.isEmpty, await isMember() else { return }
        await refresh(store, watched.sorted())
        let member = await isMember()
        // From here to the save nothing waits: the list is read, judged and saved in one go, so two checks that
        // overlap cannot both fire the same alert.
        var next = store.data
        var prices: [String: Double] = [:]
        for symbol in Set((next.alerts ?? []).filter(\.enabled).map(\.symbol)) { prices[symbol] = store.alertPrice(symbol, now: now) }
        let fired = next.fireAlerts(AlertEngine.due(next.alerts ?? [], prices: prices, isMember: member), now: now)
        guard !fired.isEmpty else { return }
        do { try store.commit(next) } catch { return }
        for alert in fired { if let price = prices[alert.symbol] { await notify(alert, price) } }
    }

    /// Whether this person is a member right now. A launch in the background can get here before StoreKit has
    /// answered for the first time, so a "no" is asked once more before it is believed.
    @MainActor static func memberNow() async -> Bool {
        let membership = MembershipStore.shared
        if !membership.has(.priceAlerts) { await membership.refreshMembership() }
        return membership.has(.priceAlerts)
    }

    /// 「0050 已到 205.5，你設定的是高於 200。」 Posted at once; it also stays in the phone's notification centre.
    static func post(_ alert: PriceAlert, price: Double) async {
        let content = UNMutableNotificationContent()
        content.title = "到價提醒"
        content.body = AlertEngine.message(alert, price: price)
        content.sound = .default
        let request = UNNotificationRequest(identifier: notificationPrefix + alert.id.uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Asks iOS for a background check in an hour or later while a member has an alert switched on; otherwise takes
    /// back any request already made (no alerts left, or the membership has lapsed).
    @MainActor static func scheduleNext() {
        guard registered, let store else { return }
        // Records that are still locked say nothing about the alerts; the run that got here was asked for while there
        // were some, so it is asked for again.
        guard store.recordsLocked || AlertEngine.watching(store.alerts, isMember: MembershipStore.shared.has(.priceAlerts)) else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(interval)
        // Refused where background refresh is switched off (or in the simulator): the checks on opening the app remain.
        try? BGTaskScheduler.shared.submit(request)
    }
}
