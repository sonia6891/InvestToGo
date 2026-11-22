import SwiftUI
import LocalAuthentication
import Security

// App 上鎖 (docs/superpowers/specs/2026-11-22-app-lock-design.md): the lock's state, the Keychain that holds the
// passcode's hash and LocalAuthentication for Face ID and the phone owner. Nothing here touches the network.

/// The phone's biometric sensor, by the name the device gives it.
enum LockBiometry: Equatable {
    case none, faceID, touchID, opticID
    var name: String {
        switch self {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .none: return ""
        }
    }
    var symbol: String {
        switch self {
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "faceid"
        }
    }
}

enum LockAuthResult: Equatable {
    case success
    /// Cancelled, or 「輸入密碼」 chosen instead: nothing to say.
    case cancelled
    /// Failed or not possible, with the reason to show.
    case failed(String)
}

/// Face ID / Touch ID, and the phone owner (Face ID or the phone's passcode) for 忘記密碼.
protocol LockAuthenticator {
    var biometry: LockBiometry { get }
    /// The phone has a passcode, so the owner can be asked for when the app passcode is forgotten.
    var ownerCheckAvailable: Bool { get }
    func biometrics(reason: String) async -> LockAuthResult
    func owner(reason: String) async -> LockAuthResult
}

struct SystemAuthenticator: LockAuthenticator {
    var biometry: LockBiometry {
        let context = LAContext()
        // biometryType is filled in by canEvaluatePolicy, also when Face ID is not enrolled or not allowed.
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        case .none: return .none
        @unknown default: return .none
        }
    }

    var ownerCheckAvailable: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    func biometrics(reason: String) async -> LockAuthResult {
        let context = LAContext()
        context.localizedFallbackTitle = "輸入密碼"
        context.localizedCancelTitle = "取消"
        return await evaluate(context, .deviceOwnerAuthenticationWithBiometrics, reason: reason)
    }

    func owner(reason: String) async -> LockAuthResult {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        return await evaluate(context, .deviceOwnerAuthentication, reason: reason)
    }

    private func evaluate(_ context: LAContext, _ policy: LAPolicy, reason: String) async -> LockAuthResult {
        let name = biometry.name
        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else { return .failed(Self.message(error, biometry: name)) }
        do {
            return try await context.evaluatePolicy(policy, localizedReason: reason) ? .success : .failed(Self.message(nil, biometry: name))
        } catch {
            let code = LAError.Code(rawValue: (error as NSError).code)
            switch code {
            case .userCancel, .userFallback, .systemCancel, .appCancel: return .cancelled
            default: return .failed(Self.message(error as NSError, biometry: name))
            }
        }
    }

    static func message(_ error: NSError?, biometry name: String) -> String {
        let sensor = name.isEmpty ? "Face ID" : name
        switch error.flatMap({ LAError.Code(rawValue: $0.code) }) {
        case .biometryNotEnrolled: return "這支 iPhone 還沒有設定 \(sensor)。"
        case .biometryNotAvailable: return "無法使用 \(sensor)：可到 iPhone 設定 › 投資袋著走 允許使用 \(sensor)。"
        case .biometryLockout: return "\(sensor) 失敗太多次，暫時無法使用，請先輸入密碼。"
        case .passcodeNotSet: return "這支 iPhone 沒有設定密碼。"
        default: return "沒有通過驗證，請再試一次。"
        }
    }
}

/// UI tests (`--ui-testing`): no Face ID, and no phone owner to ask.
struct UITestAuthenticator: LockAuthenticator {
    var biometry: LockBiometry { .none }
    var ownerCheckAvailable: Bool { true }
    func biometrics(reason: String) async -> LockAuthResult { .failed("UI 測試不使用 Face ID。") }
    func owner(reason: String) async -> LockAuthResult { .failed("UI 測試無法確認 iPhone 的主人。") }
}

