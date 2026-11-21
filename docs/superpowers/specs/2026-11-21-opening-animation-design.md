# 開場動畫（短設計）

Owner decisions, 2026-11-21:
- 「一秒半會不會太短了？起碼要三秒吧。」
- 「右上角有略過或者是手點一下就可以了吧。」
- 「時間拉長一點，我覺得比較有感覺。」

## Intent

Right now the opening screen is still. It appears only on the first launch, so most people never see it. The owner wants a game-like opening: about three seconds long, played on every cold launch, and skippable in one tap.

## Approaches

1. **Animate the existing first-launch splash only.** The cheapest option, but almost nobody sees it twice. Rejected by the owner, who wants it felt.
2. **One opening, played on every cold launch.** First launch: the animation plays, then holds on 「→ 輕點開始 ←」 and onboarding follows as today. Later launches: the same animation plays, then goes on to the lobby by itself. **Chosen.**
3. **A separate short logo sting on later launches plus the full splash on the first.** Two animations to keep in step across four 外觀主題; no gain over 2 at three seconds with 略過.

## Design

### Timeline

The timeline runs about 3.0 s, using the skin's `SkinMotion` easing.

| Time | What happens |
|---|---|
| 0.0–0.6 s | The gold stage ring springs open from 0.6 scale. |
| 0.4–1.0 s | The 3D 「$」 drops in from above and lands with a small squash. A light haptic plays on landing (`Feedback`). |
| 0.9–1.6 s | The skin's rays (`SkinDecor(page: .splash)`) sweep out from the centre, rotating and scaling from 0. |
| 1.4–2.2 s | 「ETF 袋著走」 rises and fades in. The 外觀主題 tag (`SkinTag`) pops. |
| 2.0–2.6 s | 「存 ETF，也存下好習慣。」 fades in. |
| 2.6–3.0 s | Hold. |

Remove the 「SKN×001」 line from this screen; the tag already names the 外觀主題.

### Per-skin character

The choreography is the same in every skin; only the character changes:
- voxel steps in pixel steps (stepped timing, as in the lobby);
- sketch reveals the rays like strokes being drawn;
- stitch and blackgold use their springs.

### After the animation

- **First launch:** 「→ 輕點開始 ←」 fades in, and its arrows breathe toward the centre (ambient, so it is off in Low Power Mode). A tap continues to onboarding, as today.
- **Later cold launches:** after 3.0 s the opening fades into the lobby on its own.
- Coming back from the background never replays the opening; only a cold launch does.

### Skipping

- A 「略過」 button sits at the top right, inside the safe area, at least 44 pt, with accessibility identifier `opening-skip`.
- A tap anywhere also skips.
- On the first launch, skipping jumps to the final frame, with 輕點開始 showing.
- On later launches, skipping goes straight to the lobby.

### Accessibility and power

- **Reduce Motion:** no movement, scale or rays sweep; elements fade in over about 0.8 s. Later launches continue after 1.2 s.
- **`--ui-testing`:**
  - Later launches skip the opening entirely, so every existing UI test and screenshot is unchanged.
  - `--open splash` shows the final frame at once, as now (identifier `splash` stays).
  - `--opening` forces the animated opening even under `--ui-testing`, for one new UI test.
- **VoiceOver:** the opening reads 「ETF 袋著走」 and offers 略過. Decorative parts are `accessibilityHidden(true)`.
- **Launch from a notification:** a cold launch that came from tapping a notification skips the opening.

### Constraints

- No new packages.
- No new art: reuse `SkinStage`, `SkinImage(.heroDollar)`, `SkinDecor`, `SkinTag` and the `Motion.swift` kit.
- Copy is Traditional Chinese.
- The screen keeps the name 「ETF 袋著走」 (owner decision).

## Left to the builder

- Exact spring values within each step.
- How the opening sits in `LaunchGate`: an overlay above `RootView`, or a state before it.
- How the notification launch is detected: for example, a flag set in `NotificationRouter`/`didReceive` before the first frame, or `launchOptions`. If neither is reliable, record a ruling.

## Tests

- **Unit:** the opening's phase-at-time function returns the right steps at 0, 0.5, 1.2, 2.0 and 3.0 s. Under Reduce Motion it returns the final state at once.
- **Unit:** the decision whether the opening shows, from these inputs:
  - first launch or not
  - `--ui-testing` with or without `--opening`
  - launched from a notification
- **UI test `testOpeningSkips`:** launch onboarded with `--opening`. `opening-skip` exists. Tap it, and `lobby-find` is hittable within 2 s.
- **CI screenshot:** `screen-splash.png` still shows the final frame.
