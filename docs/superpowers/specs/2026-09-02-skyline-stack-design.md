# Skyline Stack — Game Design Spec

**Date:** 2026-09-02
**Status:** Approved by owner (concept, monetization, art direction)
**Codename:** Skyline Stack (repo codename GameForge until rename)

---

## 1. Pitch

A premium 3D physics tower-builder for iOS. You stack city districts upward on a
tower that genuinely sways, flexes and groans under real physics. Collapse loses
a district — never the run. Your skyline persists between sessions and becomes a
living record of every risk you took. Free to play, no forced ads, monetized
through fair optional purchases.

**Positioning:** "Tower Bloxx's fantasy with Tricky Towers' real physics, in
Monument Valley's clothes, with a fair F2P model."

## 2. Core Loop

```
Place district block (grid-snap + magnetism)
  → physics settles (does it hold?)
  → citizens move in, windows light up
  → earn rent (Coins) + stability score
  → wind gusts test the tower
  → height milestone? celebrate
  → repeat until collapse or player stops
```

- **Session shape:** 3–7 minute core runs. The persistent skyline provides
  long-term continuity between sessions.
- **One skyline = one run**, but districts persist into the city meta
  (see §5).

## 3. Mechanics & Rules

### 3.1 Placement
- **Grid-snap with magnetism.** Districts snap to a coarse grid on the current
  tower top. Snap is input-only; simulation is honest rigid-body physics.
- **Sweet zone:** drop within ±15% of perfect alignment = "perfect placement"
  bonus (extra Coins, combo streak like Stack). Slightly off = legal but adds
  lean. Way off = the physics punishes you.
- Input: drag horizontally to position the swinging/hovering district, release
  to drop. One finger. (Tower Bloxx drop-lane convention.)

### 3.2 Physics
- Real rigid-body simulation (SceneKit physics in the app; the *rules and
  scoring* live in GameCore).
- **District curing:** settled lower districts freeze (sleeping bodies) after
  N seconds of stability — solves the >30-body jitter problem and caps CPU.
  Cured districts re-awaken only if impact force exceeds a threshold.
- **Telegraphs, never surprises:** lean meter (HUD), creaking audio, slow
  drift before collapse. Players must always see failure coming.
- **Cascade cap:** one collapse event removes at most ONE district. Never a
  full-cascade loss.
- **Grace period:** after a revive, 5–10 s of stabilized physics so the retry
  isn't doomed.

### 3.3 Failure & Revive
- Collapse → the top district is destroyed (dramatic slow-mo, auto-captured
  for sharing).
- **Revive offer (the monetization moment):** "Stabilize & Continue — watch
  an ad" → physics freezes 10 s + the collapsed district is repaired.
  Decline → lose the district, run continues free. Both options are viable;
  the offer fires at the moment of near-loss (highest conversion point).
- Run ends only when the player quits or the foundation is destroyed
  (foundation destruction requires 3 consecutive unrepaired collapses).

### 3.3b Economy (v1 numbers, tunable via remote config)
- Rent: 1 Coin per citizen housed per milestone; perfect placement = +5,
  combo streak multiplier ×1.5 max.
- Coins buy helpers: Stabilizer (freeze 10 s), Wind Barrier (next 3 gusts
  negated), Foundation Reinforce (cure threshold up), Extra Revive.
- Premium currency (also called Coins for v1 simplicity — one currency,
  earned slowly, buyable) — see §6.

### 3.4 Controls & Camera
- One-finger drag = position district; release = drop.
- One-finger drag on background = orbit camera (pitch capped ~60°).
- Two-finger pinch = zoom; two-finger drag = pan.
- Follow-cam keeps tower top centered; tower shrinks in frame as it grows
  (zoom-out = progress visual).

## 4. Art Direction — Monument Minimalism

- **Look:** sandstone & terracotta geometry, soft global illumination, long
  soft shadows, tiny glowing windows. Few shapes, perfect light. Monument
  Valley school.
- **Lighting tells the story:** day = building phase; golden hour = milestone
  reached; night = the city lights up room by room (the chill payoff moment).
- **Materials:** max 3 materials per district. Generous negative space.
- **Post:** subtle bloom, color grading, vignette (SceneKit-supported).
- **Animation:** ease-in-out everything; squash & stretch on placement; dust
  puff; slow-mo collapse at high frame-rate.
- **UI:** one elegant display font, hairline dividers, minimal HUD, big touch
  targets (≥44 pt), the tower is the screen.
- **Renderer:** SceneKit with baked-style lighting; no expensive real-time
  shadows on older devices; 30 FPS target for battery (60 when placing).

## 5. Progression & Retention

