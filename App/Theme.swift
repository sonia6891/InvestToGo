import SwiftUI
import Charts
import UIKit

enum Palette {
    static let blue = Color(red: 0.12, green: 0.42, blue: 1.0)
    static let deepBlue = Color(red: 0.07, green: 0.31, blue: 0.88)
    // Text and surfaces follow the light or dark appearance chosen in Settings.
    static let ink = Color(light: UIColor(red: 0.06, green: 0.12, blue: 0.24, alpha: 1), dark: UIColor(red: 0.91, green: 0.93, blue: 0.98, alpha: 1))
    static let muted = Color(light: UIColor(red: 0.42, green: 0.48, blue: 0.60, alpha: 1), dark: UIColor(red: 0.59, green: 0.64, blue: 0.74, alpha: 1))
    static let background = Color(light: UIColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 1), dark: UIColor(red: 0.055, green: 0.086, blue: 0.157, alpha: 1))
    static let card = Color(light: .white, dark: UIColor(red: 0.09, green: 0.13, blue: 0.23, alpha: 1))
    static let cardSoft = Color(light: UIColor(red: 0.953, green: 0.965, blue: 1.0, alpha: 1), dark: UIColor(red: 0.114, green: 0.161, blue: 0.27, alpha: 1))
    static let teal = Color(red: 0.07, green: 0.70, blue: 0.77)
    static let red = Color(red: 0.90, green: 0.22, blue: 0.27)
    static let green = Color(red: 0.05, green: 0.62, blue: 0.42)
    static let orange = Color(red: 1.0, green: 0.58, blue: 0.10)
    static let pink = Color(red: 0.93, green: 0.33, blue: 0.52)
    static let purple = Color(red: 0.49, green: 0.33, blue: 0.96)
    // The approved design shows gains in green and losses in red (same as the web preview).
    static let up = green
    static let down = red
    /// Lighter versions for text on the blue hero gradient.
    static let heroUp = Color(red: 0.77, green: 0.97, blue: 0.83)
    static let heroDown = Color(red: 1.0, green: 0.82, blue: 0.83)
    static func trend(_ value: Double) -> Color { value > 0 ? up : (value < 0 ? down : muted) }
    static func strategy(_ value: Strategy) -> Color { switch value { case .saving: return pink; case .income: return green; case .risk: return purple; case .unclassified: return muted } }
    static func status(_ value: DividendStatus) -> Color { switch value { case .paid: return green; case .announced: return blue; case .estimated: return pink } }
    static let hero = LinearGradient(colors: [Color(red: 0.27, green: 0.58, blue: 1.0), Color(red: 0.08, green: 0.33, blue: 0.93)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let page = LinearGradient(colors: [Color(light: UIColor(red: 0.88, green: 0.92, blue: 1.0, alpha: 1), dark: UIColor(red: 0.075, green: 0.13, blue: 0.25, alpha: 1)), background], startPoint: .top, endPoint: .bottom)
    /// Allocation groups shown in the design's legends.
    static func theme(_ value: String) -> Color { switch value { case "市值型": return blue; case "高股息": return purple; case "產業主題": return teal; case "個股": return pink; default: return orange } }
    static let series: [Color] = [blue, pink, teal, orange, purple, green, Color(red: 0.54, green: 0.63, blue: 0.77)]
}
extension Color {
    init(light: UIColor, dark: UIColor) { self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light }) }
}

func money(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
func decimal(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
func priceText(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2))) }
func signed(_ value: Double, _ format: (Double) -> String = money) -> String { (value > 0 ? "+" : (value < 0 ? "-" : "")) + format(abs(value)) }
func percentText(_ value: Double) -> String { signed(value, decimal) + "%" }
func shown(_ text: String, hidden: Bool) -> String { hidden ? "＊＊＊＊" : text }
func weekdayText(_ date: Date) -> String { ["週日", "週一", "週二", "週三", "週四", "週五", "週六"][Calendar.current.component(.weekday, from: date) - 1] }
func ymdText(_ date: Date) -> String { let c = Calendar.current.dateComponents([.year, .month, .day], from: date); return String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0) }
/// Large totals in 萬 so they fit inside a donut.
func wanText(_ value: Double) -> String { abs(value) >= 1_000_000 ? "\(decimal((value / 1000).rounded() / 10))萬" : money(value) }
func monthDay(_ date: Date) -> String { "\(Calendar.current.component(.month, from: date))/\(Calendar.current.component(.day, from: date))" }

