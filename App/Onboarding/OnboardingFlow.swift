import SwiftUI
import UserNotifications

/// Where a launch starts the first-launch flow (spec 5.1, 5.2), or nil for the lobby.
enum OnboardingStart: Equatable { case splash, page(Int) }

enum Onboarding {
    /// Set once the first-launch flow has been finished; every later launch opens on the lobby.
    static let doneKey = "onboarded"
    /// What the flow asked, kept for the features that will use them (plan, reminders).
    static let monthlyKey = "onboarding.monthly"
    static let symbolKey = "onboarding.symbol"
    static let dayKey = "onboarding.debitDay"
    static let remindKey = "onboarding.remind"
    static let remindMinutesKey = "onboarding.remindMinutes"
    static let remindEveKey = "onboarding.remindEve"
    static let keys = [doneKey, monthlyKey, symbolKey, dayKey, remindKey, remindMinutesKey, remindEveKey]

    static let amounts = [1000, 3000, 5000, 10000]
    static let starters = ["0050", "006208", "00878"]
    static let days = Array(3...9)
    static let pageCount = 4

    /// A first launch opens on the splash; once onboarded, the lobby. With `--ui-testing` only: `--skip-onboarding`
    /// goes to the lobby, and `--open splash` / `--open onboarding [--page n]` open the flow even when onboarded
    /// (screenshots).
    static func start(_ arguments: [String], onboarded: Bool) -> OnboardingStart? {
        let testing = arguments.contains("--ui-testing")
        if testing, let i = arguments.firstIndex(of: "--open"), arguments.indices.contains(i + 1) {
            switch arguments[i + 1] {
            case "splash": return .splash
            case "onboarding":
                var page = 1
                if let j = arguments.firstIndex(of: "--page"), arguments.indices.contains(j + 1), let n = Int(arguments[j + 1]) {
                    page = min(max(n, 1), pageCount)
                }
                return .page(page)
            default: break
            }
        }
        if onboarded || (testing && arguments.contains("--skip-onboarding")) { return nil }
        return .splash
    }

    /// `--ui-testing --reset` starts as a fresh install: the flow shows again and remembers nothing.
    static func reset(_ arguments: [String], defaults: UserDefaults = .standard) {
        guard arguments.contains("--ui-testing"), arguments.contains("--reset") else { return }
        for key in keys { defaults.removeObject(forKey: key) }
    }
}

/// The first launch: the splash, then the four onboarding pages, then the lobby. Full screen, no bottom bar.
struct FirstLaunchView: View {
    let onFinish: () -> Void
    /// 0 is the splash; 1–4 the onboarding pages.
    @State private var page: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(start: OnboardingStart, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        switch start {
        case .splash: _page = State(initialValue: 0)
        case .page(let n): _page = State(initialValue: n)
        }
    }

    var body: some View {
        ZStack {
            if page == 0 {
                SplashView { withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.35)) { page = 1 } }
                    .transition(.opacity)
            } else {
                OnboardingFlow(page: $page, onFinish: onFinish)
                    .transition(.opacity)
            }
        }
    }
}

