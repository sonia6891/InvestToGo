import XCTest
import SwiftUI
@testable import ETFToGo

/// App 上鎖 (docs/superpowers/specs/2026-11-22-app-lock-design.md): the passcode hash, the back-off after wrong tries,
/// when the app locks, and the lock's own state as the scene comes and goes.
final class AppLockRulesTests: XCTestCase {
    // MARK: Passcode and its hash

    func testOnlySixPlainDigitsAreAPasscode() {
        XCTAssertTrue(Passcode.isValid("123456"))
        XCTAssertTrue(Passcode.isValid("000000"))
        XCTAssertFalse(Passcode.isValid("12345"))
        XCTAssertFalse(Passcode.isValid("1234567"))
        XCTAssertFalse(Passcode.isValid("12345a"))
        XCTAssertFalse(Passcode.isValid("１２３４５６"), "Full-width digits are not the keypad's digits")
        XCTAssertFalse(Passcode.isValid(""))
    }

    func testTheHashMatchesOnlyTheSameCode() {
        let hash = PasscodeHash.make("246810")
        XCTAssertTrue(hash.matches("246810"))
        XCTAssertFalse(hash.matches("246811"))
        XCTAssertFalse(hash.matches("024681"))
        XCTAssertFalse(hash.matches(""))
    }

    func testTheHashIsSaltedAndNeverTheCode() {
        let a = PasscodeHash.make("123456"), b = PasscodeHash.make("123456")
        XCTAssertEqual(a.salt.count, 16)
        XCTAssertNotEqual(a.salt, b.salt, "Every passcode gets its own salt")
        XCTAssertNotEqual(a.digest, b.digest, "So the same code never stores the same digest twice")
        XCTAssertEqual(a.digest.count, 32)
        XCTAssertGreaterThan(a.rounds, 1, "The digest is stretched")
        // The stored form holds neither the code nor its plain SHA-256.
        let stored = String(decoding: try! JSONEncoder().encode(a), as: UTF8.self)
        XCTAssertFalse(stored.contains("123456"))
        XCTAssertNotEqual(a.digest, SHA256Digest.hash(Data("123456".utf8)))
    }

