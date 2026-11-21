import SwiftUI

/// 記一筆定投: this month's DCA from a prefilled sheet (fund, amount, an estimated share count). Nothing is saved
/// until 「記好了」, every field stays editable, and the entry lands in the trade log like any other buy.
struct QuickDCASheet: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.skin) private var skin
    let onDone: () -> Void

    @State private var loaded = false
    @State private var symbol = ""
    @State private var amountText = ""
    @State private var sharesText = ""
    @State private var broker = ""
    @State private var date = Date()
    @State private var note: String?
    /// The person typed the share count: it is theirs from then on, and no estimate replaces it.
    @State private var sharesEdited = false
    /// A save has started; stays set once it succeeds, so a second tap while the sheet closes records nothing.
    @State private var saving = false

    init(onDone: @escaping () -> Void) { self.onDone = onDone }

    private var code: String { symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    private var amount: Int? { Int(amountText.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var shares: Int? { Int(sharesText.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var known: Bool { !code.isEmpty && store.quickDCAKnows(code) }
    private var problem: QuickDCAProblem? { QuickDCA.problem(known: known, shares: shares, amount: amount) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("ETF 代號") {
                        TextField("例如 0050", text: $symbol).multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .accessibilityIdentifier("quick-dca-symbol")
                    }
                    if !code.isEmpty, !known {
                        Text("找不到這檔 ETF").font(.footnote).foregroundStyle(.red).accessibilityIdentifier("quick-dca-error")
                    }
                    LabeledContent("金額") {
                        HStack(spacing: 4) {
                            TextField("每月投入", text: $amountText).keyboardType(.numberPad).multilineTextAlignment(.trailing).monospacedDigit()
                                .accessibilityIdentifier("quick-dca-amount")
                            Text("元").foregroundStyle(.secondary)
                        }
                    }
                    DatePicker("日期", selection: $date, in: ...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("quick-dca-date")
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("股數") {
                            HStack(spacing: 4) {
                                TextField("成交股數", text: Binding(get: { sharesText }, set: { sharesText = $0; sharesEdited = true }))
                                    .keyboardType(.numberPad).multilineTextAlignment(.trailing).monospacedDigit()
                                    .accessibilityIdentifier("quick-dca-shares")
                                Text("股").foregroundStyle(.secondary)
                            }
                        }
                        if let note, !sharesEdited { Text(note).font(.footnote).foregroundStyle(.secondary) }
                    }
                    LabeledContent("券商（選填）") {
                        TextField("例如 國泰證券", text: $broker).multilineTextAlignment(.trailing).accessibilityIdentifier("quick-dca-broker")
                    }
                } footer: {
                    Text("記好後會出現在交易紀錄，之後都能修改或刪除。")
                }
                Section {
                    Button(action: save) { Text("記好了").frame(maxWidth: .infinity) }
                        .buttonStyle(SkinButtonStyle(seed: SkinSeed.of("記好了")))
                        .disabled(problem != nil || saving)
                        .opacity(problem != nil || saving ? 0.4 : 1)
                        .accessibilityIdentifier("quick-dca-save")
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("記一筆定投").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationDetents([.medium, .large])
        .onAppear(perform: load)
        .onChange(of: symbol) { _, _ in estimate() }
        .onChange(of: amountText) { _, _ in estimate() }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let start = store.quickDCADraft()
        symbol = start.symbol
        amountText = start.amount.map(String.init) ?? ""
        broker = start.broker
        date = start.date
        sharesText = start.shares.map(String.init) ?? ""
        note = start.closeNote
    }

    /// The code or the amount changed: the share count follows the latest close, until the person sets it themselves.
    private func estimate() {
        guard loaded, !sharesEdited else { return }
        let latest = store.quote(code)
        let estimate = QuickDCA.estimatedShares(amount: amount, close: latest?.price)
        sharesText = estimate.map(String.init) ?? ""
        note = estimate == nil ? nil : latest.flatMap { QuickDCA.closeNote(day: $0.date) }
    }

    private func save() {
        guard !saving, problem == nil, let amount, let shares else { return }
        saving = true
        let draft = QuickDCADraft(symbol: code, amount: amount, shares: shares, date: date, broker: broker, closeNote: note)
        do {
            try store.logQuickDCA(draft)
            ConfirmFeedback.confirm(skin)
            onDone()
        } catch {
            saving = false
            store.message = error.localizedDescription
        }
    }
}
