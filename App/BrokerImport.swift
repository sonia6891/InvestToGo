import Foundation
import CoreFoundation

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
        guard headers.count <= 100, rows.allSatisfy({ $0.count == headers.count }) else { throw AppDataError("CSV 每列欄位數不一致。") }
        return Self(headers: headers, rows: rows)
    }
    func guess(_ names: [String]) -> Int { headers.firstIndex { names.contains($0.lowercased()) } ?? -1 }
}
struct BrokerMapping {
    var symbol: Int
    var name: Int
    var shares: Int
    var cost: Int
    var lots: Bool = false
    var totalCost: Bool = true
}
struct BrokerPreview {
    var holdings: [Holding]
    var sourceAccount: String
    var broker: String
    var stocks: Set<String> = []
    var totalCost: Double { holdings.reduce(0) { $0 + $1.cost } }
    static func make(table: CSVTable, mapping: BrokerMapping, broker: String, account: String, funds: [Fund]) throws -> Self {
        let name = broker.trimmingCharacters(in: .whitespacesAndNewlines); let alias = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, !alias.isEmpty, alias.count <= 80,
              [mapping.symbol, mapping.shares, mapping.cost].allSatisfy({ table.headers.indices.contains($0) }),
              Set([mapping.symbol, mapping.shares, mapping.cost]).count == 3 else { throw AppDataError("請填券商、帳戶暱稱，並指定不同的代碼、數量與成本欄。") }
        let source = StableID.make("broker-account", name + "\u{0}" + alias).uuidString
        var holdings: [Holding] = []; var seen = Set<String>(); var stocks = Set<String>()
        for (offset, row) in table.rows.enumerated() {
            let code = row[mapping.symbol].uppercased()
            func number(_ index: Int) -> Double? { Double(row[index].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")) }
            guard DataChecks.code(code), let qty = number(mapping.shares), let cost = number(mapping.cost), qty.isFinite, qty > 0, cost.isFinite, cost >= 0 else { throw AppDataError("第 \(offset + 2) 列有無效代碼、數量或成本，整份未匯入。") }
            guard seen.insert(code).inserted else { throw AppDataError("\(code) 有多列，請先將同帳戶同代碼合併為一筆庫存。") }
            if mapping.lots && (code.hasSuffix("C") || code.hasSuffix("K")) { throw AppDataError("\(code) 為外幣級別，交易單位可能不是 1,000 股；請將數量改為實際股數再匯入。") }
            let shares = qty * (mapping.lots ? 1000 : 1)
            // Codes outside the ETF catalogue are imported as individual stocks for the user to classify.
            let fund = funds.first { $0.id == code }
            if fund == nil { stocks.insert(code) }
            let holding = Holding(id: StableID.make("broker-position", source + "\u{0}" + code), symbol: code,
                                  name: table.headers.indices.contains(mapping.name) && !row[mapping.name].isEmpty ? row[mapping.name] : (fund?.name ?? code),
                                  shares: shares, unitCost: mapping.totalCost ? cost / shares : cost, broker: name, strategy: fund?.strategy ?? .unclassified, sourceAccount: source)
            try holding.validate(); holdings.append(holding)
        }
        return Self(holdings: holdings, sourceAccount: source, broker: name, stocks: stocks)
    }
}
extension PortfolioStore {
    func importBroker(_ preview: BrokerPreview, replaceAccount: Bool) throws {
        var next = data
        // Keep the user's own strategy choice when a periodic re-import updates the same position.
        let strategies = Dictionary(uniqueKeysWithValues: next.holdings.map { ($0.id, $0.strategy) })
        if replaceAccount { next.holdings.removeAll { $0.sourceAccount == preview.sourceAccount } }
        for var holding in preview.holdings {
            holding.strategy = strategies[holding.id] ?? holding.strategy
            if let i = next.holdings.firstIndex(where: { $0.id == holding.id }) { next.holdings[i] = holding } else { next.holdings.append(holding) }
        }
        try saveRecovery(); try commit(next)
    }
}
