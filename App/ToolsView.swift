import SwiftUI
import UniformTypeIdentifiers

struct ToolsView: View {
    @EnvironmentObject var store: PortfolioStore
    var body: some View {
        Page {
            Text("把投資整理得更明白").font(.subheadline).foregroundStyle(.secondary)
            NavigationLink { AllocationView() } label: {
                HStack(spacing: 18) { Image(systemName: "chart.pie.fill").font(.system(size: 35)).foregroundStyle(.white.opacity(0.9)); VStack(alignment: .leading, spacing: 7) { Text("持有配置").font(.title2.bold()); Text("看看資金放在哪裡").font(.subheadline).foregroundStyle(.white.opacity(0.8)) }; Spacer(); Image(systemName: "arrow.up.right") }.padding(24).foregroundStyle(.white).background(Palette.blue, in: RoundedRectangle(cornerRadius: 24))
            }
            Card {
                NavigationLink { ExposureView() } label: { toolRow("持股穿透", "合併 ETF 成分與直接持有的個股", icon: "square.stack.3d.up") }
            }
            SectionHeading(title: "規劃與比較")
            Card {
                NavigationLink { ComparisonView() } label: { toolRow("ETF 比較", "並排查看策略與已取得的報價", icon: "rectangle.split.2x1") }
                Divider().padding(.vertical, 7)
                NavigationLink { ScenarioView() } label: { toolRow("三種情境試算", "用目前持有推算 3～50 年", icon: "chart.line.uptrend.xyaxis") }
                Divider().padding(.vertical, 7)
                NavigationLink { CalculatorView() } label: { toolRow("複利試算", "每月多存一點，未來有什麼不同", icon: "function") }
                Divider().padding(.vertical, 7)
                NavigationLink { PlanView() } label: { toolRow("配息再投入試算", "延續舊版試算設定與現金規劃", icon: "arrow.2.circlepath") }
            }
            SectionHeading(title: "連線與資料")
            Card {
                NavigationLink { ConnectionView() } label: { toolRow("富果行情連線", "使用你自己的 API Key", icon: "waveform.path") }
                Divider().padding(.vertical, 7)
                NavigationLink { BrokerView() } label: { toolRow("券商持有資料", "所有券商 CSV 欄位對應與預覽", icon: "building.columns") }
                Divider().padding(.vertical, 7)
                NavigationLink { BackupView() } label: { toolRow("資料備份", "匯出與匯入，保留你的每筆紀錄", icon: "externaldrive") }
            }
            HStack(alignment: .top, spacing: 12) { Image(systemName: "lock.shield").foregroundStyle(Palette.blue); VStack(alignment: .leading, spacing: 6) { Text("你的紀錄，留在你的手機").font(.subheadline.bold()); Text("持有與配息儲存在本機，行情金鑰使用 iOS Keychain 保存，不包含在備份內。").font(.caption).foregroundStyle(.secondary) } }.padding(.horizontal, 4)
            Text("ETF 袋著走 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · 原生 iPhone App").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 10)
        }.navigationTitle("工具")
    }
    func toolRow(_ title: String, _ subtitle: String, icon: String) -> some View { HStack(spacing: 13) { Image(systemName: icon).font(.title3).foregroundStyle(Palette.blue).frame(width: 40, height: 44); VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline).foregroundStyle(Palette.ink); Text(subtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 7) }
}
struct AllocationView: View {
    @EnvironmentObject var store: PortfolioStore
    var body: some View { Page {
        Card { Text("投入成本").foregroundStyle(.secondary); Text("$\(money(store.data.cost))").font(.largeTitle.bold()).padding(.top, 6) }
        SectionHeading(title: "依代碼分配")
        let symbols = Array(Set(store.data.holdings.map(\.symbol))).sorted()
        ForEach(symbols, id: \.self) { symbol in
            let holdings = store.data.holdings.filter { $0.symbol == symbol }
            let amount = holdings.reduce(0) { $0 + $1.cost }
            Card { HStack { Text(holdings.first?.name ?? symbol).font(.headline); Spacer(); Text("\(decimal(amount / max(store.data.cost, 1) * 100))%").font(.headline).foregroundStyle(Palette.blue) }; ProgressView(value: amount, total: max(store.data.cost, 1)).padding(.vertical, 12); Text("\(symbol) · 成本 $\(money(amount))").font(.caption).foregroundStyle(.secondary) }
        }
        if symbols.isEmpty { ContentUnavailableView("還沒有持有紀錄", systemImage: "chart.pie") }
        Text("這裡顯示 ETF 與個股的投入成本配置；股票曝險請前往持股穿透，兩檔 ETF 共同成分可在 ETF 比較查看。").font(.caption).foregroundStyle(.secondary)
    }.navigationTitle("持有配置").navigationBarTitleDisplayMode(.inline) }
}
struct ComparisonView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var left = "0050"
    @State private var right = "00878"
    var body: some View { Page {
        HStack { fundPicker("左側 ETF", selection: Binding(get: { left }, set: { left = $0; saveSelection() })); fundPicker("右側 ETF", selection: Binding(get: { right }, set: { right = $0; saveSelection() })) }
        HStack(alignment: .top, spacing: 12) { column(left); column(right) }
        OverlapPanel(left: left, right: right)
        Text("策略分類為初步標籤，資料日期與範圍須一起比較。").font(.caption).foregroundStyle(.secondary)
    }.navigationTitle("ETF 比較").navigationBarTitleDisplayMode(.inline)
        .onAppear { if let saved = store.data.comparison, saved.count >= 2 { left = saved[0]; right = saved[1] } }
    }
    private func saveSelection() { var next = store.data; next.comparison = [left, right] + Array((next.comparison ?? []).dropFirst(2)); do { try store.commit(next) } catch { store.message = error.localizedDescription } }
    func fundPicker(_ title: String, selection: Binding<String>) -> some View { Picker(title, selection: selection) { ForEach(store.funds) { Text($0.id).tag($0.id) } }.pickerStyle(.menu).frame(maxWidth: .infinity).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 15)) }
    func column(_ symbol: String) -> some View { let fund = store.funds.first { $0.id == symbol } ?? Fund(id: symbol, name: symbol, strategy: .unclassified); return Card { VStack(alignment: .leading, spacing: 18) { Text(symbol).font(.title2.bold()).foregroundStyle(Palette.blue); Text(fund.name).font(.headline).frame(minHeight: 44, alignment: .topLeading); StrategyPill(strategy: fund.strategy); Divider(); Text("已取得報價").font(.caption).foregroundStyle(.secondary); Text(store.data.quotes[symbol].map { decimal($0.price) } ?? "—").font(.title2.bold()); Text(store.data.quotes[symbol]?.date ?? "尚未取得").font(.caption2).foregroundStyle(.secondary) } } }
}
struct CalculatorView: View {
    @State private var initial = "100000"
    @State private var monthly = "5000"
    @State private var years = 10
    @State private var rate = 4.0
    var valid: Bool { guard let a = Double(initial), let b = Double(monthly) else { return false }; return a.isFinite && b.isFinite && a >= 0 && b >= 0 && a <= 1e12 && b <= 1e9 }
    var total: Double { Projection.value(initial: Double(initial) ?? 0, monthly: Double(monthly) ?? 0, years: years, annualPercent: rate) }
    var principal: Double { (Double(initial) ?? 0) + (Double(monthly) ?? 0) * Double(years * 12) }
    var body: some View { Form {
        Section("投入計畫") { TextField("起始本金（元）", text: $initial).keyboardType(.decimalPad); TextField("每月底投入（元）", text: $monthly).keyboardType(.decimalPad); Stepper("累積 \(years) 年", value: $years, in: 1...40); VStack(alignment: .leading) { Text("假設年報酬率 \(decimal(rate))%"); Slider(value: $rate, in: -10...15, step: 0.5) } }
        Section("試算結果") { if valid { LabeledContent("累計投入", value: "$\(money(principal))"); LabeledContent("期末試算金額", value: "$\(money(total))").foregroundStyle(Palette.blue); LabeledContent("試算損益", value: "$\(money(total - principal))") } else { Text("請輸入有效且非負的本金及每月投入金額。").foregroundStyle(.red) } }
        Section { Text("假設報酬按月平均複利、每月底投入，不含稅費與通膨。這是情境試算，不是預測或保證。負報酬情境下可能虧損本金。").font(.footnote).foregroundStyle(.secondary) }
    }.navigationTitle("複利試算").navigationBarTitleDisplayMode(.inline) }
}
struct ConnectionView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var key = ""
    @State private var hasKey = false
    @State private var message = ""
    var body: some View { Form {
        Section { Label(hasKey ? "已儲存金鑰" : "尚未設定金鑰", systemImage: hasKey ? "key.fill" : "key").foregroundStyle(hasKey ? Palette.green : .secondary); SecureField("貼上富果 API Key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled(); Button("安全儲存金鑰") { do { guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { message = "請先輸入金鑰。"; return }; try SecureKey.save(key); key = ""; hasKey = true; message = "已存入這台 iPhone 的 Keychain；尚未驗證行情權限。" } catch { message = error.localizedDescription } }.disabled(store.isDemo) }
        Section { Button(store.refreshing ? "連線中…" : "驗證連線並取得 0050 報價") { Task { await store.refresh(symbols: ["0050"]); if store.message == nil, let quote = store.data.quotes["0050"] { message = "已取得 \(quote.date) 報價：\(decimal(quote.price)) 元。" } } }.disabled(!hasKey || store.refreshing || store.isDemo); if hasKey { Button("移除金鑰", role: .destructive) { do { try SecureKey.remove(); hasKey = false; message = "已移除金鑰。" } catch { message = error.localizedDescription } }.disabled(store.isDemo) } }
        if !message.isEmpty { Section { Text(message).font(.subheadline) } }
        Section { Link("申請或管理富果行情金鑰", destination: URL(string: "https://developer.fugle.tw/docs/key/")!); Text("金鑰只傳送給富果官方 API，且不寫入備份。是否即時、可用商品與請求額度依你的富果方案而定。").font(.footnote).foregroundStyle(.secondary); Link("查看富果行情 API 說明", destination: URL(string: "https://developer.fugle.tw/docs/data/http-api/getting-started/")!) }
    }.navigationTitle("行情連線").navigationBarTitleDisplayMode(.inline).onAppear { do { hasKey = !(try SecureKey.read()).isEmpty } catch { message = error.localizedDescription } } }
}
struct BackupView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var importing = false
    @State private var exportURL: URL?
    @State private var pending: Data?
    @State private var preview: Portfolio?
    @State private var confirmation = false
    @State private var message = ""
    var body: some View { Form {
        Section("匯出") { Text("包含持有、配息、收藏與已取得報價，不包含行情金鑰。").font(.subheadline).foregroundStyle(.secondary); Button("建立備份檔") { do { exportURL = try store.export() } catch { message = error.localizedDescription } }; if let exportURL { ShareLink("儲存或分享備份", item: exportURL) } }
        Section("匯入") { Button("選擇備份檔") { importing = true }; Text("匯入會合併紀錄；相同識別碼更新，其他現有紀錄保留。支援目前原生版、舊原生版與 PWA 備份。匯入前顯示筆數並保留復原副本；舊版手填參考價保留在備份中，不當成即時報價。").font(.footnote).foregroundStyle(.secondary) }
        if let preview { Section("預覽") { LabeledContent("持有", value: "\(preview.holdings.count) 筆"); LabeledContent("配息", value: "\(preview.dividends.count) 筆"); LabeledContent("收藏", value: "\(preview.favorites.count) 檔"); LabeledContent("投入成本", value: "$\(money(preview.cost))"); if preview.legacyPlan != nil { Text("包含舊版試算設定，會可在「配息再投入試算」繼續使用。") }; Button("確認合併匯入") { confirmation = true } } }
        if !message.isEmpty { Section { Text(message) } }
    }.navigationTitle("資料備份").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            pending = nil; preview = nil; message = ""
            do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let bytes = try DataChecks.readFile(url); preview = try BackupImport.decode(bytes); pending = bytes } catch { message = error.localizedDescription }
        }.confirmationDialog("合併這份備份？", isPresented: $confirmation, titleVisibility: .visible) { Button("合併匯入") { do { if let pending { try store.importBackup(pending); message = "匯入完成，匯入前資料已保存於復原副本。"; preview = nil; self.pending = nil } } catch { message = error.localizedDescription } }; Button("取消", role: .cancel) { } }
    }
}
