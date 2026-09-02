# AGENTS.md — Operating manual for coding agents

Last verified: 2026-09-02. Keep this file accurate; it is the contract for
every future agent working here.

## CURRENT STATUS — where we are (2026-09-02)

The foundation phase is **complete**. Everything below is proven working:

- **TestFlight delivery works.** Build 19 is on TestFlight (app record
  "AdrezGame", ASC app ID `6807883902`) and the owner can install it.
  Shipping is one command: `./scripts/trigger-testflight.sh` (streams status).
  Export compliance is declared in `project.yml`
  (`ITSAppUsesNonExemptEncryption=NO`) so builds no longer get stuck in
  "Missing Compliance".
- **Signing is solved** via manual signing in `codemagic.yaml`
  (`gameforge-testflight` workflow): decrypts the committed encrypted cert
  (`signing/gameforge-dist.p12.enc`), matches it by SHA-1 fingerprint,
  renews the profile, archives, uploads. Password lives in the Codemagic env
  var group `gameforge-signing` (`GAMEFORGE_P12_ENC_PASSWORD`).
- **Local dev works** on this Linux container: `swift test` (GameCore),
  `swiftlint` both pass. App target builds only in CI/Codemagic (no Xcode
  here) — see Commands below.
- **Skills installed**: 56 agent skills in `.github/skills/` (mirrored in
  `.claude/skills/`) — `axiom-games` (SpriteKit), `mobile-games`, ASO suite,
  superpowers workflow skills.

### The next phase: actually design and build the game

The genre is still undecided — that is the immediate next step. Suggested
approach for a new session:

1. Brainstorm the game concept with the owner (genre, core loop, scope).
   Use the `brainstorming` skill before any creative work, `axiom-games` +
   `mobile-games` for SpriteKit/mobile specifics.
2. Write the game design decision down here and in `docs/architecture.md`.
3. Build gameplay in GameCore (pure logic + tests) first, then wire it into
   `Sources/Game` SpriteKit scenes, reusing the existing `Session` pattern.
4. Ship often with `./scripts/trigger-testflight.sh`.

**Read `docs/HANDOFF.md` if TestFlight builds are failing** — it documents
the whole signing saga in detail, though the pipeline currently works.

## What this project is

An iOS game, codename **GameForge**, native Swift from the ground up. The
game genre is **not decided yet**. This repository is the foundation: app
shell, rendering layer, logic package, tests, CI, and a cloud release
pipeline that delivers TestFlight builds to the owner's physical iPhone.

## The golden rule: logic in GameCore, rendering in the app

- **`Packages/GameCore`** — pure Swift game logic: rules, state machines,
  RNG, persistence models. No SwiftUI, SpriteKit, UIKit or Foundation UI.
  This is where gameplay belongs.
- **`Sources/Game`** — SpriteKit scenes and bridges. Scenes translate
  rendering into events; they never own gameplay rules.
- **`Sources/UI`** — SwiftUI screens (menu, HUD, overlays).
- **`Sources/App`** — app entry point and root navigation.

If a rule can be expressed without a screen, it belongs in GameCore.

## Agent skills

Installed skills live in **`.github/skills/`** (VS Code / GitHub Copilot
convention — each skill is a folder with a `SKILL.md`). A mirrored copy is
kept in `.claude/skills/` for Claude Code compatibility. Both are committed.

When adding/updating skills via skillfish, install into one folder and copy
to the other:

```bash
npx skillfish add <owner>/<repo> [skill] --project -y --force < /dev/null
cp -R .claude/skills/. .github/skills/   # or back
```

## Commands

Local machine (Linux dev container, Ubuntu 24.04, 4 cores / 15 GB RAM):

| Task | Command | Notes |
|---|---|---|
| Test GameCore locally | `swift test` (in `Packages/GameCore`) | Works — Swift 6.3.3 at `/opt/swift/usr/bin` |
| Lint locally | `swiftlint --config .swiftlint.yml` | SwiftLint 0.65.1 at `/usr/local/bin/swiftlint` |
| Typecheck Swift locally | `xcrun swiftc -typecheck -swift-version 6 <files>` | Not available — `xcrun` is macOS-only |

