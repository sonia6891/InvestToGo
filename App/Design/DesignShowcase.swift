import SwiftUI

/// 3D 元件展示: the home hero and the fee-detail pattern built from the design system, with demo figures, so the
/// look and feel can be checked on a phone before every page is rebuilt.
struct DesignShowcase: View {
    var close: () -> Void = {}
    @ObservedObject private var skins = SkinStore.shared
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
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .black)).foregroundStyle(Color(rgb: skin.foreground))
                        .frame(width: 36, height: 36).overlay(Circle().stroke(Color(rgb: skin.foreground), lineWidth: 1.5))
                }.buttonStyle(.plain).accessibilityLabel("關閉").accessibilityIdentifier("showcase-close")
                VStack(alignment: .leading, spacing: 2) {
                    Text("PKT×\(String(format: "%03d", streak))").font(.system(size: 11, design: .monospaced))
                    Text("連續領息 \(streak) 個月").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Color(rgb: skin.foreground))
                }.foregroundStyle(Color(rgb: skin.muted))
                Spacer()
                Toggle(isOn: $skins.soundOn) { Text("音效").font(.system(size: 12, design: .monospaced)) }
                    .toggleStyle(.button).tint(Color(rgb: skin.accent)).foregroundStyle(Color(rgb: skin.foreground))
                SkinPicker(skins: skins)
            }
            HStack(spacing: 8) {
                tab("首頁", 0, id: "showcase-tab-home", skin: skin)
                tab("費用率細項", 1, id: "showcase-tab-fees", skin: skin)
                Spacer()
            }.padding(.top, 10)

            ZStack {
                PosterShards(center: UnitPoint(x: 0.5, y: 0.5), colors: skin.burst.map { Color(rgb: $0) })
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
        .statusBarHidden(false)
        .preferredColorScheme(contrastRatio(skin.foreground, 0x000000) > contrastRatio(skin.foreground, 0xFFFFFF) ? .dark : .light)
    }

    private func tab(_ title: String, _ index: Int, id: String, skin: Skin) -> some View {
        Button { screen = index; Haptics.tick(); SoundFX.tick(enabled: skins.soundOn) } label: {
            Text(title).font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(rgb: screen == index ? skin.background : skin.muted))
                .padding(.horizontal, 16).frame(minHeight: 36)
                .background(Capsule().fill(screen == index ? Color(rgb: skin.foreground) : .clear))
                .overlay(Capsule().stroke(Color(rgb: screen == index ? skin.foreground : skin.line), lineWidth: 1.5))
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
        .accessibilityAddTraits(screen == index ? .isSelected : [])
    }

    private func homeCaption(_ skin: Skin) -> some View {
        VStack(spacing: 6) {
            Text("PKT×\(String(format: "%03d", streak))").font(.system(size: 11, design: .monospaced)).tracking(1).foregroundStyle(Color(rgb: skin.muted))
            Text("+$\(amount.formatted())").font(.system(size: 60, weight: .black).width(.condensed)).foregroundStyle(Color(rgb: skin.foreground))
                .minimumScaleFactor(0.6).lineLimit(1)
                .accessibilityIdentifier("showcase-amount").accessibilityLabel("這個月口袋 +$\(amount.formatted())")
            Text("本月入袋").font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(Color(rgb: skin.foreground))
                .padding(.horizontal, 8).padding(.vertical, 2).overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(rgb: skin.foreground), lineWidth: 1))
            Text("連續領息 \(streak) 個月・今年 \(paidThisMonth ? 11 : 10)／12 個月已入袋").font(.system(size: 12)).foregroundStyle(Color(rgb: skin.muted)).padding(.top, 2)
            Button("記錄配息") { drops += 1 }
                .buttonStyle(HexButtonStyle(skin: skin)).padding(.top, 8)
                .accessibilityIdentifier("showcase-record")
            HStack(spacing: 18) {
                ForEach(Skins.all) { item in
                    Button { skins.skin = item; Haptics.tick(); SoundFX.tick(enabled: skins.soundOn) } label: {
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 12).fill(Color(rgb: item.metal.color))
                                .overlay(RoundedRectangle(cornerRadius: 12).inset(by: 9).fill(Color(rgb: item.matte)))
                                .frame(width: 52, height: 52)
                                .shadow(color: .black.opacity(0.35), radius: 6, y: 4)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(rgb: skin.foreground), lineWidth: item.id == skin.id ? 2.5 : 0))
                            if item.id != skin.id {
                                Text("新").font(.system(size: 9, weight: .black)).foregroundStyle(Color(rgb: 0x17130E))
                                    .padding(.horizontal, 4).padding(.vertical, 1).background(Color(rgb: 0xF2B632), in: RoundedRectangle(cornerRadius: 3)).offset(x: -6, y: -6)
                            }
                        }
                    }.buttonStyle(.plain).accessibilityLabel("皮膚 \(item.name) \(item.rarity)")
                }
            }.padding(.top, 12)
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
