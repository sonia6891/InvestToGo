import Foundation

public enum BackupImport {
    public struct OldDividend: Codable {
        public let id: String; public let code: String; public let name: String; public let paymentDate: String; public let exDate: String?
        public let eligibleShares: Double; public let perShare: Double; public let deductions: Double; public let status: String; public let actualReceived: Double?; public let sourceUrl: String?
        public var amount: Double { status == "received" ? (actualReceived ?? 0) : eligibleShares * perShare - deductions }
        public func validate() throws {
            guard eligibleShares.isFinite, eligibleShares > 0, eligibleShares <= 1e10, eligibleShares.rounded() == eligibleShares,
                  perShare.isFinite, (0...1e5).contains(perShare), deductions.isFinite, (0...(eligibleShares * perShare)).contains(deductions),
                  status != "received" || actualReceived != nil, actualReceived.map({ $0.isFinite && (0...1e15).contains($0) }) ?? true,
                  !name.isEmpty, name.count <= 120 else { throw StoreError.unsupportedBackup }
            if let exDate { guard DataChecks.date(exDate) != nil, exDate <= paymentDate else { throw StoreError.unsupportedBackup } }
            if let sourceUrl, !sourceUrl.isEmpty { guard sourceUrl.count <= 2048, let u = URL(string: sourceUrl), ["http", "https"].contains(u.scheme), u.host != nil, u.user == nil, u.password == nil else { throw StoreError.unsupportedBackup } }
        }
    }
    public struct OldHolding: Decodable { let id: String; let code: String; let name: String; let shares: Double; let cost: Double; let price: Double?; let priceDate: String? }
    public struct Planning: Decodable { let version: Int; let holdings: [OldHolding]; let dividends: [OldDividend]; let plan: LegacyPlan? }
    public struct Envelope: Decodable { let app: String; let version: Int; let planning: Planning; let favorites: [String]; let comparison: [String]; let components: [String: ComponentSnapshot]? }
    public static func decode(_ bytes: Data) throws -> Portfolio {
        guard bytes.count <= 5_000_000, let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw StoreError.unsupportedBackup }
        if root["schema"] != nil { return try Portfolio.decodeBackup(bytes) }
        let decoder = JSONDecoder(); let planning: Planning
        var result = Portfolio()
        if root["app"] != nil {
            let old = try decoder.decode(Envelope.self, from: bytes)
            guard (old.app == "ETF_CLASSIFIER" && old.version == 3) || (old.app == "ETF_TOGO_NATIVE" && old.version == 1), old.favorites.count <= 1000, old.comparison.count <= 3, old.favorites.allSatisfy(DataChecks.code), old.comparison.allSatisfy(DataChecks.code) else { throw StoreError.unsupportedBackup }
            planning = old.planning; result.favorites = Set(old.favorites); result.comparison = old.comparison; result.components = old.components
        } else { planning = try decoder.decode(Planning.self, from: bytes) }
        guard planning.version == 2, planning.holdings.count <= 10000, planning.dividends.count <= 50000,
              Set(planning.holdings.map(\.id)).count == planning.holdings.count,
              Set(planning.dividends.map(\.id)).count == planning.dividends.count else { throw StoreError.unsupportedBackup }
        result.legacyPlan = planning.plan
        for h in planning.holdings {
            guard !h.id.isEmpty, h.id.count <= 80, DataChecks.code(h.code), !h.name.isEmpty, h.name.count <= 120, h.shares.isFinite, h.shares > 0, h.shares <= 1e10, h.cost.isFinite, (0...1e13).contains(h.cost) else { throw StoreError.unsupportedBackup }
            let id = UUID(uuidString: h.id) ?? StableID.make("legacy-holding", h.id)
            result.holdings.append(Holding(id: id, symbol: h.code, name: h.name, shares: h.shares, unitCost: h.cost / h.shares, broker: "舊版匯入（券商未記錄）", strategy: .unclassified))
            // User-entered reference prices are preserved separately, never promoted to a verified live quote.
            if let price = h.price {
                guard price.isFinite, price >= 0, let day = h.priceDate, DataChecks.date(day) != nil else { throw StoreError.unsupportedBackup }
                if result.legacyPrices == nil { result.legacyPrices = [:] }
                result.legacyPrices?[h.id] = LegacyPrice(symbol: h.code, price: price, date: day)
            }
        }
        let statuses: [String: DividendStatus] = ["received": .paid, "announced": .announced, "planned": .estimated]
        for d in planning.dividends {
            try d.validate()
            guard !d.id.isEmpty, d.id.count <= 80, DataChecks.code(d.code), let date = DataChecks.date(d.paymentDate), let status = statuses[d.status], d.amount.isFinite, d.amount >= 0 else { throw StoreError.unsupportedBackup }
            result.dividends.append(Dividend(id: UUID(uuidString: d.id) ?? StableID.make("legacy-dividend", d.id), symbol: d.code, date: date, amount: d.amount, status: status))
            if result.legacyDividends == nil { result.legacyDividends = [:] }; result.legacyDividends?[d.id] = d
        }
        _ = try Portfolio.decodeBackup(JSONEncoder().encode(result)); return result
    }
}
