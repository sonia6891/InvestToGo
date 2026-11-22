import SwiftUI
import UIKit

// App 上鎖's screens: the lock screen and the cover (in `LockWindow`), the passcode pad they share with the settings
// sheet, and the 「App 上鎖」 card in 設定 › 隱私與安全. Drawn in the worn 外觀主題: its page, card and ink colours, its
// stage behind the 「$」, and keys in the family of its buttons.

// MARK: - Lock screen

/// The app name, six passcode dots and a number pad, with Face ID when it is on (it opens by itself once each time the
/// app locks). 忘記密碼 asks the phone for its owner, then sets a new passcode; the records stay.
struct AppLockScreen: View {
    @ObservedObject private var lock = AppLock.shared
    @Environment(\.skin) private var skin
    @Environment(\.motionReduced) private var reduceMotion
    @State private var code = ""
    @State private var message: String?
    @State private var warning = false
    @State private var shakes = 0
    /// 忘記密碼 passed: a new passcode is being entered.
    @State private var resetting: PasscodeSetup?
    @State private var now = Date()
    /// The lock (`AppLock.lockCount`) Face ID last opened by itself for.
    @State private var promptedFor = 0

    private var blocked: Bool { resetting == nil && lock.backoff.isBlocked(at: now) }
    private var biometry: LockBiometry? { lock.faceIDOn && resetting == nil && lock.biometry != .none ? lock.biometry : nil }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            SkinStage(size: 80) { SkinImage(.heroDollar).padding(16) }
                .accessibilityHidden(true)
            Text("投資袋著走").skinFont(.title(22)).foregroundStyle(skin.color(\.ink))
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
            PasscodePanel(prompt: prompt, message: shownMessage, warning: warning || blocked, filled: code.count, shakes: shakes,
                          digitsEnabled: !blocked, biometry: biometry, onDigit: digit, onDelete: delete, onBiometry: useBiometry)
                .padding(.top, 14)
            Button(action: forgot) {
                Text(resetting == nil ? "忘記密碼" : "取消重設").skinFont(.body(15)).foregroundStyle(skin.color(\.sub))
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("lock-forgot")
            .padding(.top, 6)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(skin.color(\.page).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lock-screen")
        .onAppear(perform: promptIfDue)
        .onChange(of: lock.active) { _, _ in promptIfDue() }
        .task(id: lock.backoff) { await countDown() }
    }

    private var prompt: String {
        guard let resetting else { return "輸入密碼" }
        return resetting.step == .confirm ? "再輸入一次新密碼" : "設定新的 App 密碼"
    }

    private var shownMessage: String? {
        guard blocked else { return message }
        let wait = AppLockRules.waitText(lock.backoff.remaining(at: now))
        return biometry.map { "密碼錯誤太多次，請在 \(wait) 後再試，或用 \($0.name) 解鎖。" } ?? "密碼錯誤太多次，請在 \(wait) 後再試。"
    }

    private func digit(_ value: Int) {
        guard code.count < Passcode.length, !blocked else { return }
        code.append(String(value))
        guard code.count == Passcode.length else { return }
        let entered = code
        code = ""
        submit(entered)
    }

    private func delete() { if !code.isEmpty { code.removeLast() } }

    private func submit(_ entered: String) {
        if var setup = resetting {
            switch setup.enter(entered) {
            case .next:
                message = "紀錄都會保留。"; warning = false
            case .mismatch:
                message = "兩次輸入的密碼不一樣，請重新設定。"; wrongFeedback()
            case .finished(let passcode):
                do { try lock.reset(to: passcode) } catch {
                    message = "無法把新密碼存進這支 iPhone，請再試一次。"; warning = true
                    setup = PasscodeSetup(askingCurrent: false)
                }
            }
            resetting = setup
            return
        }
        switch lock.unlock(entered) {
        case .right: message = nil; warning = false
        case .wrong: message = "密碼錯誤"; wrongFeedback()
        case .blocked: wrongFeedback()
        }
    }

    private func wrongFeedback() {
        warning = true
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 0.4)) { shakes += 1 }
    }

    private func useBiometry() {
        Task {
            if case .failed(let reason) = await lock.unlockWithBiometrics() { message = reason; warning = true }
        }
    }

    /// Face ID opens by itself once each time the app locks, when the app is in front.
    private func promptIfDue() {
        guard lock.active, biometry != nil, promptedFor != lock.lockCount else { return }
        promptedFor = lock.lockCount
        useBiometry()
    }

    private func forgot() {
        if resetting != nil {
            resetting = nil; code = ""; message = nil; warning = false
            return
        }
        Task {
            switch await lock.verifyOwner() {
            case .success:
                code = ""
                resetting = PasscodeSetup(askingCurrent: false)
                message = "已確認是你。紀錄都會保留。"; warning = false
            case .cancelled:
                break
            case .failed(let reason):
                message = reason; warning = true
            }
        }
    }

    private func countDown() async {
        now = Date()
        while lock.backoff.isBlocked(at: now) {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            now = Date()
        }
    }
}

