import Foundation

struct SymbolHistory {
    var bars: [DailyBar]
    var dividends: [DividendEvent]
    var splits: [SplitEvent]
    /// The close series looks unadjusted (a jump the splits do not explain); results get a caveat note.
    var suspect: Bool
    /// The bars are 富果's adjusted closes (dividends already in the price), not the exchanges' own.
    var fromFugle = false
}

struct BacktestInput {
    /// Weights sum to 1.
    var legs: [(symbol: String, weight: Double)]
    var monthly: Double
    var start: YearMonth
    var end: YearMonth
    var reinvest: Bool
}

struct BacktestResult {
    var invested: Double
    var endValue: Double
    var dividends: Double
    var xirr: Double?
    /// 0…1, peak-to-trough on the monthly value series.
    var maxDrawdown: Double
    var curve: [(month: YearMonth, invested: Double, value: Double)]
    var notes: [String]
}

enum Finance {
    /// Annualised internal rate of return, 365-day convention; bisection on -0.99…10; nil without a sign change.
    static func xirr(_ flows: [(date: Date, amount: Double)]) -> Double? {
        guard let t0 = flows.map(\.date).min(), let t1 = flows.map(\.date).max(),
              t1.timeIntervalSince(t0) >= 86_400,
              flows.contains(where: { $0.amount > 0 }), flows.contains(where: { $0.amount < 0 }) else { return nil }
        func f(_ r: Double) -> Double {
            flows.reduce(0) { sum, flow in
                let years = flow.date.timeIntervalSince(t0) / 86_400 / 365
                return sum + flow.amount / pow(1 + r, years)
            }
        }
        var lo = -0.99, hi = 10.0
        var fLo = f(lo)
        let fHi = f(hi)
        guard fLo.isFinite, fHi.isFinite, fLo * fHi <= 0 else { return nil }
        if fLo == 0 { return lo }
        if fHi == 0 { return hi }
        for _ in 0..<200 {
            let mid = (lo + hi) / 2
            let fMid = f(mid)
            if fMid == 0 { return mid }
            if (fMid < 0) == (fLo < 0) { lo = mid; fLo = fMid } else { hi = mid }
            if hi - lo < 1e-10 { break }
        }
        return (lo + hi) / 2
    }
}

enum Backtest {
    /// Largest peak-to-trough fall as a fraction of the peak.
    static func maxDrawdown(_ values: [Double]) -> Double {
        var peak = -Double.infinity, worst = 0.0
        for v in values {
            peak = max(peak, v)
            if peak > 0 { worst = max(worst, (peak - v) / peak) }
        }
        return worst
    }

    private static func month(of date: String) -> YearMonth? {
        let p = date.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]) else { return nil }
        return YearMonth(year: y, month: m)
    }

    private static func parse(_ date: String) -> Date? {
        let p = date.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal.date(from: DateComponents(year: y, month: m, day: d))
    }

    /// One leg's state at a month end.
    private struct MonthEnd { var holding: Double; var cash: Double }

    static func run(_ input: BacktestInput, history: [String: SymbolHistory]) -> BacktestResult {
        var notes: [String] = []
        var flows: [(date: Date, amount: Double)] = []
        var totalDividends = 0.0
        var lastBarDate: String?
        var holdings: [YearMonth: Double] = [:]
        var cash: [YearMonth: Double] = [:]
        var contributed: [YearMonth: Double] = [:]
        var active: Set<YearMonth> = []

        var months: [YearMonth] = []
        var cursor = input.start
        while cursor <= input.end { months.append(cursor); cursor = cursor.next() }

        for leg in input.legs {
            guard let h = history[leg.symbol] else {
                notes.append("\(leg.symbol) 沒有取得歷史資料，這次沒有計入")
                continue
            }
            let bars = h.bars.sorted { $0.date < $1.date }
            let splits = h.splits.sorted { $0.resumeDate < $1.resumeDate }
            let dividends = h.dividends.sorted { $0.exDate < $1.exDate }
            var si = 0, di = 0
            var shares = 0.0, legCash = 0.0
            var boughtMonths: Set<YearMonth> = []
            var firstMonth: YearMonth?
            var endState: [YearMonth: MonthEnd] = [:]

            for bar in bars {
                guard let bm = month(of: bar.date), bm >= input.start, bm <= input.end else { continue }
                if firstMonth == nil { firstMonth = bm }
                // (1) splits and (2) dividends due by this bar, in date order (split first on a tie); a dividend is
                // paid on the shares held at its date and reinvested at this close (next bar if its ex-date has none)
                while true {
                    let sd = si < splits.count && splits[si].resumeDate <= bar.date ? splits[si].resumeDate : nil
                    let dd = di < dividends.count && dividends[di].exDate <= bar.date ? dividends[di].exDate : nil
                    if let sdate = sd, dd == nil || sdate <= dd! {
                        shares *= splits[si].ratio; si += 1
                    } else if dd != nil {
                        let amount = shares * dividends[di].cash
                        totalDividends += amount
                        if input.reinvest, bar.close > 0 { shares += amount / bar.close } else { legCash += amount }
                        di += 1
                    } else { break }
                }
                // (3) monthly buy on the leg's first bar of the month
                if !boughtMonths.contains(bm), bar.close > 0 {
                    boughtMonths.insert(bm)
                    let amount = input.monthly * leg.weight
                    shares += amount / bar.close
                    contributed[bm, default: 0] += amount
                    if let d = parse(bar.date) { flows.append((d, -amount)) }
                }
                if lastBarDate == nil || bar.date > lastBarDate! { lastBarDate = bar.date }
                endState[bm] = MonthEnd(holding: shares * bar.close, cash: legCash)
            }
            // A month with no bar after listing keeps the leg's last known state; before listing it adds nothing.
            var carried: MonthEnd?
            for mm in months {
                if let s = endState[mm] { carried = s }
                guard let s = carried else { continue }
                holdings[mm, default: 0] += s.holding
                cash[mm, default: 0] += s.cash
                active.insert(mm)
            }
            if firstMonth == nil {
                notes.append("\(leg.symbol) 沒有取得歷史資料，這次沒有計入")
            }
            if let fm = firstMonth, fm > input.start {
                notes.append("\(leg.symbol) 於 \(fm.key) 上市，之前的月份不投入")
            }
            if h.suspect { notes.append("\(leg.symbol) 資料可能未還原，結果僅供參考") }
        }

        var curve: [(month: YearMonth, invested: Double, value: Double)] = []
        var running = 0.0
        // No points past the month of the latest bar: months beyond the data are not fabricated.
        let lastMonth = lastBarDate.flatMap { month(of: $0) } ?? input.end
        for mm in months {
            running += contributed[mm] ?? 0
            guard active.contains(mm), mm <= lastMonth else { continue }
            curve.append((mm, running, (holdings[mm] ?? 0) + (cash[mm] ?? 0)))
        }
        let endValue = curve.last?.value ?? 0
        var xirr: Double?
        if running > 0, let last = lastBarDate, let d = parse(last) {
            xirr = Finance.xirr(flows + [(d, endValue)])
        }
        return BacktestResult(invested: running, endValue: endValue, dividends: totalDividends, xirr: xirr,
                              maxDrawdown: maxDrawdown(curve.map(\.value)), curve: curve, notes: notes)
    }
}
