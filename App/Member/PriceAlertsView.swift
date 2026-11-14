import SwiftUI
import UserNotifications

/// 到價提醒 (spec 5.7, 口袋會員): one price to watch per alert, 高於 or 低於. An alert fires once and is switched off; its
/// switch turns it on again. Prices are checked when the app is opened and when iOS runs the background check.
struct PriceAlertsView: View {
    @EnvironmentObject private var store: PortfolioStore
    @State private var symbolText: String
    @State private var above = true
    @State private var targetText = ""
    @State private var formError: String?
    /// Notifications are switched off for the app: said under the form, with where to switch them on.
    @State private var notificationsOff = false
    @FocusState private var focus: Field?
    private enum Field { case symbol, price }

    private static let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    private static let notificationsOffText = "未取得通知權限，可到 iPhone 設定 › 通知 開啟。"

    /// `symbol`: the code the form starts with (「設到價提醒」 on a fund's 詳情).
    init(symbol: String? = nil) { _symbolText = State(initialValue: symbol ?? "") }

    private var code: String { symbolText.trimmingCharacters(in: .whitespaces).uppercased() }
    private var full: Bool { store.alerts.count >= AlertEngine.limit }

    var body: some View {
        Page {
            MemberLock(.priceAlerts) { alerts } preview: { preview }
            Text("沒有富果金鑰時，以每日收盤價判斷；iPhone 會在背景不定時檢查，不保證即時。")
                .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("price-alerts-note")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { VStack(spacing: 0) { Text("到價提醒").font(.headline).foregroundStyle(Palette.ink); Text("價格到了你設定的數字就通知").font(.caption2).foregroundStyle(Palette.muted) } } }
        // Reading the setting never asks for permission; asking waits for the first alert (`add`), or for alerts that
        // are here without `add` ever having run on this phone (restored from a backup): without the question they
        // would be judged and fired with no notification allowed to show.
        .task {
            guard MembershipStore.shared.has(.priceAlerts) else { return }
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if Self.asksPermissionOnAppear(status: status, hasAlerts: !store.alerts.isEmpty, testing: Self.testing) {
                notificationsOff = !(await DividendReminders.requestAccess())
            } else if !store.alerts.isEmpty {
                notificationsOff = status == .denied
            }
        }
    }

    /// Whether opening the screen asks for the notification permission: there are alerts, iOS has never been asked,
    /// and this is not a UI test (which must never meet the system's prompt).
    static func asksPermissionOnAppear(status: UNAuthorizationStatus, hasAlerts: Bool, testing: Bool) -> Bool {
        hasAlerts && status == .notDetermined && !testing
    }

    // MARK: Member

