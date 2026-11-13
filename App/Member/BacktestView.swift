import SwiftUI
import Charts

/// Runs one 回測: downloads each ETF's history in turn, then hands it to `Backtest.run`. Leaving the screen cancels it.
@MainActor final class BacktestModel: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var progress = 0.0
    @Published private(set) var result: BacktestResult?
    /// The finished or running result reads 富果's adjusted closes instead of the exchanges.
    @Published private(set) var fromFugle = false
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    /// Only the latest run may report: a cancelled one stays silent.
    private var runID = 0

    func run(legs: [(symbol: String, weight: Double)], markets: [String: String], monthly: Double, years: Int, reinvest: Bool,
             client: OfficialHistoryClient = .shared) {
        task?.cancel()
        runID += 1
        let id = runID
        running = true; progress = 0; error = nil; result = nil
        fromFugle = client.usesFugle
        task = Task {
            let end = YearMonth(Date())
            let start = YearMonth(year: end.year - years, month: end.month)
            let count = Double(max(legs.count, 1))
            var history: [String: SymbolHistory] = [:]
            do {
                for (i, leg) in legs.enumerated() {
                    history[leg.symbol] = try await client.history(symbol: leg.symbol, market: markets[leg.symbol], from: start, to: end) { part in
                        Task { @MainActor in self.report(id, (Double(i) + part) / count) }
                    }
                }
                try Task.checkCancellation()
                let input = BacktestInput(legs: legs, monthly: monthly, start: start, end: end, reinvest: reinvest)
                self.finish(id, result: Backtest.run(input, history: history), error: nil)
            } catch {
                self.finish(id, result: nil, error: Task.isCancelled || error is CancellationError ? nil : error.localizedDescription)
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

    private func finish(_ id: Int, result: BacktestResult?, error: String?) {
        guard id == runID else { return }
        self.result = result; self.error = error
        running = false
    }
}

/// 回測 (spec 5.6, 口袋會員): 1–3 ETFs bought every month from N years ago, on real past prices.
struct BacktestView: View {
    @EnvironmentObject private var store: PortfolioStore
    @StateObject private var model = BacktestModel()
    /// The last inputs. Codes and their percentages are comma-separated lists of the same length.
    @AppStorage("backtest.symbols") private var savedSymbols = "0050"
    @AppStorage("backtest.weights") private var savedWeights = "100"
    @AppStorage("backtest.monthly") private var monthlyText = "10000"
    @AppStorage("backtest.years") private var years = 5
    @AppStorage("backtest.reinvest") private var reinvest = true
    @State private var codeText = ""
    @State private var formError: String?

    private static let spans = [1, 3, 5, 10]

    private var symbols: [String] {
        var seen = Set<String>()
        let list = savedSymbols.split(separator: ",").map(String.init).filter { DataChecks.code($0) && seen.insert($0).inserted }
        return Array(list.prefix(3))
    }

    private var weightTexts: [String] {
        let saved = savedWeights.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        return symbols.indices.map { $0 < saved.count ? saved[$0] : "" }
    }

    /// Held and favourite codes that are not picked yet.
    private var candidates: [String] {
        let picked = Set(symbols)
        var seen = Set<String>()
        let own = store.data.holdings.map(\.symbol) + store.data.favorites.sorted()
        return Array(own.filter { DataChecks.code($0) && !picked.contains($0) && seen.insert($0).inserted }.prefix(8))
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
        .onDisappear { model.cancel() }
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
            Toggle("配息再投入", isOn: $reinvest).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).padding(.top, 12)
            Text(reinvest ? "配息在除息日以收盤價買回。" : "配息領現金，計入期末市值。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 2)
        }
        if model.running {
            Card {
                ProgressView(value: model.progress)
                Text("下載歷史資料 \(Int(model.progress * 100))%").font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.ink).padding(.top, 10)
                Text("第一次下載需要幾十秒，離開這頁會停止").font(.caption).foregroundStyle(Palette.muted).padding(.top, 4)
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
        if let error = model.error {
            Card { Text("沒有完成：\(error)").font(.subheadline).foregroundStyle(Palette.red).fixedSize(horizontal: false, vertical: true) }
        }
        if let result = model.result { resultCard(result) }
        Text(sourceLine).font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("backtest-source")
    }

    private var sourceLine: String {
        guard model.result != nil || model.running else { return "資料來源：證交所／櫃買中心；有儲存富果金鑰時改用富果還原價。" }
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
        let code = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard DataChecks.code(code) else { formError = "代號格式不符，請輸入像 0056 或 00679B 的代號。"; return }
        guard !symbols.contains(code) else { formError = "\(code) 已經在清單裡。"; return }
        guard symbols.count < 3 else { formError = "最多 3 檔。"; return }
        formError = nil; codeText = ""
        setSymbols(symbols + [code])
    }

    private func start() {
        guard let input else { return }
        var markets: [String: String] = [:]
        for leg in input.legs {
            if let market = store.funds.first(where: { $0.id == leg.symbol })?.market { markets[leg.symbol] = market }
        }
        formError = nil
        model.run(legs: input.legs, markets: markets, monthly: input.monthly, years: years, reinvest: reinvest)
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
