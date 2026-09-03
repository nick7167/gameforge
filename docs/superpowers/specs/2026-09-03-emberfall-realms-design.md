# Emberfall Realms — Game Design Spec

**Date:** 2026-09-03
**Status:** Draft — awaiting owner review
**Codename:** Emberfall Realms (repo codename GameForge until rename)
**Supersedes:** `2026-09-02-skyline-stack-design.md` (Skyline Stack gameplay will be deleted; see §14)

---

## 1. Pitch

A premium 3D idle RPG for iPhone. Your squad of five stylized heroes auto-battles
through the twilight realm of Emberfall — you decide **when** to unleash each hero's
Ultimate. Loot, gold, and XP keep flowing while you're away. Collect 20 heroes,
roll the gacha, forge gear, push endless chapters, and climb a real global
leaderboard backed by your own backend.

**Positioning:** "AFK Arena's progression depth + Infinite Magicraid's modern 3D
presentation + Idle Heroes' juicy gold UI — rebuilt for one-thumb portrait play,
with a real backend and fair monetization."

**Name:** *Emberfall Realms* (research: `docs/name-research.md` — fully clean across
App Store/Play/Steam/web/trademarks/domains; final USPTO attorney clearance before launch).

## 2. Platform & Orientation

- **iPhone only, iOS 17+, portrait orientation** (one-thumb play anywhere)
- English only at launch (no localization scaffolding)
- Swift 6 strict concurrency; Swift Testing for GameCore; XCTest smoke tests for app

## 3. Core Loop

```
3D World Hub (home)
  → tap Portal → battle stage (auto-fight, ~30s; boss ~90s)
  → tap glowing ult portraits to fire Ultimates (the active skill)
  → victory → loot burst (gold, gear, shards, XP)
  → upgrade heroes / gear / summon new heroes
  → advance stage (chapter boss every 10th; new biome every chapter)
  → close app → idle income accrues (flat best-stage rate, 12h cap)
  → return → claim idle chest → push deeper
```

- **Session shape:** 1–3 min active sessions; idle income between sessions.
- **Loss rule (wall):** lose → stay at stage, keep all loot, upgrade, retry.
  After 3 consecutive losses, show a "power up" hint (suggest which hero/gear to upgrade).

## 4. Battle System

### 4.1 Presentation
- **Side-on 3D stage** (SceneKit): heroes left, enemies right, staggered depth
- Fixed cinematic camera with subtle drift; camera shake + flash on ults
- **Glowing stage circles under every unit** (faction color, pulse on action)
- Skeletal-rigged characters (free CC0 packs now via `HeroModelProvider`, custom art later)
- Procedural juice layered on rigs: hit-flash, knockback, squash on hit, death sink+fade
- Floating damage numbers (crit = big gold, ult = huge), heal = green
- Bloom post-processing, warm key light + faction rim lights, ember particles, light shafts
- Biomes change per chapter: dusk forest → midnight marsh → ember depths → starlit peaks

### 4.2 Rules
- **5-hero squad** vs 1–5 enemies (boss stages: 1 big boss + adds)
- Auto-battle: heroes auto-attack on individual timers; ults charge from dealing/taking damage
- **Ultimates:** player taps a ready portrait → screen flash, hero name banner,
  particle burst, big damage. **AUTO-ult unlocks at chapter 5** (toggle)
- **Speed:** 1×/2×/4× (4× = Monthly Card perk)
- **Battle length:** normal ~30s, boss ~90s with 2 phases (enrage at 50% HP)
- **Faction identities:** Ember = burst damage, Frost = control/sustain,
  Verdant = healing/shields, Void = crit/poise. Synergy-only (no elemental counters):
  2 same-faction = +8% ATK, 4 = +20% ATK + faction bonus effect
- **Roles (7):** Tank, DPS, Healer, Support, Ranger, Controller, Assassin
- **Skills:** 1 Ultimate + 2 passives per hero; Legendaries get a unique mechanic

### 4.3 Boss design
- Chapter boss (stage X-10): 1.5× scale, 2 phases, enrage timer (90s soft enrage:
  damage ramps), dramatic red rim light, boss HP bar at top of screen

## 5. Campaign Structure

