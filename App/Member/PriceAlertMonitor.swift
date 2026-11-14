import BackgroundTasks
import Foundation
import UserNotifications

extension PortfolioStore {
    // The list itself (`alerts`) and its file are in `PortfolioStore`: every change below is one `saveAlerts`, which
    // writes the alerts' own file and never the records.

    /// The list as a `Portfolio` holds it, for the rules written there (`addAlert`, `fireAlerts`, `mergeAlerts`).
    private var alertBook: Portfolio {
        var book = Portfolio()
        book.alerts = alerts
        return book
    }

    func addAlert(symbol: String, above: Bool, price: Double) throws {
        var next = alertBook
        try next.addAlert(symbol: symbol, above: above, price: price)
        try saveAlerts(next.alerts ?? [])
    }

    /// Switches an alert on or off. One that fired keeps the time it fired when it is switched on again.
    func setAlert(_ id: UUID, enabled: Bool) throws {
        var list = alerts
        guard let i = list.firstIndex(where: { $0.id == id }), list[i].enabled != enabled else { return }
        list[i].enabled = enabled
        try saveAlerts(list)
    }

    func removeAlert(_ id: UUID) throws {
        guard alerts.contains(where: { $0.id == id }) else { return }
        try saveAlerts(alerts.filter { $0.id != id })
    }

    /// Marks these alerts as fired at `now`, switched off, and saves the list; returns them as they are now. Saved
    /// before anything is said about them, so an alert can never be announced twice.
    func fireAlerts(_ ids: [UUID], now: Date) throws -> [PriceAlert] {
        var next = alertBook
        let fired = next.fireAlerts(ids, now: now)
        if !fired.isEmpty { try saveAlerts(next.alerts ?? []) }
        return fired
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

/// True for the first caller only, whichever thread it is on.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// Lets a check through at most once in `gap`.
struct CheckGate {
    let gap: TimeInterval
    /// When the last check that was let through began; nil until the first one.
    private(set) var last: Date?
    init(gap: TimeInterval) { self.gap = gap }

    /// Whether a check may begin at `now`; when it may, `now` is remembered as the last one.
    mutating func open(at now: Date) -> Bool {
        // A clock that was set back does not hold the checks up until it catches up again.
        if let last, now >= last, now.timeIntervalSince(last) < gap { return false }
        last = now
        return true
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
    /// The least time between two checks made because the app came to the front: someone going in and out of the app
    /// does not have every watched code asked for again each time.
    static let foregroundGap: TimeInterval = 300
    @MainActor private static var foregroundGate = CheckGate(gap: foregroundGap)

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
            // The run and the expiration handler are on different threads; whichever comes first reports, once.
            let finished = OnceFlag()
            let work = Task { @MainActor in
                await runInBackground()
                let success = !Task.isCancelled
                if finished.claim() { task.setTaskCompleted(success: success) }
            }
            // iOS is out of patience: it is told at once that the task is over, without waiting for the requests
            // under way to stop. (Weak: the task keeps this handler, so the handler must not keep the task.)
            task.expirationHandler = { [weak task] in
                work.cancel()
                if finished.claim() { task?.setTaskCompleted(success: false) }
            }
        }
    }

    /// One background run: the request for the next run, then the check.
    @MainActor private static func runInBackground() async {
        // Background runs mostly come while the phone is locked. The records cannot be opened then (they are read
        // here if they can be, see `PortfolioStore.reloadIfLocked`), and the check does not need them: the alerts
        // have their own file, the prices are the day's closes, and what fires is saved to the alerts' file.
        store?.reloadIfLocked()
        // Asked for before the check: a run that iOS cuts short is reported as over at once, and the app may be
        // suspended before anything after the check runs. StoreKit is heard first: at a launch in the background it
        // has not answered yet, and `scheduleNext` would take a member for none and take the request back.
        _ = await memberNow()
        // iOS ended the run while StoreKit was answering: it has been reported as over, nothing more is done.
        guard !Task.isCancelled else { return }
        scheduleNext()
        await check()
        // An alert that fired is switched off: with nothing left to watch the request is taken back.
        scheduleNext()
    }

    /// The check made each time the app comes to the front. One that would begin within `foregroundGap` of the last
    /// does nothing. Background runs and the check after adding an alert go straight to `check()`.
    @MainActor static func checkOnReturn(now: Date = Date()) async {
        guard foregroundGate.open(at: now) else { return }
        await check()
    }

    /// The app's own store, checked with the real membership, quotes and notifications. Locked records do not stop
    /// it: nothing it reads or writes is in them.
    @MainActor static func check() async {
        guard let store else { return }
        await check(store)
    }

    /// The prices a check is judged on. With the records open: the usual quiet refresh (富果 with a key, else the
    /// day's closes), saved with the records. With the records locked the phone is locked: the keychain that holds
    /// the 富果 key is closed too and nothing may be written to the records, so only the day's closes are fetched;
    /// they go to their own file, which is not protected that way.
    @MainActor static func refreshPrices(_ store: PortfolioStore, _ symbols: [String]) async {
        if store.recordsLocked { await store.refreshDaily(manual: true) } else { await store.refresh(symbols: symbols, quiet: true) }
    }

    /// Refreshes the prices of the codes being watched, then fires what is due: each alert is switched off with the
    /// time it fired (saved first, so it can never fire twice), then its notification is posted. Membership is read
    /// here every time: a lapsed member's alerts stay in the list and are never fired.
    @MainActor static func check(_ store: PortfolioStore, now: Date = Date(),
                      isMember: () async -> Bool = { await PriceAlertMonitor.memberNow() },
                      refresh: (PortfolioStore, [String]) async -> Void = { await PriceAlertMonitor.refreshPrices($0, $1) },
                      notify: (PriceAlert, Double) async -> Void = { await PriceAlertMonitor.post($0, price: $1) }) async {
        let watched = Set(store.alerts.filter(\.enabled).map(\.symbol))
        guard !watched.isEmpty, await isMember() else { return }
        await refresh(store, watched.sorted())
        let member = await isMember()
        // From here to the save nothing waits: the list is read, judged and saved in one go, so two checks that
        // overlap cannot both fire the same alert.
        var prices: [String: Double] = [:]
        for symbol in Set(store.alerts.filter(\.enabled).map(\.symbol)) { prices[symbol] = store.alertPrice(symbol, now: now) }
        // Saved to the alerts' own file, before any notification; a save that fails says nothing.
        guard let fired = try? store.fireAlerts(AlertEngine.due(store.alerts, prices: prices, isMember: member), now: now), !fired.isEmpty else { return }
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
        // While nothing can be said about the alerts (their file cannot be opened before the first unlock; an earlier
        // build's alerts are still in locked records), the run that got here was asked for while there were some, so
        // it is asked for again.
        guard store.alertsUnknown || AlertEngine.watching(store.alerts, isMember: MembershipStore.shared.has(.priceAlerts)) else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(interval)
        // Refused where background refresh is switched off (or in the simulator): the checks on opening the app remain.
        try? BGTaskScheduler.shared.submit(request)
    }
}
