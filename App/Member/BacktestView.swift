import SwiftUI
import Charts

/// Runs one 回測: downloads each ETF's history in turn, then hands it to `Backtest.run`. Leaving the screen cancels it.
@MainActor final class BacktestModel: ObservableObject {
    /// A first download takes minutes and stops when the app is suspended, so the screen stays on for as long as a
    /// run lasts and not a moment longer: however a run ends (result, error, cancel, leaving the page), `running`
    /// goes back to false here and the auto-lock comes back with it.
    @Published private(set) var running = false {
        didSet { if running != oldValue { keepAwake(running) } }
    }
    private let keepAwake: @MainActor (Bool) -> Void
    @Published private(set) var progress = 0.0
    @Published private(set) var result: BacktestResult?
    /// The finished or running result reads 富果's adjusted closes instead of the exchanges. It is what was really
    /// used: a run that began on 富果 and had to turn to the exchanges says the exchanges.
    @Published private(set) var fromFugle = false
    /// A 富果 key is saved, so the next run asks 富果 first (what the wait is said to be before a run).
    @Published private(set) var keySaved = false
    /// A download that failed, in plain words (offline or not); shown with 「再試一次」.
    @Published private(set) var error: String?
    /// A code neither exchange knows: the user's to fix, not a failed download.
    @Published private(set) var notFound: String?
    /// Seconds the next download is expected to take; nil until worked out, or with a 富果 key.
    @Published private(set) var estimate: Int?
    private var task: Task<Void, Never>?
    /// Only the latest run may report: a cancelled one stays silent.
    private var runID = 0

    init(keepAwake: @escaping @MainActor (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }) {
        self.keepAwake = keepAwake
    }

    /// `years` × 12 monthly buys, the last one this month (Taipei time): five years from November 2026 is
    /// December 2021 to November 2026, 60 months.
    static func window(years: Int, now: Date = Date()) -> (start: YearMonth, end: YearMonth) {
        let end = YearMonth(now)
        return (YearMonth(year: end.year - years, month: end.month).next(), end)
    }

    /// What the wait will be like, said before and during the download.
    static func estimateText(seconds: Int?, fugle: Bool) -> String? {
        if fugle { return "用富果下載，不到 1 分鐘，離開這頁會停止。" }
        guard let seconds else { return nil }
        if seconds <= 0 { return "歷史資料已經在手機裡，不用再下載。" }
        if seconds < 60 { return "下載不到 1 分鐘，離開這頁會停止。" }
        let minutes = Int((Double(seconds) / 60).rounded(.up))
        return "第一次下載大約需要 \(minutes) 分鐘（之後會快很多），離開這頁會停止。"
    }

    /// Reads the cache (no network) to see how much is left to download for these codes.
    func refreshEstimate(symbols: [String], markets: [String: String], listed: [String: YearMonth], years: Int,
                         client: OfficialHistoryClient = .shared) async {
        guard !running else { return }
        // Not `fromFugle`: that belongs to the result on screen, and a finished run's source does not change.
        keySaved = client.usesFugle
        let window = Self.window(years: years)
        var seconds = 0
        for symbol in symbols {
            seconds += await client.estimatedSeconds(symbol: symbol, market: markets[symbol], listed: listed[symbol], from: window.start, to: window.end)
        }
        guard !Task.isCancelled, !running else { return }
        estimate = seconds
    }