extension Strategy {
    /// Illustration in Assets.xcassets/Art (generated with Figma AI for the design); none for unclassified funds.
    var artwork: String? { switch self { case .saving: return "cat-saving"; case .income: return "cat-income"; case .risk: return "cat-risk"; case .unclassified: return nil } }
    var tagline: String { switch self { case .saving: return "長期累積"; case .income: return "配息現金流"; case .risk: return "高風險機會"; case .unclassified: return "尚未分類" } }
    var explanation: String {
        switch self {
        case .saving: return "追蹤大型權值或市值指數，成分股分散，適合長期定期投入累積。仍會隨股市漲跌波動。"
        case .income: return "名稱屬高股息／高息類型，著重配息現金流。配息可能來自收益或本金，配息率不等於報酬率。"
        case .risk: return "槓桿或反向型，每日重設、波動放大，較適合短期且需嚴格控管部位。"
        case .unclassified: return "尚未符合自動分類規則；新增持有時可自行選擇策略。"
        }
    }
    static let basis = "依 ETF 名稱自動整理：含「正2／反1／槓桿／反向」為老虎機；含「高股息／優息／高息」為印鈔機；元大台灣50、富邦台50、元大富櫃50 為存錢筒；其餘待分類。分類是整理策略的方式，不是收益保證。\n\n風險標示依資產類型參考投信基金 RR 風險等級慣例：股票型約 RR4（中高）、槓桿／反向型 RR5（高）、債券型 RR2–RR3（中低～中）。實際等級以各基金公開說明書為準。"
}
extension Fund {
    var isActive: Bool { id.hasSuffix("A") || name.contains("主動") || (fundType ?? "").contains("主動") }
    var managementStyle: String { isActive ? "主動式" : "被動式" }
    var marketName: String { market == "TPEx" ? "上櫃" : (market == "TWSE" ? "上市" : "上市櫃") }
    var assetClass: String {
        let type = fundType ?? ""
        if type.contains("債") || name.contains("債") { return "債券" }
        if type.contains("槓桿") || strategy == .risk { return "槓桿／反向" }
        if type.contains("期貨") { return "期貨" }
        if type.contains("國外") { return "海外股票" }
        if type.contains("國內") { return "台股" }
        return "其他"
    }
    static let assetClasses = ["台股", "海外股票", "債券", "槓桿／反向", "期貨", "其他"]
    private func matches(_ pattern: String, in text: String? = nil) -> Bool { (text ?? name).range(of: pattern, options: .regularExpression) != nil }
    /// The design's filter vocabulary, from the official fund type and the fund name.
    var assetKind: String {
        let type = fundType ?? ""
        if type.contains("債") || name.contains("債") { return "債券" }
        if type.contains("期貨") || matches("黃金|原油|白銀|黃豆|小麥|商品|石油") { return "商品" }
        return "股票"
    }
    var structure: String {
        if matches("正2|槓桿|2X") || id.hasSuffix("L") { return "槓桿型" }
        if matches("反1|反向|-1") || id.hasSuffix("R") { return "反向型" }
        return "一般型"
    }
    var industry: String? {
        guard assetKind == "股票" else { return nil }
        if matches("半導體|科技|電子|5G|AI|晶片|IC|通訊|網通|資安|雲端|電動車|機器人|元宇宙|智能|創新|未來|數位|網路") { return "科技" }
        if matches("金融|銀行|保險|證券") { return "金融" }
        if matches("航運|鋼鐵|塑化|水泥|營建|綠能|電池|原物料|能源|基建|公用|不動產|REIT|生技|醫療|消費|汽車|工業") { return "傳產" }
        return "跨產業"
    }
    var region: String {
        let type = fundType ?? "", text = name + " " + (fullName ?? "")
        if type.contains("國內") { return "台灣" }
        if matches("美國|美股|美債|標普|S&P|那斯達克|NASDAQ|道瓊|費城|美元|美", in: text) { return "美國" }
        if matches("日本|日經|東證", in: text) { return "日本" }
        if matches("中國|滬深|上證|A50|恒生|香港|中概|深證", in: text) { return "中國／香港" }
        if matches("印度", in: text) { return "印度" }
        if matches("歐洲|德國|歐盟|英國", in: text) { return "歐洲" }
        if matches("越南|東協|新興", in: text) { return "新興市場" }
        if matches("全球|世界|已開發", in: text) { return "全球" }
        return type.contains("國外") ? "其他海外" : "台灣"
    }
    var theme: String {
        if strategy == .income || matches("高股息|高息|優息|股利") { return "高股息" }
        if strategy == .saving || matches("台灣50|台50|中型100|市值|MSCI台灣|摩台|富櫃50|臺灣50|台灣領袖") { return "市值型" }
        if matches("半導體|科技|電動車|5G|AI|晶片|IC|通訊|網通|資安|雲端|生技|醫療|金融|綠能|電池|元宇宙|機器人|航運|創新|智能|電子|未來|ESG|永續") { return "產業主題" }
        return "其他"
    }
    var managementType: String { isActive ? "主動型" : "被動型" }
    /// Fund house, read from the start of the fund's name.
    var issuer: String? {
        let houses = [("華南永昌", "華南永昌投信"), ("第一金", "第一金投信"), ("大華銀", "大華銀投信"), ("富蘭克林", "富蘭克林華美投信"), ("FT", "富蘭克林華美投信"), ("中國信託", "中國信託投信"), ("中信", "中國信託投信"), ("貝萊德", "貝萊德投信"), ("聯博", "聯博投信"), ("野村", "野村投信"), ("摩根", "摩根投信"), ("安聯", "安聯投信"), ("匯豐", "匯豐中華投信"), ("街口", "街口投信"), ("元大", "元大投信"), ("富邦", "富邦投信"), ("國泰", "國泰投信"), ("群益", "群益投信"), ("復華", "復華投信"), ("永豐", "永豐投信"), ("凱基", "凱基投信"), ("統一", "統一投信"), ("兆豐", "兆豐投信"), ("新光", "新光投信"), ("台新", "台新投信"), ("玉山", "玉山投信"), ("中租", "中租投信"), ("保德信", "保德信投信"), ("瀚亞", "瀚亞投信"), ("路博邁", "路博邁投信")]
        for text in [fullName ?? "", name] {
            var trimmed = text
            for prefix in ["主動", "期"] where trimmed.hasPrefix(prefix) { trimmed.removeFirst(prefix.count) }
            if let hit = houses.first(where: { trimmed.hasPrefix($0.0) }) { return hit.1 }
        }
        return nil
    }
    /// Rough risk label by asset type, following the RR convention described in `Strategy.basis`.
    var riskLevel: String {
        switch assetClass {
        case "槓桿／反向", "期貨": return "高"
        case "債券": return "中"
        default: return "中高"
        }
    }
    var riskSentence: String {
        switch riskLevel {
        case "高": return "槓桿或期貨部位使波動放大，屬高風險。"
        case "中": return "以債券為主，價格仍受利率影響，屬中度風險。"
        default: return "股價波動直接反映在淨值，屬中高風險。"
        }
    }
}
extension Quote {
    var changeAmount: Double? {
        if let change { return change }
        guard let percent = changePercent, percent > -100 else { return nil }
        return price * percent / (100 + percent)
    }
}
extension PortfolioStore {
    func name(for symbol: String) -> String {
        funds.first { $0.id == symbol }?.name ?? stock(symbol)?.name ?? data.holdings.first { $0.symbol == symbol }?.name ?? symbol
    }
}

