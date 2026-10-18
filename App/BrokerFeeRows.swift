import SwiftUI

/// 券商 with its selling fee: picking or typing a broker brings in its fee (the viewer's own rate for it, else its
/// common online rate, else the list price), shown right below and editable there. The form keeps the rate with
/// `SellCosts.remember` when it saves, so 市值 uses it from then on.
struct BrokerFeeRows: View {
    @EnvironmentObject var store: PortfolioStore
    @Binding var broker: String
    @Binding var rate: FeeRate
    var placeholder = "例如 元大證券"
    var identifier = ""
    /// Plain rows for a Form, instead of the cards' titled rows.
    var inForm = false

    var body: some View {
        Group {
            if inForm {
                HStack { nameField; menu }
                if hasBroker {
                    fees
                    note
                }
            } else {
                FieldRow(title: "券商（選填）") { HStack { nameField; menu } }
                if hasBroker {
                    FieldRow(title: "賣出手續費") { fees }
                    note.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear { rate = SellCosts.rate(for: broker) }
        // Typing on (國泰證 → 國泰證券) or fixing a typo keeps what the viewer typed in the fee; a different broker's rate replaces it.
        .onChange(of: broker) { old, value in if SellCosts.rate(for: old) != SellCosts.rate(for: value) { rate = SellCosts.rate(for: value) } }
    }
    private var hasBroker: Bool { !SellCosts.brokerKey(broker).isEmpty }
    private var nameField: some View {
        TextField(placeholder, text: $broker).accessibilityIdentifier(identifier)
    }
    /// The viewer's brokers first, then the ones with a common rate, then the others.
    private var menu: some View {
        let own = Set(store.data.holdings.map { SellCosts.brokerKey($0.broker) }).filter { !$0.isEmpty }.sorted()
        var seen = Set<String>(), choices: [String] = []
        for name in own + SellCosts.presets.map(\.name) + SellCosts.otherBrokers where seen.insert(name).inserted { choices.append(name) }
        return Menu {
            ForEach(choices, id: \.self) { name in Button(name) { broker = name } }
        } label: {
            Image(systemName: "chevron.down").foregroundStyle(Palette.blue)
        }.accessibilityLabel("選擇券商")
    }
    private var fees: some View {
        HStack(spacing: 4) {
            TextField("10", value: $rate.discount, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .frame(width: 44).accessibilityLabel("手續費折扣（折）")
            Text("折").font(.subheadline).foregroundStyle(Palette.muted)
            Spacer(minLength: 6)
            Text("最低").font(.caption).foregroundStyle(Palette.muted)
            TextField("20", value: $rate.minimum, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .frame(width: 40).accessibilityLabel("最低手續費（元）")
            Text("元").font(.subheadline).foregroundStyle(Palette.muted)
        }
    }
    private var note: some View {
        Text(SellCosts.rateNote(for: broker)).font(.caption2).foregroundStyle(Palette.muted)
    }
}
