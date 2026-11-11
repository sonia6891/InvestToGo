import Foundation

/// A broker's selling fee: the discount in 折 (2.8 means 28% of the list 0.1425%) and the smallest fee charged.
struct FeeRate: Codable, Equatable {
    var discount: Double
    var minimum: Double
    var valid: FeeRate { FeeRate(discount: min(max(discount, 0), 10), minimum: min(max(minimum, 0), 1000)) }
}

/// 市值 the way brokers show it: what selling today would bring in, the price × shares less the estimated selling fee
/// (0.1425% × the broker's discount, rounded down, at least its minimum) and the securities transaction tax (stocks
/// 0.3%, ETFs 0.1%, bond ETFs exempt through 2026), also rounded down. Discounts differ by broker and by account, so
/// each broker's rate is the viewer's to set in 設定; a broker without one is charged the list price.
enum SellCosts {
    static let netKey = "netMarketValue", ratesKey = "brokerFeeRates"
    /// The list price: no discount, at least NT$20 (most brokers' minimum on a board-lot trade).
    static let standard = FeeRate(discount: 10, minimum: 20)
    /// Bond ETFs are exempt from the transaction tax until the end of 2026.
    static let bondExemptionEnd = DataChecks.date("2027-01-01")!
    /// Deduct the estimated selling costs from 市值 (on unless turned off).
    static var enabled: Bool { (UserDefaults.standard.object(forKey: netKey) as? Bool) ?? true }

    /// The broker a fee belongs to: 融資 holdings sell through the same broker as cash ones.
    static func brokerKey(_ broker: String) -> String {
        broker.replacingOccurrences(of: "（融資）", with: "").replacingOccurrences(of: "(融資)", with: "").trimmingCharacters(in: .whitespaces)
    }
    /// The rates the viewer set, by broker; the key "" holds a default for every other broker. Decoded once per
    /// defaults store and kept, since marketValue(of:) asks for a rate on every holding of every render.
    static func rates(in defaults: UserDefaults = .standard) -> [String: FeeRate] {
        if defaults === UserDefaults.standard, let known = cached { return known }
        let stored = defaults.data(forKey: ratesKey).flatMap { try? JSONDecoder().decode([String: FeeRate].self, from: $0) } ?? [:]
        if defaults === UserDefaults.standard { cached = stored }
        return stored
    }
    static func save(_ rates: [String: FeeRate], in defaults: UserDefaults = .standard) {
        if let bytes = try? JSONEncoder().encode(rates) { defaults.set(bytes, forKey: ratesKey) }
        if defaults === UserDefaults.standard { cached = rates }
    }
    /// The app's own store, decoded once; test suites are read each time.
    private static var cached: [String: FeeRate]?
    /// The viewer's own rate for the broker, else its common online rate, else the viewer's default, else the list price.
    static func rate(for broker: String, in defaults: UserDefaults = .standard) -> FeeRate {
        let set = rates(in: defaults), key = brokerKey(broker)
        return (set[key] ?? preset(for: key) ?? set[""] ?? standard).valid
    }
    /// Whether this broker's fee is known (the viewer's own, or a common rate) rather than the list price.
    static func isSet(for broker: String, in defaults: UserDefaults = .standard) -> Bool {
        let set = rates(in: defaults), key = brokerKey(broker)
        return set[key] != nil || preset(for: key) != nil || set[""] != nil
    }
    /// Keeps the rate the viewer confirmed for a broker (adding a holding, a trade or an import); a rate equal to what
    /// the broker would get anyway is not stored, so a common rate stays a common rate.
    static func remember(_ rate: FeeRate, for broker: String, in defaults: UserDefaults = .standard) {
        let key = brokerKey(broker)
        guard !key.isEmpty else { return }
        var set = rates(in: defaults)
        if set[key] == nil && rate.valid == (preset(for: key) ?? set[""] ?? standard).valid { return }
        set[key] = rate.valid
        save(set, in: defaults)
    }
    /// Where a broker's rate comes from, in a sentence for the screen.
    static func rateNote(for broker: String, in defaults: UserDefaults = .standard) -> String {
        let set = rates(in: defaults), key = brokerKey(broker)
        if set[key] != nil { return "你為\(key)設定的折扣，用來估算市值。" }
        if preset(for: key) != nil { return "\(key)常見的電子下單優惠，實際以你的帳戶為準，可直接修改。" }
        if set[""] != nil { return "用你在設定裡的預設折扣；這家的優惠不同可直接修改。" }
        return "沒有這家的常見優惠，先用原價（不打折、最低 20 元）；請改成你的折扣。"
    }

    /// Common online-order (電子下單) rates as reported in 2026. Promotions differ by account, monthly amount and over
    /// time, so they are only where a broker starts; the viewer's own rate always wins.
    static let presets: [(name: String, core: String, rate: FeeRate)] = [
        ("國泰證券", "國泰", FeeRate(discount: 2.8, minimum: 1)),
        ("永豐金證券", "永豐", FeeRate(discount: 2, minimum: 1)),
        ("元大證券", "元大", FeeRate(discount: 6, minimum: 20)),
        ("富邦證券", "富邦", FeeRate(discount: 6, minimum: 20)),
        ("凱基證券", "凱基", FeeRate(discount: 6, minimum: 20)),
        ("群益證券", "群益", FeeRate(discount: 6, minimum: 20)),
    ]
    /// Other brokers offered for picking; they start at the list price.
    static let otherBrokers = ["元富證券", "統一證券", "兆豐證券", "第一金證券", "華南永昌證券", "台新證券", "玉山證券", "中國信託證券", "康和證券", "國票證券", "新光證券"]
    /// 「國泰」, 「國泰證券」 and 「國泰綜合證券」 are the same broker.
    static func preset(for broker: String) -> FeeRate? {
        let key = brokerKey(broker)
        guard !key.isEmpty else { return nil }
        return presets.first { key.contains($0.core) }?.rate
    }

    static func taxRate(stock: Bool, bond: Bool, on day: Date = Date()) -> Double {
        if stock { return 0.003 }
        return bond && day < bondExemptionEnd ? 0 : 0.001
    }
    static func fee(_ gross: Double, rate: FeeRate) -> Double {
        guard gross > 0 else { return 0 }
        return max(rate.minimum, down(gross * 0.001425 * rate.discount / 10))
    }
    /// The price × shares after the estimated fee and tax of selling them.
    static func net(_ gross: Double, stock: Bool, bond: Bool, rate: FeeRate, on day: Date = Date()) -> Double {
        guard gross > 0 else { return gross }
        let tax = down(gross * taxRate(stock: stock, bond: bond, on: day))
        return gross - fee(gross, rate: rate.valid) - tax
    }
    /// Rounded down to whole dollars; a hair is added so 300.0 that comes out as 299.9999… stays 300.
    private static func down(_ value: Double) -> Double { (value + 1e-6).rounded(.down) }
}
