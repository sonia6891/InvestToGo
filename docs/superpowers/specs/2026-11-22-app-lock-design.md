# App 上鎖（短設計）

Owner decisions, 2026-11-22:
- 「ETF 這東西比較私人」, so the app gets a lock.
- 「有設密碼，然後看他們用那個 Face ID 還是說用密碼解鎖」: the person sets an app passcode, then unlocks with Face ID (or Touch ID) or the passcode.
- 「就接着做」: build it right after the opening animation.
- Android will also be listed and should get its own lock (pattern, PIN, fingerprint). There is no Android project yet, so that is out of scope here and recorded for the Android build.

## Intent

Holdings and amounts are private. Someone who picks up the phone, or sees it in the app switcher, should not see them. This is a lock on this phone, not a login: no account, no network, and the data stays on the phone.

## Approaches

1. **Use only the phone's own Face ID and phone passcode** (`deviceOwnerAuthentication`). The simplest, with nothing to forget, but there is no app passcode, which the owner asked for.
2. **Use an app passcode, with Face ID as the quick way in. Chosen.** The person sets a 6-digit passcode for this app and may turn on Face ID. Unlocking asks for Face ID first and falls back to the passcode. If they forget it, 「忘記密碼」 verifies the phone owner with the phone's passcode and lets them set a new app passcode, with the records kept.
3. **Rely on the iOS 18 「鎖定 App」 system feature.** No code, but people rarely find it, and it does not cover the app-switcher snapshot.

## Design

### Settings (設定 › 隱私)

- The 「App 上鎖」 toggle is off by default. Turning it on asks for a new 6-digit passcode twice.
- Once a passcode is set, 「用 Face ID 解鎖」 shows on its own toggle, with the name from the device: Face ID, or Touch ID on devices with a fingerprint reader. It is offered right after the passcode is set.
- 「變更密碼」 asks for the current passcode, then the new one twice.
- Turning the lock off asks for Face ID or the passcode first.

### When it locks

- On every cold launch.
- On return from the background after more than 60 s.
- When the app goes to the background, a cover hides the screen at once, so the app-switcher snapshot shows the cover, never the screen. The cover shows only the app mark, with no amounts.

### The lock screen

- It shows the app name and six passcode dots, a number pad, and a Face ID button when Face ID is on.
- With Face ID on, the Face ID prompt opens by itself when the lock screen appears.
- A wrong passcode shakes the dots. Five wrong tries in a row block attempts for 30 s, and later blocks double each time. Face ID and 「忘記密碼」 still work during a block.
- 「忘記密碼」 asks the system for the phone's owner, by Face ID or the phone's passcode. On success the person sets a new app passcode, and the records stay.

### Order with the opening

- On a cold launch, the opening plays first, then the lock screen appears.
- With the lock on, the opening goes on to the lock screen, not to the lobby.
- Onboarding on the first launch is never locked, because no passcode exists yet.

### Storage and privacy

- Only a salted hash of the passcode is stored, in the Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). It is never in UserDefaults, backups or exports.
- An imported backup never carries or changes the lock.
- Face ID needs `NSFaceIDUsageDescription`: 「用 Face ID 解鎖投資袋著走」.
- Nothing about the lock touches the network.

### Other surfaces

- Notifications already never show holdings (the reminder shows only the planned monthly amount, and that can be turned off).
- The home widget (a later plan) shows no amounts while the app lock is on.

### Testing hooks

- Under `--ui-testing` the lock is off unless `--lock` is passed. With `--lock`, the passcode is `123456` and Face ID is unavailable, so a UI test types the passcode.
- Replace the 「目前未提供 App 內上鎖」 card in `App/HomeScreens.swift` with the real setting.

## Constraints

- No new packages. Use `LocalAuthentication` and the Keychain only.
- Copy is Traditional Chinese.
- Every existing accessibility identifier keeps its name.
- New identifiers: `lock-toggle`, `lock-faceid-toggle`, `lock-change`, `lock-screen`, `lock-key-0`…`lock-key-9`, `lock-delete`, `lock-faceid`, `lock-forgot`.

## Left to the builder

- The lock screen's look within each 外觀主題, reusing the existing `SkinStage`/`Palette`.
- Where the privacy cover hooks in (`scenePhase` in `LaunchGate`).

## Tests

- **Unit:**
  - Passcode hashing and checking.
  - The back-off schedule: 5 wrong tries give 30 s, then 60 s, and so on.
  - The "should lock" decision from three inputs: cold launch, time in the background, lock on or off.
- **UI test `testAppLockWithPasscode`:**
  1. Launch with `--lock`. `lock-screen` exists.
  2. A wrong code keeps it locked.
  3. `123456` reaches `lobby-find`.
- **UI test `testTurnOnLock`:** in settings, turn on `lock-toggle` and enter a new code twice. The toggle reads on.