struct PortfolioSummary {
    let cost: Double
    let marketValue: Double?
    let paidTotal: Double
    let monthPaid: Double
    let monthPending: Double
    let symbolCount: Int
    init(_ data: Portfolio, month: Date = Date(), marketValue: Double?) {
        let inMonth = data.dividends.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
        cost = data.cost
        self.marketValue = marketValue
        paidTotal = data.dividends.filter { $0.status == .paid }.reduce(0) { $0 + $1.amount }
        monthPaid = inMonth.filter { $0.status == .paid }.reduce(0) { $0 + $1.amount }
        monthPending = inMonth.filter { $0.status != .paid }.reduce(0) { $0 + $1.amount }
        symbolCount = Set(data.holdings.map(\.symbol)).count
    }
    var unrealized: Double? { marketValue.map { $0 - cost } }
    var unrealizedPercent: Double? {
        guard let unrealized, cost > 0 else { return nil }
        return unrealized / cost * 100
    }
    var totalReturn: Double? { unrealized.map { $0 + paidTotal } }
    var totalReturnPercent: Double? {
        guard let totalReturn, cost > 0 else { return nil }
        return totalReturn / cost * 100
    }
}

struct ValuePoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}
enum ChartRange: String, CaseIterable, Identifiable {
    case week = "1週", month = "1月", quarter = "3月", year = "1年", threeYears = "3年", fiveYears = "5年", all = "全部"
    var id: String { rawValue }
    func start(from end: Date) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .week: return calendar.date(byAdding: .day, value: -7, to: end)
        case .month: return calendar.date(byAdding: .month, value: -1, to: end)
        case .quarter: return calendar.date(byAdding: .month, value: -3, to: end)
        case .year: return calendar.date(byAdding: .year, value: -1, to: end)
        case .threeYears: return calendar.date(byAdding: .year, value: -3, to: end)
        case .fiveYears: return calendar.date(byAdding: .year, value: -5, to: end)
        case .all: return nil
        }
    }
}
enum TrendMath {
    private static let parser: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Taipei"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    static func points(_ history: PriceHistory) -> [ValuePoint] {
        history.points.compactMap { point in parser.date(from: point.date).map { ValuePoint(date: $0, value: point.close) } }
    }
    /// Current share counts valued at each adjusted close. Only days on which every held ETF has a price are kept,
    /// and nothing is shown unless every holding has a TWD quote and a stored history.
    static func portfolio(_ data: Portfolio) -> [ValuePoint] {
        var shares: [String: Double] = [:]
        for holding in data.holdings { shares[holding.symbol, default: 0] += holding.shares }
        guard !shares.isEmpty else { return [] }
        var totals: [String: Double] = [:]
        var counts: [String: Int] = [:]
        for (symbol, quantity) in shares {
            guard data.quotes[symbol]?.isTWD == true, let history = data.histories?[symbol] else { return [] }
            for point in history.points {
                totals[point.date, default: 0] += quantity * point.close
                counts[point.date, default: 0] += 1
            }
        }
        var result: [ValuePoint] = []
        for (day, value) in totals where counts[day] == shares.count {
            if let date = parser.date(from: day) { result.append(ValuePoint(date: date, value: value)) }
        }
        return result.sorted { $0.date < $1.date }
    }
    static func slice(_ points: [ValuePoint], _ range: ChartRange) -> [ValuePoint] {
        guard let last = points.last, let start = range.start(from: last.date) else { return points }
        return points.filter { $0.date >= start }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: Palette.blue.opacity(0.07), radius: 12, y: 4)
    }
}
struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .modifier(MinimizeOnScroll())
        .background { Palette.page.ignoresSafeArea() }
    }
}
struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Capsule().fill(Palette.blue).frame(width: 4, height: 16)
                Text(title).font(.headline).foregroundStyle(Palette.ink)
            }
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Palette.muted) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct StrategyPill: View {
    let strategy: Strategy
    var body: some View {
        Text(strategy.rawValue).font(.caption2.bold()).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(Palette.strategy(strategy))
            .background(Palette.strategy(strategy).opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
    }
}
struct StatusPill: View {
    let status: DividendStatus
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Palette.status(status)).frame(width: 6, height: 6)
            Text(status.rawValue).font(.caption2.bold())
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .foregroundStyle(Palette.status(status))
        .background(Palette.status(status).opacity(0.12), in: Capsule())
    }
}
/// One of the design's illustrations, scaled to fit a square; decorative, so hidden from VoiceOver.
struct Artwork: View {
    let name: String
    var size: CGFloat = 56
    var body: some View {
        Image(name).resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
/// The strategy's illustration, or a tag symbol for unclassified funds.
struct StrategyArt: View {
    let strategy: Strategy
    var size: CGFloat = 56
    var body: some View {
        if let name = strategy.artwork {
            Artwork(name: name, size: size)
        } else {
            Image(systemName: "tag.fill").font(.system(size: size * 0.45)).foregroundStyle(Palette.muted)
                .frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}
/// "▲ +1.20 (+0.65%)" in the design's colours (gains green, losses red); nothing is invented when the quote has no change data.
struct QuoteChange: View {
    let quote: Quote?
    var font: Font = .caption
    var body: some View {
        if let quote, quote.trial == true {
            Text("試撮 \(quote.changePercent.map(percentText) ?? "")").font(font.weight(.semibold)).monospacedDigit().lineLimit(1).foregroundStyle(Palette.muted)
        } else if let quote, let percent = quote.changePercent {
            let arrow = percent > 0 ? "▲" : (percent < 0 ? "▼" : "－")
            let amount = quote.changeAmount.map { signed($0, priceText) } ?? ""
            Text("\(arrow) \(amount) (\(percentText(percent)))")
                .font(font.weight(.semibold)).monospacedDigit().lineLimit(1)
                .foregroundStyle(Palette.trend(percent))
        } else {
            Text(quote == nil ? "未取得報價" : "無漲跌資料").font(font).foregroundStyle(Palette.muted)
        }
    }
}
struct SegmentBar: View {
    let items: [String]
    @Binding var selection: Int
    var pill = false
    /// Blue filled selection, as the design's main page tabs.
    var filled = false
    var icons: [String]? = nil
    var body: some View {
        HStack(spacing: pill ? 4 : 0) {
            ForEach(items.indices, id: \.self) { index in
                Button { withAnimation(.snappy) { selection = index } } label: { label(index) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(items[index])
                    .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
        .padding(pill ? 4 : 0)
        .background(pill ? Palette.blue.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
    }
    @ViewBuilder private func label(_ index: Int) -> some View {
        let active = selection == index
        if pill {
            HStack(spacing: 5) {
                if let icons, icons.indices.contains(index) { Image(systemName: icons[index]).font(.caption.bold()) }
                Text(items[index]).font(.subheadline.weight(active ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
                .foregroundStyle(active ? (filled ? Color.white : Palette.blue) : Palette.muted)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(active ? (filled ? Palette.blue : Palette.card) : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                .shadow(color: active && filled ? Palette.blue.opacity(0.28) : .clear, radius: 6, y: 3)
                .contentShape(Rectangle())
        } else {
            VStack(spacing: 7) {
                Text(items[index]).font(.subheadline.weight(active ? .bold : .medium))
                    .foregroundStyle(active ? Palette.blue : Palette.muted)
                Capsule().fill(active ? Palette.blue : Color.clear).frame(width: 26, height: 3)
            }
            .frame(maxWidth: .infinity).padding(.top, 4)
            .contentShape(Rectangle())
        }
    }
}
struct RangeChips: View {
    let options: [ChartRange]
    @Binding var selection: ChartRange
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                Button { selection = option } label: {
                    Text(option.rawValue).font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .foregroundStyle(selection == option ? .white : Palette.ink)
                        .background(selection == option ? Palette.blue : Palette.card, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
    }
}
struct ValueChart: View {
    let points: [ValuePoint]
    var showAxes = false
    var height: CGFloat = 150
    var tint: Color = Palette.blue
    var body: some View {
        let values = points.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.12, abs(high) * 0.002, 0.01)
        let base = low - pad
        Chart(points) { point in
            AreaMark(x: .value("日期", point.date), yStart: .value("基準", base), yEnd: .value("數值", point.value))
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.26), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("日期", point.date), y: .value("數值", point.value))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: base...(high + pad))
        .chartXAxis(showAxes ? .automatic : .hidden)
        .chartYAxis(showAxes ? .automatic : .hidden)
        .frame(height: height)
    }
}
struct StatTile: View {
    let title: String
    let value: String
    var icon: String? = nil
    var tint: Color = Palette.blue
    /// An illustration from Assets.xcassets/Art, shown instead of `icon`.
    var art: String? = nil
    var body: some View {
        HStack(spacing: 10) {
            if let art {
                Artwork(name: art, size: 40).frame(width: 46, height: 46).background(tint.opacity(0.1), in: Circle())
            } else if let icon {
                Image(systemName: icon).font(.headline).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(tint.gradient, in: Circle())
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption).foregroundStyle(Palette.muted)
                Text(value).font(.title3.bold()).monospacedDigit().foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: Palette.blue.opacity(0.06), radius: 10, y: 3)
    }
}
struct ToolRow: View {
    let title: String
    let subtitle: String
    let icon: String
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.title3).foregroundStyle(Palette.blue)
                .frame(width: 42, height: 42).background(Palette.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                Text(subtitle).font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
        }.padding(.vertical, 8)
    }
}
struct PrimaryButtonLabel: View {
    let title: String
    var icon = "plus"
    var body: some View {
        Label(title, systemImage: icon).font(.headline)
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .foregroundStyle(.white)
            .background(Palette.hero, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: Palette.blue.opacity(0.3), radius: 10, y: 4)
    }
}

/* Components for the template set: floating tab bar, date boxes, accent rows, donut and bar lists. */
struct TabSpec {
    let title: String
    let icon: String
    let colors: [Color]
}
enum AppTabs {
    static let items: [TabSpec] = [
        TabSpec(title: "首頁", icon: "house.fill", colors: [Color(red: 0.37, green: 0.64, blue: 1.0), Palette.blue]),
        TabSpec(title: "探索", icon: "magnifyingglass", colors: [Color(red: 0.25, green: 0.84, blue: 0.84), Color(red: 0.05, green: 0.62, blue: 0.71)]),
        TabSpec(title: "持有", icon: "bag.fill", colors: [Color(red: 1.0, green: 0.75, blue: 0.31), Palette.orange]),
        TabSpec(title: "配息", icon: "calendar", colors: [Color(red: 1.0, green: 0.49, blue: 0.67), Palette.pink]),
        TabSpec(title: "工具", icon: "square.grid.2x2.fill", colors: [Color(red: 0.67, green: 0.55, blue: 1.0), Palette.purple]),
    ]
}
/// The design's floating tab bar with iOS 26-style motion. Each icon is a glass orb; the selection is a round glass
/// lens that flows like a droplet from the old orb to the new one and settles around it. Icons bounce, presses
/// squeeze, and scrolling down shrinks the bar to the current tab (scrolling up or tapping restores it).
/// On iOS 26 the bar and orbs use Liquid Glass; earlier versions draw glossy orbs on a frosted bar.
struct FloatingTabBar: View {
    @Binding var selection: Int
    var minimized = false
    var reselect: (Int) -> Void
    var expand: () -> Void = {}
    @State private var bounce = [0, 0, 0, 0, 0]
    @State private var centres: [Int: CGFloat] = [:]
    @State private var lensX: CGFloat = 0
    @State private var lensWidth: CGFloat = 52
    @State private var flowing = false
    /// Vertical centre of an orb inside the row of tabs.
    private let orbCentreY: CGFloat = 20
    var body: some View {
        HStack(spacing: 0) {
            if minimized {
                Button(action: expand) { orb(selection, on: false).padding(6) }
                    .buttonStyle(PressScale())
                    .accessibilityLabel("展開分頁列，目前在\(AppTabs.items[selection].title)")
            } else {
                ForEach(AppTabs.items.indices, id: \.self) { index in item(index) }
            }
        }
        .coordinateSpace(.named("tabbar"))
        .background(alignment: .topLeading) {
            if !minimized {
                SelectionLens()
                    .frame(width: lensWidth, height: flowing ? 46 : 52)
                    .offset(x: lensX, y: orbCentreY - (flowing ? 23 : 26))
                    .allowsHitTesting(false)
            }
        }
        .onPreferenceChange(OrbCentresKey.self) { value in
            centres = value
            if !flowing, let centre = value[selection] { lensX = centre - 26; lensWidth = 52 }
        }
        .onChange(of: selection) { old, new in flow(from: old, to: new) }
        .padding(.vertical, minimized ? 0 : 7).padding(.horizontal, minimized ? 0 : 4)
        .modifier(LiquidGlass(shape: RoundedRectangle(cornerRadius: 30, style: .continuous)))
        .frame(maxWidth: .infinity, alignment: minimized ? .leading : .center)
        .padding(.horizontal, minimized ? 16 : 12).padding(.bottom, 4)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: minimized)
        .sensoryFeedback(.selection, trigger: selection)
    }
    private func flow(from old: Int, to new: Int) {
        guard let a = centres[old], let b = centres[new] else { return }
        withAnimation(.easeInOut(duration: 0.2)) { lensX = min(a, b) - 26; lensWidth = abs(b - a) + 52; flowing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.6)) { lensX = b - 26; lensWidth = 52; flowing = false }
        }
    }
    private func item(_ index: Int) -> some View {
        let item = AppTabs.items[index], on = selection == index
        return Button {
            if on { reselect(index) } else { bounce[index] += 1; selection = index }
        } label: {
            VStack(spacing: 3) {
                orb(index, on: on)
                Text(item.title).font(.caption2.weight(on ? .heavy : .bold)).foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 3)
            .background(GeometryReader { proxy in Color.clear.preference(key: OrbCentresKey.self, value: [index: proxy.frame(in: .named("tabbar")).midX]) })
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(item.title)
        .accessibilityIdentifier("tab-\(item.title)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
    private func orb(_ index: Int, on: Bool) -> some View {
        let item = AppTabs.items[index]
        return Image(systemName: item.icon).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            .shadow(color: Color.black.opacity(0.18), radius: 1, y: 1)
            .symbolEffect(.bounce, value: bounce[index])
            .frame(width: 40, height: 40)
            .modifier(GlassOrb(colors: item.colors))
            .scaleEffect(on ? 1.12 : 1).offset(y: on ? -3 : 0)
            .animation(.spring(response: 0.38, dampingFraction: 0.6), value: on)
    }
}
private struct OrbCentresKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) { value.merge(nextValue()) { $1 } }
}
/// A coloured orb: tinted, interactive Liquid Glass on iOS 26; a glossy sphere (highlight, rim, inner shade) before that.
struct GlassOrb: ViewModifier {
    let colors: [Color]
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(colors.last ?? Palette.blue).interactive(), in: Circle())
                .shadow(color: (colors.last ?? Palette.blue).opacity(0.35), radius: 6, y: 3)
        } else {
            glossy(content)
        }
        #else
        glossy(content)
        #endif
    }
    private func glossy(_ content: Content) -> some View {
        content
            .background {
                ZStack {
                    Circle().fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    Circle().fill(RadialGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0)], center: UnitPoint(x: 0.3, y: 0.22), startRadius: 0, endRadius: 18))
                    Ellipse().fill(LinearGradient(colors: [Color.white.opacity(0.75), Color.white.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 26, height: 15).offset(y: -10)
                    Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                    Circle().strokeBorder(LinearGradient(colors: [Color.clear, Color.black.opacity(0.14)], startPoint: .top, endPoint: .bottom), lineWidth: 4).blur(radius: 2)
                }
                .clipShape(Circle())
            }
            .shadow(color: (colors.last ?? Palette.blue).opacity(0.35), radius: 6, y: 3)
    }
}
/// The round glass lens around the selected orb.
struct SelectionLens: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(RadialGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.18)], center: UnitPoint(x: 0.5, y: 0.28), startRadius: 0, endRadius: 34))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
            .overlay(Capsule(style: .continuous).strokeBorder(LinearGradient(colors: [Color.clear, Palette.blue.opacity(0.18)], startPoint: .top, endPoint: .bottom), lineWidth: 5).blur(radius: 3))
            .shadow(color: Palette.blue.opacity(0.22), radius: 10, y: 6)
    }
}
/// Buttons squeeze while pressed and spring back.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
/// Liquid Glass on iOS 26 (interactive, so it reacts to touch); a frosted material with a light rim before that.
struct LiquidGlass<S: Shape>: ViewModifier {
    let shape: S
    var interactive = true
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            frosted(content)
        }
        #else
        frosted(content)
        #endif
    }
    private func frosted(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.45), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.12), radius: 16, y: 8)
    }
}
/// Pages report scrolling so the tab bar can shrink while reading and come back when scrolling up.
private struct TabBarMinimizeKey: EnvironmentKey {
    static let defaultValue: (Bool) -> Void = { _ in }
}
extension EnvironmentValues {
    var tabBarMinimize: (Bool) -> Void {
        get { self[TabBarMinimizeKey.self] }
        set { self[TabBarMinimizeKey.self] = newValue }
    }
}
struct MinimizeOnScroll: ViewModifier {
    @Environment(\.tabBarMinimize) private var report
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { old, new in
                if new < 60 { report(false) } else if new - old > 8 { report(true) } else if old - new > 8 { report(false) }
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
struct DateBox: View {
    let date: Date
    var body: some View {
        VStack(spacing: 1) {
            Text(monthDay(date)).font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.blue)
            Text(weekdayText(date)).font(.caption2).foregroundStyle(Palette.muted)
        }
        .frame(width: 50).padding(.vertical, 5)
        .background(Palette.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }
}
struct AccentRow: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 12).padding(.leading, 18).padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) { Capsule().fill(color).frame(width: 4).padding(.vertical, 10) }
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Palette.blue.opacity(0.06), radius: 8, y: 3)
    }
}
extension View {
    func accentRow(_ color: Color) -> some View { modifier(AccentRow(color: color)) }
    /// Room for the floating tab bar. The tab stack's own inset does not reach pushed screens, so every destination adds it.
    func tabBarSpace() -> some View { safeAreaInset(edge: .bottom) { Color.clear.frame(height: 76) } }
}
/// Rising bars drawn on the blue hero cards.
struct HeroDeco: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array([0.32, 0.46, 0.4, 0.62, 0.78, 0.95].enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.22 + Double(index) * 0.08)).frame(width: 11, height: 58 * height)
            }
        }
        .frame(height: 58)
        .accessibilityHidden(true)
    }
}
struct Slice: Identifiable {
    let label: String
    let amount: Double
    let color: Color
    var id: String { label }
}
func makeSlices<T>(_ items: [T], key: (T) -> String, value: (T) -> Double) -> [Slice] {
    var totals: [String: Double] = [:]
    for item in items { totals[key(item), default: 0] += value(item) }
    return totals.filter { $0.value > 0 }.sorted { $0.value > $1.value }.enumerated().map { Slice(label: $0.element.key, amount: $0.element.value, color: Palette.series[$0.offset % Palette.series.count]) }
}
struct DonutChart: View {
    let slices: [Slice]
    var center: (title: String, value: String)? = nil
    var showAmounts = false
    var hidden = false
    var body: some View {
        let total = max(slices.reduce(0.0) { $0 + $1.amount }, 0.000001)
        HStack(spacing: 14) {
            Chart(slices) { slice in
                SectorMark(angle: .value("金額", slice.amount), innerRadius: .ratio(0.68), angularInset: 1.5)
                    .foregroundStyle(slice.color)
                    .cornerRadius(3)
            }
            .chartLegend(.hidden)
            .frame(width: 118, height: 118)
            .overlay {
                if let center {
                    VStack(spacing: 1) {
                        Text(center.title).font(.caption2).foregroundStyle(Palette.muted)
                        Text(center.value).font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1)
                    }.frame(width: 74)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                ForEach(slices) { slice in
                    HStack(spacing: 6) {
                        Circle().fill(slice.color).frame(width: 9, height: 9)
                        Text(slice.label).font(.subheadline).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        Text("\(decimal(slice.amount / total * 100))%").font(showAmounts ? .caption : .subheadline.bold()).monospacedDigit().foregroundStyle(showAmounts ? Palette.muted : Palette.ink)
                        if showAmounts { Text(shown(money(slice.amount), hidden: hidden)).font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.ink) }
                    }
                }
            }
        }
    }
}
struct BarList: View {
    let slices: [Slice]
    var body: some View {
        let total = max(slices.reduce(0.0) { $0 + $1.amount }, 0.000001)
        VStack(spacing: 10) {
            ForEach(slices) { slice in
                HStack(spacing: 10) {
                    Text(slice.label).font(.caption.bold()).foregroundStyle(Palette.ink).frame(width: 76, alignment: .leading).lineLimit(1)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.blue.opacity(0.1))
                            Capsule().fill(slice.color).frame(width: proxy.size.width * slice.amount / total)
                        }
                    }.frame(height: 7)
                    Text("\(decimal(slice.amount / total * 100))%").font(.caption.bold()).monospacedDigit().foregroundStyle(Palette.ink).frame(width: 52, alignment: .trailing)
                }
            }
        }
    }
}
struct NumberedHeading: View {
    let number: Int
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Text("\(number)").font(.caption.bold()).foregroundStyle(.white).frame(width: 22, height: 22).background(Palette.blue, in: Circle())
            Text(title).font(.headline).foregroundStyle(Palette.ink)
        }
    }
}
struct TagChip: View {
    let title: String
    var icon: String? = nil
    var art: String? = nil
    var tint: Color = Palette.ink
    var body: some View {
        HStack(spacing: 5) {
            if let art { Artwork(name: art, size: 18) } else if let icon { Image(systemName: icon).font(.caption.bold()) }
            Text(title).font(.caption.bold())
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Palette.card, in: Capsule())
        .shadow(color: Palette.blue.opacity(0.08), radius: 5, y: 2)
    }
}
/// Small pill in a chosen colour, e.g. a status or a market label.
struct TintPill: View {
    let title: String
    var color: Color = Palette.blue
    var body: some View {
        Text(title).font(.caption2.bold()).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
    }
}
/// A labelled number field with a unit, as in the design's forms.
struct FieldRow<Field: View>: View {
    let title: String
    var bar = false
    @ViewBuilder var field: Field
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                if bar { Capsule().fill(Palette.blue).frame(width: 3, height: 14) }
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(2)
            }.frame(width: 118, alignment: .leading)
            field
                .padding(.horizontal, 10).padding(.vertical, 10)
                .background(Palette.cardSoft, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.vertical, 4)
    }
}
struct UnitField: View {
    let placeholder: String
    @Binding var text: String
    let unit: String
    var identifier: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text).keyboardType(.decimalPad).monospacedDigit()
                .accessibilityIdentifier(identifier ?? placeholder)
            if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(Palette.muted) }
        }
    }
}