    func testTheHashIsTheSameForTheSameSaltAndSurvivesStorage() throws {
        let salt: [UInt8] = Array(0..<16)
        let a = PasscodeHash.make("135790", salt: salt), b = PasscodeHash.make("135790", salt: salt)
        XCTAssertEqual(a, b)
        let decoded = try JSONDecoder().decode(PasscodeHash.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(decoded, a)
        XCTAssertTrue(decoded.matches("135790"))
        XCTAssertFalse(decoded.matches("135791"))
    }

    // MARK: Back-off

    func testFiveWrongTriesBlockForThirtySeconds() {
        var backoff = PasscodeBackoff()
        let start = Date(timeIntervalSince1970: 1_000_000)
        for i in 1...4 {
            backoff.recordWrong(at: start)
            XCTAssertFalse(backoff.isBlocked(at: start), "Not blocked after \(i) wrong")
        }
        XCTAssertTrue(backoff.recordWrong(at: start), "The fifth wrong try starts a block")
        XCTAssertTrue(backoff.isBlocked(at: start))
        XCTAssertEqual(backoff.remaining(at: start), 30, accuracy: 0.001)
        XCTAssertTrue(backoff.isBlocked(at: start.addingTimeInterval(29.9)))
        XCTAssertFalse(backoff.isBlocked(at: start.addingTimeInterval(30)))
    }

    func testLaterBlocksDouble() {
        XCTAssertEqual(PasscodeBackoff.length(ofBlock: 1), 30)
        XCTAssertEqual(PasscodeBackoff.length(ofBlock: 2), 60)
        XCTAssertEqual(PasscodeBackoff.length(ofBlock: 3), 120)
        XCTAssertEqual(PasscodeBackoff.length(ofBlock: 4), 240)
        var backoff = PasscodeBackoff()
        var now = Date(timeIntervalSince1970: 2_000_000)
        for expected in [30.0, 60, 120, 240] {
            for _ in 1...5 { backoff.recordWrong(at: now) }
            XCTAssertEqual(backoff.remaining(at: now), expected, accuracy: 0.001)
            now = now.addingTimeInterval(expected)
            XCTAssertFalse(backoff.isBlocked(at: now))
        }
    }

    func testBlocksStopGrowingAtAnHour() {
        XCTAssertEqual(PasscodeBackoff.length(ofBlock: 8), 3600)
        XCTAssertEqual(PasscodeBackoff.length(ofBlock: 40), 3600)
    }

    func testWrongTriesDuringABlockDoNotCount() {
        var backoff = PasscodeBackoff()
        let start = Date(timeIntervalSince1970: 3_000_000)
        for _ in 1...5 { backoff.recordWrong(at: start) }
        for _ in 1...10 { XCTAssertFalse(backoff.recordWrong(at: start.addingTimeInterval(5))) }
        XCTAssertEqual(backoff.remaining(at: start.addingTimeInterval(5)), 25, accuracy: 0.001, "The block is not lengthened")
        // After the block, it takes five more wrong tries to block again, now for 60 s.
        let after = start.addingTimeInterval(30)
        for _ in 1...4 { backoff.recordWrong(at: after) }
        XCTAssertFalse(backoff.isBlocked(at: after))
        backoff.recordWrong(at: after)
        XCTAssertEqual(backoff.remaining(at: after), 60, accuracy: 0.001)
    }

    func testTheRightCodeStartsOver() {
        var backoff = PasscodeBackoff()
        let start = Date(timeIntervalSince1970: 4_000_000)
        for _ in 1...5 { backoff.recordWrong(at: start) }
        let later = start.addingTimeInterval(31)
        for _ in 1...3 { backoff.recordWrong(at: later) }
        backoff.recordRight()
        XCTAssertEqual(backoff, PasscodeBackoff())
        for _ in 1...5 { backoff.recordWrong(at: later) }
        XCTAssertEqual(backoff.remaining(at: later), 30, accuracy: 0.001, "Back to the first block's length")
    }

    func testAClockSetBackNeverLengthensABlock() {
        var backoff = PasscodeBackoff()
        let start = Date(timeIntervalSince1970: 5_000_000)
        for _ in 1...5 { backoff.recordWrong(at: start) }
        let dayBefore = start.addingTimeInterval(-86_400)
        XCTAssertEqual(backoff.remaining(at: dayBefore), 30, accuracy: 0.001)
        backoff.settle(at: dayBefore)
        XCTAssertFalse(backoff.isBlocked(at: dayBefore.addingTimeInterval(30)))
    }

    func testTheBackOffSurvivesARelaunch() throws {
        var backoff = PasscodeBackoff()
        let start = Date(timeIntervalSince1970: 6_000_000)
        for _ in 1...5 { backoff.recordWrong(at: start) }
        let decoded = try JSONDecoder().decode(PasscodeBackoff.self, from: JSONEncoder().encode(backoff))
        XCTAssertEqual(decoded, backoff)
        XCTAssertTrue(decoded.isBlocked(at: start.addingTimeInterval(10)))
    }

    func testTheWaitReadsInSecondsAndMinutes() {
        XCTAssertEqual(AppLockRules.waitText(30), "30 秒")
        XCTAssertEqual(AppLockRules.waitText(29.2), "30 秒", "Rounded up, never 0 while still blocked")
        XCTAssertEqual(AppLockRules.waitText(60), "1 分鐘")
        XCTAssertEqual(AppLockRules.waitText(90), "1 分 30 秒")
        XCTAssertEqual(AppLockRules.waitText(3600), "60 分鐘")
    }

    // MARK: When it locks

    func testShouldLock() {
        // Off: never.
        XCTAssertFalse(AppLockRules.shouldLock(lockOn: false, coldLaunch: true, away: nil))
        XCTAssertFalse(AppLockRules.shouldLock(lockOn: false, coldLaunch: false, away: 3600))
        // Every cold launch.
        XCTAssertTrue(AppLockRules.shouldLock(lockOn: true, coldLaunch: true, away: nil))
        XCTAssertTrue(AppLockRules.shouldLock(lockOn: true, coldLaunch: true, away: 5))
        // Back from the background after more than 60 s.
        XCTAssertFalse(AppLockRules.shouldLock(lockOn: true, coldLaunch: false, away: nil), "Never in the background")
        XCTAssertFalse(AppLockRules.shouldLock(lockOn: true, coldLaunch: false, away: 0))
        XCTAssertFalse(AppLockRules.shouldLock(lockOn: true, coldLaunch: false, away: 30))
        XCTAssertFalse(AppLockRules.shouldLock(lockOn: true, coldLaunch: false, away: 60))
        XCTAssertTrue(AppLockRules.shouldLock(lockOn: true, coldLaunch: false, away: 60.5))
        XCTAssertTrue(AppLockRules.shouldLock(lockOn: true, coldLaunch: false, away: 3600))
        // A clock set back while away: locked, rather than trusting a negative time.
        XCTAssertTrue(AppLockRules.shouldLock(lockOn: true, coldLaunch: false, away: -10))
    }

    func testUITestingIsUnlockedUnlessAskedToLock() {
        XCTAssertNil(AppLockRules.uiTestPasscode(["--ui-testing"]))
        XCTAssertEqual(AppLockRules.uiTestPasscode(["--ui-testing", "--lock"]), "123456")
        XCTAssertNil(AppLockRules.uiTestPasscode(["--lock"]), "--lock means nothing outside UI tests")
        XCTAssertTrue(AppLockRules.isUITesting(["--ui-testing"]))
        XCTAssertFalse(AppLockRules.isUITesting([]))
    }

    // MARK: Setting a passcode

    func testANewPasscodeIsEnteredTwice() {
        var setup = PasscodeSetup(askingCurrent: false)
        XCTAssertEqual(setup.step, .new)
        XCTAssertEqual(setup.enter("111222"), .next)
        XCTAssertEqual(setup.step, .confirm)
        XCTAssertEqual(setup.enter("111222"), .finished("111222"))
    }

    func testTwoDifferentEntriesStartOver() {
        var setup = PasscodeSetup(askingCurrent: false)
        _ = setup.enter("111222")
        XCTAssertEqual(setup.enter("111223"), .mismatch)
        XCTAssertEqual(setup.step, .new, "Back to the first entry")
        XCTAssertEqual(setup.enter("333444"), .next)
        XCTAssertEqual(setup.enter("333444"), .finished("333444"))
    }

    func testChangingAsksForTheCurrentCodeFirst() {
        var setup = PasscodeSetup(askingCurrent: true)
        XCTAssertEqual(setup.step, .current)
        setup.currentAccepted()
        XCTAssertEqual(setup.step, .new)
        _ = setup.enter("555666")
        XCTAssertEqual(setup.enter("555666"), .finished("555666"))
    }
}

/// The lock's state: what the settings switch does, and the scene's phases at a cold launch and on returns.
@MainActor final class AppLockStateTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "AppLockStateTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeLock(vault: MemoryPasscodeVault = MemoryPasscodeVault()) -> AppLock {
        AppLock(vault: vault, authenticator: StubAuthenticator(), defaults: defaults, testing: false)
    }

    func testOffByDefaultAndTheLobbyIsReleasedAtOnce() {
        let lock = makeLock()
        XCTAssertFalse(lock.isOn)
        lock.scene(.active)
        lock.openingEnded(onboarding: false)
        XCTAssertFalse(lock.locked)
        XCTAssertTrue(lock.lobbyReleased)
    }

    func testTurningOnStoresOnlyAHashAndAFlag() throws {
        let vault = MemoryPasscodeVault()
        let lock = makeLock(vault: vault)
        try lock.turnOn(passcode: "123456")
        XCTAssertTrue(lock.isOn)
        guard case .found(let hash) = vault.read() else { return XCTFail("The vault holds the hash") }
        XCTAssertTrue(hash.matches("123456"))
        // UserDefaults says only that the lock is on: nothing of the passcode.
        let stored = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("appLock.") }
        for (key, value) in stored { XCTAssertFalse("\(value)".contains("123456"), key) }
        XCTAssertEqual(lock.check("123456"), .right)
        XCTAssertEqual(lock.check("654321"), .wrong)
    }

    func testAColdLaunchLocksOnceTheOpeningHasGone() throws {
        let vault = MemoryPasscodeVault()
        try makeLock(vault: vault).turnOn(passcode: "123456")
        let lock = makeLock(vault: vault)
        lock.scene(.inactive)
        lock.scene(.active)
        XCTAssertFalse(lock.locked, "Not while the opening plays")
        XCTAssertFalse(lock.lobbyReleased, "Nor is the lobby built behind it")
        lock.openingEnded(onboarding: false)
        XCTAssertTrue(lock.locked)
        XCTAssertFalse(lock.lobbyReleased)
        XCTAssertEqual(lock.unlock("000000"), .wrong)
        XCTAssertTrue(lock.locked)
        XCTAssertEqual(lock.unlock("123456"), .right)
        XCTAssertFalse(lock.locked)
        XCTAssertTrue(lock.lobbyReleased)
    }

    func testOnboardingIsNeverLocked() throws {
        let vault = MemoryPasscodeVault()
        try makeLock(vault: vault).turnOn(passcode: "123456")
        let lock = makeLock(vault: vault)
        lock.scene(.active)
        lock.openingEnded(onboarding: true)
        XCTAssertFalse(lock.locked)
        XCTAssertTrue(lock.lobbyReleased)
    }

    func testReturningLocksOnlyAfterAMinuteAway() throws {
        let lock = makeLock()
        lock.scene(.active)
        lock.openingEnded(onboarding: false)
        try lock.turnOn(passcode: "123456")
        let start = Date()
        lock.scene(.inactive, now: start)
        lock.scene(.background, now: start)
        XCTAssertTrue(lock.covered, "The cover is up at once")
        lock.scene(.inactive, now: start.addingTimeInterval(30))
        lock.scene(.active, now: start.addingTimeInterval(30))
        XCTAssertFalse(lock.locked, "30 s away")
        XCTAssertFalse(lock.covered)
        lock.scene(.inactive, now: start.addingTimeInterval(100))
        lock.scene(.background, now: start.addingTimeInterval(100))
        lock.scene(.inactive, now: start.addingTimeInterval(200))
        lock.scene(.active, now: start.addingTimeInterval(200))
        XCTAssertTrue(lock.locked, "100 s away")
    }

    func testTheCoverWaitsForTheFirstActive() throws {
        let vault = MemoryPasscodeVault()
        try makeLock(vault: vault).turnOn(passcode: "123456")
        let lock = makeLock(vault: vault)
        lock.scene(.inactive)
        XCTAssertFalse(lock.covered, "A launch passes through inactive before the opening: no cover over it")
        lock.scene(.active)
        lock.scene(.inactive)
        XCTAssertTrue(lock.covered, "Leaving for the app switcher covers the screen")
        lock.scene(.active)
        XCTAssertFalse(lock.covered)
    }

    func testTurningOffForgetsThePasscode() throws {
        let vault = MemoryPasscodeVault()
        let lock = makeLock(vault: vault)
        try lock.turnOn(passcode: "123456")
        lock.turnOff()
        XCTAssertFalse(lock.isOn)
        XCTAssertFalse(lock.faceIDOn)
        guard case .missing = vault.read() else { return XCTFail("The hash is removed") }
    }

    func testChangingThePasscode() throws {
        let lock = makeLock()
        try lock.turnOn(passcode: "123456")
        try lock.change(to: "987654")
        XCTAssertEqual(lock.check("123456"), .wrong)
        XCTAssertEqual(lock.check("987654"), .right)
    }

    func testABlockRefusesEvenTheRightCode() throws {
        let lock = makeLock()
        try lock.turnOn(passcode: "123456")
        let now = Date()
        for _ in 1...5 { XCTAssertEqual(lock.check("000000", now: now), .wrong) }
        XCTAssertEqual(lock.check("123456", now: now), .blocked)
        XCTAssertEqual(lock.check("123456", now: now.addingTimeInterval(31)), .right)
    }

    func testAFlagWithoutItsHashIsOff() {
        // A phone restored from a backup carries UserDefaults but not this-device-only Keychain items.
        defaults.set(true, forKey: AppLock.onKey)
        let lock = makeLock()
        lock.scene(.active)
        lock.openingEnded(onboarding: false)
        XCTAssertFalse(lock.isOn)
        XCTAssertFalse(lock.locked)
    }

    func testForgottenPasscodeIsReplacedAndUnlocks() async throws {
        let vault = MemoryPasscodeVault()
        try makeLock(vault: vault).turnOn(passcode: "123456")
        let lock = makeLock(vault: vault)
        lock.scene(.active)
        lock.openingEnded(onboarding: false)
        XCTAssertTrue(lock.locked)
        let owner = await lock.verifyOwner()
        XCTAssertEqual(owner, .success)
        try lock.reset(to: "222333")
        XCTAssertFalse(lock.locked)
        XCTAssertTrue(lock.isOn, "Still locked next time, with the new code")
        XCTAssertEqual(lock.check("222333"), .right)
    }
}

/// No Face ID; the phone owner always passes.
private struct StubAuthenticator: LockAuthenticator {
    var biometry: LockBiometry { .none }
    var ownerCheckAvailable: Bool { true }
    func biometrics(reason: String) async -> LockAuthResult { .failed("") }
    func owner(reason: String) async -> LockAuthResult { .success }
}