/// The privacy cover: the worn 外觀主題's stage and 「$」 on its page colour, nothing else (no amounts). Also what the
/// app's own window shows at a cold launch until the lock is passed.
struct LockCover: View {
    @Environment(\.skin) private var skin
    var body: some View {
        SkinStage(size: 140) { SkinImage(.heroDollar).padding(28) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(skin.color(\.page).ignoresSafeArea())
            .accessibilityHidden(true)
    }
}

// MARK: - The passcode pad

/// A prompt, six dots that shake on a wrong code, a line for messages and the number pad: 1–9, then Face ID (when
/// offered), 0 and delete.
struct PasscodePanel: View {
    let prompt: String
    let message: String?
    var warning = false
    let filled: Int
    let shakes: Int
    var digitsEnabled = true
    /// The Face ID key, when it is offered.
    var biometry: LockBiometry?
    let onDigit: (Int) -> Void
    let onDelete: () -> Void
    var onBiometry: () -> Void = {}

    @Environment(\.skin) private var skin
    static let key: CGFloat = 66
    private static let rows = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    var body: some View {
        VStack(spacing: 12) {
            Text(prompt).skinFont(.title(18)).foregroundStyle(skin.color(\.ink)).multilineTextAlignment(.center)
            PasscodeDots(filled: filled)
                .modifier(ShakeEffect(shakes: CGFloat(shakes)))
                .padding(.vertical, 4)
            Text(message ?? " ").skinFont(.body(14))
                .foregroundStyle(warning ? Palette.red : skin.color(\.sub))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .top)
                .accessibilityHidden(message == nil)
            keypad
        }
    }

    private var keypad: some View {
        VStack(spacing: 12) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 22) { ForEach(row, id: \.self) { digitKey($0) } }
            }
            HStack(spacing: 22) {
                if let biometry, biometry != .none {
                    Button(action: onBiometry) { Image(systemName: biometry.symbol).font(.system(size: 28)) }
                        .buttonStyle(LockKeyStyle(plain: true))
                        .accessibilityLabel("用 \(biometry.name) 解鎖")
                        .accessibilityIdentifier("lock-faceid")
                } else {
                    Color.clear.frame(width: Self.key, height: Self.key).accessibilityHidden(true)
                }
                digitKey(0)
                Button(action: onDelete) { Image(systemName: "delete.left").font(.system(size: 24)) }
                    .buttonStyle(LockKeyStyle(plain: true))
                    .disabled(!digitsEnabled)
                    .accessibilityLabel("刪除")
                    .accessibilityIdentifier("lock-delete")
            }
        }
    }

    private func digitKey(_ value: Int) -> some View {
        Button { onDigit(value) } label: { Text("\(value)").skinFont(.title(28)) }
            .buttonStyle(LockKeyStyle(seed: UInt64(value + 11)))
            .disabled(!digitsEnabled)
            .accessibilityLabel("\(value)")
            .accessibilityIdentifier("lock-key-\(value)")
    }
}

