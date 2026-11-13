import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Reads holdings from the text of a broker's inventory screenshot. The app runs the system's on-device text
/// recognition and passes the lines here, so this part works on plain text and is tested without images.
/// A holding is found by a listed code, else by a listed name. Each lot (one row or card of the screenshot) stays a
/// row of its own for review. A figure the text does not clearly label stays empty, and a name that fits no single
/// code leaves the code for the user to choose; nothing is estimated.
enum ScreenshotImport {
    /// 現股 (paid in full), 融資 (bought with a margin loan) or 融券 (sold short, not a holding, never imported).
    enum Kind: String, CaseIterable { case cash = "現股", margin = "融資", short = "融券" }
    /// What a cost figure is: the total paid, or a price per share (成本價、均價).
    enum Basis { case total, perShare }
    struct Row: Equatable {
        var symbol: String
        var shares: Double? = nil
        var cost: Double? = nil
        /// The name the screenshot showed when it did not settle on one code; `choices` are the codes it may be.
        var name: String? = nil
        var choices: [String] = []
        /// A hint for the user, such as a row cut off at a screenshot's edge.
        var note: String? = nil
        var kind: Kind = .cash
        /// What `cost` is, when its title said so.
        var basis: Basis? = nil
    }
    /// A row of the editable list the user checks before importing. Its cost is a total or, with `perShare`, a
    /// price per share; `costNote` says why a cost read from the screenshot was not filled in.
    struct Draft: Identifiable, Equatable {
        var id = UUID()
        var symbol = ""
        var shares = ""
        var cost = ""
        var perShare = false
        var kind: Kind = .cash
        var seen = ""
        var choices: [String] = []
        var note: String?
        var costNote: String?
        init() {}
        /// `price` is the latest price, which tells a price per share from a total when the title did not say.
        init(_ row: Row, price: Double? = nil) {
            symbol = row.symbol; shares = row.shares.map(Self.plain) ?? ""
            kind = row.kind; seen = row.name ?? ""; choices = row.choices; note = row.note
            guard let read = row.cost else { return }
            if let basis = row.basis ?? row.shares.flatMap({ ScreenshotImport.basis(cost: read, shares: $0, price: price) }) {
                cost = Self.plain(read); perShare = basis == .perShare
            } else {
                let reason = price == nil ? "沒有現價可比對" : row.shares == nil ? "沒有股數可換算" : "當每股價格或總金額都跟現價對不起來"
                costNote = "截圖讀到成本 \(Self.plain(read))，\(reason)，看不出是每股價格還是總金額，請確認後填入。"
            }
        }
        var shareCount: Double? { BrokerPreview.shareCount(shares) }
        var costValue: Double? { BrokerPreview.number(cost) }
        /// What this lot cost in all: the cost, or the price per share times the shares.
        var totalCost: Double? {
            guard let count = shareCount, let value = costValue else { return nil }
            return perShare ? value * count : value
        }
        var averageCost: Double? {
            guard let count = shareCount, count > 0, let total = totalCost else { return nil }
            return total / count
        }
        private static func plain(_ value: Double) -> String { value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value) }
    }
    /// A cost with no title saying what it is: a total when cost ÷ shares is near the latest price, a price per share
    /// when the cost itself is; nil when neither is, or there is no price to compare with.
    static func basis(cost: Double, shares: Double, price: Double?) -> Basis? {
        guard let price, price > 0, shares > 0 else { return nil }
        if plausible(cost / shares, price) { return .total }
        if plausible(cost, price) { return .perShare }
        return nil
    }
    /// An average cost between 0.3 and 3 times the latest price.
    static func plausible(_ average: Double, _ price: Double) -> Bool { (0.3...3.0).contains(average / price) }
    /// The stock and ETF lists by code and by name.
    struct Listing {
        private(set) var codes: Set<String> = []
        private var byName: [String: [String]] = [:]
        private var names: [(key: [Character], code: String)] = []
        init(_ entries: [(code: String, name: String)]) {
            for entry in entries where DataChecks.code(entry.code) && !codes.contains(entry.code) {
                codes.insert(entry.code)
                let key = Self.key(entry.name)
                guard !key.isEmpty else { continue }
                byName[key, default: []].append(entry.code); names.append((key: Array(key), code: entry.code))
            }
        }
        func knows(_ code: String) -> Bool { codes.contains(code) }
        /// Codes whose name is exactly this, ignoring spaces, full-width letters and 臺／台.
        func exact(_ name: String) -> [String] { byName[Self.key(name)] ?? [] }
        /// Codes whose name is one misread character away, or begins with this cut-off name: choices, never a match.
        func near(_ name: String) -> [String] {
            var key = Array(Self.key(name))
            while let last = key.last, last == "…" || last == "." { key.removeLast() }
            guard key.count >= 3 else { return [] }
            return Array(names.filter { $0.key.starts(with: key) || ($0.key.count >= 3 && Self.oneEdit(key, $0.key)) }.map { $0.code }.prefix(8))
        }
        static func key(_ text: String) -> String {
            var scalars = String.UnicodeScalarView()
            for scalar in text.unicodeScalars where !scalar.properties.isWhitespace {
                switch scalar.value {
                case 0xFF01...0xFF5E: scalars.append(Unicode.Scalar(scalar.value - 0xFEE0)!)
                case 0x81FA: scalars.append("台")
                default: scalars.append(scalar)
                }
            }
            return String(scalars).uppercased()
        }
        /// One character replaced, added or left out.
        private static func oneEdit(_ a: [Character], _ b: [Character]) -> Bool {
            if a.count == b.count { return zip(a, b).filter { $0 != $1 }.count == 1 }
            guard abs(a.count - b.count) == 1 else { return false }
            let short = a.count < b.count ? a : b, long = a.count < b.count ? b : a
            var i = 0, j = 0, skipped = false
            while i < short.count && j < long.count {
                if short[i] == long[j] { i += 1; j += 1 } else if skipped { return false } else { skipped = true; j += 1 }
            }
            return true
        }
    }
    private enum Field { case shares, lots, total, perShare, anyCost }
    /// Titles of a share count; a count in 張 (1,000 shares) is converted.
    static let shareLabels: Set<String> = ["股數", "庫存股數", "現股庫存", "持有股數", "現股股數", "集保股數", "集保庫存"]
    static let lotLabels: Set<String> = ["張數", "庫存張數", "持有張數", "現股張數"]
    /// Titles of the total amount paid.
    static let costLabels: Set<String> = ["付出成本", "持有成本", "總成本", "成本金額", "投資成本", "成本總額"]
    /// Titles of a price per share. 國泰證券's holdings screen calls the price paid per share 成交價.
    static let unitCostLabels: Set<String> = ["成本價", "均價", "平均成本", "平均成本價", "成交均價", "買進均價", "持有均價", "成本均價", "平均價", "成本單價",
                                              "成交價", "成交單價", "成交價格", "買進價", "買入價", "買進單價"]

    /// Language correction reads Chinese better but may "correct" codes and figures, so each screenshot is read
    /// both ways and every word with a digit is taken from the uncorrected reading of the same place.
    static func combine(corrected: [(text: String, box: CGRect)], raw: [(text: String, box: CGRect)]) -> [(text: String, box: CGRect)] {
        corrected.map { item -> (text: String, box: CGRect) in
            guard let twin = raw.max(by: { overlap($0.box, item.box) < overlap($1.box, item.box) }), overlap(twin.box, item.box) >= 0.5 else { return item }
            let words = item.text.split(separator: " "), plain = twin.text.split(separator: " ")
            guard words.count == plain.count else { return hasDigit(Substring(twin.text)) ? (text: twin.text, box: item.box) : item }
            let text = zip(words, plain).map { fixed, read in hasDigit(fixed) || hasDigit(read) ? String(read) : String(fixed) }.joined(separator: " ")
            return (text: text, box: item.box)
        }
    }
    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let shared = a.intersection(b)
        guard !shared.isNull, shared.width > 0, shared.height > 0 else { return 0 }
        let both = shared.width * shared.height
        return both / (a.width * a.height + b.width * b.height - both)
    }
    private static func hasDigit(_ word: Substring) -> Bool { word.unicodeScalars.contains { (0x30...0x39).contains($0.value) || (0xFF10...0xFF19).contains($0.value) } }

    /// Groups recognised text boxes (Vision's normalised boxes, origin at the bottom left) into lines, top to bottom:
    /// a box joins the line whose middle is nearest, if within half the smaller text height.
    static func lines(from boxes: [(text: String, box: CGRect)]) -> [String] {
        var rows: [(middle: CGFloat, height: CGFloat, items: [(x: CGFloat, text: String)])] = []
        for item in boxes.sorted(by: { $0.box.midY > $1.box.midY }) where !item.text.trimmingCharacters(in: .whitespaces).isEmpty {
            let distance = { (i: Int) in abs(rows[i].middle - item.box.midY) }
            let near = rows.indices.filter { distance($0) < min(rows[$0].height, item.box.height) / 2 }
            if let i = near.min(by: { distance($0) < distance($1) }) {
                rows[i].items.append((x: item.box.minX, text: item.text))
            } else {
                rows.append((middle: item.box.midY, height: item.box.height, items: [(x: item.box.minX, text: item.text)]))
            }
        }
        return rows.map { row in row.items.sorted { $0.x < $1.x }.map { $0.text }.joined(separator: " ") }
    }

    /// The lots in the order they appear. A listed code or name starts a lot; a share count or total cost is taken
    /// when its title is beside it (付出成本 580,365) or above it in a row of titles. The same holding named again
    /// before any figure (a card's title and its name line) is the same lot; after a figure it is the next lot.
    static func parse(_ lines: [String], in listing: Listing) -> [Row] {
        var rows: [Row] = []
        var current: Int?
        var header: [Field?]?
        var headerFresh = false
        for line in lines {
            let words = tokens(line)
            guard !words.isEmpty else { continue }
            // Totals belong to no single lot.
            if words.contains(where: { $0.contains("合計") || $0.contains("總計") || $0.contains("小計") }) { current = nil; headerFresh = false; continue }
            let found = holding(in: words, listing)
            if let found {
                let row = Row(symbol: found.code ?? "", name: found.code == nil ? found.name : nil, choices: found.choices)
                let continues = current.map { rows[$0].symbol == row.symbol && rows[$0].name == row.name && rows[$0].shares == nil && rows[$0].cost == nil } ?? false
                if !continues { rows.append(row); current = rows.count - 1 }
            } else if unlisted(words) {
                current = nil
            }
            // 融資 or 融券 written anywhere in a lot's lines marks that lot (融券 wins).
            func mark() { if let i = current, let marked = kind(of: words), marked == .short || rows[i].kind == .cash { rows[i].kind = marked } }
            let fields = words.map(field)
            if fields.contains(where: { $0 != nil }) {
                var paired = false
                for j in words.indices.dropLast() {
                    if let kind = fields[j], let value = amount(words[j + 1]) { paired = true; if let current { fill(&rows[current], kind, value) } }
                }
                // Titles with no value beside them head the values on the lines below.
                if !paired && found == nil { header = fields; headerFresh = true } else { headerFresh = false }
                mark(); continue
            }
            // Under a row of titles: the line right below it, or a table row of its own. Values line up from the
            // right, since a name may take two words; a line shorter than the titles is left alone.
            if let header, words.count >= header.count, found != nil || headerFresh || leadingName(words) != nil {
                let offset = words.count - header.count
                var figures = Row(symbol: "")
                for (k, kind) in header.enumerated() {
                    if let kind, !(found?.words.contains(k + offset) ?? false), let value = amount(words[k + offset]) { fill(&figures, kind, value) }
                }
                if found == nil && !headerFresh {
                    // A table row whose name fits nothing in the lists: its figures are kept, the code left to the user.
                    guard figures.shares != nil, let name = leadingName(words) else { mark(); headerFresh = false; continue }
                    rows.append(Row(symbol: "", name: name)); current = rows.count - 1
                }
                if let current {
                    if rows[current].shares == nil { rows[current].shares = figures.shares }
                    if let cost = figures.cost { setCost(&rows[current], cost, figures.basis) }
                }
            }
            mark(); headerFresh = false
        }
        return rows
    }

    /// All screenshots' lots for review. A long list is captured in several overlapping screenshots, so a row that
    /// matches an earlier screenshot's row exactly (code, shares, cost and kind) is that row again and appears once;
    /// rows within one screenshot are separate lots and are all kept. A row with a figure missing that fits a fuller
    /// row of another screenshot is probably cut off at the edge, and says so. 融券 rows are returned apart.
    static func review(_ pages: [[Row]]) -> (rows: [Row], short: [Row]) {
        var result: [Row] = [], page: [Int] = []
        for (number, rows) in pages.enumerated() {
            var matched = Set<Int>()
            for row in rows {
                if let i = result.indices.first(where: { page[$0] < number && !matched.contains($0) && result[$0] == row }) { matched.insert(i); continue }
                result.append(row); page.append(number)
            }
        }
        for i in result.indices where result[i].shares == nil || result[i].cost == nil {
            if result.indices.contains(where: { page[$0] != page[i] && covers(result[$0], result[i]) }) {
                result[i].note = "這一列可能是截圖邊緣只拍到一部分的重複列；若與其他列是同一批，請刪除。"
            }
        }
        return (result.filter { $0.kind != .short }, result.filter { $0.kind == .short })
    }
    /// `full` is the same lot as `part` with more of its figures read.
    private static func covers(_ full: Row, _ part: Row) -> Bool {
        full.symbol == part.symbol && full.name == part.name && full.kind == part.kind
            && (part.shares == nil || part.shares == full.shares) && (part.cost == nil || (part.cost == full.cost && part.basis == full.basis))
            && [full.shares, full.cost].compactMap { $0 }.count > [part.shares, part.cost].compactMap { $0 }.count
    }
    /// 融券 when a lot's text says 融券, 券賣 or a lone 券; 融資 when it says 融資, 資買 or a lone 資.
    private static func kind(of words: [String]) -> Kind? {
        if words.contains(where: { $0.contains("融券") || $0.contains("券賣") || $0 == "券" }) { return .short }
        if words.contains(where: { $0.contains("融資") || $0.contains("資買") || $0 == "資" }) { return .margin }
        return nil
    }

    /// The holding a line names: a listed code, else a listed name of up to three words (the longest first), else
    /// names one misread character away, offered as choices.
    private struct Found { var words: Range<Int>; var code: String?; var name: String; var choices: [String] }
    private static func holding(in words: [String], _ listing: Listing) -> Found? {
        let upper = words.map { $0.uppercased() }
        if let i = upper.indices.first(where: { DataChecks.code(upper[$0]) && listing.knows(upper[$0]) }) { return Found(words: i..<i + 1, code: upper[i], name: "", choices: []) }
        let parts = words.map(namePart)
        for i in words.indices {
            for count in stride(from: min(3, words.count - i), through: 1, by: -1) {
                let piece = parts[i..<i + count]
                guard !piece.contains(where: { $0 == nil }) else { continue }
                let name = piece.compactMap { $0 }.joined()
                let codes = listing.exact(name)
                if codes.count == 1 { return Found(words: i..<i + count, code: codes[0], name: name, choices: []) }
                if codes.count > 1 { return Found(words: i..<i + count, code: nil, name: name, choices: codes) }
            }
        }
        for i in words.indices {
            guard let word = parts[i], ideographs(word) >= 2 else { continue }
            let near = listing.near(word)
            if !near.isEmpty { return Found(words: i..<i + 1, code: nil, name: word, choices: near) }
        }
        return nil
    }
    /// A word that may be part of a name: not a title, amount, code, kind, signed figure or percentage. A trailing
    /// note in brackets, as in 台積電(現股), is dropped.
    private static func namePart(_ word: String) -> String? {
        guard field(word) == nil, amount(word) == nil, !DataChecks.code(word.uppercased()), kind(of: [word]) == nil, word != "現股",
              !word.contains(","), !word.contains("%"), !word.hasPrefix("+"), !word.hasPrefix("-") else { return nil }
        return word.replacingOccurrences(of: #"[(（][^)）]*[)）]$"#, with: "", options: .regularExpression)
    }
    /// The words before a line's figures, when they read as a name (two or more Chinese characters).
    private static func leadingName(_ words: [String]) -> String? {
        let name = words.prefix(while: { namePart($0) != nil }).compactMap(namePart).joined()
        return ideographs(name) >= 2 ? name : nil
    }
    private static func ideographs(_ text: String) -> Int { text.unicodeScalars.filter { $0.properties.isIdeographic }.count }

    private static let rewrites: [(String, String)] = [
        (#"[(（]([0-9]{4,6}[A-Z]?)[)）]"#, " $1 "),                                    // 台積電(2330)
        (#"\s+(?=[(（])"#, ""),                                                         // 付出成本 (元)
        (#"(?<![0-9,.])([0-9]{4,6}[A-Z]?)(?=\p{Han})(?![股張])(?!元(?!大))"#, "$1 "),   // 2330台積電, 0050元大台灣50
        (#"(?<=\p{Han})(?=[0-9]{4,6}[A-Z]?(?![0-9,.]))"#, " "),                         // 台積電2330
        ("(" + shareLabels.union(lotLabels).union(costLabels).union(unitCostLabels).union(["成本"]).sorted { $0.count > $1.count }.joined(separator: "|") + #")((?:[(（][^)）]*[)）])?)(?=[0-9])"#, "$1$2 ")  // 股數1,000
    ]
    /// The words of a line, with full-width digits and punctuation made plain and codes split from names.
    private static func tokens(_ line: String) -> [String] {
        var scalars = String.UnicodeScalarView()
        for scalar in line.unicodeScalars {
            switch scalar.value {
            case 0xFF10...0xFF19: scalars.append(Unicode.Scalar(scalar.value - 0xFF10 + 0x30)!)
            case 0xFF08: scalars.append("(")
            case 0xFF09: scalars.append(")")
            case 0xFF0C: scalars.append(",")
            case 0xFF0E: scalars.append(".")
            case 0x3A, 0xFF1A, 0x3000: scalars.append(" ")
            default: scalars.append(scalar)
            }
        }
        var text = String(scalars)
        for (pattern, template) in rewrites { text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression) }
        return text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
    /// What a title labels; a unit in brackets such as (張) is read too.
    private static func field(_ word: String) -> Field? {
        var title = word, inLots = false
        if let unit = title.range(of: #"[(（][^)）]*[)）]$"#, options: .regularExpression) { inLots = title[unit].contains("張"); title.removeSubrange(unit) }
        if costLabels.contains(title) { return .total }
        if unitCostLabels.contains(title) { return .perShare }
        if title == "成本" { return .anyCost }
        if lotLabels.contains(title) { return .lots }
        if shareLabels.contains(title) { return inLots ? .lots : .shares }
        return nil
    }
    /// A plain amount such as 1,000 or 580,365; signed figures and percentages are gains, not holdings.
    private static func amount(_ word: String) -> (number: Double, lots: Bool)? {
        var text = word, lots = false
        if text.hasSuffix("張") { lots = true; text.removeLast() } else if text.hasSuffix("股") || text.hasSuffix("元") { text.removeLast() }
        guard text.range(of: #"^([0-9]{1,3}(,[0-9]{3})+|[0-9]+)(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let number = Double(text.replacingOccurrences(of: ",", with: "")), number.isFinite else { return nil }
        return (number, lots)
    }
    /// A code missing from the lists beside a company name: a holding the app cannot import, so the figures
    /// after it must not go to the holding before it.
    private static func unlisted(_ words: [String]) -> Bool {
        words.indices.prefix(2).contains { i in
            DataChecks.code(words[i].uppercased()) && [i - 1, i + 1].contains { j in
                words.indices.contains(j) && field(words[j]) == nil && ideographs(words[j]) >= 2
            }
        }
    }
    private static func fill(_ row: inout Row, _ kind: Field, _ value: (number: Double, lots: Bool)) {
        switch kind {
        case .total: setCost(&row, value.number, .total)
        case .perShare: setCost(&row, value.number, .perShare)
        case .anyCost: setCost(&row, value.number, nil)
        case .shares, .lots:
            let shares = value.number * (kind == .lots || value.lots ? 1000 : 1)
            if row.shares == nil, shares > 0, shares == shares.rounded() { row.shares = shares }
        }
    }
    /// A total read under its title beats a price per share, which beats a cost whose title does not say which;
    /// of equal standing the first is kept.
    private static func setCost(_ row: inout Row, _ cost: Double, _ basis: Basis?) {
        func standing(_ basis: Basis?) -> Int { basis == .total ? 3 : basis == .perShare ? 2 : 1 }
        if row.cost == nil || standing(basis) > standing(row.basis) { row.cost = cost; row.basis = basis }
    }
}
