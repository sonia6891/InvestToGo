import Foundation
import Security

/// 口袋會員前 7 天全開's record (`MemberOpenRecord`) in the Keychain: on this device only and readable after the
/// phone's first unlock (a price-alert check in the background reads it too). Never in a device backup, never in
/// iCloud Keychain, never in the app's own backup file; the Keychain outlives the app, so deleting and reinstalling it
/// does not start a new 7 days.
final class KeychainMemberOpenVault: MemberOpenVault {
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "ETFToGo.MemberOpen",
        kSecAttrAccount as String: "seven-days",
    ]

    func read() -> MemberOpenRead {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess, let bytes = item as? Data else { return .unreadable }
        // An item that cannot be decoded is not a start: kept as unreadable, so it is never replaced by a new one.
        guard let record = try? JSONDecoder().decode(MemberOpenRecord.self, from: bytes) else { return .unreadable }
        return .found(record)
    }

    func save(_ record: MemberOpenRecord) throws {
        let bytes = try JSONEncoder().encode(record)
        let update: [String: Any] = [
            kSecValueData as String: bytes,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw StoreError.keychain(status) }
        var add = query
        add.merge(update) { _, new in new }
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw StoreError.keychain(added) }
    }
}

extension MemberOpenDays {
    /// The 7 days for this launch. A real launch keeps them in the Keychain and starts them at the first open. UI tests
    /// have them off unless `--member-open <day>` sets the day (in memory, nothing in the simulator's Keychain), and
    /// the unit-test host has them off: its tests make their own.
    static func forLaunch(arguments: [String] = ProcessInfo.processInfo.arguments,
                          environment: [String: String] = ProcessInfo.processInfo.environment) -> MemberOpenDays {
        if arguments.contains("--ui-testing") {
            let vault = MemoryMemberOpenVault()
            if let day = uiTestDay(arguments) { vault.record = MemberOpenRecord(start: uiTestStart(day: day, now: Date())) }
            return MemberOpenDays(vault: vault, starts: false, catchUp: false)
        }
        if environment["XCTestConfigurationFilePath"] != nil {
            return MemberOpenDays(vault: MemoryMemberOpenVault(), starts: false)
        }
        return MemberOpenDays(vault: KeychainMemberOpenVault())
    }
}
