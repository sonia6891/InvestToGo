import SwiftUI
import UniformTypeIdentifiers

struct BrokerView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var broker = ""
    @State private var account = ""
    @State private var table: CSVTable?
    @State private var mapping = BrokerMapping(symbol: -1, name: -1, shares: -1, cost: -1)
    @State private var importing = false
    @State private var preview: BrokerPreview?
    @State private var confirmation = false
    @State private var replace = false
    @State private var message: String?
    var body: some View { Form {
        Section("所有券商：持有對帳單匯入") {
            Text("可匯入券商匯出的 CSV，再選擇對應欄位。這是檔案匯入，尚未連接券商帳戶自動同步。").font(.subheadline)
            TextField("券商名稱", text: $broker).accessibilityIdentifier("broker-import-name")
            TextField("帳戶暱稱（例如主要帳戶）", text: $account).accessibilityIdentifier("broker-import-account")
            Text("ETF 與個股可放在同一份 CSV。同券商同暱稱會更新同一組庫存，並保留你改過的策略分類；請勿輸入完整帳號或密碼。成本請先換算為台幣。").font(.caption).foregroundStyle(.secondary)
            Button("選擇庫存 CSV") { importing = true }.disabled(store.isDemo)
        }
        if let table {
            Section("對應欄位 · \(table.rows.count) 筆") {
                column("代碼（ETF 或個股）", selection: $mapping.symbol, table: table)
                column("名稱（選填）", selection: $mapping.name, table: table)
                column("持有數量", selection: $mapping.shares, table: table)
                column("成本", selection: $mapping.cost, table: table)
                Toggle("數量以張為單位（1 張 = 1,000 股）", isOn: $mapping.lots)
                Toggle("成本欄是總成本", isOn: $mapping.totalCost)
                Text(mapping.totalCost ? "總成本會除以股數，轉成每股成本。" : "成本欄會直接當成每股台幣成本。").font(.caption)
                Button("驗證並預覽") { do { preview = try BrokerPreview.make(table: table, mapping: mapping, broker: broker, account: account, funds: store.funds); message = nil } catch { preview = nil; message = error.localizedDescription } }
            }
        }
        if let preview {
            Section("確認匯入內容") {
                LabeledContent("券商", value: preview.broker); LabeledContent("筆數", value: "\(preview.holdings.count)"); LabeledContent("總成本（台幣）", value: money(preview.totalCost))
                if !preview.stocks.isEmpty { Text("其中 \(preview.stocks.count) 筆不在 ETF 名單，會以個股匯入，新部位的策略為待分類。若其實是新上市 ETF，請先到「找 ETF」更新名單。").font(.caption) }
                ForEach(preview.holdings.prefix(20)) { h in VStack(alignment: .leading) { Text("\(h.symbol) \(h.name)\(preview.stocks.contains(h.symbol) ? " · 個股" : "")"); Text("\(decimal(h.shares)) 股 · 總成本 \(money(h.cost))").font(.caption).foregroundStyle(.secondary) } }
                Toggle("替換此帳戶先前匯入的庫存", isOn: $replace)
                Text(replace ? "會移除這個帳戶先前匯入、但本次檔案已沒有的部位。其他帳戶與手動紀錄保留。" : "只新增或更新本檔部位；檔案未列出的舊部位保留。").font(.caption)
                Button("確認匯入 \(preview.holdings.count) 筆") { confirmation = true }.disabled(store.isDemo)
            }
        }
        if let message { Section { Text(message) } }
        Section("帳戶授權同步") {
            Text("各券商需分別提供 API、帳務查詢權限與憑證。目前沒有已驗證的自動同步帳戶；不會用行情金鑰冒充帳戶授權。").font(.footnote)
            Link("富果合作券商與申請說明", destination: URL(string: "https://developer.fugle.tw/docs/trading/brokerage_partner/")!)
            Link("富邦官方 API 說明", destination: URL(string: "https://www.fbs.com.tw/TradeAPI/docs/trading/quickstart/")!)
            Link("永豐官方帳務 API 說明", destination: URL(string: "https://sinotrade.github.io/tutor/accounting/position/")!)
        }
    }.navigationTitle("券商持有資料").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            preview = nil; table = nil; message = nil
            do {
                let value = try CSVTable.parse(DataChecks.readFile(result.get())); table = value
                mapping = BrokerMapping(symbol: value.guess(["代碼", "股票代號", "證券代號", "商品代碼", "symbol", "code"]), name: value.guess(["名稱", "股票名稱", "證券名稱", "name"]), shares: value.guess(["股數", "庫存股數", "庫存數量", "數量", "shares", "quantity"]), cost: value.guess(["總成本", "投資成本", "成本", "cost"]))
            } catch { message = error.localizedDescription }
        }
        .confirmationDialog("將匯入庫存，並先保存一份復原備份。", isPresented: $confirmation, titleVisibility: .visible) { Button("匯入") { do { if let preview { try store.importBroker(preview, replaceAccount: replace); message = "已匯入 \(preview.holdings.count) 筆。"; self.preview = nil; table = nil } } catch { message = error.localizedDescription } }; Button("取消", role: .cancel) {} }
        .onChange(of: broker) { _, _ in preview = nil }.onChange(of: account) { _, _ in preview = nil }
        .onChange(of: mapping.symbol) { _, _ in preview = nil }.onChange(of: mapping.name) { _, _ in preview = nil }.onChange(of: mapping.shares) { _, _ in preview = nil }.onChange(of: mapping.cost) { _, _ in preview = nil }.onChange(of: mapping.lots) { _, _ in preview = nil }.onChange(of: mapping.totalCost) { _, _ in preview = nil }
    }
    private func column(_ title: String, selection: Binding<Int>, table: CSVTable) -> some View { Picker(title, selection: selection) { Text("未選擇").tag(-1); ForEach(table.headers.indices, id: \.self) { i in Text("\(i + 1). \(table.headers[i])").tag(i) } } }
}
