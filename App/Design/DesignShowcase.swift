import SwiftUI

/// 3D 元件展示: the home hero and the fee-detail pattern built from the design system, with demo figures, so the
/// look and feel can be checked on a phone before every page is rebuilt.
struct DesignShowcase: View {
    @StateObject private var skins = SkinStore()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var screen = 0
    @State private var streak = 12
    @State private var amount = 1240
    @State private var drops = 0
    @State private var bursts = 0
    @State private var paidThisMonth = false
    @State private var feeIndex = 0
    private let fees: [(String, String)] = [("總費用", "0.42%"), ("經理費", "0.20%"), ("保管費", "0.03%"), ("交易手續費", "0.08%"), ("交易稅", "0.07%"), ("其他費用", "0.06%"), ("申贖扣抵", "−0.02%")]

    var body: some View {
        let skin = skins.skin
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PKT×\(String(format: "%03d", streak))").font(.system(size: 11, design: .monospaced))
                    Text("連續領息 \(streak) 個月").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Color(rgb: skin.foreground))
                }.foregroundStyle(Color(rgb: skin.muted))
                Spacer()
                Toggle(isOn: $skins.soundOn) { Text("音效").font(.system(size: 12, design: .monospaced)) }
                    .toggleStyle(.button).tint(Color(rgb: skin.accent)).foregroundStyle(Color(rgb: skin.foreground))
                SkinPicker(skins: skins)
            }
            Picker("畫面", selection: $screen) { Text("首頁").tag(0); Text("費用率細項").tag(1) }
                .pickerStyle(.segmented).padding(.top, 10).accessibilityIdentifier("showcase-screen")

            ZStack {
                BurstView(trigger: bursts, center: UnitPoint(x: 0.5, y: 0.32), colors: skin.burst.map { Color(rgb: $0) })
                PocketHero(value: screen == 0 ? "\(streak)" : fees[feeIndex].1, showsPocket: screen == 0, skin: skin, drops: drops,
                           label: screen == 0 ? "連續領息 \(streak) 個月" : "\(fees[feeIndex].0) \(fees[feeIndex].1)") {
                    landed()
                }
            }
            .frame(maxHeight: screen == 0 ? .infinity : 230)

            if screen == 0 { homeCaption(skin) } else { feeList(skin) }
            Text("示範數據・拖曳可轉動・點「皮膚」換整套材質").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color(rgb: skin.muted)).padding(.vertical, 8)
        }
        .padding(.horizontal, 16)
        .background(Color(rgb: skin.background).ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: skin.id)
        .navigationTitle("3D 元件展示").navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(contrastRatio(skin.foreground, 0x000000) > contrastRatio(skin.foreground, 0xFFFFFF) ? .dark : .light, for: .navigationBar)
    }

    private func homeCaption(_ skin: Skin) -> some View {
        VStack(spacing: 8) {
            Text("十一月").font(.system(size: 12, weight: .black)).tracking(2).foregroundStyle(Color(rgb: skin.accent == skin.foreground ? skin.background : skin.background))
                .padding(.horizontal, 10).padding(.vertical, 3).background(Color(rgb: skin.accent), in: RoundedRectangle(cornerRadius: 3))
            (Text("這個月口袋 ").font(.system(size: 28, weight: .black)) + Text("+$\(amount.formatted())").font(.system(size: 32, weight: .black, design: .rounded)).foregroundColor(Color(rgb: skin.accent)))
                .foregroundStyle(Color(rgb: skin.foreground))
                .accessibilityIdentifier("showcase-amount")
            Button("記錄配息") { drops += 1 }
                .buttonStyle(HexButtonStyle(skin: skin)).padding(.top, 6)
                .accessibilityIdentifier("showcase-record")
            HStack(spacing: 2) {
                ForEach(1...12, id: \.self) { month in
                    let paid = month <= 10 || (month == 11 && paidThisMonth)
                    VStack(spacing: 5) {
                        Circle().fill(paid ? Color(rgb: skin.accent) : .clear).overlay(Circle().stroke(Color(rgb: paid ? skin.accent : skin.line), lineWidth: 1.5)).frame(width: 18, height: 18)
                        Text("\(month)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color(rgb: month == 11 ? skin.foreground : skin.muted))
                    }.frame(maxWidth: .infinity)
                    .accessibilityElement().accessibilityLabel("\(month) 月\(paid ? "已領息" : "尚未領息")")
                }
            }.padding(.top, 14)
        }
    }

    private func feeList(_ skin: Skin) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("FEE×2025 · 市值型示範 ETF").font(.system(size: 11, design: .monospaced)).tracking(1.5).foregroundStyle(Color(rgb: skin.muted))
                Text("一年總共吃掉多少").font(.system(size: 20, weight: .black)).foregroundStyle(Color(rgb: skin.foreground)).padding(.bottom, 10)
                Rectangle().fill(Color(rgb: skin.foreground)).frame(height: 2)
                ForEach(fees.indices, id: \.self) { i in
                    Button { feeIndex = i; Haptics.tick(); SoundFX.tick(enabled: skins.soundOn) } label: {
                        HUDRow(title: fees[i].0, value: fees[i].1, selected: i == feeIndex, skin: skin)
                    }.buttonStyle(.plain).accessibilityIdentifier("fee-row-\(i)")
                }
            }
        }
    }

    private func landed() {
        bursts += 1
        SoundFX.coin(enabled: skins.soundOn)
        Haptics.coinDrop()
        if !paidThisMonth { paidThisMonth = true; streak += 1 }
        amount += 320
    }
}
