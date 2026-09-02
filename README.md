# GameForge

A native iOS game foundation: Swift 6 + SwiftUI + SpriteKit, built to be
extended by coding agents. The actual game concept is not chosen yet —
this repository provides everything around the game so that adding one is
a pure game-design exercise.

**Read [`AGENTS.md`](AGENTS.md) before working in this repository.**

## What is in place

- SwiftUI app shell (`Sources/App`), menu / gameplay / game-over flow
- A playable SpriteKit demo scene (`Sources/Game/DemoScene.swift`) proving
  physics, touch input, scoring and SwiftUI bridging work end to end
- `GameCore` — a pure-Swift, UI-free game-logic package with unit tests
- xcodegen project generation (the `.xcodeproj` is never committed)
- GitHub Actions CI (lint + tests + build on every push)
- Codemagic pipeline that signs, uploads to TestFlight and delivers to a
  physical iPhone without any local Xcode
- App Store Connect registration automated via `scripts/asc-api.py`

## Status

Foundation complete. Game concept: to be decided.