/// Six dots, filled as digits are entered: squares for pixel, hand-drawn rings for sketch, circles otherwise.
struct PasscodeDots: View {
    let filled: Int
    @Environment(\.skin) private var skin

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<Passcode.length, id: \.self) { index in dot(index, on: index < filled) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("密碼")
        .accessibilityValue("已輸入 \(filled) 位，共 \(Passcode.length) 位")
    }

    @ViewBuilder private func dot(_ index: Int, on: Bool) -> some View {
        let ink = skin.color(\.ink)
        switch skin.style.button {
        case .pixelBlock:
            Rectangle().fill(on ? ink : Color.clear).overlay(Rectangle().strokeBorder(ink, lineWidth: 2)).frame(width: 14, height: 14)
        case .sketchBox:
            ZStack {
                if on { Circle().fill(ink).padding(1.5) }
                SketchCircleShape(seed: UInt64(index + 1)).stroke(ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
            .frame(width: 15, height: 15)
        default:
            Circle().fill(on ? ink : Color.clear).overlay(Circle().strokeBorder(ink, lineWidth: 1.5)).frame(width: 14, height: 14)
        }
    }
}

/// A side-to-side shake, one per step of `shakes`; it rests at whole numbers.
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(shakes * .pi * 4), y: 0))
    }
}

/// A key of the pad in the 外觀主題's button family: a hexagon (black-gold), a block with a hard shadow (pixel), sewn
/// paper (stitch), a hand-drawn ring (sketch). `plain`: the Face ID and delete keys, the symbol alone.
private struct LockKeyStyle: ButtonStyle {
    var plain = false
    var seed: UInt64 = 1
    func makeBody(configuration: Configuration) -> some View {
        LockKey(plain: plain, pressed: configuration.isPressed, seed: seed) { configuration.label }
    }
}

private struct LockKey<Label: View>: View {
    @Environment(\.skin) private var skin
    @Environment(\.motionReduced) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    let plain: Bool
    let pressed: Bool
    let seed: UInt64
    let label: Label

    init(plain: Bool, pressed: Bool, seed: UInt64, @ViewBuilder label: () -> Label) {
        self.plain = plain; self.pressed = pressed; self.seed = seed; self.label = label()
    }