enum VaultRead {
    case found(PasscodeHash)
    case missing
    /// The Keychain cannot be read now (the phone is locked): the lock keeps its state.
    case unreadable
}

/// Where the passcode's hash is kept.
protocol PasscodeVault: AnyObject {
    func read() -> VaultRead
    func save(_ hash: PasscodeHash) throws
    func remove() throws
}

/// The Keychain, on this device only and readable only while it is unlocked: never in a device backup, never in
/// iCloud Keychain, never in the app's own backup file.
final class KeychainPasscodeVault: PasscodeVault {
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "ETFToGo.AppLock",
        kSecAttrAccount as String: "passcode-hash",
    ]

    func read() -> VaultRead {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess, let bytes = item as? Data else { return .unreadable }
        guard let hash = try? JSONDecoder().decode(PasscodeHash.self, from: bytes) else { return .missing }
        return .found(hash)
    }

    func save(_ hash: PasscodeHash) throws {
        // Replaced whole, so the item always carries this accessibility (an item left by an earlier install too).
        let removed = SecItemDelete(query as CFDictionary)
        guard removed == errSecSuccess || removed == errSecItemNotFound else { throw StoreError.keychain(removed) }
        var add = query
        add[kSecValueData as String] = try JSONEncoder().encode(hash)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.keychain(status) }
    }
}

/// UI tests and unit tests: nothing is written to the simulator's Keychain.
final class MemoryPasscodeVault: PasscodeVault {
    private var hash: PasscodeHash?
    func read() -> VaultRead { hash.map { .found($0) } ?? .missing }
    func save(_ hash: PasscodeHash) throws { self.hash = hash }
    func remove() throws { hash = nil }
}

/// The lock. `isOn` is a flag in UserDefaults (it says only that the lock is on); the passcode lives only as a hash
/// in the vault, and the lock counts as on only while both are there: a phone restored from a backup carries the flag
/// but not the this-device-only Keychain item, and then the lock is off. Nothing here is part of the app's backup
/// file, so importing one never carries or changes the lock.
///
/// It locks on every cold launch once the opening has gone (`openingEnded`), and on a return from the background
/// after more than 60 s; with the lock on, a cover hides the screen as the app leaves the front, so the app-switcher
/// snapshot shows the cover. Onboarding is never locked. Both the lock screen and the cover are drawn by `LockWindow`,
/// above every sheet and alert.
@MainActor final class AppLock: ObservableObject {
    static let shared = AppLock()
    nonisolated static let onKey = "appLock.on", faceIDKey = "appLock.faceID", backoffKey = "appLock.backoff"

    @Published private(set) var isOn: Bool
    @Published private(set) var faceIDOn: Bool
    @Published private(set) var locked = false
    @Published private(set) var covered = false
    /// The lobby may be built: the cold launch has been decided and the app is unlocked. Stays true once set.
    @Published private(set) var lobbyReleased = false
    @Published private(set) var backoff: PasscodeBackoff
    @Published private(set) var biometry: LockBiometry
    /// The scene is in front (the lock screen's Face ID prompt waits for it).
    @Published private(set) var active = false
    /// Counts the times the app has locked, so the lock screen opens Face ID by itself once each time.
    @Published private(set) var lockCount = 0

    let authenticator: LockAuthenticator
    private let vault: PasscodeVault
    private let defaults: UserDefaults
    private let testing: Bool
    private var cachedHash: PasscodeHash?
    /// The cold launch has not been decided yet.
    private var coldPending = true
    /// The opening has gone (or there was none), so a cold launch may lock now.
    private var openingDone = false
    private var phase: ScenePhase?
    private var awaySince: Date?
    /// A Face ID or phone-passcode prompt is up: the scene goes inactive under it, which is not leaving the app.
    private var authenticating = false