```
Chapter 1 (biome: Duskwood Vale)
  Stage 1-1 … 1-9, 1-10 (chapter boss)
Chapter 2 (biome: Ashen Marsh)
  Stage 2-1 … 2-10 (chapter boss)
… forever (procedural difficulty curve; hand-made chapters added in updates)
```

- Display format "3-7"; boss stages flagged with a skull icon
- Each chapter: new biome (scenery/palette/music), +difficulty step
- **Highest chapter-stage (e.g. 12-4) is the leaderboard metric**
- Light chapter flavor: chapter name + one-line lore card on chapter start

## 6. Heroes & Gacha

### 6.1 Roster
- **20 heroes at launch**, 4 factions (5 per faction), 7 roles distributed
- Rarities: Common (gray) → Rare (blue) → Epic (purple) → Legendary (gold)
- Distribution: 4 Legendary, 6 Epic, 6 Rare, 4 Common
- Every hero: portrait card (rarity frame, stars, level badge, faction icon),
  full-body 3D model, 1 ult + 2 passives, lore line

### 6.2 Summoning (gacha)
- Currency: **Summon Shards** (premium-adjacent; earned + bought)
- **Permanent pool** + **weekly featured banner** (one Legendary rate-up, rotates Mondays)
- Rates: Legendary 2%, Epic 10%, Rare 30%, Common 58% (featured banner: Legendary 4%,
  50% of Legendaries are the featured hero)
- **Pity:** guaranteed Epic within 10 pulls, Legendary within 60 (visible pity meter)
- **1× and 10× pulls** (10× discounted ~10%, guaranteed Rare+)
- **Daily free single summon** (resets daily)
- **Duplicates** → faction shards → ascend/star-up heroes (dupe loop)
- **Summon ritual reveal:** portal opens → light beam → silhouette → card flip with
  rarity fireworks (gold = Legendary celebration)
- "Rates ⓘ" disclosure screen (App Store requirement)

### 6.3 Hero progression
- **Level** (gold + XP potions), cap by account level
- **Ascend/star-up** (faction shards from dupes): ★1–★6, stars multiply base stats
- **Skill upgrades** (skill tomes from quests/market)

## 7. Equipment

- **4 slots per hero:** Weapon, Armor, Trinket, Relic
- Gear rarity tiers mirror heroes; **main stat + 0–2 random sub-stats by rarity**
- **Enhancement:** gold levels gear (+every 5 levels bonus); never destroys gear (forgiving)
- **Rerolls:** gems reroll sub-stats (endgame min-max sink)
- **Sets:** 2-piece and 4-piece bonuses (e.g., 4× Emberfang = +25% crit damage)
- Gear drops from battles; **Inventory screen** with filter by rarity/slot/hero,
  equip-compare view, mass-enhance
- Equipment screen follows IMR pattern: roster left, gear grid + stat panel right
  (portrait-adapted: stacked vertically)

## 8. Economy

| Currency | Source | Sink |
|---|---|---|
| **Gold** | battles, idle, quests | hero levels, gear enhance, market |
| **Gems/Shards** (premium) | IAP, quests, achievements, ads | summons, rerolls, idle cap, market |
| **Arena tokens** | Arena (v1.5) | exclusive heroes/gear (v1.5) |
| **Quest tokens** | dailies/weeklies | market items, materials |

- **No energy system** — campaign is ungated (friendliest idle pattern)
- **Offline income:** flat rate based on best stage, 12h cap (24h with Monthly Card
  perk or one-time IAP)
- **Fast rewards:** claim 2h of idle instantly, 3× daily free (more via ads)

## 9. Quests & Retention

- **Dailies** (5 quests: fight 5 battles, summon 1×, enhance 2×, claim idle, spend gold)
  → quest tokens + gems
- **Weekly achievements** (bigger objectives) → gems
- **Achievement cards** (story-flavored, permanent) → gems
- **7-day new-player login calendar** (day 7 = free Epic hero)
- **Monthly login calendar** (all players)
- **Milestone celebrations:** first Legendary, first 5★, chapter clears, rank-ups
- **Notifications (local):** idle chest full, daily reset
- **Mail/Inbox:** server-sent rewards, compensation, announcements (backend-coupled)

## 10. Navigation & Screens

**Portrait, 5-tab bottom bar:** Hub · Heroes · Summon · Market · More