    var body: some View {
        let size = PasscodePanel.key
        ZStack {
            if !plain { chrome }
            label.foregroundStyle(skin.color(\.ink))
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .scaleEffect(pressed && !reduceMotion ? 0.94 : 1)
        .opacity(enabled ? (pressed && plain ? 0.5 : 1) : 0.35)
        .animation(.easeOut(duration: 0.1), value: pressed)
    }

    @ViewBuilder private var chrome: some View {
        let fill = pressed ? skin.color(\.line) : skin.color(\.card)
        switch skin.style.button {
        case .hex:
            RegularHexagonShape().fill(fill)
                .overlay(RegularHexagonShape().stroke(skin.color(\.ink).opacity(0.45), lineWidth: 1.5))
        case .pixelBlock:
            Rectangle().fill(fill).hardShadow(skin.extra(2, or: \.line), offset: pressed ? 1 : 3)
                .overlay(Rectangle().strokeBorder(skin.extra(1, or: \.accent), lineWidth: 2))
        case .paperStitch:
            Circle().fill(fill).paperShadow()
                .overlay(StitchSeam(color: skin.color(\.dim), cornerRadius: 0, inset: 5, lineWidth: 1.5, circle: true))
        case .sketchBox:
            ZStack {
                Circle().fill(pressed ? skin.color(\.line) : Color.clear)
                SketchCircleShape(seed: seed).stroke(skin.color(\.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Settings

/// 設定 › 隱私與安全 › 「App 上鎖」: the switch (a new passcode twice to turn it on; Face ID or the passcode to turn it
/// off), 用 Face ID 解鎖 once a passcode is set, and 變更密碼.
struct AppLockSettingsCard: View {
    @ObservedObject private var lock = AppLock.shared
    @ObservedObject private var skins = SkinStore.shared
    @State private var flow: LockFlow?
    @State private var note: String?
    @State private var working = false

    var body: some View {
        Card {
            HStack(spacing: 12) {
                Text("App 上鎖").font(.headline).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Toggle("App 上鎖", isOn: Binding(get: { lock.isOn }, set: switchLock))
                    .labelsHidden().tint(Palette.blue)
                    .accessibilityIdentifier("lock-toggle")
            }
            Text("開啟後，每次打開 App，或離開超過 1 分鐘再回來，都要先輸入 6 位數密碼解鎖；切到背景時，畫面會先遮住。")
                .font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 6)
            if lock.isOn {
                if lock.biometry != .none {
                    Divider().padding(.vertical, 10)
                    HStack(spacing: 12) {
                        Text("用 \(lock.biometry.name) 解鎖").font(.subheadline.bold()).foregroundStyle(Palette.ink)
                        Spacer(minLength: 8)
                        Toggle("用 \(lock.biometry.name) 解鎖", isOn: Binding(get: { lock.faceIDOn }, set: switchFaceID))
                            .labelsHidden().tint(Palette.blue).disabled(working)
                            .accessibilityIdentifier("lock-faceid-toggle")
                    }
                }
                Divider().padding(.vertical, 10)
                Button { note = nil; flow = .change } label: {
                    HStack {
                        Text("變更密碼").font(.subheadline.bold()).foregroundStyle(Palette.ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lock-change")
            }
            if let note { Text(note).font(.caption).foregroundStyle(Palette.red).padding(.top, 8) }
            Text("密碼本身不會被儲存：只把加鹽雜湊放在這支 iPhone 的 Keychain，不寫入備份或匯出，匯入備份也不會改變上鎖。忘記密碼時，先用 iPhone 本身的密碼或 Face ID 確認是你，就能設定新密碼，紀錄都會保留。")
                .font(.caption).foregroundStyle(Palette.muted).padding(.top, 10)
        }
        .sheet(item: $flow) { flow in
            LockFlowSheet(flow: flow) { note = $0 }
                .environment(\.skin, skins.skin)
                .preferredColorScheme(skins.colorScheme)
        }
    }

    private func switchLock(_ on: Bool) {
        note = nil
        guard on else { flow = .turnOff; return }
        // 忘記密碼 relies on the phone's own passcode: without one, a forgotten app passcode could never be reset.
        guard lock.authenticator.ownerCheckAvailable else {
            note = "請先在 iPhone 設定開啟 iPhone 密碼：忘記 App 密碼時，要用它確認是你。"
            return
        }
        flow = .turnOn
    }

    private func switchFaceID(_ on: Bool) {
        note = nil
        working = true
        Task {
            note = await lock.setFaceID(on)
            working = false
        }
    }
}

enum LockFlow: String, Identifiable {
    case turnOn, turnOff, change
    var id: String { rawValue }
}

/// The settings sheet: a new passcode twice (開啟), the current one (關閉, or Face ID), or the current one and then a
/// new one twice (變更密碼). Right after a passcode is set, Face ID is offered when the phone has it.
struct LockFlowSheet: View {
    let flow: LockFlow
    let onNote: (String?) -> Void

    @ObservedObject private var lock = AppLock.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.skin) private var skin
    @Environment(\.motionReduced) private var reduceMotion
    @State private var setup: PasscodeSetup
    @State private var code = ""
    @State private var message: String?
    @State private var warning = false
    @State private var shakes = 0
    @State private var offering = false
    @State private var now = Date()
    @State private var prompted = false

    init(flow: LockFlow, onNote: @escaping (String?) -> Void) {
        self.flow = flow
        self.onNote = onNote
        _setup = State(initialValue: PasscodeSetup(askingCurrent: flow != .turnOn))
    }

    private var checkingCurrent: Bool { setup.step == .current }
    private var blocked: Bool { checkingCurrent && lock.backoff.isBlocked(at: now) }
    /// Turning the lock off takes Face ID as well as the passcode.
    private var biometry: LockBiometry? {
        flow == .turnOff && checkingCurrent && lock.faceIDOn && lock.biometry != .none ? lock.biometry : nil
    }

    var body: some View {
        NavigationStack {
            Group { if offering { offer } else { entry } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(skin.color(\.page).ignoresSafeArea())
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .task(id: lock.backoff) { await countDown() }
        .onAppear {
            guard biometry != nil, !prompted else { return }
            prompted = true
            useBiometry()
        }
    }

    private var title: String {
        switch flow {
        case .turnOn: return "開啟 App 上鎖"
        case .turnOff: return "關閉 App 上鎖"
        case .change: return "變更密碼"
        }
    }

    private var prompt: String {
        switch setup.step {
        case .current: return "輸入目前的密碼"
        case .new: return flow == .turnOn ? "設定 6 位數的 App 密碼" : "輸入新密碼"
        case .confirm: return flow == .turnOn ? "再輸入一次" : "再輸入一次新密碼"
        }
    }

    private var shownMessage: String? {
        guard blocked else { return message }
        return "密碼錯誤太多次，請在 \(AppLockRules.waitText(lock.backoff.remaining(at: now))) 後再試。"
    }

    private var entry: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            PasscodePanel(prompt: prompt, message: shownMessage, warning: warning || blocked, filled: code.count, shakes: shakes,
                          digitsEnabled: !blocked, biometry: biometry, onDigit: digit, onDelete: delete, onBiometry: useBiometry)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
    }

    private var offer: some View {
        let name = lock.biometry.name
        return VStack(spacing: 16) {
            Spacer()
            Image(systemName: lock.biometry.symbol).font(.system(size: 56)).foregroundStyle(skin.color(\.accent))
                .accessibilityHidden(true)
            Text("要用 \(name) 解鎖嗎？").skinFont(.title(20)).foregroundStyle(skin.color(\.ink))
            Text("打開 App 時就能用 \(name) 解鎖，也隨時可以改輸入密碼。").skinFont(.body(15)).foregroundStyle(skin.color(\.sub))
                .multilineTextAlignment(.center)
            SkinButton("使用 \(name)") {
                Task {
                    onNote(await lock.setFaceID(true))
                    dismiss()
                }
            }
            .padding(.top, 8)
            SkinButton("暫時不要", primary: false) { dismiss() }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func digit(_ value: Int) {
        guard code.count < Passcode.length, !blocked else { return }
        code.append(String(value))
        guard code.count == Passcode.length else { return }
        let entered = code
        code = ""
        submit(entered)
    }

    private func delete() { if !code.isEmpty { code.removeLast() } }

    private func submit(_ entered: String) {
        if checkingCurrent {
            switch lock.check(entered) {
            case .right:
                if flow == .turnOff {
                    lock.turnOff()
                    onNote(nil)
                    dismiss()
                } else {
                    setup.currentAccepted()
                    message = nil; warning = false
                }
            case .wrong:
                message = "密碼錯誤"; wrongFeedback()
            case .blocked:
                wrongFeedback()
            }
            return
        }
        switch setup.enter(entered) {
        case .next:
            message = nil; warning = false
        case .mismatch:
            message = "兩次輸入的密碼不一樣，請重新輸入。"; wrongFeedback()
        case .finished(let passcode):
            do {
                if flow == .turnOn { try lock.turnOn(passcode: passcode) } else { try lock.change(to: passcode) }
                if flow == .turnOn, lock.biometry != .none {
                    withAnimation(.easeOut(duration: 0.2)) { offering = true }
                } else {
                    onNote(nil)
                    dismiss()
                }
            } catch {
                message = "無法把密碼存進這支 iPhone，請再試一次。"; warning = true
                setup = PasscodeSetup(askingCurrent: false)
            }
        }
    }

    private func wrongFeedback() {
        warning = true
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 0.4)) { shakes += 1 }
    }

    private func useBiometry() {
        Task {
            switch await lock.biometricCheck(reason: "關閉投資袋著走的 App 上鎖") {
            case .success:
                lock.turnOff()
                onNote(nil)
                dismiss()
            case .cancelled:
                break
            case .failed(let reason):
                message = reason; warning = true
            }
        }
    }

    private func countDown() async {
        now = Date()
        while lock.backoff.isBlocked(at: now) {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            now = Date()
        }
    }
}