    convenience init() {
        let arguments = ProcessInfo.processInfo.arguments
        if AppLockRules.isUITesting(arguments) {
            // UI tests: in memory, starting fresh every launch; on with 123456 only under `--lock`.
            let suite = "ETFToGo.ui-test.app-lock"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            let vault = MemoryPasscodeVault()
            if let code = AppLockRules.uiTestPasscode(arguments) {
                try? vault.save(.make(code))
                defaults.set(true, forKey: Self.onKey)
            }
            self.init(vault: vault, authenticator: UITestAuthenticator(), defaults: defaults, testing: true)
        } else {
            self.init(vault: KeychainPasscodeVault(), authenticator: SystemAuthenticator(), defaults: .standard, testing: false)
        }
    }

    init(vault: PasscodeVault, authenticator: LockAuthenticator, defaults: UserDefaults, testing: Bool) {
        self.vault = vault
        self.authenticator = authenticator
        self.defaults = defaults
        self.testing = testing
        isOn = defaults.bool(forKey: Self.onKey)
        faceIDOn = defaults.bool(forKey: Self.faceIDKey)
        var backoff = (defaults.data(forKey: Self.backoffKey)).flatMap { try? JSONDecoder().decode(PasscodeBackoff.self, from: $0) } ?? PasscodeBackoff()
        backoff.settle(at: Date())
        self.backoff = backoff
        biometry = authenticator.biometry
    }

    // MARK: Launch and the scene

    /// The opening has gone, or there was none: a cold launch locks now (with the lock on). `onboarding`: the
    /// first-launch flow is showing, which is never locked.
    func openingEnded(onboarding: Bool) {
        guard coldPending else { return }
        openingDone = true
        if onboarding {
            coldPending = false
            lobbyReleased = true
            return
        }
        // With the lock off, a launch in the background waits for the front before building the lobby: the flag may
        // not have been readable yet (UserDefaults before the phone's first unlock).
        if isOn || active || testing { decideColdLaunch() }
    }

    /// A scene that never reports itself active (it should) is still decided a second after the opening.
    func openingFallback() {
        guard coldPending, openingDone, phase != .background else { return }
        decideColdLaunch()
    }

    func scene(_ new: ScenePhase, now: Date = Date()) {
        let previous = phase
        phase = new
        switch new {
        case .background:
            active = false
            if awaySince == nil { awaySince = now }
            if isOn { covered = true }
        case .inactive:
            active = false
            // Only on leaving the front (the app switcher, Control Center), never while a launch passes through
            // inactive before its first frame, nor under the Face ID prompt.
            if isOn, previous == .active, !authenticating { covered = true }
        case .active:
            refresh()
            if coldPending {
                if openingDone { decideColdLaunch() }
            } else if let away = awaySince, AppLockRules.shouldLock(lockOn: isOn, coldLaunch: false, away: now.timeIntervalSince(away)) {
                lock()
            }
            awaySince = nil
            covered = false
            active = true
        @unknown default:
            break
        }
    }

    private func decideColdLaunch() {
        coldPending = false
        refresh()
        if AppLockRules.shouldLock(lockOn: isOn, coldLaunch: true, away: nil) { lock() } else { lobbyReleased = true }
    }

    private func lock() {
        guard !locked else { return }
        locked = true
        lockCount += 1
    }

    /// The flag without its hash (a phone restored from a backup) is off. A Keychain that cannot be read yet keeps
    /// the lock as it is. Face ID's availability may have changed in iPhone settings.
    private func refresh() {
        isOn = defaults.bool(forKey: Self.onKey)
        faceIDOn = defaults.bool(forKey: Self.faceIDKey)
        biometry = authenticator.biometry
        guard isOn else { return }
        if case .missing = vault.read() {
            cachedHash = nil
            setFlags(on: false, faceID: false)
        }
    }

    private func setFlags(on: Bool, faceID: Bool) {
        defaults.set(on, forKey: Self.onKey)
        defaults.set(faceID, forKey: Self.faceIDKey)
        isOn = on
        faceIDOn = faceID
    }

