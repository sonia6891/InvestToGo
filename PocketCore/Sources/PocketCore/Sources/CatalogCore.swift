import Foundation

struct CatalogSnapshot: Codable {
    var funds: [Fund]
    var listedDate: String
    var fetchedDay: String
    var sources: [String]
    /// When this list was fetched on the device (spec 9: LoadFailed shows the last good data's day and time); nil for
    /// the bundled list and lists saved before it was recorded.
    var fetchedAt: Date? = nil
    func validate() throws {
        guard !funds.isEmpty, funds.count <= 2000, Set(funds.map(\.id)).count == funds.count,
              DataChecks.date(listedDate) != nil, DataChecks.date(fetchedDay) != nil,
              listedDate <= DataChecks.day(), fetchedDay <= DataChecks.day(),
              funds.allSatisfy({ DataChecks.code($0.id) && !$0.name.isEmpty && $0.name.count <= 120 && ["TWSE", "TPEx"].contains($0.market ?? "") })
        else { throw AppDataError("ETF 名單未通過驗證，保留上次成功資料。") }
    }
    static func bundled() -> CatalogSnapshot? {
        guard let url = CoreBundle.bundle.url(forResource: "catalog", withExtension: "json"), let bytes = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: bytes), (try? value.validate()) != nil else { return nil }
        return value
    }
}
enum CatalogAPI {
    static let listedURL = "https://openapi.twse.com.tw/v1/opendata/t187ap47_L"
    static let twseURL = "https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL"
    static let otcURL = "https://www.tpex.org.tw/openapi/v1/tpex_mainboard_quotes"
    static func strategy(_ name: String) -> Strategy {
        if name.contains("正2") || name.contains("反1") || name.contains("槓桿") || name.contains("反向") { return .risk }
        if name.contains("高股息") || name.contains("優息") || name.contains("高息") { return .income }
        if ["元大台灣50", "富邦台50", "元大富櫃50"].contains(name) { return .saving }
        return .unclassified
    }
    /// The ETFs are the codes starting with 00 in each exchange's daily trading list (TWSE 上市個股日成交資訊, TPEx 上櫃股票
    /// 收盤行情), so funds that left the market or are not listed yet drop out. TWSE 基金基本資料彙總表 adds the full name,
    /// fund type and listing day of listed ETFs; the open data has none of these for OTC ETFs, so they carry over from
    /// the previous list.
    static func decode(listed: Data, twse: Data, otc: Data, previous: CatalogSnapshot? = nil, today: String = DataChecks.day()) throws -> CatalogSnapshot {
        var details: [String: [String: Any]] = [:]; var dates: [String] = []
        for row in try rows(listed) {
            guard let code = text(row["基金代號"]), let day = DataChecks.rocDay(text(row["出表日期"]) ?? ""), day <= today, details[code] == nil else { throw AppDataError("上市基本資料欄位或日期改變，未覆寫。") }
            details[code] = row; dates.append(day)
        }
        let known = Dictionary((previous?.funds ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var funds: [Fund] = []
        for (market, bytes, codeKey, nameKey) in [("TWSE", twse, "Code", "Name"), ("TPEx", otc, "SecuritiesCompanyCode", "CompanyName")] {
            let records = try rows(bytes), before = funds.count
            guard records[0][codeKey] != nil, records[0][nameKey] != nil else { throw AppDataError("每日成交資料欄位改變，未覆寫。") }
            for row in records {
                guard let code = text(row[codeKey]), code.hasPrefix("00"), DataChecks.code(code), let name = text(row[nameKey]).map(unescape) else { continue }
                let detail = market == "TWSE" ? details[code] : nil, old = known[code]
                funds.append(Fund(id: code, name: name, strategy: strategy(name), market: market,
                                  fullName: text(detail?["基金中文名稱"]).map(unescape) ?? old?.fullName,
                                  fundType: text(detail?["基金類型"]) ?? old?.fundType,
                                  listingDate: DataChecks.rocDay(text(detail?["上市日期"]) ?? "") ?? old?.listingDate))
            }
            guard funds.count > before else { throw AppDataError("上市或上櫃資料不完整，保留原名單。") }
        }
        let value = CatalogSnapshot(funds: funds.sorted { $0.id < $1.id }, listedDate: dates.max() ?? today, fetchedDay: today, sources: [listedURL, twseURL, otcURL])
        try value.validate(); return value
    }
    private static func rows(_ bytes: Data) throws -> [[String: Any]] {
        guard let rows = DataChecks.jsonRows(bytes), !rows.isEmpty else { throw AppDataError("上市或上櫃資料不完整，保留原名單。") }
        return rows
    }
    private static func text(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        return text
    }
    /// The TWSE fund list writes some characters as HTML entities ("S&amp;P", "&#63754;").
    static func unescape(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        while let range = result.range(of: "&#[0-9]{1,7};", options: .regularExpression), let scalar = UInt32(result[range].dropFirst(2).dropLast()).flatMap({ Unicode.Scalar($0) }) {
            result.replaceSubrange(range, with: String(Character(scalar)))
        }
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] { result = result.replacingOccurrences(of: entity, with: character) }
        return result
    }
}
