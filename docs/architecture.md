# Architecture

## Layers

```
┌─────────────────────────────────────────────┐
│ Sources/App        SwiftUI app entry,       │
│                    RootView navigation      │
├─────────────────────────────────────────────┤
│ Sources/UI         SwiftUI screens          │
│                    (menu, HUD, overlays)    │
├─────────────────────────────────────────────┤
│ Sources/Game       SpriteKit scenes +       │
│                    view bridge              │
├─────────────────────────────────────────────┤
│ Packages/GameCore  Pure game logic          │
│                    (no UI dependencies)     │
└─────────────────────────────────────────────┘
```

Dependency direction is strictly downward: Game knows nothing about UI;
GameCore knows nothing about any layer above it.

## Data flow (demo game)

1. `RootView` owns a `Session` (GameCore value type).
2. Menu → `session.start()` → `GameView` presents `DemoScene`.
3. `DemoScene` translates rendering input (taps) into `DemoGameEvent`s.
4. `RootView` applies events to `Session` (`addScore`, `finish`).
5. Finished rounds persist best scores through `HighScoreStore`.

The scene never owns gameplay rules — it only reports events. This makes
every rule unit-testable in GameCore without a simulator.

## Extension points when the genre is chosen

- **Game rules / progression / economy** → new types in `Packages/GameCore`,
  each with Swift Testing unit tests.
- **World rendering** → new `SKScene` subclasses in `Sources/Game`. Keep
  them dumb: translate input to events, events to visual state.
- **Menus/HUD** → SwiftUI in `Sources/UI`.
- **Persistence** → implement `HighScoreStore` (or extend the pattern with
  a `SaveStore` protocol) backed by `UserDefaults` or files in the app
  layer; GameCore keeps models Codable so snapshots persist verbatim.
- **Determinism** → use `SeededGenerator` (SplitMix64) anywhere replayable
  or synchronized randomness is needed.

## Concurrency model

- Swift 6 language mode everywhere.
- `GameCore` types are value types, `Sendable`, actor-agnostic — usable
  from any executor.
- SpriteKit scenes are `@MainActor`; they are the only mutable visual
  state. Cross-layer communication is event callbacks invoked on the main
  actor.