| Screen | Content |
|---|---|
| **Hub (home)** | 3D world hub: buildings ARE buttons — Tavern=Summon, Forge=Equipment/Inventory, Portal=Campaign, Arena Gate (v1.5 locked), Tower (v1.5 locked), Guild Hall (v2 locked), Merchant stand=Premium Shop. Heroes idle-walk. Idle chest floats. Event banner carousel on top |
| **Heroes** | Roster grid (sort by power/rarity/faction) → Hero Detail (full-body 3D hero in diorama, stat block w/ green deltas, skills, Ascend/Emblem buttons) + Team editor (5 slots) |
| **Summon** | Banner carousel, pity meter, 1×/10×, daily free, ritual reveal, rates ⓘ |
| **Market** | 4 tabs: Gold / Gems / Arena (v1.5) / Quest tokens. Daily rotating stock + free items + refresh timer |
| **More** | Leaderboard, Quests, Mail, Profile, Settings, Game Center link |
| **Premium Shop** | Real-money IAP storefront (gem icon in top bar + merchant stand in Hub): gem packs, Growth Bundle, Monthly Card, Remove Ads, rotating featured offers |
| **Battle** | Minimal HUD: ult portraits bottom-center, speed+auto bottom-left, stage/wave top corners, boss bar top |
| **Victory/Defeat** | Loot burst, stage progress, NEXT |
| **Leaderboard** | Custom ornate board (NOT Game Center popups): Top 100 global + rival bracket (50 around your rank) + your pinned row + season countdown |
| **Profile** | Avatar, name, level, squad showcase (5 heroes w/ gear), stats, rank |
| **Quests** | Daily / Weekly / Achievements tabs, claim-all |
| **Mail** | Server rewards, expiry timers |
| **Inventory** | Gear bag, filters, compare, reroll, mass-enhance |
| **Settings** | Sound, graphics, notifications, Sign in with Apple, restore purchases, support, delete account (Apple requirement) |

**Popups:** victory/defeat, idle chest, summon reveal, login calendars, milestone
celebrations, IAP prompts.

## 11. Backend (Cloudflare)

- **Stack:** Cloudflare Workers + D1 (SQLite) + KV. Free tier at launch scale.
- **Model: server-authoritative.** Progress lives on the server; game is offline-playable
  with queued sync (client simulates, server validates plausibility on reconnect)
- **Accounts:** silent anonymous account on first launch (device token);
  prompt Sign in with Apple after ~10 min of play or before big purchases;
  account linking merges progress
- **v1 endpoints:** auth (guest/Apple), profile (name, avatar, level, squad showcase),
  save sync (validated), leaderboard (global top 100 + rival bracket of 50 around your rank),
  mail, remote config (gacha rates, shop prices, banner lineup)
- **Anti-cheat:** plausibility checks (max stage per playtime, sane currency deltas,
  server clamps) — no full replay validation in v1
- **Guild-ready schema from day one** (guild tables exist, unused in v1)
- **v1.5:** weekly season boards (cron reset), Arena snapshots
- **v2:** guilds, guild bosses, events/banners (server remote config drives them)

## 12. Monetization

### Premium Shop (real money)
| Item | Price | Notes |
|---|---|---|
| Gem packs | $0.99–$99 | 6 tiers |
| **Growth Bundle** | $4.99 one-time | hero + shards + gear; highest-converting offer |
| **Monthly Card** | $4.99/mo | daily gem drip 30 days + 4× speed + 24h idle cap |
| Remove Ads | $3.99 one-time | rewarded ads only, never forced |
| Featured offers | varies | rotating starter/level-up bundles |

### Rewarded ads (all optional)
- **Daily free 5-pull** (once per day, watch to claim)
- Offline chest ×2
- Instant 2h idle claim

### Market (in-game currency)
- Gold tab: gear boxes, materials, XP potions
- Gem tab: summons, rerolls, idle cap extensions, cosmetic frames
- Arena tab (v1.5): exclusive heroes/gear
- Quest tab: materials, shards, cosmetics
- Daily rotating stock + free items + refresh timer

## 13. Art Direction (art bible: `docs/art-reference/`, 29 refs)

