import Foundation

public struct BrokerMapping {
    public var symbol: Int
    public var name: Int
    public var shares: Int
    public var cost: Int
    public var lots: Bool = false
    public var totalCost: Bool = true
    public init(symbol: Int, name: Int, shares: Int, cost: Int, lots: Bool = false, totalCost: Bool = true) {
        self.symbol = symbol; self.name = name; self.shares = shares; self.cost = cost; self.lots = lots; self.totalCost = totalCost
    }
}

public struct BrokerPreview {
    public var holdings: [Holding]
    public var sourceAccount: String
    public var broker: String
    public var totalCost: Double { holdings.reduce(0) { $0 + $1.cost } }
    public static func make(table: CSVTable, mapping: BrokerMapping, broker: String, account: String, funds: [Fund]) throws -> Self {
        let name = broker.trimmingCharacters(in: .whitespacesAndNewlines); let alias = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, !alias.isEmpty, alias.count <= 80,
              [mapping.symbol, mapping.shares, mapping.cost].allSatisfy({ table.headers.indices.contains($0) }),
              Set([mapping.symbol, mapping.shares, mapping.cost]).count == 3 else { throw AppDataError("請填券商、帳戶暱稱，並指定不同的代碼、數量與成本欄。") }
        let source = StableID.make("broker-account", name + "\u{0}" + alias).uuidString
        var holdings: [Holding] = []; var seen = Set<String>()
        for (offset, row) in table.rows.enumerated() {
            let code = row[mapping.symbol].uppercased()
            func number(_ index: Int) -> Double? { Double(row[index].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")) }
            guard DataChecks.code(code), let qty = number(mapping.shares), let cost = number(mapping.cost), qty.isFinite, qty > 0, cost.isFinite, cost >= 0 else { throw AppDataError("第 \(offset + 2) 列有無效代碼、數量或成本，整份未匯入。") }
            guard seen.insert(code).inserted else { throw AppDataError("\(code) 有多列，請先將同帳戶同 ETF 合併為一筆庫存。") }
            if mapping.lots && (code.hasSuffix("C") || code.hasSuffix("K")) { throw AppDataError("\(code) 為外幣級別，交易單位可能不是 1,000 股；請將數量改為實際股數再匯入。") }
            let shares = qty * (mapping.lots ? 1000 : 1)
            let fund = funds.first { $0.id == code }
            guard fund != nil else { throw AppDataError("第 \(offset + 2) 列 \(code) 不在目前 ETF 名單；請先更新名單，或移除非 ETF 列。") }
            let holding = Holding(id: StableID.make("broker-position", source + "\u{0}" + code), symbol: code,
                                  name: table.headers.indices.contains(mapping.name) && !row[mapping.name].isEmpty ? row[mapping.name] : fund!.name,
                                  shares: shares, unitCost: mapping.totalCost ? cost / shares : cost, broker: name, strategy: fund!.strategy, sourceAccount: source)
            try holding.validate(); holdings.append(holding)
        }
        return Self(holdings: holdings, sourceAccount: source, broker: name)
    }
}