    func run(legs: [(symbol: String, weight: Double)], markets: [String: String], listed: [String: YearMonth], monthly: Double, years: Int,
             reinvest: Bool, client: OfficialHistoryClient = .shared) {
        task?.cancel()
        runID += 1
        let id = runID
        running = true; progress = 0; error = nil; notFound = nil; result = nil
        fromFugle = client.usesFugle
        keySaved = fromFugle
        task = Task {
            let window = Self.window(years: years)
            let count = Double(max(legs.count, 1))
            var history: [String: SymbolHistory] = [:]
            var current = ""
            do {
                var fugle = client.usesFugle
                var i = 0
                while i < legs.count {
                    let leg = legs[i], index = i
                    current = leg.symbol
                    let one = try await client.history(symbol: leg.symbol, market: markets[leg.symbol], listed: listed[leg.symbol],
                                                       from: window.start, to: window.end, fugle: fugle,
                                                       fellBack: { Task { @MainActor in self.usesExchanges(id) } }) { part in
                        Task { @MainActor in self.report(id, (Double(index) + part) / count) }
                    }
                    if fugle, !one.fromFugle {
                        // 富果 did not answer for this one. Every leg then reads the exchanges, the ones already
                        // read from 富果 too: a result has one source and one way of counting dividends.
                        fugle = false
                        self.usesExchanges(id)
                        if i > 0 { history = [:]; i = 0; continue }
                    }
                    history[leg.symbol] = one
                    i += 1
                }
                try Task.checkCancellation()
                let input = BacktestInput(legs: legs, monthly: monthly, start: window.start, end: window.end, reinvest: reinvest)
                self.finish(id, result: Backtest.run(input, history: history))
            } catch {
                if Task.isCancelled || error is CancellationError {
                    self.finish(id, result: nil)
                } else if let known = error as? AppDataError, known.text == OfficialHistoryClient.notFound {
                    self.finish(id, result: nil, notFound: "找不到 \(current) 的歷史資料，請確認代號。")
                } else {
                    // Reported with the screen's name only: no codes, holdings or amounts.
                    let offline = Connectivity.shared.offline || (error as? URLError)?.code == .notConnectedToInternet
                    CrashReporting.capture(error, context: "backtest", offline: offline)
                    self.finish(id, result: nil, error: offline ? "目前沒有網路，稍後再試。" : "暫時取不到，稍後再試。")
                }
            }
        }
    }

    func cancel() {
        task?.cancel(); task = nil
        runID += 1
        running = false
    }

    private func report(_ id: Int, _ value: Double) {
        guard id == runID, running else { return }
        progress = max(progress, min(1, value))
    }

    /// 富果 did not answer in this run: what is shown from here on is the exchanges' data. How long their download
    /// takes was not worked out (with a key the estimate is 富果's), so no wait is promised.
    private func usesExchanges(_ id: Int) {
        guard id == runID, running else { return }
        fromFugle = false
        estimate = nil
    }

    private func finish(_ id: Int, result: BacktestResult?, error: String? = nil, notFound: String? = nil) {
        guard id == runID else { return }
        self.result = result; self.error = error; self.notFound = notFound
        running = false
    }
}

/// What 回測 remembers on the phone, outside the records: the last form.
enum BacktestSettings {
    static let symbolsKey = "backtest.symbols", weightsKey = "backtest.weights", monthlyKey = "backtest.monthly"
    static let yearsKey = "backtest.years", reinvestKey = "backtest.reinvest"

    /// `--ui-testing --reset` starts as a fresh install: the form as it first opens (0050 at 100%, 10,000 a month from
    /// 5 years ago, 配息再投入 on), whatever an earlier UI test left in it.
    static func reset(_ arguments: [String], defaults: UserDefaults = .standard) {
        guard arguments.contains("--ui-testing"), arguments.contains("--reset") else { return }
        for key in [symbolsKey, weightsKey, monthlyKey, yearsKey, reinvestKey] { defaults.removeObject(forKey: key) }
    }
}

/// What the 回測 form takes. Only ETFs: the history has cash dividends and ETF splits, not a stock's 配股 or 減資, so
/// a stock would come out with wrong figures.
enum BacktestForm {
    static let onlyETF = "回測只支援 ETF。"

    /// The code to add to the picked ones, or why it cannot be added.
    static func adding(_ text: String, to picked: [String], isETF: (String) -> Bool) -> Result<String, AppDataError> {
        let code = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard DataChecks.code(code) else { return .failure(AppDataError("代號格式不符，請輸入像 0056 或 00679B 的代號。")) }
        guard isETF(code) else { return .failure(AppDataError(onlyETF)) }
        guard !picked.contains(code) else { return .failure(AppDataError("\(code) 已經在清單裡。")) }
        guard picked.count < 3 else { return .failure(AppDataError("最多 3 檔。")) }
        return .success(code)
    }

    /// The person's own codes offered as one-tap choices: ETFs only, none picked already, at most eight.
    static func candidates(own: [String], picked: [String], isETF: (String) -> Bool) -> [String] {
        let taken = Set(picked)
        var seen = Set<String>()
        return Array(own.filter { DataChecks.code($0) && isETF($0) && !taken.contains($0) && seen.insert($0).inserted }.prefix(8))
    }
}