    @ViewBuilder private var alerts: some View {
        Card {
            Text("新增提醒").font(.caption).foregroundStyle(Palette.muted)
            FieldRow(title: "代號", bar: true) {
                TextField("例如 0050", text: $symbolText)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled().monospacedDigit()
                    .focused($focus, equals: .symbol)
                    .accessibilityIdentifier("price-alert-symbol")
            }
            if let known { Text(known).font(.caption).monospacedDigit().foregroundStyle(Palette.muted).padding(.top, 2) }
            Picker("條件", selection: $above) {
                Text("高於").tag(true)
                Text("低於").tag(false)
            }
            .pickerStyle(.segmented).padding(.vertical, 8).accessibilityIdentifier("price-alert-direction")
            FieldRow(title: "價格", bar: true) {
                HStack(spacing: 6) {
                    TextField("價格", text: $targetText).keyboardType(.decimalPad).monospacedDigit()
                        .focused($focus, equals: .price)
                        .accessibilityIdentifier("price-alert-price")
                    Text("元").font(.caption).foregroundStyle(Palette.muted)
                }
            }
            if let formError {
                Text(formError).font(.caption).foregroundStyle(Palette.red).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6).accessibilityIdentifier("price-alert-error")
            }
            if full {
                Text("已經有 \(AlertEngine.limit) 個提醒（上限）。先刪除不用的，才能再加。").font(.caption).foregroundStyle(Palette.red)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10).accessibilityIdentifier("price-alert-full")
            } else {
                Button { add() } label: { PrimaryButtonLabel(title: "加入提醒", icon: "bell.badge") }
                    .buttonStyle(.plain).padding(.top, 10).accessibilityIdentifier("price-alert-add")
            }
            if notificationsOff {
                Text(Self.notificationsOffText).font(.caption).foregroundStyle(Palette.red).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
        }
        Card {
            Text("我的提醒 \(store.alerts.count)／\(AlertEngine.limit)").font(.caption).monospacedDigit().foregroundStyle(Palette.muted)
                .accessibilityIdentifier("price-alert-count")
            if store.alerts.isEmpty {
                Text("還沒有提醒。").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 8)
            }
            ForEach(store.alerts) { row($0) }
            Text("每個提醒到價一次後自動停用，打開開關可以再提醒一次。").font(.caption).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
        }
    }

    /// 「目前 205.50（2026/11/13）」 for the code being typed, when a price is known.
    private var known: String? {
        guard DataChecks.code(code), let quote = store.quote(code) else { return nil }
        return "\(store.name(for: code))・目前 \(priceText(quote.price))（\(quote.date.replacingOccurrences(of: "-", with: "/"))）"
    }

    private func row(_ alert: PriceAlert) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(alert.symbol).font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.ink)
                    Text(store.name(for: alert.symbol)).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Text(alert.condition).font(.headline).monospacedDigit().foregroundStyle(Palette.ink)
                    .accessibilityIdentifier("price-alert-condition-\(alert.symbol)")
                Text(Self.status(alert)).font(.caption).monospacedDigit().foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { alert.enabled }, set: { value in change { try store.setAlert(alert.id, enabled: value) } }))
                .labelsHidden()
                .accessibilityLabel("\(alert.symbol) \(alert.condition) 提醒")
                .accessibilityIdentifier("price-alert-switch-\(alert.symbol)")
            Button { change { try store.removeAlert(alert.id) } } label: { Image(systemName: "trash").foregroundStyle(Palette.muted) }
                .buttonStyle(.plain).frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("刪除 \(alert.symbol) \(alert.condition)")
        }
        .padding(.top, 12)
    }

    /// 「監看中」, 「11/14 已到價，提醒已停用」 or 「已停用」.
    static func status(_ alert: PriceAlert) -> String {
        if alert.enabled { return alert.firedAt.map { "監看中・上次到價 \(monthDay($0))" } ?? "監看中" }
        if let fired = alert.firedAt { return "\(monthDay(fired)) 已到價，提醒已停用" }
        return "已停用"
    }

    private func change(_ action: () throws -> Void) {
        do { try action(); formError = nil } catch { formError = error.localizedDescription }
    }

    private func add() {
        formError = nil
        let symbol = code
        guard DataChecks.code(symbol), store.funds.contains(where: { $0.id == symbol }) || store.quote(symbol) != nil else {
            formError = "找不到這個代號，請確認後再試。"; return
        }
        let price: Double
        do { price = try Self.price(from: targetText) } catch { formError = error.localizedDescription; return }
        do { try store.addAlert(symbol: symbol, above: above, price: price) } catch { formError = error.localizedDescription; return }
        targetText = ""; focus = nil
        // UI tests stop here: no permission prompt, no request for prices.
        guard !Self.testing else { return }
        Task {
            // Asked with the first alert, never earlier; later alerts only read the answer.
            notificationsOff = !(await DividendReminders.requestAccess())
            await PriceAlertMonitor.check()
        }
    }

    /// The price typed into the form, or what is wrong with it.
    static func price(from text: String) throws -> Double {
        guard let price = Double(text.replacingOccurrences(of: ",", with: "")), price > 0 else { throw AppDataError("請輸入大於 0 的價格。") }
        guard price <= AlertEngine.maxPrice else { throw AppDataError("價格太大了，請確認後再試。") }
        return price
    }

    // MARK: Preview behind the lock

    /// Made-up alerts: what the screen looks like, never anyone's own.
    private var preview: some View {
        Card {
            Text("我的提醒").font(.caption).foregroundStyle(Palette.muted)
            ForEach([("範例 ETF A", "高於 200", "監看中", true), ("範例 ETF B", "低於 18.5", "11/13 已到價，提醒已停用", false)], id: \.0) { item in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0).font(.subheadline.bold()).foregroundStyle(Palette.ink)
                        Text(item.1).font(.headline).foregroundStyle(Palette.ink)
                        Text(item.2).font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: .constant(item.3)).labelsHidden()
                }
                .padding(.top, 12)
            }
        }
    }
}