- **DNA:** dark rich backgrounds + high-contrast glow; gold-trimmed ornate frames;
  rarity color language (gray/green/blue/purple/gold) on ALL frames; particles and
  light rays in every screen; big outlined damage numbers; glowing stage circles;
  chunky beveled buttons with gradients + inner light
- **Schools:** IMR painterly 3D stage + Idle Heroes juicy gold UI + AFK Arena dramatic glow
- **World:** the Emberfall — a twilight spirit realm (sun never fully sets): glowing
  forests, floating isles, ember spirits. Biomes: Duskwood Vale → Ashen Marsh →
  Ember Depths → Starlit Peaks
- **Renderer:** SceneKit; warm key + faction rim lights; bloom; ACES tone mapping;
  30 FPS target (60 during ults)
- **Characters:** skeletal rigs (Quaternius/Kenney CC0 placeholders via
  `HeroModelProvider`; custom art later = drop-in swap)
- **UI:** gold-trimmed ornate panels (9-slice), rarity frames, one display font +
  clean sans, animated everything (press-scale, rolling counters, loot arcs)
- **Audio:** full music set (per biome + menu), full SFX set, hero voice lines
  (ult callouts), CC0/free assets first
- **Reference validated:** WebGL prototype (lighting rig/palette/UI system) approved
  by owner; SceneKit must match it shot-for-shot

## 14. Tech Architecture

### Keep from current repo
- xcodegen (`project.yml`), Codemagic TestFlight pipeline, signing, ASC scripts/keys,
  RevenueCat, AdMob, Game Center service, SwiftLint config, GameCore SPM package shell,
  `docs/art-reference/`, `docs/name-research.md`

### Delete (Skyline Stack gameplay — after this spec + plan are approved)
- GameCore: `District`, `Placement`, `TowerState`, `WindSystem`, `CollapseRules`,
  `SkylineMeta`, `DailyChallenge`, `SkylineSession` + their tests
- App: `TowerScene`, `TowerSceneView`, tower UI screens (`GameHUD`, `ReviveOffer`,
  `GameOverScreen`, `ShopScreen`, `StartScreen`, `GameplayView`), `SkylineGameModel`
- Old spec/plan docs (archived to `docs/superpowers/archive/`)

### New structure
```
Packages/GameCore/Sources/GameCore/
  HeroCatalog.swift        // 20 hero definitions, factions, roles, stats
  GachaEngine.swift        // seeded RNG, pity, banners, dupes→shards
  BattleEngine.swift       // tick-based auto-combat sim (no UI), ults, crits, phases
  EquipmentSystem.swift    // gear gen, sub-stats, sets, enhance, reroll
  IdleIncome.swift         // offline math, caps, fast rewards
  StageProgression.swift   // chapters, difficulty curve, biome mapping
  QuestSystem.swift        // dailies, weeklies, achievements
  PlayerProfile.swift      // roster, currencies, squad, persistence models
  EmberSession.swift       // facade (Sendable)
Sources/Game/
  BattleScene.swift        // SceneKit stage, units, VFX
  HubScene.swift           // 3D world hub
  HeroModelProvider.swift  // CC0 pack loading (swap point for custom art)
Sources/UI/                 // SwiftUI: Hub, Heroes, Summon, Market, Shop, More,
                            // Battle HUD, Leaderboard, Profile, Quests, Mail, popups
Sources/App/                // GameModel facade, persistence, services (RC/AdMob/Firebase)
backend/                    // Cloudflare Workers (TS), D1 schema, KV config
```

### Services
- RevenueCat (IAP), AdMob (rewarded only), Firebase Analytics, Game Center
  (achievements only — leaderboard is our custom UI), Cloudflare backend

## 15. Phases

- **v1 (launch):** everything in this spec except Arena + Tower
- **v1.5:** Arena (async PvP vs snapshots), Tower climb, weekly season leaderboards
- **v2:** Guilds + guild bosses, events & rotating banners (server remote config),
  push notifications

## 16. Success Criteria

- 55+ GameCore tests green (battle sim, gacha pity, economy, progression)
- Battle feels like the WebGL prototype: glow circles, ult spectacle, damage numbers
- Hub looks like a "big studio" game: 3D world, heroes walking, ornate UI
- TestFlight build on the owner's iPhone via existing pipeline
- Leaderboard shows real players from the Cloudflare backend
