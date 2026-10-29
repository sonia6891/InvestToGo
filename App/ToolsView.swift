import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct ToolsView: View {
    var body: some View {
        Page {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("工具中心").font(.title.bold()).foregroundStyle(Palette.ink)
                    Text("各種實用工具，幫助你更聰明投資 ETF").font(.subheadline).foregroundStyle(Palette.muted)
                }
                Spacer()
                Artwork(name: "misc-bulb", size: 56)
            }.padding(.top, 6)
            section("試算", icon: "function", color: Palette.blue) {
                wide("個股＋ETF 組合試算", "3、5、10 年資產預估", art: "tool-compound", route: .combo).accessibilityIdentifier("tool-combo").padding(.bottom, 10)
                HStack(spacing: 10) {
                    tile("股息複利", "複利試算", art: "cat-saving", route: .plan, tint: Palette.pink)
                    tile("領息目標", "達成規劃", art: "tool-goal", route: .goal)
                    tile("定期定額", "投資試算", art: "tool-dca", route: .calculator)
                }
            }
            section("分析", icon: "chart.line.uptrend.xyaxis", color: Palette.green) {
                HStack(spacing: 10) {
                    wide("三檔比較", "績效分析", art: "tool-compare", route: .comparison)
                    wide("持股透視", "成分與集中度", art: "tool-exposure", route: .exposure)
                }
            }
            section("管理", icon: "wrench.and.screwdriver.fill", color: Palette.orange) {
                HStack(spacing: 10) {
                    tile("提醒中心", "重要通知", art: "tool-alerts", route: .notices, tint: Palette.orange)
                    tile("券商資料", "對帳匯入", art: "tool-broker", route: .broker).accessibilityIdentifier("tool-broker")
                    tile("備份資料", "匯出／匯入", art: "tool-backup", route: .backup).accessibilityIdentifier("tool-backup")
                }
            }
            Text("試算都是情境假設，不是預測或保證；比較與透視使用你取得的實際資料。").font(.caption).foregroundStyle(Palette.muted)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
    private func section<Content: View>(_ title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        Card(padding: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.caption.bold()).foregroundStyle(.white).frame(width: 26, height: 26).background(color, in: RoundedRectangle(cornerRadius: 8))
                Text(title).font(.headline).foregroundStyle(Palette.ink)
            }.padding(.bottom, 10)
            content()
        }
    }
    private func tile(_ title: String, _ subtitle: String, art: String, route: AppRoute, tint: Color? = nil) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 3) {
                Artwork(name: art, size: 50)
                Text(title).font(.subheadline.bold()).foregroundStyle(Palette.ink).padding(.top, 4)
                Text(subtitle).font(.caption2).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background((tint ?? Palette.blue).opacity(tint == nil ? 0.06 : 0.14), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
    private func wide(_ title: String, _ subtitle: String, art: String, route: AppRoute) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 10) {
                Artwork(name: art, size: 44)
                VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.bold()).foregroundStyle(Palette.ink); Text(subtitle).font(.caption2).foregroundStyle(Palette.muted) }
                Spacer(minLength: 0)
            }
            .padding(12).frame(maxWidth: .infinity)
            .background(Palette.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
}
enum ComparisonDefaults {
    static func symbols(_ saved: [String]?) -> [String] {
        var result: [String] = []
        for code in (saved ?? []) where result.count < 3 && !result.contains(code) { result.append(code) }
        if result.count >= 2 { return result }
        for code in ["0050", "00878", "00919", "0056", "006208"] where result.count < 3 && !result.contains(code) { result.append(code) }
        return result
    }
}
extension PortfolioStore {
    /// Total change and annualised volatility over the past year of the adjusted history the user fetched.
    func yearStats(_ symbol: String) -> (change: Double, volatility: Double?)? {
        guard let history = data.histories?[symbol] else { return nil }
        let from = DataChecks.day(Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date())
        guard let first = history.points.first, first.date <= from else { return nil }
        var sliced = history; sliced.points = history.points.filter { $0.date >= from }
        guard sliced.points.count >= 20, let stats = try? PerformanceStats(sliced) else { return nil }
        return (stats.change, stats.volatility)
    }
    /// Past-year official distributions per unit divided by the latest price.
    func trailingYield(_ symbol: String) -> Double? {
        guard let price = data.quotes[symbol]?.price, price > 0, let amount = official.trailingAmount(symbol) else { return nil }
        return amount / price * 100
    }
}
struct ComparisonView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var pair = 0
    @State private var busy = false
    @State private var error: String?
    private let colors: [[Color]] = [[Color(red: 0.37, green: 0.64, blue: 1), Palette.blue], [Color(red: 1, green: 0.55, blue: 0.71), Palette.pink], [Color(red: 0.71, green: 0.59, blue: 1), Palette.purple]]
    var body: some View {
        let symbols = ComparisonDefaults.symbols(store.data.comparison)
        let pairs = [(0, 1), (0, 2), (1, 2)].filter { $0.1 < symbols.count }
        let missing = symbols.filter { store.yearStats($0) == nil }
        Page {
            HStack(spacing: 8) { ForEach(0..<3, id: \.self) { chip($0, symbols: symbols) } }
            Card(padding: 12) {
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Text("").frame(width: 84)
                        ForEach(symbols.indices, id: \.self) { i in
                            Text(symbols[i]).font(.subheadline.bold()).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(LinearGradient(colors: colors[i], startPoint: .top, endPoint: .bottom), in: UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10))
                        }
                    }
                    metric("最新價", symbols) { s in store.quote(s).map { priceText($0.price) } ?? "—" }
                    metric("總報酬率\n(1年)", symbols, color: { s in store.yearStats(s).map { Palette.trend($0.change) } ?? Palette.muted }) { s in store.yearStats(s).map { percentText($0.change * 100) } ?? "—" }
                    metric("內扣費用率", symbols) { s in AnnualFeeCatalog.bundled?.records[s].map { "\(decimal($0.total))%" } ?? "未收錄" }
                    metric("風險指標\n(年化波動度)", symbols) { s in store.yearStats(s)?.volatility.map { "\(decimal($0 * 100))%" } ?? "—" }
                    metric("殖利率\n(近1年)", symbols) { s in store.trailingYield(s).map { "\(decimal($0))%" } ?? "—" }
                    metric("配息頻率", symbols) { s in store.official.frequency(s) ?? "—" }
                }
            }
            if !missing.isEmpty {
                Button(busy ? "取得中…" : "取得 \(missing.joined(separator: "、")) 的一年績效資料") { Task { await loadYear(missing) } }
                    .buttonStyle(.bordered).disabled(busy)
                if let error { Text(error).font(.caption).foregroundStyle(Palette.red) }
            }
            if !pairs.isEmpty {
                SegmentBar(items: pairs.map { "\(symbols[$0.0]) × \(symbols[$0.1])" }, selection: $pair, pill: true)
                let current = pairs[min(pair, pairs.count - 1)]
                OverlapPanel(left: symbols[current.0], right: symbols[current.1])
            }
            Text("總報酬率與波動度依還原日收盤價；內扣費用率為公布的年度實際總費用率；殖利率＝近一年官方每單位配息合計 ÷ 最新價。").font(.caption).foregroundStyle(Palette.muted)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { VStack(spacing: 0) { Text("三檔比較").font(.headline).foregroundStyle(Palette.ink); Text("選擇最多三檔 ETF 進行績效與指標比較").font(.caption2).foregroundStyle(Palette.muted) } } }
    }
    private func chip(_ index: Int, symbols: [String]) -> some View {
        let code = symbols.indices.contains(index) ? symbols[index] : nil
        return ZStack(alignment: .topTrailing) {
            Menu {
                ForEach(store.funds) { fund in Button("\(fund.id) \(fund.name)") { set(index, fund.id, symbols: symbols) } }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    if let code {
                        Text(code).font(.subheadline.bold()).foregroundStyle(Palette.ink)
                        Text(store.name(for: code)).font(.caption2).foregroundStyle(Palette.muted).lineLimit(1)
                    } else {
                        Text("＋ 加入").font(.subheadline.bold()).foregroundStyle(Palette.blue).frame(maxWidth: .infinity)
                    }
                }
                .padding(10).padding(.trailing, 14).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: Palette.blue.opacity(0.06), radius: 6, y: 2)
            }
            if let code, symbols.count > 2 {
                Button { remove(index, symbols: symbols) } label: { Image(systemName: "xmark").font(.caption2.bold()).foregroundStyle(Palette.muted).padding(8) }
                    .buttonStyle(.plain).accessibilityLabel("移除 \(code)")
            }
        }
    }
    private func metric(_ title: String, _ symbols: [String], color: ((String) -> Color)? = nil, value: @escaping (String) -> String) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 4) {
                Text(title).font(.caption).foregroundStyle(Palette.muted).frame(width: 84, alignment: .leading)
                ForEach(symbols, id: \.self) { s in Text(value(s)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(color?(s) ?? Palette.ink).frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.7) }
            }.padding(.vertical, 10)
        }
    }
    private func set(_ index: Int, _ code: String, symbols: [String]) {
        var list = symbols
        if index < list.count { list[index] = code } else { list.append(code) }
        save(Array(NSOrderedSet(array: list)) as? [String] ?? list)
    }
    private func remove(_ index: Int, symbols: [String]) { var list = symbols; list.remove(at: index); pair = 0; save(list) }
    private func save(_ list: [String]) { var next = store.data; next.comparison = Array(list.prefix(3)); do { try store.commit(next) } catch { store.message = error.localizedDescription } }
    private func loadYear(_ list: [String]) async {
        busy = true; error = nil
        defer { busy = false }
        for code in list {
            do { try store.saveHistory(await Fugle.history(symbol: code, years: 1)) } catch { self.error = "\(code)：\(error.localizedDescription)"; return }
        }
    }
}
struct CalculatorView: View {
    @State private var initial = "100000"
    @State private var monthly = "5000"
    @State private var years = "10"
    @State private var rate = "4"
    var body: some View {
        let a = Double(initial) ?? -1, b = Double(monthly) ?? -1, y = Int(years) ?? 0, r = Double(rate) ?? 0
        let valid = a >= 0 && b >= 0 && a <= 1e12 && b <= 1e9 && (1...40).contains(y) && r > -50 && r < 50
        let total = valid ? Projection.value(initial: a, monthly: b, years: y, annualPercent: r) : 0
        let principal = valid ? a + b * Double(y * 12) : 0
        Page {
            Card {
                FieldRow(title: "起始本金", bar: true) { UnitField(placeholder: "本金", text: $initial, unit: "元") }
                FieldRow(title: "每月投入", bar: true) { UnitField(placeholder: "每月", text: $monthly, unit: "元") }
                FieldRow(title: "投資年期", bar: true) { UnitField(placeholder: "年", text: $years, unit: "年") }
                FieldRow(title: "預估年報酬率", bar: true) { UnitField(placeholder: "%", text: $rate, unit: "%") }
            }
            Card {
                HStack { Text("試算結果").font(.headline).foregroundStyle(Palette.ink); Spacer(); TintPill(title: "假設試算") }
                if valid {
                    VStack(spacing: 2) { Text("期末試算金額").font(.caption).foregroundStyle(Palette.muted); Text("\(money(total)) 元").font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Palette.blue) }.frame(maxWidth: .infinity).padding(.vertical, 10)
                    LabeledContent("累計投入", value: money(principal))
                    LabeledContent("試算損益") { Text(signed(total - principal)).foregroundStyle(Palette.trend(total - principal)) }.padding(.top, 6)
                } else { Text("請輸入有效且非負的本金與每月投入，年數 1–40 年。").font(.subheadline).foregroundStyle(Palette.red).padding(.top, 8) }
            }
            Text("假設報酬按月平均複利、每月底投入，不含稅費與通膨。這是情境試算，不是預測或保證；負報酬情境下可能虧損本金。").font(.caption).foregroundStyle(Palette.muted)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { VStack(spacing: 0) { Text("定期定額試算").font(.headline).foregroundStyle(Palette.ink); Text("固定每月投入，試算累積成果").font(.caption2).foregroundStyle(Palette.muted) } } }
    }
}
struct GoalView: View {
    @EnvironmentObject var store: PortfolioStore
    @AppStorage("goalMonthlyIncome") private var target = 10000.0
    @AppStorage("goalAssumedYield") private var assumedYield = 5.0
    @AppStorage("goalCapital") private var capital = -1.0
    @State private var targetText = ""
    @State private var capitalText = ""
    @State private var yieldText = ""
    private var lastYearPaid: Double {
        let start = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? Date()
        return store.data.dividends.filter { $0.status == .paid && $0.date >= start && $0.date <= Date() }.reduce(0.0) { $0 + $1.amount }
    }
    var body: some View {
        let money0 = max(capital, 0), yearly = money0 * assumedYield / 100, monthly = yearly / 12
        let rate = target > 0 ? monthly / target : 0, need = assumedYield > 0 ? target * 12 / (assumedYield / 100) : 0, gap = need - money0
        Page {
            Card {
                FieldRow(title: "每月期望領息金額", bar: true) { UnitField(placeholder: "目標", text: $targetText, unit: "元") }
                FieldRow(title: "預計投入資金", bar: true) { UnitField(placeholder: "資金", text: $capitalText, unit: "元") }
                FieldRow(title: "預估殖利率", bar: true) { UnitField(placeholder: "%", text: $yieldText, unit: "%") }
            }
            Button { apply() } label: { PrimaryButtonLabel(title: "開始試算", icon: "function") }.buttonStyle(.plain)
            Card {
                HStack { Label("假設試算結果", systemImage: "target").font(.headline).foregroundStyle(Palette.ink); Spacer(); Text("不代表未來報酬").font(.caption2).foregroundStyle(Palette.muted) }
                HStack(spacing: 8) {
                    result("預期每月領息", "\(money(monthly)) 元", Palette.blue)
                    result("預期每年領息", "\(money(yearly)) 元", Palette.blue)
                    result("達成率", "\(decimal(min(rate, 9.99) * 100))%", Palette.green)
                }.padding(.top, 10)
                ProgressView(value: min(rate, 1)).tint(Palette.green).scaleEffect(x: 1, y: 2.2).padding(.vertical, 12)
                HStack(spacing: 8) {
                    Artwork(name: "misc-bulb", size: 22)
                    Text(gap > 0 ? "再投入 \(money(gap)) 元，預期每月領息可達 \(money(target)) 元" : "目前資金已可達成每月 \(money(target)) 元的目標").font(.subheadline)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
            }
            Card {
                Text("目前進度（近 12 個月已入帳）").font(.headline).foregroundStyle(Palette.ink)
                LabeledContent("平均每月已領", value: money(lastYearPaid / 12)).padding(.top, 10)
                LabeledContent("與目標的比例", value: target > 0 ? "\(decimal(min(lastYearPaid / 12 / target, 9.99) * 100))%" : "—").padding(.top, 6)
            }
            Text("所需本金以固定殖利率估算；配息率不等於報酬率，配息也可能來自本金。這是假設試算，不代表未來報酬。").font(.caption).foregroundStyle(Palette.muted)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { VStack(spacing: 0) { Text("領息目標試算").font(.headline).foregroundStyle(Palette.ink); Text("設定每月領息目標，試算所需資金").font(.caption2).foregroundStyle(Palette.muted) } } }
        .onAppear {
            if capital < 0 { capital = store.data.cost.rounded() }
            targetText = String(Int(target)); capitalText = String(Int(max(capital, 0))); yieldText = decimal(assumedYield)
        }
    }
    private func apply() {
        if let value = Double(targetText.replacingOccurrences(of: ",", with: "")), value >= 0 { target = value }
        if let value = Double(capitalText.replacingOccurrences(of: ",", with: "")), value >= 0 { capital = value }
        if let value = Double(yieldText), value > 0, value <= 30 { assumedYield = value } else { store.message = "請輸入 0–30% 之間的殖利率。" }
    }
    private func result(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption2).foregroundStyle(Palette.muted); Text(value).font(.subheadline.bold()).monospacedDigit().foregroundStyle(color).minimumScaleFactor(0.6).lineLimit(1) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Palette.cardSoft, in: RoundedRectangle(cornerRadius: 12))
    }
}
enum DividendReminders {
    static let key = "dividendReminders"
    private static let prefix = "dividend-"
    static func syncIfEnabled(_ dividends: [Dividend]) async {
        guard UserDefaults.standard.bool(forKey: key) else { return }
        await sync(dividends)
    }
    static func requestAccess() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    /// Schedules a 09:00 reminder on the expected payment day of each announced or estimated dividend.
    @discardableResult static func sync(_ dividends: [Dividend]) async -> Int {
        await clear()
        let center = UNUserNotificationCenter.current()
        let now = Date()
        var scheduled = 0
        for item in dividends.filter({ $0.status != .paid }).sorted(by: { $0.date < $1.date }) where scheduled < 60 {
            var parts = Calendar.current.dateComponents([.year, .month, .day], from: item.date)
            parts.hour = 9
            guard let fire = Calendar.current.date(from: parts), fire > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "配息提醒：\(item.symbol)"
            content.body = "\(item.status.rawValue)配息 $\(money(item.amount)) 預計今天入帳。確認入帳後，可在配息明細按「我已確認入帳」。"
            content.sound = .default
            let request = UNNotificationRequest(identifier: prefix + item.id.uuidString, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            do { try await center.add(request); scheduled += 1 } catch { continue }
        }
        return scheduled
    }
    static func clear() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
    }
}
struct ReminderCenterView: View {
    @EnvironmentObject var store: PortfolioStore
    @AppStorage(DividendReminders.key) private var enabled = false
    @State private var working = false
    @State private var note: String?
    private var upcoming: [Dividend] {
        let today = Calendar.current.startOfDay(for: Date())
        return store.data.dividends.filter { $0.status != .paid && $0.date >= today }.sorted { $0.date < $1.date }
    }
    var body: some View {
        Page {
            Card {
                Toggle(isOn: Binding(get: { enabled }, set: { value in Task { await setEnabled(value) } })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("配息入帳提醒").font(.headline).foregroundStyle(Palette.ink)
                        Text("在已公告／預估配息的預計入帳日早上 9 點通知").font(.caption).foregroundStyle(Palette.muted)
                    }
                }.tint(Palette.blue).disabled(working)
                if let note { Text(note).font(.caption).foregroundStyle(Palette.muted).padding(.top, 10) }
            }
            SectionHeading(title: "即將入帳", subtitle: "依你的配息紀錄")
            if upcoming.isEmpty {
                Card { ContentUnavailableView("目前沒有待入帳配息", systemImage: "bell.slash", description: Text("在配息月曆新增「已公告」或「預估」的紀錄。")) }
            } else {
                Card(padding: 12) { ForEach(upcoming) { item in NavigationLink(value: AppRoute.dividendDetail(item.id)) { DividendDateRow(item: item) }.buttonStyle(.plain) } }
            }
            Card {
                Label("價格與折溢價提醒", systemImage: "chart.line.uptrend.xyaxis").font(.headline).foregroundStyle(Palette.ink)
                Text("需要背景行情服務，目前尚未提供；不會以過期報價觸發通知。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 6)
            }
        }.navigationTitle("提醒中心").navigationBarTitleDisplayMode(.inline)
    }
    private func setEnabled(_ value: Bool) async {
        working = true
        defer { working = false }
        if value {
            guard await DividendReminders.requestAccess() else { enabled = false; note = "未取得通知權限，可到 iPhone 設定 › 通知 開啟。"; return }
            enabled = true
            let count = await DividendReminders.sync(store.data.dividends)
            note = "已排程 \(count) 則提醒。新增或刪除配息紀錄時會自動更新。"
        } else {
            enabled = false
            await DividendReminders.clear()
            note = "已關閉並清除排程提醒。"
        }
    }
}
struct ConnectionView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var key = ""
    @State private var hasKey = false
    @State private var message = ""
    var body: some View { Form {
        Section { Label(hasKey ? "已儲存金鑰" : "尚未設定金鑰", systemImage: hasKey ? "key.fill" : "key").foregroundStyle(hasKey ? Palette.green : .secondary); SecureField("貼上富果 API Key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled(); Button("安全儲存金鑰") { do { guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { message = "請先輸入金鑰。"; return }; try SecureKey.save(key); key = ""; hasKey = true; store.live.restart(); message = "已存入這台 iPhone 的 Keychain；尚未驗證行情權限。" } catch { message = error.localizedDescription } } }
        Section { Button(store.refreshing ? "連線中…" : "驗證連線並取得 0050 報價") { Task { await store.refresh(symbols: ["0050"]); if store.message == nil, let quote = store.quote("0050") { message = "已取得 \(quote.date) \(quote.trial == true ? "試撮價" : "報價")：\(decimal(quote.price)) 元。" } } }.disabled(!hasKey || store.refreshing); if hasKey { Button("移除金鑰", role: .destructive) { do { try SecureKey.remove(); hasKey = false; store.live.restart(); message = "已移除金鑰。" } catch { message = error.localizedDescription } } } }
        if !message.isEmpty { Section { Text(message).font(.subheadline) } }
        Section { Link("申請或管理富果行情金鑰", destination: URL(string: "https://developer.fugle.tw/docs/key/")!); Text("沒有金鑰時顯示每個交易日的開盤與收盤價，收盤後更新。想看盤中即時價，請向富果申請你自己的個人金鑰貼在上方；金鑰只供你本人使用，請勿分享給他人。金鑰只傳送給富果官方 API，且不寫入備份；可用商品與請求額度依你的富果方案而定。").font(.footnote).foregroundStyle(.secondary); Link("查看富果行情 API 說明", destination: URL(string: "https://developer.fugle.tw/docs/data/http-api/getting-started/")!) }
    }.navigationTitle("行情連線").navigationBarTitleDisplayMode(.inline).onAppear { do { hasKey = !(try SecureKey.read()).isEmpty } catch { message = error.localizedDescription } } }
}
/// 備份與券商資料: backup export/import, broker statement import and (not yet available) broker linking.
struct BackupView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var importing = false
    @State private var exportURL: URL?
    @State private var pending: Data?
    @State private var preview: Portfolio?
    @State private var confirmation = false
    @State private var message = ""
    var body: some View {
        Page {
            Card {
                SectionHeading(title: "資料備份與還原", subtitle: "匯出或匯入持有、配息、交易、收藏與已取得報價；不含行情金鑰與可重新取得的歷史走勢")
                HStack(spacing: 10) {
                    actionTile("匯出備份 (JSON)", "包含自選、持股、設定", icon: "arrow.down.to.line", color: Palette.green) { do { exportURL = try store.export(); message = "已建立備份檔，可用下方按鈕儲存或分享。" } catch { message = error.localizedDescription } }
                    actionTile("匯入資料 (JSON)", "選擇備份檔案恢復資料", icon: "arrow.up.to.line", color: Palette.blue) { importing = true }
                }.padding(.top, 10)
                if let exportURL { ShareLink("儲存或分享備份", item: exportURL).font(.subheadline.bold()).padding(.top, 10) }
                if let preview {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("預覽").font(.subheadline.bold())
                        Text("持有 \(preview.holdings.count) 筆・配息 \(preview.dividends.count) 筆・收藏 \(preview.favorites.count) 檔・投入成本 $\(money(preview.cost))").font(.caption)
                        Button("確認合併匯入") { confirmation = true }.buttonStyle(.borderedProminent)
                    }.padding(.top, 10)
                }
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(Palette.muted).padding(.top, 8) }
                Text("匯入會合併紀錄；相同識別碼更新，其他現有紀錄保留。支援目前原生版、舊原生版與 PWA 備份，匯入前保留復原副本。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 8)
            }
            Card {
                SectionHeading(title: "券商對帳匯入", subtitle: "匯入券商提供的庫存 CSV，自動解析持股")
                NavigationLink(value: AppRoute.broker) {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text.fill").foregroundStyle(.white).frame(width: 38, height: 38).background(Palette.blue, in: Circle())
                        VStack(alignment: .leading, spacing: 2) { Text("上傳對帳單").font(.subheadline.bold()).foregroundStyle(Palette.ink); Text("支援 CSV（UTF-8、UTF-16 或 Big5）；PDF 請先另存 CSV").font(.caption2).foregroundStyle(Palette.muted) }
                        Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                    }.padding(12).background(Palette.cardSoft, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).padding(.top, 10)
            }
            Card {
                SectionHeading(title: "券商連結設定", subtitle: "連結券商帳戶，自動同步持股餘額（開發中）")
                HStack(spacing: 10) {
                    status("未連線", "尚未連結券商帳戶", icon: "powerplug", color: Palette.red)
                    status("自動同步", "待串接・開發中", icon: "arrow.triangle.2.circlepath", color: Palette.muted)
                }.padding(.top, 10)
            }
        }
        .navigationTitle("備份與券商資料").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            pending = nil; preview = nil; message = ""
            do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let bytes = try DataChecks.readFile(url); preview = try BackupImport.decode(bytes); pending = bytes } catch { message = error.localizedDescription }
        }
        .confirmationDialog("合併這份備份？", isPresented: $confirmation, titleVisibility: .visible) { Button("合併匯入") { do { if let pending { try store.importBackup(pending); message = "匯入完成，匯入前資料已保存於復原副本。"; preview = nil; self.pending = nil } } catch { message = error.localizedDescription } }; Button("取消", role: .cancel) { } }
    }
    private func actionTile(_ title: String, _ subtitle: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.headline).foregroundStyle(.white).frame(width: 34, height: 34).background(color, in: Circle())
                VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption.bold()).foregroundStyle(Palette.ink); Text(subtitle).font(.caption2).foregroundStyle(Palette.muted) }
                Spacer(minLength: 0)
            }.padding(10).frame(maxWidth: .infinity).background(Palette.cardSoft, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
    private func status(_ title: String, _ subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.white).frame(width: 32, height: 32).background(color, in: Circle())
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption.bold()).foregroundStyle(color == Palette.muted ? Palette.ink : color); Text(subtitle).font(.caption2).foregroundStyle(Palette.muted) }
            Spacer(minLength: 0)
        }.padding(10).frame(maxWidth: .infinity).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}
