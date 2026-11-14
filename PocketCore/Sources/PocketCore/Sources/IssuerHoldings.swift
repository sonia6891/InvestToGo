import Foundation

/// Fund companies whose own public holdings pages the app can read.
enum Issuer: String, CaseIterable, Codable {
    case yuanta, cathay, fubon, capital, fhtrust, ctbc

    var displayName: String {
        switch self {
        case .yuanta: return "元大投信"
        case .cathay: return "國泰投信"
        case .fubon: return "富邦投信"
        case .capital: return "群益投信"
        case .fhtrust: return "復華投信"
        case .ctbc: return "中國信託投信"
        }
    }
}

/// Which fund company runs an ETF, read from the start of its name.
enum IssuerDirectory {
    private static let prefixes: [(String, Issuer)] = [
        ("元大", .yuanta), ("國泰", .cathay), ("富邦", .fubon), ("群益", .capital),
        ("復華", .fhtrust), ("中信", .ctbc), ("中國信託", .ctbc),
    ]

    static func issuer(forFundName name: String) -> Issuer? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return prefixes.first { trimmed.hasPrefix($0.0) }?.1
    }
}

/// Parsers for each fund company's holdings response. A reshaped or error body throws; none returns an empty snapshot.
enum IssuerHoldings {
    // MARK: Values

    private static func fail(_ issuer: Issuer, _ why: String) -> AppDataError {
        AppDataError("\(issuer.displayName)持股資料\(why)")
    }

