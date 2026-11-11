import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PhotosUI
import Vision

struct BrokerView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var broker = ""
    @State private var account = ""
    @State private var table: CSVTable?
    @State private var mapping = BrokerMapping(symbol: -1, name: -1, shares: -1, cost: -1)
    @State private var importing = false
    @State private var shots: [PhotosPickerItem] = []
    @State private var reading = false
    @State private var progress = ""
    @State private var drafts: [ScreenshotImport.Draft] = []
    @State private var skipped: [ScreenshotImport.Row] = []
    @State private var preview: BrokerPreview?
    @State private var confirmation = false
    @State private var replace = false
    @State private var message: String?
    @State private var costHint: String?
    @State private var feeRate = SellCosts.standard
    var body: some View { Form {
        Section("所有券商：持有對帳單匯入") {
            Text("可匯入券商匯出的 CSV，再選擇對應欄位；不能匯出 CSV 的券商（例如國泰證券），可改用庫存畫面截圖。這是檔案匯入，尚未連接券商帳戶自動同步。").font(.subheadline)
            BrokerFeeRows(broker: $broker, rate: $feeRate, placeholder: "券商名稱", identifier: "broker-import-name", inForm: true)
            TextField("帳戶暱稱（例如主要帳戶）", text: $account).accessibilityIdentifier("broker-import-account")
            Text("同券商同暱稱會更新同一組庫存；請勿輸入完整帳號或密碼。成本請先換算為台幣。").font(.caption).foregroundStyle(.secondary)
            Button("選擇庫存 CSV") { importing = true }
            PhotosPicker(selection: $shots, maxSelectionCount: 20, matching: .images) { Text("從截圖匯入") }.disabled(reading).accessibilityIdentifier("broker-import-screenshots")
            Text("庫存很長時可捲動分段截圖，一次選多張（最多 20 張）；截圖重疊處完全相同的列只算一次，同一檔分批買進的會分列顯示。只有名稱沒有代號也可以。文字只在這支手機上辨識，不會上傳。").font(.caption).foregroundStyle(.secondary)
        }
        if reading { Section { HStack(spacing: 10) { ProgressView(); Text(progress.isEmpty ? "正在辨識截圖文字…" : progress) } } }
        if let table {
            Section("對應欄位 · \(table.rows.count) 筆") {
                column("股票／ETF 代號", selection: $mapping.symbol, table: table)
                column("名稱（選填）", selection: $mapping.name, table: table)
                column("持有數量", selection: $mapping.shares, table: table)
                column("成本", selection: $mapping.cost, table: table)
                Toggle("數量以張為單位（1 張 = 1,000 股）", isOn: $mapping.lots)
                Toggle("成本欄是總成本", isOn: $mapping.totalCost)
                Text(mapping.totalCost ? "總成本會除以股數，轉成每股成本。" : "成本欄會直接當成每股台幣成本。").font(.caption)
                Button("驗證並預覽") {
                    do {
                        let made = try BrokerPreview.make(table: table, mapping: mapping, broker: broker, account: account, funds: store.funds, stock: { store.stock($0) })
                        preview = made; costHint = otherCostColumn(made, table); message = nil
                    } catch { preview = nil; message = error.localizedDescription }
                }
            }
        }
        if !drafts.isEmpty { screenshotRows }
        if !skipped.isEmpty { skippedRows }
        if let preview {
            Section("確認匯入內容") {
                LabeledContent("券商", value: preview.broker); LabeledContent("筆數", value: "\(preview.holdings.count)"); LabeledContent("總成本（台幣）", value: money(preview.totalCost))
                ForEach(preview.holdings.prefix(20)) { h in
                    VStack(alignment: .leading) {
                        Text("\(h.symbol) \(h.name)" + (h.broker.hasSuffix("（融資）") ? " · 融資" : ""))
                        Text("\(decimal(h.shares)) 股 · 總成本 \(money(h.cost)) · 平均 \(priceText(h.unitCost)) 元").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(preview.warnings(price: { price($0) }), id: \.self) { Text($0).font(.caption).foregroundStyle(Palette.red) }
                if let costHint { Text(costHint).font(.caption.bold()).foregroundStyle(Palette.red) }
                if !preview.skipped.isEmpty {
                    Text("略過 \(preview.skipped.count) 列，不會匯入：").font(.caption.bold()).foregroundStyle(Palette.red)
                    ForEach(preview.skipped.prefix(20), id: \.self) { Text($0).font(.caption) }
                    if preview.skipped.count > 20 { Text("另有 \(preview.skipped.count - 20) 列略過。").font(.caption) }
                }
                Toggle("替換此帳戶先前匯入的庫存", isOn: $replace)
                Text((replace ? "會移除這個帳戶先前匯入、但本次檔案已沒有的部位。其他帳戶與手動紀錄保留。" : "只新增或更新本檔部位；檔案未列出的舊部位保留。") + (replace && !preview.skippedCodes.isEmpty ? "略過列上的代號保留上次匯入的庫存。" : "")).font(.caption)
                Button("確認匯入 \(preview.holdings.count) 筆") { confirmation = true }
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
            preview = nil; table = nil; drafts = []; skipped = []; message = nil; replace = false
            do {
                let value = try CSVTable.parse(DataChecks.readFile(result.get())); table = value
                mapping = BrokerMapping(guessing: value)
            } catch { message = error.localizedDescription }
        }
        .onChange(of: shots) { _, items in if !items.isEmpty { Task { await read(items) } } }
        .confirmationDialog("將匯入庫存，並先保存一份復原備份。", isPresented: $confirmation, titleVisibility: .visible) { Button("匯入") { do { if let preview { SellCosts.remember(feeRate, for: broker); try store.importBroker(preview, replaceAccount: replace); message = "已匯入 \(preview.holdings.count) 筆。"; self.preview = nil; table = nil; drafts = []; skipped = [] } } catch { message = error.localizedDescription } }; Button("取消", role: .cancel) {} }
        .onChange(of: broker) { _, _ in preview = nil }.onChange(of: account) { _, _ in preview = nil }.onChange(of: drafts) { _, _ in preview = nil }
        .onChange(of: mapping.symbol) { _, _ in preview = nil }.onChange(of: mapping.name) { _, _ in preview = nil }.onChange(of: mapping.shares) { _, _ in preview = nil }.onChange(of: mapping.cost) { _, _ in preview = nil }.onChange(of: mapping.lots) { _, _ in preview = nil }.onChange(of: mapping.totalCost) { _, _ in preview = nil }
    }
    private func column(_ title: String, selection: Binding<Int>, table: CSVTable) -> some View { Picker(title, selection: selection) { Text("未選擇").tag(-1); ForEach(table.headers.indices, id: \.self) { i in Text("\(i + 1). \(table.headers[i])").tag(i) } } }
    /// What the screenshots showed, one section per lot, for the user to check before the usual preview.
    @ViewBuilder private var screenshotRows: some View {
        Section {
            Text("每一列是截圖上的一批。請逐筆對照截圖確認或修改；沒辨識到的欄位會留空，請自行填入。股數以股為單位（1 張 = 1,000 股），總成本填含手續費的台幣金額。")
                .font(.caption)
            Text("匯入時，同一檔同類別的多批合併成一筆：總成本是每一批的總成本（或每股成本 × 股數）相加，平均成本＝總成本÷總股數。融資另存一筆，券商名稱標「（融資）」。")
                .font(.caption).foregroundStyle(.secondary)
            Button("成本全部當作每股價格") { for i in drafts.indices { drafts[i].perShare = true } }
            Button("成本全部當作總金額") { for i in drafts.indices { drafts[i].perShare = false } }
        } header: {
            Text("截圖辨識結果 · \(drafts.count) 批")
        }
        ForEach($drafts) { $draft in
            let number = (drafts.firstIndex { $0.id == draft.id } ?? 0) + 1
            Section {
                if draft.symbol.isEmpty && !draft.seen.isEmpty {
                    Text(draft.choices.isEmpty ? "截圖上的「\(draft.seen)」對不到股票或 ETF 名單，請填代號。" : "截圖上的「\(draft.seen)」有 \(draft.choices.count) 個可能，請選擇代號。")
                        .font(.caption).foregroundStyle(Palette.red)
                }
                if !draft.choices.isEmpty && (draft.symbol.isEmpty || draft.choices.contains(draft.symbol)) {
                    Picker("選擇代號", selection: $draft.symbol) {
                        Text("未選擇").tag("")
                        ForEach(draft.choices, id: \.self) { code in Text("\(code) \(listedName(code))").tag(code) }
                    }
                }
                LabeledContent("代號") { TextField("例如 2330", text: $draft.symbol).textInputAutocapitalization(.characters).autocorrectionDisabled().multilineTextAlignment(.trailing) }
                Picker("類別", selection: $draft.kind) {
                    Text(ScreenshotImport.Kind.cash.rawValue).tag(ScreenshotImport.Kind.cash)
                    Text(ScreenshotImport.Kind.margin.rawValue).tag(ScreenshotImport.Kind.margin)
                }.pickerStyle(.segmented)
                LabeledContent("股數") { TextField("未辨識，請填寫", text: $draft.shares).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                Picker("成本是", selection: $draft.perShare) {
                    Text("總金額").tag(false)
                    Text("每股價格").tag(true)
                }.pickerStyle(.segmented)
                LabeledContent(draft.perShare ? "每股成本（元）" : "總成本（元）") { TextField(draft.costNote == nil ? "未辨識，請填寫" : "成本待確認", text: $draft.cost).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                if let costNote = draft.costNote, draft.cost.isEmpty { Text("成本待確認：\(costNote)").font(.caption).foregroundStyle(Palette.red) }
                if let line = figures(draft) { Text(line).font(.caption).foregroundStyle(.secondary) }
                if let warning = costWarning(draft) { Text(warning).font(.caption).foregroundStyle(Palette.red) }
                if let note = draft.note { Text(note).font(.caption).foregroundStyle(Palette.red) }
                Button("刪除這一筆", role: .destructive) { drafts.removeAll { $0.id == draft.id } }
            } header: {
                Text("第 \(number) 筆 · \(title(draft)) · \(draft.kind.rawValue)")
            }
        }
        Section {
            Button("新增一筆") { drafts.append(ScreenshotImport.Draft()) }
            Button("驗證並預覽") { do { preview = try BrokerPreview.make(drafts: drafts, broker: broker, account: account, funds: store.funds, stock: { store.stock($0) }); costHint = nil; message = nil } catch { preview = nil; message = error.localizedDescription } }
        }
    }
    /// 融券 lots: listed so the user sees why they are not imported.
    private var skippedRows: some View {
        Section {
            ForEach(skipped.indices, id: \.self) { i in Text(describe(skipped[i])) }
        } header: {
            Text("不匯入：融券 \(skipped.count) 筆")
        } footer: {
            Text("融券是借券賣出的放空部位，不是持有的股票，所以不會匯入。")
        }
    }
    private func describe(_ row: ScreenshotImport.Row) -> String {
        var parts = [row.symbol.isEmpty ? "「\(row.name ?? "")」" : "\(row.symbol) \(listedName(row.symbol))"]
        if let shares = row.shares { parts.append("\(decimal(shares)) 股") }
        if let cost = row.cost { parts.append("總成本 \(money(cost))") }
        return parts.joined(separator: " · ")
    }
    /// Shares, cost per share, total and, with a price, market value and gain: enough to see a wrong cost at once.
    private func figures(_ draft: ScreenshotImport.Draft) -> String? {
        guard let shares = draft.shareCount, let total = draft.totalCost, let average = draft.averageCost else { return nil }
        var parts = ["\(decimal(shares)) 股", "每股成本 \(priceText(average)) 元", "總成本 \(money(total)) 元"]
        if let latest = price(draft.symbol) {
            let value = latest * shares, gain = value - total
            parts += ["現價 \(priceText(latest)) 元", "市值約 \(money(value)) 元", "損益約 " + (gain >= 0 ? "+" : "") + money(gain) + " 元"]
        }
        return parts.joined(separator: " · ")
    }
    private func costWarning(_ draft: ScreenshotImport.Draft) -> String? {
        draft.averageCost.flatMap { BrokerPreview.costWarning(average: $0, price: price(draft.symbol)) }
    }
    /// The latest price: the viewer's own quote or the exchanges' last close.
    private func price(_ symbol: String) -> Double? {
        let code = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return code.isEmpty ? nil : store.quote(code)?.price
    }
    /// When the CSV's costs look wrong, whether reading the cost column the other way fits the prices better.
    private func otherCostColumn(_ made: BrokerPreview, _ table: CSVTable) -> String? {
        let now = made.warnings(price: { price($0) }).count
        guard now > 0 else { return nil }
        var other = mapping; other.totalCost.toggle()
        guard let alternative = try? BrokerPreview.make(table: table, mapping: other, broker: broker, account: account, funds: store.funds, stock: { store.stock($0) }),
              alternative.warnings(price: { price($0) }).count < now else { return nil }
        return mapping.totalCost ? "成本欄看起來是每股價格：請關閉「成本欄是總成本」再預覽。" : "成本欄看起來是總成本：請打開「成本欄是總成本」再預覽。"
    }
    private func title(_ draft: ScreenshotImport.Draft) -> String {
        let code = draft.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !code.isEmpty { return "\(code) \(listedName(code))" }
        return draft.seen.isEmpty ? "新的一筆" : "「\(draft.seen)」"
    }
    private func listedName(_ symbol: String) -> String {
        let code = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return store.funds.first { $0.id == code }?.name ?? store.stock(code)?.name ?? "（不在股票或 ETF 名單）"
    }
    /// Reads the chosen screenshots one by one, then lists what was found for the user to check.
    private func read(_ items: [PhotosPickerItem]) async {
        reading = true; preview = nil; table = nil; drafts = []; skipped = []; message = nil
        let etfs = store.funds.map { (code: $0.id, name: $0.name) }
        let stocks = (store.stockSnapshot?.stocks ?? []).map { (code: $0.id, name: $0.name) }
        let listing = ScreenshotImport.Listing(etfs + stocks)
        var pages: [[ScreenshotImport.Row]] = [], failed = 0
        for (index, item) in items.enumerated() {
            progress = "正在辨識第 \(index + 1)／\(items.count) 張截圖…"
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { failed += 1; continue }
                let lines = try await Task.detached(priority: .userInitiated) { try ScreenshotReader.lines(data) }.value
                pages.append(ScreenshotImport.parse(lines, in: listing))
            } catch { failed += 1 }
        }
        let review = ScreenshotImport.review(pages)
        drafts = review.rows.map { ScreenshotImport.Draft($0, price: price($0.symbol)) }; skipped = review.short
        // Screenshots show the whole inventory, so importing them again replaces what this account imported before
        // (same stable IDs), which also fixes costs an earlier version read wrongly.
        replace = true
        var notes: [String] = []
        if !drafts.isEmpty { notes.append("已從 \(pages.count) 張截圖讀出 \(drafts.count) 批，請在上方逐筆對照確認。同一檔分批買進的會分列，匯入時再依現股／融資合併。") }
        let unsure = drafts.filter { $0.costNote != nil }.count
        if unsure > 0 { notes.append("其中 \(unsure) 批的成本看不出是每股價格還是總金額，已留空待確認。") }
        let unresolved = drafts.filter { $0.symbol.isEmpty }.count
        if unresolved > 0 { notes.append("其中 \(unresolved) 批只辨識出名稱，請選擇或填入代號。") }
        if !skipped.isEmpty { notes.append("另有 \(skipped.count) 筆融券不匯入。") }
        if failed > 0 { notes.append("有 \(failed) 張圖片無法辨識。") }
        if drafts.isEmpty && skipped.isEmpty && !pages.isEmpty { notes.append("截圖裡沒有找到股票或 ETF 名單中的代號或名稱。請確認截圖有顯示庫存清單，或到「持有 › 新增持有」逐筆輸入。") }
        message = notes.isEmpty ? nil : notes.joined(separator: "\n")
        reading = false; progress = ""; shots = []
    }
}

/// Reads a screenshot's text with the system's text recognition, on this phone only (nothing is uploaded).
enum ScreenshotReader {
    /// Two readings in one pass over the image: with language correction for the Chinese, and without it so codes
    /// and figures are never "corrected" (ScreenshotImport.combine takes each word from the right one).
    static func lines(_ data: Data) throws -> [String] {
        guard let image = UIImage(data: data), let picture = image.cgImage else { throw AppDataError("無法讀取這張圖片。") }
        let corrected = request(correction: true), plain = request(correction: false)
        try VNImageRequestHandler(cgImage: picture, orientation: orientation(image.imageOrientation)).perform([corrected, plain])
        return ScreenshotImport.lines(from: ScreenshotImport.combine(corrected: boxes(corrected), raw: boxes(plain)))
    }
    private static func request(correction: Bool) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hant", "en-US"]
        request.usesLanguageCorrection = correction
        return request
    }
    private static func boxes(_ request: VNRecognizeTextRequest) -> [(text: String, box: CGRect)] {
        (request.results ?? []).compactMap { observation in observation.topCandidates(1).first.map { (text: $0.string, box: observation.boundingBox) } }
    }
    private static func orientation(_ value: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch value {
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        default: return .up
        }
    }
}