/// The four onboarding pages (spec 5.2): habit, amount and ETF, reminders, login. A four-part progress bar on top;
/// 「‹ 返回」 goes back a page and keeps every choice made.
struct OnboardingFlow: View {
    @Binding var page: Int
    let onFinish: () -> Void
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.skin) private var skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var habit: Habit?
    @State private var amount: Int?
    @State private var symbol: String?
    @State private var searchingOther = false
    @State private var otherSymbol = ""
    @State private var day: Int?
    @State private var remind = false
    @State private var remindTime = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    @State private var remindEve = false
    @State private var note: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch page {
                    case 1: habitPage
                    case 2: amountPage
                    case 3: reminderPage
                    default: loginPage
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
                .id(page)
                .transition(.opacity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom) {
            if page < Onboarding.pageCount {
                SkinButton("下一步") { go(page + 1) }
                    .accessibilityIdentifier("onboarding-next")
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(skin.color(\.page))
            }
        }
        .background(skin.color(\.page).ignoresSafeArea())
    }

    private func go(_ next: Int) {
        withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.25)) { page = next }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            if page > 1 {
                Button { go(page - 1) } label: {
                    Text("‹ 返回").skinFont(.title(14)).foregroundStyle(skin.color(\.ink))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")
                .accessibilityIdentifier("onboarding-back")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            HStack(spacing: 6) {
                ForEach(1...Onboarding.pageCount, id: \.self) { i in
                    Capsule().fill(i <= page ? skin.color(\.accent) : skin.color(\.line)).frame(height: 5)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("第 \(page) 步，共 \(Onboarding.pageCount) 步")
            .accessibilityIdentifier("onboarding-progress")
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
    }

    private func heading(_ step: Int, _ title: String, _ subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STEP×\(String(format: "%02d", step))").skinFont(.mono(11)).tracking(1.5).foregroundStyle(skin.color(\.sub))
            Text(title).skinFont(.title(26)).foregroundStyle(skin.color(\.ink))
            if let subtitle { Text(subtitle).skinFont(.body(14)).foregroundStyle(skin.color(\.sub)) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: 1 Habit

    private var habitPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading(1, "想養成哪個習慣？", "之後的本月任務會跟著它挑。")
            ForEach(Habit.allCases, id: \.self) { item in habitCard(item) }
        }
    }

    private func habitCard(_ item: Habit) -> some View {
        let selected = habit == item
        let text = Self.habitText(item)
        return Button { habit = item } label: {
            HStack(spacing: 14) {
                SkinStage(size: 64) { SkinImage(Self.habitArt(item)).padding(13) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(text.title).skinFont(.title(18))
                    Text(text.subtitle).skinFont(.body(13)).opacity(0.75)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? skin.color(\.page) : skin.color(\.ink))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(selected ? skin.color(\.ink) : skin.color(\.card)))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(skin.color(\.line), lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text.title)
        .accessibilityHint(text.subtitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("habit-\(item.rawValue)")
    }

    static func habitText(_ habit: Habit) -> (title: String, subtitle: String) {
        switch habit {
        case .dca: return ("定期定額", "每月固定買一點，不看盤也能存")
        case .dividends: return ("領息", "記下每一筆配息，看它慢慢變多")
        case .savingGoal: return ("存錢目標", "朝一個目標，一個月一個月存")
        }
    }

    static func habitArt(_ habit: Habit) -> SkinArtName {
        switch habit {
        case .dca: return .heroDollar
        case .dividends: return .dividends
        case .savingGoal: return .goal
        }
    }

    // MARK: 2 Amount and ETF

    private var amountPage: some View {
        let grid = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        return VStack(alignment: .leading, spacing: 18) {
            heading(2, "每月投入多少？", "之後隨時可以改。")
            LazyVGrid(columns: grid, spacing: 8) {
                ForEach(Onboarding.amounts, id: \.self) { value in
                    SkinChip(value.formatted(), selected: amount == value) { amount = value }
                        .accessibilityLabel("每月 \(value.formatted()) 元")
                        .accessibilityIdentifier("amount-\(value)")
                }
            }
            Text("想買哪一檔 ETF？").skinFont(.title(18)).foregroundStyle(skin.color(\.ink)).padding(.top, 6)
            LazyVGrid(columns: grid, spacing: 8) {
                ForEach(Onboarding.starters, id: \.self) { code in
                    SkinChip(code, selected: !searchingOther && symbol == code) { searchingOther = false; symbol = code }
                        .accessibilityLabel([code, store.name(for: code)].joined(separator: " "))
                        .accessibilityIdentifier("etf-\(code)")
                }
                SkinChip("搜尋其他", selected: searchingOther) { searchingOther = true }
                    .accessibilityIdentifier("etf-other")
            }
            if searchingOther {
                SkinSearchField(text: $otherSymbol, prompt: "輸入代碼，例：00919", identifier: "etf-other-field")
            }
            if let code = chosenSymbol, let fund = store.funds.first(where: { $0.id == code }) {
                Text("\(fund.id) \(fund.name)").skinFont(.body(14)).foregroundStyle(skin.color(\.sub))
            }
        }
    }

    private var chosenSymbol: String? {
        if searchingOther {
            let code = otherSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return code.isEmpty ? nil : code
        }
        return symbol
    }

    // MARK: 3 Reminders

    private var reminderPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading(3, "什麼時候提醒你？", "選每月扣款的日子。")
            Text("扣款日").skinFont(.title(16)).foregroundStyle(skin.color(\.ink))
            HStack(spacing: 4) {
                ForEach(Onboarding.days, id: \.self) { value in dayButton(value) }
            }
            .frame(maxWidth: .infinity)
            SkinCard {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(get: { remind }, set: { value in Task { await setRemind(value) } })) {
                        Text("扣款日提醒").skinFont(.title(15))
                    }
                    .tint(skin.color(\.accent))
                    .disabled(day == nil)
                    .accessibilityIdentifier("remind-toggle")
                    if day == nil { Text("先選扣款日，才能開提醒。").skinFont(.body(12)).foregroundStyle(skin.color(\.sub)) }
                    DatePicker(selection: $remindTime, displayedComponents: .hourAndMinute) {
                        Text("提醒時間").skinFont(.body(14))
                    }
                    .disabled(!remind)
                    Toggle(isOn: $remindEve) { Text("前一天也提醒").skinFont(.body(14)) }
                        .tint(skin.color(\.accent))
                        .disabled(!remind)
                    if let note { Text(note).skinFont(.body(12)).foregroundStyle(skin.color(\.sub)) }
                }
            }
        }
    }

    private func dayButton(_ value: Int) -> some View {
        let selected = day == value
        return Button { day = value } label: {
            Text("\(value)").skinFont(.big(selected ? 22 : 17))
                .foregroundStyle(selected ? skin.onFill(skin.colors.accent) : skin.color(\.ink))
                .frame(width: 44, height: 44)
                .background(Circle().fill(selected ? skin.color(\.accent) : skin.color(\.card)))
                .overlay(Circle().strokeBorder(skin.color(\.line), lineWidth: selected ? 0 : 1.5))
                .scaleEffect(selected ? 1.12 : 1)
                .animation(reduceMotion ? nil : .snappy, value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("每月 \(value) 日")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("day-\(value)")
    }

    /// The same permission flow as 配息提醒 (`DividendReminders.requestAccess`).
    private func setRemind(_ value: Bool) async {
        guard value, day != nil else { remind = false; note = nil; return }
        if await DividendReminders.requestAccess() {
            remind = true; note = nil
        } else {
            remind = false; note = "未取得通知權限，可到 iPhone 設定 › 通知 開啟。"
        }
    }

    // MARK: 4 Login

    private var loginPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading(4, "登入，資料跟著你走", "登入即將開放；現在可以先開始，資料存在這支 iPhone。")
            VStack(spacing: 12) {
                Button(action: finish) { Label("使用 Apple 登入", systemImage: "apple.logo") }
                    .buttonStyle(SkinButtonStyle(primary: true))
                    .accessibilityIdentifier("login-apple")
                Button(action: finish) { Text("使用 Google 登入") }
                    .buttonStyle(SkinButtonStyle(primary: false))
                    .accessibilityIdentifier("login-google")
                Button(action: finish) {
                    Text("用 Email 連結登入").skinFont(.body(14)).underline().foregroundStyle(skin.color(\.ink))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("login-email")
            }
            .frame(maxWidth: .infinity)
            Text("繼續即表示你同意服務條款與隱私權政策。").skinFont(.mono(11)).foregroundStyle(skin.color(\.sub))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            Button(action: finish) {
                Text("稍後再說").skinFont(.title(15)).foregroundStyle(skin.color(\.sub))
                    .frame(minWidth: 120, minHeight: 44)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("login-later")
        }
    }

    // MARK: Finish

    /// Every login button and 稍後再說 lead to the lobby for now (sign-in is planned separately, 2026-11-11 文件).
    private func finish() {
        let defaults = UserDefaults.standard
        if let amount { defaults.set(amount, forKey: Onboarding.monthlyKey) }
        if let code = chosenSymbol { defaults.set(code, forKey: Onboarding.symbolKey) }
        if let day { defaults.set(day, forKey: Onboarding.dayKey) }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: remindTime)
        let minutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
        defaults.set(remind && day != nil, forKey: Onboarding.remindKey)
        defaults.set(minutes, forKey: Onboarding.remindMinutesKey)
        defaults.set(remindEve, forKey: Onboarding.remindEveKey)
        if let habit { try? store.updateGame { $0.habit = habit } }
        // Off, or no day: no debit-day reminder is left over from an earlier choice.
        if remind, let day { Task { await DCAReminders.schedule(day: day, minutes: minutes, dayBefore: remindEve) } }
        else { DCAReminders.clear() }
        onFinish()
    }
}

/// The monthly debit-day reminder chosen in onboarding, repeating every month at the chosen time.
enum DCAReminders {
    static let ids = ["dca-reminder", "dca-reminder-eve"]
    static func clear() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids) }
    static func schedule(day: Int, minutes: Int, dayBefore: Bool) async {
        let center = UNUserNotificationCenter.current()
        clear()
        var requests = [(ids[0], day, "今天是每月 \(day) 日的扣款日，記得確認定期定額。")]
        if dayBefore { requests.append((ids[1], day - 1, "明天是每月 \(day) 日的扣款日。")) }
        for (id, fireDay, body) in requests {
            var parts = DateComponents()
            parts.day = fireDay; parts.hour = minutes / 60; parts.minute = minutes % 60
            let content = UNMutableNotificationContent()
            content.title = "定期定額提醒"
            content.body = body
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)))
        }
    }
}