/// 回測 (spec 5.6, 口袋會員): 1–3 ETFs bought every month from N years ago, on real past prices.
struct BacktestView: View {
    @EnvironmentObject private var store: PortfolioStore
    @StateObject private var model = BacktestModel()
    /// The last inputs. Codes and their percentages are comma-separated lists of the same length.
    @AppStorage(BacktestSettings.symbolsKey) private var savedSymbols = "0050"
    @AppStorage(BacktestSettings.weightsKey) private var savedWeights = "100"
    @AppStorage(BacktestSettings.monthlyKey) private var monthlyText = "10000"
    @AppStorage(BacktestSettings.yearsKey) private var years = 5
    @AppStorage(BacktestSettings.reinvestKey) private var reinvest = true
    @State private var codeText = ""
    @State private var formError: String?

    private static let spans = [1, 3, 5, 10]
    /// The saved span, or 5 when what is saved is not one of the choices.
    private var span: Int { Self.spans.contains(years) ? years : 5 }

    /// 上市／上櫃 and the listing month of each picked code, where the catalogue has them.
    private var catalogueFacts: (markets: [String: String], listed: [String: YearMonth]) {
        var markets: [String: String] = [:]
        var listed: [String: YearMonth] = [:]
        for code in symbols {
            guard let fund = store.funds.first(where: { $0.id == code }) else { continue }
            if let market = fund.market { markets[code] = market }
            if let date = fund.listingDate.flatMap(DataChecks.date) { listed[code] = YearMonth(date) }
        }
        return (markets, listed)
    }

    /// Before a run: what a saved key promises. During one: what the run is really reading.
    private var estimateLine: String? { BacktestModel.estimateText(seconds: model.estimate, fugle: model.running ? model.fromFugle : model.keySaved) }

    private var symbols: [String] {
        var seen = Set<String>()
        let list = savedSymbols.split(separator: ",").map(String.init).filter { DataChecks.code($0) && seen.insert($0).inserted }
        return Array(list.prefix(3))
    }

    private var weightTexts: [String] {
        let saved = savedWeights.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        return symbols.indices.map { $0 < saved.count ? saved[$0] : "" }
    }

    /// Held and favourite ETFs that are not picked yet.
    private var candidates: [String] {
        BacktestForm.candidates(own: store.data.holdings.map(\.symbol) + store.data.favorites.sorted(), picked: symbols) { store.isETF($0) }
    }

    /// The form as numbers, or nil while something is missing: every weight above 0, 100% in all, a monthly amount.
    private var input: (legs: [(symbol: String, weight: Double)], monthly: Double)? {
        let codes = symbols
        let weights = weightTexts.map { Double($0) ?? 0 }
        guard !codes.isEmpty, weights.allSatisfy({ $0 > 0 }), abs(weights.reduce(0, +) - 100) < 0.01,
              let monthly = Double(monthlyText.replacingOccurrences(of: ",", with: "")), monthly > 0, monthly <= 10_000_000 else { return nil }
        var legs: [(symbol: String, weight: Double)] = []
        for (i, code) in codes.enumerated() { legs.append((symbol: code, weight: weights[i] / 100)) }
        return (legs: legs, monthly: monthly)
    }

    var body: some View {
        Page {
            MemberLock(.backtest) { form } preview: { preview }
            VStack(alignment: .leading, spacing: 4) {
                Text("過去績效不代表未來。")
                Text("情境試算，不是預測或保證。")
                Text("每月第一個交易日以收盤價買入，不含手續費與稅。")
            }
            .font(.caption).foregroundStyle(Palette.muted)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { VStack(spacing: 0) { Text("回測").font(.headline).foregroundStyle(Palette.ink); Text("如果幾年前就開始每月投入").font(.caption2).foregroundStyle(Palette.muted) } } }
        .onAppear { if years != span { years = span } }
        .onDisappear { model.cancel() }
        // Works out the wait from what is already on the phone; again when the codes or span change or a run ends.
        .task(id: "\(savedSymbols)|\(years)|\(model.running)") {
            guard MembershipStore.shared.has(.backtest) else { return }
            let facts = catalogueFacts
            await model.refreshEstimate(symbols: symbols, markets: facts.markets, listed: facts.listed, years: span)
        }
    }

    // MARK: Form