Swift toolchain setup on this container: toolchain extracted to
`/opt/swift` (add `/opt/swift/usr/bin` to PATH — done via `~/.bashrc.d/swift.sh`).
System deps for Swift on Ubuntu 24.04 were installed with apt (binutils,
libcurl4-openssl-dev, libedit2, libgcc-13-dev, libpython3-dev, libsqlite3-0,
libstdc++-13-dev, libxml2-dev, libncurses-dev, libz3-dev, tzdata, zlib1g-dev).
SwiftLint is the official `swiftlint_linux_amd64.zip` from realm/SwiftLint releases.

**Local limitation:** no Xcode/xcodebuild/xcodegen here. The app target
(SwiftUI/SpriteKit) cannot be compiled or smoke-tested locally — that
verification happens in CI and Codemagic only. There is also no `swift test`
need for `./scripts/fix-local-clt.sh` anymore (that script was for the old
Mac's broken Command Line Tools and kept for reference).

Remote (this is the real verification loop):

| Task | Command |
|---|---|
| Watch CI | `gh run watch` / `gh run list --repo nick7167/gameforge` |
| Run tests | `gh workflow run` is not needed; CI runs on every push and PR |

### CI layout (`.github/workflows/ci.yml`)

1. `lint` — SwiftLint on all Swift files
2. `gamecore-tests` — `swift test` in `Packages/GameCore`
3. `app-build-test` — xcodegen, unsigned `xcodebuild build`, smoke tests on
   a cloud simulator

All three must be green before merging to `main`.

## Conventions

- Swift 6, strict concurrency. `GameCore` is Sendable-clean.
- Swift Testing (`@Test`) for GameCore; XCTest for app smoke tests.
- No logic in views. No state outside `Session`/GameCore.
- 2-space Swift indent, 150-char lines (`.swiftlint.yml`).
- Commit style: short imperative subject (`Add level state machine`).
- Never commit: `.xcodeproj` (generated), secrets, `.p8` files, `.env*`.
  This is enforced by `.gitignore` — keep it that way.

## Release pipeline (TestFlight → phone)

`codemagic.yaml` defines workflow `gameforge-testflight`: generates the
project, runs GameCore tests, applies signing, builds a signed IPA and
uploads it to TestFlight. Trigger it after changes you want on the phone:

```bash
./scripts/trigger-testflight.sh            # build main, stream status
```

Codemagic application ID: `6a983f614174f1fe53ef6630` (repo
`nick7167/gameforge`). Raw trigger:

```bash
set -a; source .env/codemagic.env; set +a
curl -s -X POST -H "Content-Type: application/json" -H "x-auth-token: $CODEMAGIC_API_TOKEN" \
  -d '{"appId": "6a983f614174f1fe53ef6630", "workflowId": "gameforge-testflight", "branch": "main"}' \
  https://api.codemagic.io/builds
# watch: curl -s -H "x-auth-token: $CODEMAGIC_API_TOKEN" https://api.codemagic.io/builds/<BUILD_ID>
```

Note: signed builds require the App Store Connect **app record** to exist
(API keys cannot create app records). If it is missing, builds fail with
"No matching profiles found" — see docs/build-and-release.md for the
one-time manual setup.

### App Store Connect API (`scripts/asc-api.py`)

For bundle IDs, app records, TestFlight groups/build status:

```bash
set -a; source .env/asc.env; set +a
python3 scripts/asc-api.py GET "/v1/apps"
```

The `.p8` and tokens live outside this repository on purpose. Never copy
them in, never print their values.

## Renaming the game (when a real name is chosen)

1. `project.yml`: `name`, `PRODUCT_BUNDLE_IDENTIFIER` (new explicit ID,
   e.g. `dev.adrez.<name>`), `PRODUCT_NAME`, display name
2. `codemagic.yaml`: `bundle_identifier`, workflow names
3. Apple Developer portal: register the new App ID (ASC API can do this)
4. App Store Connect: new app record under the new name (ASC API can do
   this); old record can be deleted while in Prepare state
5. Update AGENTS.md, README.md, this repo's GitHub name if desired

## Architecture details

See `docs/architecture.md` for component boundaries and data flow, and
`docs/build-and-release.md` for the full release/runbook documentation.