    private static func object(_ data: Data, _ issuer: Issuer) throws -> [String: Any] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw fail(issuer, "格式不符（不是 JSON 物件）")
        }
        return obj
    }

    private static func text(_ any: Any?) -> String? {
        (any as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func filled(_ any: Any?) -> String? {
        guard let s = text(any), !s.isEmpty else { return nil }
        return s
    }

    /// A JSON number, or a string such as "1,234.5" or "4.123%".
    private static func number(_ any: Any?) -> Double? {
        var value: Double?
        if let s = any as? String {
            let plain = s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "%", with: "")
                .replacingOccurrences(of: "％", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            value = Double(plain)
        } else if let d = any as? Double {
            value = d
        } else if let i = any as? Int {
            value = Double(i)
        } else if let n = any as? NSNumber {
            value = n.doubleValue
        }
        guard let v = value, v.isFinite else { return nil }
        return v
    }

    /// "20261111", "2026/11/11" or "2026-11-11" -> "2026-11-11".
    static func day(_ any: Any?) -> String? {
        guard let s = text(any) else { return nil }
        var parts = s.components(separatedBy: CharacterSet(charactersIn: "/-"))
        if parts.count == 1, s.count == 8 {
            parts = [String(s.prefix(4)), String(s.dropFirst(4).prefix(2)), String(s.suffix(2))]
        }
        let digits = parts.allSatisfy { part in !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber } }
        guard parts.count == 3, digits, parts[0].count == 4,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// The response names its own ETF; a different one must not be filed under `symbol`.
    private static func checkFund(_ issuer: Issuer, _ any: Any?, _ symbol: String) throws {
        if let code = filled(any), code.uppercased() != symbol.uppercased() {
            throw fail(issuer, "與查詢的 ETF 不符（回應為 \(code)）")
        }
    }

    /// Builds the snapshot from the stock rows. Rows without a code are skipped (cash-like lines); a row with a code
    /// but no readable weight throws, so a snapshot never silently loses weight. The same code twice is summed.
    private static func snapshot(_ issuer: Issuer, symbol: String, date: String?, rows: [[String: Any]],
                                 code: String, name: String, weight: String) throws -> ComponentSnapshot {
        guard let date = date else { throw fail(issuer, "格式不符（缺少資料日期）") }
        guard !rows.isEmpty else { throw fail(issuer, "沒有股票成分") }
        var order: [String] = []
        var found: [String: FundComponent] = [:]
        for row in rows {
            guard let id = filled(row[code]) else { continue }
            guard let w = number(row[weight]) else { throw fail(issuer, "無法解析（\(id) 的權重無效）") }
            let label = filled(row[name])
            if var old = found[id] {
                old.weight += w
                if old.name == nil { old.name = label }
                found[id] = old
            } else {
                order.append(id)
                found[id] = FundComponent(symbol: id, name: label, weight: w)
            }
        }
        guard !order.isEmpty else { throw fail(issuer, "無法解析（\(rows.count) 列皆無效）") }
        let value = ComponentSnapshot(symbol: symbol, date: date, components: order.compactMap { found[$0] },
                                      source: issuer.displayName)
        try value.validate()
        return value
    }

    // MARK: Holdings

    /// 元大 PCF：`FundWeights.StockWeights[] {code,name,weights}`，日期 `PCF.trandate`。
    static func yuanta(_ data: Data, symbol: String) throws -> ComponentSnapshot {
        let issuer = Issuer.yuanta
        let obj = try object(data, issuer)
        guard let pcf = obj["PCF"] as? [String: Any] else { throw fail(issuer, "格式不符（缺少 PCF）") }
        try checkFund(issuer, pcf["markcd"], symbol)
        guard let rows = (obj["FundWeights"] as? [String: Any])?["StockWeights"] as? [[String: Any]] else {
            throw fail(issuer, "格式不符（缺少 StockWeights）")
        }
        return try snapshot(issuer, symbol: symbol, date: day(pcf["trandate"]), rows: rows,
                            code: "code", name: "name", weight: "weights")
    }

    /// 國泰 GetETFDetailStockList：`result[] {stockCode,stockName,weights}`；回應沒有日期，由查詢日期帶入。
    static func cathay(_ data: Data, symbol: String, date: String) throws -> ComponentSnapshot {
        let issuer = Issuer.cathay
        let obj = try object(data, issuer)
        if let ok = obj["success"] as? Bool, !ok {
            let message = filled(obj["returnMessage"])
            throw fail(issuer, "回應異常：" + (message ?? "success 為 false"))
        }
        guard let rows = obj["result"] as? [[String: Any]] else { throw fail(issuer, "格式不符（缺少 result）") }
        return try snapshot(issuer, symbol: symbol, date: day(date), rows: rows,
                            code: "stockCode", name: "stockName", weight: "weights")
    }

    /// 富邦 Assets.aspx：股票代碼/股票名稱/股數/金額/權重(%) 表頭之後、同一張表內的列；日期「資料日期：yyyy/MM/dd」。
    static func fubon(_ html: String, symbol: String) throws -> ComponentSnapshot {
        let issuer = Issuer.fubon
        let date = matches(#"資料日期\s*[：:]\s*(\d{4}/\d{1,2}/\d{1,2})"#, in: html).first.flatMap { day($0[0]) }
        guard let mark = html.range(of: #"(?i)<t[dh]\b[^>]*>\s*股票代碼\s*</t[dh]>"#, options: .regularExpression),
              let start = html.range(of: "<tr", options: [.backwards, .caseInsensitive],
                                     range: html.startIndex..<mark.lowerBound)?.lowerBound else {
            throw fail(issuer, "格式不符（缺少股票表頭）")
        }
        let end = html.range(of: "</table", options: .caseInsensitive, range: mark.upperBound..<html.endIndex)?.lowerBound
            ?? html.endIndex
        let table: [[String]] = matches(#"(?i)<tr\b[^>]*>(.*?)</tr>"#, in: String(html[start..<end])).map { tr in
            matches(#"(?i)<t[dh]\b[^>]*>(.*?)</t[dh]>"#, in: tr[0]).map { cellText($0[0]) }
        }
        guard let head = table.first, let ci = head.firstIndex(of: "股票代碼"),
              let wi = head.firstIndex(where: { $0.hasPrefix("權重") }) else {
            throw fail(issuer, "欄位不符（缺少「股票代碼」或「權重」）")
        }
        let ni = head.firstIndex(of: "股票名稱")
        // A row with a different cell count (a 合計 line) is not a holding.
        let rows: [[String: Any]] = table.dropFirst().filter { $0.count == head.count }.map { cells in
            ["code": cells[ci], "name": ni.map { cells[$0] } ?? "", "weight": cells[wi]]
        }
        return try snapshot(issuer, symbol: symbol, date: date, rows: rows, code: "code", name: "name", weight: "weight")
    }

    /// 群益 buyback：`data.stocks[] {stocNo,stocName,weight}`，日期 `data.pcf.date2`。
    static func capital(_ data: Data, symbol: String) throws -> ComponentSnapshot {
        let issuer = Issuer.capital
        let obj = try object(data, issuer)
        if let code = number(obj["code"]), code != 200 {
            let message = filled(obj["message"])
            throw fail(issuer, "回應異常：" + (message ?? String(format: "code %.0f", code)))
        }
        guard let body = obj["data"] as? [String: Any] else { throw fail(issuer, "格式不符（缺少 data）") }
        guard let rows = body["stocks"] as? [[String: Any]] else { throw fail(issuer, "格式不符（缺少 stocks）") }
        return try snapshot(issuer, symbol: symbol, date: day((body["pcf"] as? [String: Any])?["date2"]), rows: rows,
                            code: "stocNo", name: "stocName", weight: "weight")
    }

    /// 復華 assets：`result[0].detail[]` 中 `ftype == "股票"` 的列，權重 `prate_addaccint`，日期 `result[0].dDate`。
    static func fhtrust(_ data: Data, symbol: String) throws -> ComponentSnapshot {
        let issuer = Issuer.fhtrust
        let obj = try object(data, issuer)
        guard let fund = (obj["result"] as? [[String: Any]])?.first else { throw fail(issuer, "格式不符（缺少 result）") }
        try checkFund(issuer, fund["etf002"], symbol)
        guard let detail = fund["detail"] as? [[String: Any]] else { throw fail(issuer, "格式不符（缺少 detail）") }
        let rows = detail.filter { text($0["ftype"]) == "股票" }
        return try snapshot(issuer, symbol: symbol, date: day(fund["dDate"]), rows: rows,
                            code: "stockid", name: "stockname", weight: "prate_addaccint")
    }

    /// 中信 ETFHoldingWeight：`Data.FundAssetsDetail[Code == "STOCK"].Data[] {code_,name_,weights_}`，
    /// 日期 `Data.FundAssets[0]["資料日期"]`。
    static func ctbc(_ data: Data, symbol: String) throws -> ComponentSnapshot {
        let issuer = Issuer.ctbc
        let obj = try object(data, issuer)
        if let code = number(obj["ResultCode"]), code != 0 {
            let message = filled(obj["ResultMsg"])
            throw fail(issuer, "回應異常：" + (message ?? String(format: "ResultCode %.0f", code)))
        }
        guard let body = obj["Data"] as? [String: Any] else { throw fail(issuer, "格式不符（缺少 Data）") }
        try checkFund(issuer, (body["Fund"] as? [[String: Any]])?.first?["ETF_ID"], symbol)
        guard let groups = body["FundAssetsDetail"] as? [[String: Any]] else {
            throw fail(issuer, "格式不符（缺少 FundAssetsDetail）")
        }
        guard let stock = groups.first(where: { text($0["Code"]) == "STOCK" }) else { throw fail(issuer, "沒有股票成分") }
        guard let rows = stock["Data"] as? [[String: Any]] else { throw fail(issuer, "格式不符（缺少股票明細）") }
        let date = day((body["FundAssets"] as? [[String: Any]])?.first?["資料日期"])
        return try snapshot(issuer, symbol: symbol, date: date, rows: rows, code: "code_", name: "name_", weight: "weights_")
    }

    // MARK: Fund-code lookups

    /// 國泰 GetETFList：the item that carries `symbol` as one of its values gives the fund code.
    /// Written from the endpoint's description (no captured sample): it searches nested lists too and accepts
    /// `fundCode` / `fundId` / `fundNo` in any letter case.
    static func cathayFundCode(_ data: Data, symbol: String) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return cathayCode(root, symbol)
    }

    private static func cathayCode(_ any: Any, _ symbol: String) -> String? {
        if let list = any as? [Any] {
            for item in list {
                if let hit = cathayCode(item, symbol) { return hit }
            }
            return nil
        }
        guard let item = any as? [String: Any] else { return nil }
        let strings: [String: String] = item.compactMapValues { text($0) }
        if strings.values.contains(where: { $0.uppercased() == symbol.uppercased() }) {
            for wanted in ["fundcode", "fundid", "fundno"] {
                let hit = strings.first { $0.key.lowercased() == wanted && !$0.value.isEmpty && $0.value != symbol }
                if let hit = hit { return hit.value }
            }
        }
        for key in item.keys.sorted() {
            if let child = item[key], let hit = cathayCode(child, symbol) { return hit }
        }
        return nil
    }

    /// 群益 items：`data[] {fundNo, stockNo}`.
    static func capitalFundNo(_ data: Data, symbol: String) -> String? {
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = obj?["data"] as? [[String: Any]] ?? []
        let hit = items.first { text($0["stockNo"]) == symbol }
        return filled(hit?["fundNo"])
    }

    /// 復華 etf_list 頁：the `ETF<n>` id written just before the ETF code (same link or same record), else just after.
    /// Written from the page's description (no captured sample); `fhtrust(_:symbol:)` rejects a wrong fund afterwards.
    static func fhtrustFundID(_ html: String, symbol: String) -> String? {
        let code = #"(?<![0-9A-Za-z])"# + NSRegularExpression.escapedPattern(for: symbol) + #"(?![0-9A-Za-z])"#
        let gap = #"(?:(?!ETF\d).){0,400}?"#
        if let before = matches(#"(ETF\d+)"# + gap + code, in: html).first { return before[0] }
        return matches(code + gap + #"(ETF\d+)"#, in: html).first?[0]
    }

    /// 中信 ETFList：`Data.Data[] {ETF_ID, FID}`.
    static func ctbcFID(_ data: Data, symbol: String) -> String? {
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = (obj?["Data"] as? [String: Any])?["Data"] as? [[String: Any]] ?? []
        let hit = items.first { text($0["ETF_ID"]) == symbol }
        return filled(hit?["FID"])
    }

    // MARK: HTML

    /// Capture groups of every match; `.` also matches newlines.
    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).map { i in
                Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    private static func cellText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, plain) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            s = s.replacingOccurrences(of: entity, with: plain)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
