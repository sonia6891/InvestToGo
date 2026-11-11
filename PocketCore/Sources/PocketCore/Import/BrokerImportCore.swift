import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif

struct CSVTable {
    var headers: [String]
    var rows: [[String]]
    static func parse(_ bytes: Data) throws -> Self {
        guard bytes.count <= 5_000_000 else { throw AppDataError("CSV 不可超過 5 MB。") }
        let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        let utf16BOM = bytes.starts(with: [0xff,0xfe]) || bytes.starts(with: [0xfe,0xff])
        let decoded = utf16BOM ? String(data: bytes, encoding: .utf16) : (String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: big5))
        guard let text = decoded else { throw AppDataError("請將對帳單另存為 UTF-8 CSV。") }
        var rows: [[String]] = []; var row: [String] = []; var cell = ""; var quoted = false; var endedQuote = false
        let chars = Array(text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}")).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")); var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { cell.append("\""); i += 1 } else { quoted = false; endedQuote = true }
                } else { cell.append(c) }
            } else if c == "\"" {
                guard cell.isEmpty, !endedQuote else { throw AppDataError("CSV 引號格式錯誤。") }; quoted = true
            } else if c == "," || c == "\n" {
                row.append(cell.trimmingCharacters(in: .whitespacesAndNewlines)); cell = ""; endedQuote = false
                if c == "\n" { if row.contains(where: { !$0.isEmpty }) { rows.append(row) }; row = [] }
            } else {
                guard !endedQuote || c == " " else { throw AppDataError("CSV 引號後出現不明字元。") }
                if !endedQuote { cell.append(c) }
            }
            i += 1
        }
        guard !quoted else { throw AppDataError("CSV 引號未結束，未匯入。") }
        row.append(cell.trimmingCharacters(in: .whitespacesAndNewlines)); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        guard rows.count >= 2, rows.count <= 10001 else { throw AppDataError("需要標題列與持有資料，最多 10,000 筆。") }
        var headers = rows.removeFirst(); headers[0] = headers[0].replacingOccurrences(of: "\u{feff}", with: "")
        // Spreadsheets often end lines with empty cells, and total or note rows are shorter than the title row.
        while headers.count > 1, headers.last?.isEmpty == true { headers.removeLast() }
        guard headers.count <= 100 else { throw AppDataError("CSV 欄位超過 100 欄。") }
        rows = rows.map { row in
            var row = row
            while row.count > headers.count, row.last?.isEmpty == true { row.removeLast() }
            return row + Array(repeating: "", count: max(headers.count - row.count, 0))
        }
        // A row still wider than the titles (such as an unquoted 1,000) is kept as is and skipped with a reason when previewed.
        return Self(headers: headers, rows: rows)
    }
    /// The column titled with one of `names`, trying the names in order (so 總成本 wins over a plain 成本).
    func guess(_ names: [String]) -> Int {
        for name in names { if let i = headers.firstIndex(where: { $0.lowercased() == name }) { return i } }
        return -1
    }
}
struct BrokerMapping {
    var symbol: Int
    var name: Int
    var shares: Int
    var cost: Int
    var lots: Bool = false
    var totalCost: Bool = true
}
extension BrokerMapping {
    /// Picks columns by their titles, including 國泰證券's (股票代號、商品名稱、現股庫存、付出成本).
    init(guessing table: CSVTable) {
        self.init(symbol: table.guess(["代碼", "代號", "股票代號", "股票代碼", "證券代號", "商品代碼", "商品代號", "symbol", "code"]),
                  name: table.guess(["名稱", "股票名稱", "證券名稱", "商品名稱", "name"]),
                  shares: table.guess(["股數", "庫存股數", "現股庫存", "庫存數量", "數量", "shares", "quantity"]),
                  cost: table.guess(["總成本", "付出成本", "持有成本", "投資成本", "成本", "cost"]))
    }
}
struct BrokerPreview {
    var holdings: [Holding]
    var sourceAccount: String
    var broker: String
    /// CSV rows not imported, each with its reason; shown before importing.
    var skipped: [String] = []
    /// Codes on skipped rows. Replacing the account keeps their earlier holdings rather than removing them.
    var skippedCodes: Set<String> = []
    var totalCost: Double { holdings.reduce(0) { $0 + $1.cost } }
    /// One position to import; `place` names it in error messages.
    private struct Entry { var place: String; var code: String; var name: String; var quantity: Double?; var cost: Double?; var margin = false; var problem: String? = nil }
    /// ETFs take the fund list's name and strategy; stocks are named from the stock list and left unclassified, as in the 新增持有 form.
    static func make(table: CSVTable, mapping: BrokerMapping, broker: String, account: String, funds: [Fund]) throws -> Self {
        guard [mapping.symbol, mapping.shares, mapping.cost].allSatisfy({ table.headers.indices.contains($0) }),
              Set([mapping.symbol, mapping.shares, mapping.cost]).count == 3 else { throw AppDataError("請指定不同的代號、數量與成本欄。") }
        let entries = table.rows.enumerated().map { offset, row in
            Entry(place: "第 \(offset + 2) 列", code: row[mapping.symbol].uppercased(), name: table.headers.indices.contains(mapping.name) ? row[mapping.name] : "",
                  quantity: number(row[mapping.shares]), cost: number(row[mapping.cost]),
                  problem: row.count > table.headers.count ? "欄位比標題列多，可能有未加引號的逗號" : nil)
        }
        return try build(entries, lots: mapping.lots, totalCost: mapping.totalCost, broker: broker, account: account, funds: funds, skipInvalid: true)
    }
    /// The lots the user checked after reading screenshots. Each lot's total is its cost, or its price per share
    /// times its shares; lots of one code and kind (現股 or 融資) become one holding with the shares and totals
    /// added up, so the average cost is total ÷ shares.
    static func make(drafts: [ScreenshotImport.Draft], broker: String, account: String, funds: [Fund]) throws -> Self {
        guard !drafts.isEmpty else { throw AppDataError("沒有要匯入的持有。") }
        var entries: [Entry] = []
        for (offset, draft) in drafts.enumerated() {
            let code = draft.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), place = "第 \(offset + 1) 筆"
            guard !code.isEmpty else { throw AppDataError("\(place)還沒有代號，請填入或刪除這一筆。") }
            guard draft.kind != .short else { throw AppDataError("\(place) \(code) 是融券（放空部位），不匯入；請刪除這一筆。") }
            guard let quantity = draft.shareCount else { throw AppDataError("\(place) \(code) 還沒有股數，請對照截圖填入。") }
            guard let total = draft.totalCost else { throw AppDataError("\(place) \(code) 還沒有\(draft.perShare ? "每股成本" : "總成本")，請對照截圖填入。") }
            guard quantity.isFinite, quantity > 0, total.isFinite, total >= 0 else { throw AppDataError("\(place) \(code) 的股數或成本不正確。") }
            let margin = draft.kind == .margin
            if let i = entries.firstIndex(where: { $0.code == code && $0.margin == margin }) {
                entries[i].quantity = (entries[i].quantity ?? 0) + quantity; entries[i].cost = (entries[i].cost ?? 0) + total
            } else {
                entries.append(Entry(place: place, code: code, name: "", quantity: quantity, cost: total, margin: margin))
            }
        }
        return try build(entries, lots: false, totalCost: true, broker: broker, account: account, funds: funds)
    }
    /// Holdings whose average cost is far from the latest price: most likely a price per share taken as a total,
    /// or the other way round. Shown before importing, never silently passed.
    func warnings(price: (String) -> Double?) -> [String] {
        var found: [String] = []
        for holding in holdings {
            guard let warning = Self.costWarning(average: holding.unitCost, price: price(holding.symbol)) else { continue }
            found.append("\(holding.symbol) \(holding.name)" + (holding.broker.hasSuffix("（融資）") ? "（融資）" : "") + "：" + warning)
        }
        return found
    }
    static func costWarning(average: Double, price: Double?) -> String? {
        guard let price, price > 0, !ScreenshotImport.plausible(average, price) else { return nil }
        let ratio = average / price
        let size = ratio < 1 ? "只有現價 \(priceText(price)) 元的 " + String(format: "%.1f", ratio * 100) + "%" : "是現價 \(priceText(price)) 元的 " + String(format: "%.1f", ratio) + " 倍"
        return "平均成本 \(priceText(average)) 元，\(size)，請確認成本是每股價格還是總金額。"
    }
    static func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")) }
    /// A share count written 1,000, 1,000股 or 2張 (1 張 = 1,000 股).
    static func shareCount(_ text: String) -> Double? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lots = value.hasSuffix("張")
        if lots || value.hasSuffix("股") { value.removeLast() }
        return number(value).map { lots ? $0 * 1000 : $0 }
    }
    /// With `skipInvalid` (CSV), a row with a bad code, quantity or cost, or a code in neither list, is skipped and
    /// listed instead of stopping the whole file; the screenshot list asks the user to fix each lot instead.
    private static func build(_ entries: [Entry], lots: Bool, totalCost: Bool, broker: String, account: String, funds: [Fund], skipInvalid: Bool = false) throws -> Self {
        let name = broker.trimmingCharacters(in: .whitespacesAndNewlines); let alias = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, !alias.isEmpty, alias.count <= 80 else { throw AppDataError("請填券商名稱與帳戶暱稱（各 80 字以內）。") }
        let source = StableID.make("broker-account", name + "\u{0}" + alias).uuidString
        var holdings: [Holding] = []; var seen = Set<String>(); var skipped: [String] = []; var skippedCodes = Set<String>()
        for entry in entries {
            let code = entry.code
            func skip(_ reason: String) throws {
                guard skipInvalid else { throw AppDataError("\(entry.place) \(code)：\(reason)，整份未匯入。") }
                skipped.append("\(entry.place)\(code.isEmpty ? "" : " " + code)：\(reason)")
                if DataChecks.code(code) { skippedCodes.insert(code) }
            }
            if let problem = entry.problem { try skip(problem); continue }
            guard DataChecks.code(code) else { try skip("不是股票或 ETF 代號"); continue }
            guard let qty = entry.quantity, let cost = entry.cost, qty.isFinite, qty > 0, cost.isFinite, cost >= 0 else { try skip("數量或成本不是有效數字"); continue }
            guard seen.insert(entry.margin ? code + "\u{0}融資" : code).inserted else { throw AppDataError("\(code) 有多列，請先將同帳戶同一檔合併為一筆庫存。") }
            if lots && (code.hasSuffix("C") || code.hasSuffix("K")) { throw AppDataError("\(code) 為外幣級別，交易單位可能不是 1,000 股；請將數量改為實際股數再匯入。") }
            let shares = qty * (lots ? 1000 : 1)
            let fund = funds.first { $0.id == code }
            guard let listed = fund?.name else {
                guard skipInvalid else { throw AppDataError("\(entry.place) \(code) 不在目前股票或 ETF 名單；請先更新名單，或移除該列。") }
                try skip("不在目前股票或 ETF 名單"); continue
            }
            // 融資 is a holding of its own beside 現股, so the two never replace each other on a later import.
            let holding = Holding(id: StableID.make("broker-position", source + "\u{0}" + code + (entry.margin ? "\u{0}融資" : "")), symbol: code, name: entry.name.isEmpty ? listed : entry.name,
                                  shares: shares, unitCost: totalCost ? cost / shares : cost, broker: entry.margin ? name + "（融資）" : name, strategy: fund?.strategy ?? .unclassified, sourceAccount: source)
            try holding.validate(); holdings.append(holding)
        }
        guard !holdings.isEmpty else { throw AppDataError("沒有可匯入的列。" + (skipped.first.map { "例如\($0)。" } ?? "")) }
        return Self(holdings: holdings, sourceAccount: source, broker: name, skipped: skipped, skippedCodes: skippedCodes)
    }
}