    // MARK: Checking

    enum Check: Equatable { case right, wrong, blocked }

    /// Checks a passcode against the stored hash, with the back-off: during a block nothing is checked.
    func check(_ code: String, now: Date = Date()) -> Check {
        if backoff.isBlocked(at: now) { return .blocked }
        guard let hash = storedHash() else { return .wrong }
        if hash.matches(code) {
            backoff.recordRight()
            saveBackoff()
            return .right
        }
        backoff.recordWrong(at: now)
        saveBackoff()
        return .wrong
    }

    /// The lock screen's passcode.
    func unlock(_ code: String) -> Check {
        let result = check(code)
        if result == .right { unlocked() }
        return result
    }

    /// The lock screen's Face ID.
    func unlockWithBiometrics() async -> LockAuthResult {
        let result = await biometricCheck(reason: "解鎖投資袋著走")
        if result == .success { unlocked() }
        return result
    }

    /// Face ID in place of the passcode (also during a block); a success starts the back-off over.
    func biometricCheck(reason: String) async -> LockAuthResult {
        guard faceIDOn else { return .cancelled }
        let result = await authenticate { await self.authenticator.biometrics(reason: reason) }
        if result == .success {
            backoff.recordRight()
            saveBackoff()
        }
        return result
    }

    /// 忘記密碼: the phone's owner, by Face ID or the phone's passcode.
    func verifyOwner() async -> LockAuthResult {
        await authenticate { await self.authenticator.owner(reason: "確認你是這支 iPhone 的主人，就能設定新的 App 密碼") }
    }

    private func authenticate(_ body: () async -> LockAuthResult) async -> LockAuthResult {
        authenticating = true
        defer { authenticating = false }
        return await body()
    }

    private func unlocked() {
        backoff.recordRight()
        saveBackoff()
        withAnimation(.easeOut(duration: 0.25)) {
            locked = false
            lobbyReleased = true
        }
    }

    private func storedHash() -> PasscodeHash? {
        if let cachedHash { return cachedHash }
        guard case .found(let hash) = vault.read() else { return nil }
        cachedHash = hash
        return hash
    }

    private func saveBackoff() {
        defaults.set(try? JSONEncoder().encode(backoff), forKey: Self.backoffKey)
    }

    // MARK: Settings

    func turnOn(passcode: String) throws {
        try store(passcode)
        backoff = PasscodeBackoff()
        saveBackoff()
        setFlags(on: true, faceID: false)
    }

    func change(to passcode: String) throws { try store(passcode) }

    /// After 忘記密碼: the new passcode, and the app opens. The records stay as they are.
    func reset(to passcode: String) throws {
        try store(passcode)
        setFlags(on: true, faceID: faceIDOn)
        unlocked()
    }

    func turnOff() {
        try? vault.remove()
        cachedHash = nil
        backoff = PasscodeBackoff()
        saveBackoff()
        setFlags(on: false, faceID: false)
    }

    /// 用 Face ID 解鎖. Turning it on asks for Face ID once, which is also when iOS asks to allow it. A message when
    /// it could not be turned on.
    func setFaceID(_ on: Bool) async -> String? {
        guard on else { setFlags(on: isOn, faceID: false); return nil }
        guard isOn else { return nil }
        let result = await authenticate { await self.authenticator.biometrics(reason: "開啟後，就能用 \(self.biometry.name) 解鎖投資袋著走") }
        biometry = authenticator.biometry
        switch result {
        case .success: setFlags(on: true, faceID: true); return nil
        case .cancelled: return nil
        case .failed(let message): return message
        }
    }

    private func store(_ passcode: String) throws {
        guard Passcode.isValid(passcode) else { throw StoreError.keychain(errSecParam) }
        let hash = PasscodeHash.make(passcode)
        try vault.save(hash)
        cachedHash = hash
    }
}
