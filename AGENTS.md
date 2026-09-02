# AGENTS.md — Operating manual for coding agents

Last verified: 2026-09-02. Keep this file accurate; it is the contract for
every future agent working here.

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

## Commands

Local machine (Intel, 8 GB RAM, **no full Xcode** — CLT only):

| Task | Command | Notes |
|---|---|---|
| Generate Xcode project | `xcodegen generate` | Run after editing `project.yml` |
| Test GameCore locally | `swift test` (in `Packages/GameCore`) | Broken until CLT repaired — see below |
| Typecheck Swift locally | `xcrun swiftc -typecheck -swift-version 6 <files>` | Limited by CLT bugs below |

**Known local limitation:** this Mac's Command Line Tools installation is
corrupted (duplicate SwiftBridging modulemap + broken
libPackageDescription.dylib). `swift test` and Foundation imports fail
locally. Run `./scripts/fix-local-clt.sh` (requires sudo, ask the user)
to repair. Until then, **all Swift compile/test verification happens in CI
and Codemagic** — push to a branch and watch the run.

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
set -a; source ~/chameleon-ios/.env.local; set +a
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
set -a; source ~/chameleon-ios/.env.local; set +a
export ASC_KEY_ID=2VNDM98D75
export ASC_KEY_PATH="$HOME/Desktop/vigtigt/AuthKey_2VNDM98D75 - APP STORE CONNECT API VILDSVAR.p8"
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
