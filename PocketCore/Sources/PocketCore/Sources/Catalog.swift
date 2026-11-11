import Foundation

public struct CatalogSnapshot: Codable {
    public var funds: [Fund]
    public var listedDate: String
    public var fetchedDay: String
    public var sources: [String]
    public init(funds: [Fund], listedDate: String, fetchedDay: String, sources: [String]) {
        self.funds = funds; self.listedDate = listedDate; self.fetchedDay = fetchedDay; self.sources = sources
    }
    public func validate() throws {
        guard !funds.isEmpty, funds.count <= 2000, Set(funds.map(\.id)).count == funds.count,
              DataChecks.date(listedDate) != nil, DataChecks.date(fetchedDay) != nil,
              listedDate <= DataChecks.day(), fetchedDay <= DataChecks.day(),
              funds.allSatisfy({ DataChecks.code($0.id) && !$0.name.isEmpty && $0.name.count <= 120 && ["TWSE", "TPEx"].contains($0.market ?? "") })
        else { throw AppDataError("ETF 名單未通過驗證，保留上次成功資料。") }
    }
    public static func bundled() -> CatalogSnapshot? {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json"), let bytes = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: bytes), (try? value.validate()) != nil else { return nil }
        return value
    }
}

public enum CatalogAPI {
    public static let listedURL = "https://openapi.twse.com.tw/v1/opendata/t187ap47_L"
    public static let otcURL = "https://info.tpex.org.tw/api/etfFilter"
    public static let activeURL = "https://www.twse.com.tw/zh/ETFortune/ajaxProductsResult"
    public static func strategy(_ name: String) -> Strategy {
        if name.contains("正2") || name.contains("反1") || name.contains("槓桿") || name.contains("反向") { return .risk }
        if name.contains("高股息") || name.contains("優息") || name.contains("高息") { return .income }
        if ["元大台灣50", "富邦台50", "元大富櫃50"].contains(name) { return .saving }
        return .unclassified
    }
    struct Listing: Decodable { var stockNo: String; var stockName: String; var listingDate: String }
    struct MarketList: Decodable { var status: String; var data: [Listing] }
    public static func decode(listed: Data, otc: Data, active: Data, today: String = DataChecks.day()) throws -> CatalogSnapshot {
        let rows = try JSONDecoder().decode([[String: String]].self, from: listed)
        let listedActive = try JSONDecoder().decode(MarketList.self, from: active)
        let otcActive = try JSONDecoder().decode(MarketList.self, from: otc)
        guard !rows.isEmpty, listedActive.status == "success", otcActive.status == "success", !listedActive.data.isEmpty, !otcActive.data.isEmpty else { throw AppDataError("上市或上櫃來源缺資料，保留原名單。") }
        var details: [String: [String: String]] = [:]; var dates: [String] = []
        for row in rows {
            guard let code = row["基金代號"], let day = DataChecks.rocDay(row["出表日期"] ?? ""), day <= today, details[code] == nil else { throw AppDataError("上市基本資料欄位或日期改變，未覆寫。") }
            details[code] = row; dates.append(day)
        }
        var funds: [Fund] = []
        for (market, records) in [("TWSE", listedActive.data), ("TPEx", otcActive.data)] {
            for item in records {
                guard let date = DataChecks.rocDay(item.listingDate) else { throw AppDataError("掛牌日期格式改變，未覆寫。") }
                if date > today { continue }
                let row = market == "TWSE" ? details[item.stockNo] : nil
                funds.append(Fund(id: item.stockNo, name: item.stockName, strategy: strategy(item.stockName), market: market, fullName: row?["基金中文名稱"], fundType: row?["基金類型"], listingDate: date))
            }
        }
        let value = CatalogSnapshot(funds: funds.sorted { $0.id < $1.id }, listedDate: dates.max() ?? today, fetchedDay: today, sources: [listedURL, activeURL, otcURL])
        try value.validate(); return value
    }
}