1. **Persistent skyline meta** — districts persist between sessions; the
   tower is a collection object, not a score. (Tower Bloxx's key lesson.)
2. **Unlock ladder** — XP/levels unlock district *variety* (new district
   types, materials, themes). Never gate core mechanics.
3. **Daily seeded challenge** — fixed seed from the date (offline-capable via
   `SeededGenerator`), Game Center leaderboard.
4. **Height milestones** — "passed the clouds", "entered space" — escalating
   visual celebrations.
5. **Shareable moments** — auto-captured slow-mo collapse, one-tap share
   sheet (Poly Bridge's viral mechanic).
6. **Daily bonus** — first run of the day grants bonus Coins.

## 6. Monetization

| Stream | Price | Notes |
|---|---|---|
| Revive-ad ("Stabilize & Continue") | free, optional | Rewarded-only; never forced |
| Rewarded helper earn | free, optional | Watch ad → 1 Stabilizer (cap 3/day) |
| Remove Ads | $3.99 one-time | No revive ads + 1 free stabilize/run + engineer district skin |
| District packs | $1.99 (5–8 districts) | Themed: Medieval Quarter, Sci-Fi Spire, etc. |
| Location packs | $2.99 | Canyon city, floating isles (new base environments) |
| Coins (premium currency) | $0.99 / $2.99 / $4.99 tiers | Buys helpers + cosmetics; earnable in-game |
| Cosmetics | via Coins | Architectural styles: Tokyo neon, art-deco, futurism |

**Hard rules:** no forced interstitials, no paywalled progress, no selling
power that breaks the game (helpers ease runs, never gate them), revive is
always the player's choice.

## 7. Architecture

Follows the repo's golden rule — logic in GameCore, rendering in the app:

- **`Packages/GameCore`** (pure Swift, Sendable, Swift Testing):
  - `TowerState` — districts, placement grid, stability scoring
  - `PlacementRules` — snap grid, sweet-zone math, combo logic
  - `Economy` — Coins, rent, helper inventory, prices
  - `WindSystem` — gust scheduling, telegraph generation
  - `CollapseRules` — cascade cap, cure thresholds, revive state machine
  - `DailyChallenge` — date-seeded challenge definitions
  - Persistence models (skyline meta, unlocks, purchases mirror)
- **`Sources/Game`** (SceneKit): tower scene, physics bridge, camera rig,
  effects (placement juice, collapse slow-mo), lighting rig per time-of-day.
- **`Sources/UI`** (SwiftUI): menu, HUD (lean meter, Coins), shop, district
  picker, settings, revive offer overlay.
- **`Sources/App`**: root navigation, StoreKit 2 purchase flow, ad SDK wrapper
  (rewarded only), Game Center sign-in.

### 7.1 Backend — Cloudflare (thin, optional at runtime)

The game is **fully playable offline**. Cloudflare adds convenience, not
dependency:

| Component | Service | Purpose |
|---|---|---|
| Remote config | Worker + KV | Economy tuning, feature flags — no app update needed |
| Content pack delivery | R2 | District/location packs download at runtime |
| Telemetry | Worker → D1 | Funnel events, crash-free stats (privacy-label-safe, no PII) |
| (Future) global services | Worker + D1 | Cross-device sync, custom leaderboards if Game Center ever insufficient |

- Worker endpoints are read-only for clients except anonymous telemetry.
- No accounts, no PII, no user data stored in v1. App Store privacy label:
  "Data not collected" (or minimal usage data if telemetry ships).

## 8. v1 Scope

**In:**
- Core loop with grid-snap placement, real physics, curing, telegraphs
- One world, 5–8 district types, one visual theme (Monument Minimalism)
- Collapse → 1-district loss + Stabilize & Continue revive
- Monetization: rewarded revive, rewarded helper earn, Remove Ads $3.99,
  one district pack $1.99, Coins tiers
- Persistent skyline meta, daily seeded challenge (Game Center leaderboard),
  ~10 cosmetic district skins (2 free via rewarded ad)
- Height milestones, share sheet for collapse clips
- Cloudflare Worker: remote config + telemetry; R2 pack delivery

**Out (v2+):**
- Versus/async multiplayer (Tricky Towers-style — big opportunity, needs
  netcode investment)
- Weather/wind modifiers as world variants, multiple worlds/themes
- Seasonal events, level editor, web share infrastructure

## 9. Testing Strategy

- GameCore: Swift Testing (`@Test`) — placement rules, scoring, collapse state
  machine, economy math, daily seed determinism. Sendable-clean under Swift 6.
- App: XCTest smoke tests (scene loads, UI navigation) in CI.
- Physics feel: manual pass on device via TestFlight
  (`./scripts/trigger-testflight.sh`), tuned via remote config where possible.

## 10. Success Criteria

- Core placement loop feels good on device (the "one more block" test)
- Crash-free sessions > 99.5%; no thermal issues in 20-min sessions
- Store page converts: screenshots show the premium look + physics drama
- D1 retention ≥ 35% for a builder genre (daily challenge + skyline meta)