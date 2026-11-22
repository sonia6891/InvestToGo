import Foundation

// App 上鎖 (docs/superpowers/specs/2026-11-22-app-lock-design.md): the pure rules, apart from the Keychain,
// LocalAuthentication and the screens, so they are unit tested (Tests/AppLockTests.swift).

/// The app passcode: six digits from the lock's own number pad.
enum Passcode {
    static let length = 6
    /// Six ASCII digits; full-width digits (a pasted string) are not the pad's.
    static func isValid(_ code: String) -> Bool {
        code.utf8.count == length && code.utf8.allSatisfy { (0x30...0x39).contains($0) }
    }
}

/// The only form the passcode is ever kept in: a salted, stretched SHA-256, stored in the Keychain
/// (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). Never in UserDefaults, backups or exports.
struct PasscodeHash: Codable, Equatable {
    /// SHA-256 applied this many times. Modest: the Keychain is what keeps the hash out of reach, and a check must
    /// stay quick on the main thread in a Debug build.
    static let defaultRounds = 1_000
    var salt: [UInt8]
    var digest: [UInt8]
    var rounds: Int

    static func make(_ code: String, salt: [UInt8] = PasscodeHash.newSalt(), rounds: Int = defaultRounds) -> PasscodeHash {
        PasscodeHash(salt: salt, digest: digest(code, salt: salt, rounds: rounds), rounds: rounds)
    }

    /// 16 bytes from the system's secure random source.
    static func newSalt() -> [UInt8] {
        var generator = SystemRandomNumberGenerator()
        return (0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
    }

    static func digest(_ code: String, salt: [UInt8], rounds: Int) -> [UInt8] {
        var value = SHA256Digest.hash(Data(salt + Array(code.utf8)))
        if rounds > 1 { for _ in 1..<rounds { value = SHA256Digest.hash(Data(value + salt)) } }
        return value
    }

    /// Compared in constant time.
    func matches(_ code: String) -> Bool {
        let candidate = Self.digest(code, salt: salt, rounds: max(rounds, 1))
        guard candidate.count == digest.count, !digest.isEmpty else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(candidate, digest) { difference |= a ^ b }
        return difference == 0
    }
}

/// Wrong passcodes in a row: five block attempts for 30 s, and each later block is twice the one before (at most an
/// hour). A block counts five new wrong tries after it ends; tries during a block are not counted. The right code (or
/// any unlock) starts over. Kept across launches, so quitting the app does not end a block.
struct PasscodeBackoff: Codable, Equatable {
    static let triesPerBlock = 5
    static let firstBlock: TimeInterval = 30
    static let longestBlock: TimeInterval = 60 * 60

    /// Wrong tries since the last block began, or since the last right one.
    private(set) var misses = 0
    /// Blocks in this run of wrong tries.
    private(set) var blocks = 0
    private(set) var blockedUntil: Date?

    /// The length of the `n`th block (1-based).
    static func length(ofBlock n: Int) -> TimeInterval {
        guard n > 0 else { return 0 }
        return min(firstBlock * pow(2, Double(min(n, 30) - 1)), longestBlock)
    }

    private var currentBlock: TimeInterval { Self.length(ofBlock: blocks) }

    /// Seconds left in the block; never more than the block's own length, should the clock have been set back.
    func remaining(at now: Date) -> TimeInterval {
        guard let until = blockedUntil else { return 0 }
        return min(max(until.timeIntervalSince(now), 0), currentBlock)
    }

    func isBlocked(at now: Date) -> Bool { remaining(at: now) > 0 }

    /// A wrong passcode; ignored during a block. True when this try started a block.
    @discardableResult mutating func recordWrong(at now: Date) -> Bool {
        guard !isBlocked(at: now) else { return false }
        misses += 1
        guard misses >= Self.triesPerBlock else { return false }
        misses = 0
        blocks += 1
        blockedUntil = now.addingTimeInterval(currentBlock)
        return true
    }

    mutating func recordRight() { self = PasscodeBackoff() }

    /// The clock was set back past the block's start: the block ends at most its own length from now.
    mutating func settle(at now: Date) {
        guard let until = blockedUntil, until.timeIntervalSince(now) > currentBlock else { return }
        blockedUntil = now.addingTimeInterval(currentBlock)
    }
}

enum AppLockRules {
    /// Back from the background after more than this, the app locks again.
    static let grace: TimeInterval = 60

    /// Whether the lock screen comes up: on every cold launch, and on a return from the background after more than
    /// `grace` seconds (`away`: nil when it never went to the background, only inactive). A negative time away means
    /// the clock was set back: locked, rather than trusted.
    static func shouldLock(lockOn: Bool, coldLaunch: Bool, away: TimeInterval?) -> Bool {
        guard lockOn else { return false }
        if coldLaunch { return true }
        guard let away else { return false }
        return away > grace || away < 0
    }

    static func isUITesting(_ arguments: [String]) -> Bool { arguments.contains("--ui-testing") }

    /// Under `--ui-testing` the lock is off unless `--lock` is passed; with it, the passcode is 123456 (and Face ID is
    /// unavailable). nil: the lock starts off. Outside UI tests `--lock` means nothing.
    static func uiTestPasscode(_ arguments: [String]) -> String? {
        isUITesting(arguments) && arguments.contains("--lock") ? "123456" : nil
    }

    /// The wait left in a block, rounded up: 「30 秒」, 「1 分 30 秒」, 「2 分鐘」.
    static func waitText(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.up)), 1)
        if total < 60 { return "\(total) 秒" }
        let minutes = total / 60, rest = total % 60
        return rest == 0 ? "\(minutes) 分鐘" : "\(minutes) 分 \(rest) 秒"
    }
}

/// Entering a new passcode twice, after the current one when changing it (or turning the lock off, which asks only
/// for the current one). The current code is checked by the lock itself (with its back-off); this only says what
/// is asked next.
struct PasscodeSetup: Equatable {
    enum Step: Equatable { case current, new, confirm }
    enum Outcome: Equatable {
        /// The next entry is asked for.
        case next
        /// The two entries differ: start again from the first.
        case mismatch
        /// Both entries agree on this passcode.
        case finished(String)
    }

    private(set) var step: Step
    private var first: String?

    init(askingCurrent: Bool) { step = askingCurrent ? .current : .new }

    mutating func currentAccepted() { if step == .current { step = .new } }

    mutating func enter(_ code: String) -> Outcome {
        switch step {
        case .current:
            return .next
        case .new:
            first = code
            step = .confirm
            return .next
        case .confirm:
            if code == first { return .finished(code) }
            first = nil
            step = .new
            return .mismatch
        }
    }
}