    @ViewBuilder private var form: some View {
        Card {
            Text("回測標的（1–3 檔，比例合計 100%）").font(.caption).foregroundStyle(Palette.muted)
            ForEach(Array(symbols.enumerated()), id: \.element) { i, code in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(code).font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.ink)
                        Text(store.name(for: code)).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    UnitField(placeholder: "比例", text: weight(i), unit: "%", identifier: "backtest-weight-\(code)")
                        .frame(width: 84)
                        .padding(.horizontal, 10).padding(.vertical, 10)
                        .background(Palette.cardSoft, in: RoundedRectangle(cornerRadius: 12))
                    if symbols.count > 1 {
                        Button { setSymbols(symbols.filter { $0 != code }) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }
                            .buttonStyle(.plain).frame(minWidth: 44, minHeight: 44).accessibilityLabel("移除 \(code)")
                    }
                }
                .padding(.top, 10)
            }
            if symbols.count < 3 {
                if !candidates.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(candidates, id: \.self) { code in
                                Button { add(code) } label: {
                                    Text("＋ \(code)").font(.caption.bold()).monospacedDigit().foregroundStyle(Palette.blue)
                                        .padding(.horizontal, 10).padding(.vertical, 8)
                                        .background(Palette.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain).accessibilityLabel("加入 \(code)")
                            }
                        }
                    }
                    .padding(.top, 12)
                }
                HStack(spacing: 10) {
                    TextField("輸入代號，例如 0056", text: $codeText)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled().monospacedDigit()
                        .padding(.horizontal, 10).padding(.vertical, 10)
                        .background(Palette.cardSoft, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("backtest-code")
                    Button("加入") { add(codeText) }.buttonStyle(.bordered).accessibilityIdentifier("backtest-add")
                }
                .padding(.top, 12)
            }
            if let formError { Text(formError).font(.caption).foregroundStyle(Palette.red).padding(.top, 6) }
        }
        Card {
            FieldRow(title: "每月投入", bar: true) { UnitField(placeholder: "每月", text: $monthlyText, unit: "元", identifier: "backtest-monthly") }
            Text("起始").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).padding(.top, 10)
            Picker("起始", selection: $years) {
                ForEach(Self.spans, id: \.self) { Text("\($0) 年前").tag($0) }
            }
            .pickerStyle(.segmented).padding(.top, 6).accessibilityIdentifier("backtest-years")
            if let estimateLine {
                Text(estimateLine).font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6).accessibilityIdentifier("backtest-estimate")
            }
            Toggle("配息再投入", isOn: $reinvest).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).padding(.top, 12)
            Text(reinvest ? "配息在除息日以收盤價買回。" : "配息領現金，計入期末市值。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 2)
        }
        if model.running {
            Card {
                ProgressView(value: model.progress)
                Text("下載歷史資料 \(Int(model.progress * 100))%").font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.ink).padding(.top, 10)
                if let estimateLine {
                    Text(estimateLine).font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                }
                if !model.fromFugle {
                    Text("年數越長、檔數越多就越久：每個月份要向交易所要一次資料，每次間隔 2 秒；下載過的月份會留在手機裡。")
                        .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                }
                Button("取消") { model.cancel() }.buttonStyle(.bordered).padding(.top, 10).accessibilityIdentifier("backtest-cancel")
            }
        } else {
            Button { start() } label: { PrimaryButtonLabel(title: "開始回測", icon: "clock.arrow.circlepath") }
                .buttonStyle(.plain).disabled(input == nil).opacity(input == nil ? 0.5 : 1)
                .accessibilityIdentifier("backtest-run")
            if input == nil {
                Text("請選 1–3 檔，比例合計 100%，並輸入每月投入金額。").font(.caption).foregroundStyle(Palette.red)
            }
        }
        if let error = model.error { LoadFailed(message: error, retry: { start() }, lastUpdated: nil) }
        if let notFound = model.notFound {
            Card { Text(notFound).font(.subheadline).foregroundStyle(Palette.red).fixedSize(horizontal: false, vertical: true) }
        }
        if let result = model.result { resultCard(result) }
        Text(sourceLine).font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("backtest-source")
    }

    private var sourceLine: String {
        guard model.result != nil || model.running else { return "資料來源：證交所／櫃買中心；有儲存富果金鑰時先用富果還原價，取不到就用交易所資料。" }
        return model.fromFugle ? "資料來源：富果（還原日收盤價）" : "資料來源：證交所／櫃買中心（日收盤價、除權息、ETF 分割）"
    }

    private func weight(_ index: Int) -> Binding<String> {
        Binding(
            get: { let texts = weightTexts; return index < texts.count ? texts[index] : "" },
            set: { value in
                var texts = weightTexts
                guard index < texts.count else { return }
                texts[index] = value.filter { "0123456789.".contains($0) }
                savedWeights = texts.joined(separator: ",")
            })
    }

    /// A new list of codes starts from equal shares.
    private func setSymbols(_ list: [String]) {
        let equal: [String]
        switch list.count {
        case 2: equal = ["50", "50"]
        case 3: equal = ["34", "33", "33"]
        default: equal = ["100"]
        }
        savedSymbols = list.joined(separator: ",")
        savedWeights = equal.joined(separator: ",")
    }

    private func add(_ text: String) {
        switch BacktestForm.adding(text, to: symbols, isETF: { store.isETF($0) }) {
        case .failure(let problem): formError = problem.text
        case .success(let code):
            formError = nil; codeText = ""
            setSymbols(symbols + [code])
        }
    }

    private func start() {
        guard let input else { return }
        // A list saved before only ETFs were taken: a stock's 配股 and 減資 are not in the data, so it is not run.
        guard input.legs.allSatisfy({ store.isETF($0.symbol) }) else { formError = BacktestForm.onlyETF; return }
        let facts = catalogueFacts
        formError = nil
        model.run(legs: input.legs, markets: facts.markets, listed: facts.listed, monthly: input.monthly, years: span, reinvest: reinvest)
    }

    // MARK: Result

    private struct CurvePoint: Identifiable {
        let id: Int
        let date: Date
        let invested: Double
        let value: Double
    }

    @ViewBuilder private func resultCard(_ result: BacktestResult) -> some View {
        let notes = result.notes + (model.fromFugle ? ["富果還原價已把配息算進價格，結果等同配息再投入"] : [])
        Card {
            if result.invested <= 0 || result.curve.isEmpty {
                Text("沒有取得可用的歷史資料，這次沒有結果。").font(.subheadline).foregroundStyle(Palette.muted)
            } else {
                Text("期末市值").font(.caption).foregroundStyle(Palette.muted)
                Text("\(money(result.endValue)) 元").font(.title.bold()).monospacedDigit().foregroundStyle(Palette.ink)
                    .minimumScaleFactor(0.6).lineLimit(1).accessibilityIdentifier("backtest-end-value")
                if let first = result.curve.first, let last = result.curve.last {
                    Text("\(first.month.key) 到 \(last.month.key)").font(.caption).monospacedDigit().foregroundStyle(Palette.muted)
                }
                row("投入總額", "\(money(result.invested)) 元")
                row("累計領息", model.fromFugle ? "已含在還原價" : "\(money(result.dividends)) 元")
                if let xirr = result.xirr { row("年化報酬", percentText(xirr * 100)) } else { row("年化報酬", "年化報酬不適用") }
                row("最大回落", "\(decimal(result.maxDrawdown * 100))%")
                chart(result)
                Text("實線：市值　虛線：投入總額").font(.caption2).foregroundStyle(Palette.muted).padding(.top, 4)
            }
            ForEach(notes, id: \.self) { note in
                Text("・\(note)").font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(Palette.muted)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink)
        }
        .padding(.top, 10)
    }

    private func chart(_ result: BacktestResult) -> some View {
        var points: [CurvePoint] = []
        for (i, point) in result.curve.enumerated() {
            let date = GameRules.taipei.date(from: DateComponents(year: point.month.year, month: point.month.month, day: 1)) ?? Date()
            points.append(CurvePoint(id: i, date: date, invested: point.invested, value: point.value))
        }
        return Chart(points) { point in
            AreaMark(x: .value("月份", point.date), y: .value("市值", point.value))
                .foregroundStyle(LinearGradient(colors: [Palette.blue.opacity(0.25), Palette.blue.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("月份", point.date), y: .value("金額", point.value), series: .value("系列", "市值"))
                .foregroundStyle(Palette.blue)
            LineMark(x: .value("月份", point.date), y: .value("金額", point.invested), series: .value("系列", "投入總額"))
                .foregroundStyle(Palette.muted)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        .frame(height: 160).padding(.top, 12)
        .accessibilityLabel("月度資產曲線")
    }

    // MARK: Locked preview

    private var preview: some View {
        Card {
            Text("期末市值").font(.caption).foregroundStyle(Palette.muted)
            Text("812,340 元").font(.title.bold()).foregroundStyle(Palette.ink)
            ForEach([("投入總額", "600,000 元"), ("累計領息", "41,280 元"), ("年化報酬", "+11.8%"), ("最大回落", "23.4%")], id: \.0) { item in
                row(item.0, item.1)
            }
        }
    }
}
