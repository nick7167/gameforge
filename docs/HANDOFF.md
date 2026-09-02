# HANDOFF — GameForge TestFlight signing (read this first)

Written: 2026-09-02. Situation at time of writing: **everything works except
the final signed build → TestFlight delivery.** This document transfers the
exact state, all debugging findings, and the proven next steps to the next
agent (and machine).

## Project snapshot

- Repo: `https://github.com/nick7167/gameforge` (public). Local clone:
  `/Users/nicklasandreasen/nyapp-intetnavn`.
- Native iOS app, Swift 6 strict concurrency, SwiftUI shell + SpriteKit demo
  scene, pure-logic `Packages/GameCore` with Swift Testing tests.
- xcodegen generates `GameForge.xcodeproj` from `project.yml` (never commit
  the xcodeproj).
- CI (GitHub Actions, `macos-26`): **fully green** — SwiftLint, GameCore
  `swift test`, unsigned app build + simulator smoke tests.
- Codemagic app exists: `6a983f614174f1fe53ef6630`, repo connected, workflows
  `gameforge-testflight` and `gameforge-debug-signing` defined in
  `codemagic.yaml`.
- App Store Connect: bundle ID `dev.adrez.gameforge` registered (bundle-ID
  resource ID `K4G2H6JYJJ`, seed/team `JDW2B73SS5`); app record **"AdrezGame"**
  exists (ASC app ID `6807883902`, SKU `GAMEFORGE-IOS-001`).
- A valid App Store provisioning profile `gameforge-appstore` (ACTIVE,
  expires 2027-09-01) exists and includes the Apple Distribution certificate
  `2L65FA23ZN` (valid until 2027-09-01).

## Credentials & IDs (never commit, never print values)

| Item | Where |
|---|---|
| `CODEMAGIC_API_TOKEN`, `APP_STORE_CONNECT_ISSUER_ID` | `~/chameleon-ios/.env.local` |
| ASC API key (key ID `2VNDM98D75`) `.p8` file | `~/Desktop/vigtigt/AuthKey_2VNDM98D75 - APP STORE CONNECT API VILDSVAR.p8` |
| Codemagic ASC integration name | `vildsvar-app-store-connect` (team-level; holds key + distribution cert for Vildsvar) |
| Codemagic app ID | `6a983f614174f1fe53ef6630` |
| ASC app record ID | `6807883902` ("AdrezGame") |
| Bundle ID resource ID | `K4G2H6JYJJ` (`dev.adrez.gameforge`) |
| Team ID | `JDW2B73SS5` |
| ASC API helper | `scripts/asc-api.py` (env: `ASC_KEY_ID`, `ASC_KEY_PATH`, `APP_STORE_CONNECT_ISSUER_ID`) |
| Build trigger | `scripts/trigger-testflight.sh` (streams status) |

## The blocker, precisely

`gameforge-testflight` fails **before any script runs** (build never reaches a
machine; `startedOn` is null) with:

```
No matching profiles found for bundle identifier "dev.adrez.gameforge" and distribution type "app_store"
```

Verified facts (all confirmed via debug builds, logs downloaded as artifacts):

1. The ASC key attached to the build (`integrations.app_store_connect:
   vildsvar-app-store-connect`) **works**: `app-store-connect
   certificates list` and `profiles list` on the build machine see the
   distribution cert and the `gameforge-appstore` profile (ACTIVE).
2. The profile is fetched live; deleting/recreating it did not change the
   pre-check result.
3. `xcode-project use-profiles` on the build machine (without
   `environment.ios_signing`) defaults to **ad-hoc** and, even with the
   project present, reports "Did not find matching provisioning profiles" and
   downloads nothing.
4. Root cause (best-supported explanation): Codemagic's signing pre-check and
   `use-profiles` require the **private key** of the signing certificate from
   Codemagic's per-app stored "Code signing identities". Those were created
   for the Vildsvar app through the Codemagic UI and are linked to that app;
   the gameforge app was added via API and has none. The public API cannot
   link them (`PATCH/PUT /apps/{id}` → 405), and the ASC API cannot create
   app records (`CREATE` not allowed for the key's role) — the app record was
   therefore created manually by the owner as "AdrezGame".

## Proven fix path (implement this next)

Manual signing entirely inside the workflow, no `environment.ios_signing`
block (that block triggers the failing pre-check). The Codemagic CLI on the
build machine can do everything; the last debug run pinned down the exact
invocations:

1. `certificates create` requires the private key to be supplied. Generate
   one on the build machine first:

   ```bash
   openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
     -out "$CM_BUILD_DIR/build/dist.key"
   app-store-connect certificates create \
     --type DISTRIBUTION \
     --certificate-key "$CM_BUILD_DIR/build/dist.key" \
     --p12-path "$CM_BUILD_DIR/build/gameforge-dist.p12" \
     --p12-password "$P12_PASSWORD" \
     --json
   ```

   Use type `DISTRIBUTION` ("Apple Distribution") — the earlier attempt with
   `IOS_DISTRIBUTION` was wrong; also note
   `certificates list --type IOS_DISTRIBUTION` returns an empty list for the
   same reason (the existing cert is type `DISTRIBUTION`).

2. Import the p12 into the login keychain:

   ```bash
   security import build/gameforge-dist.p12 \
     -k ~/Library/Keychains/login.keychain-db \
     -P "$P12_PASSWORD" -T /usr/bin/codesign
   security find-identity -v -p codesigning   # should list the new identity
   ```

3. Create the profile including the NEW cert (capture the new cert's ASC
   resource ID from the `certificates create --json` output):

   ```bash
   app-store-connect profiles create \
     --type IOS_APP_STORE \
     --certificate-ids <NEW_CERT_ID> K4G2H6JYJJ \
     --name "gameforge-build" --save
   ```

4. Archive and export with manual signing (xcodebuild, not build-ipa):

   ```bash
   xcodebuild archive \
     -project GameForge.xcodeproj -scheme GameForge \
     -configuration Release -destination 'generic/platform=iOS' \
     -archivePath build/GameForge.xcarchive \
     CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=JDW2B73SS5 \
     PROVISIONING_PROFILE_SPECIFIER=gameforge-build \
     CODE_SIGN_IDENTITY="Apple Distribution" \
     CURRENT_PROJECT_VERSION=$BUILD_NUMBER

   cat > build/exportOptions.plist <<'PLIST'
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0"><dict>
     <key>method</key><string>app-store</string>
     <key>teamID</key><string>JDW2B73SS5</string>
     <key>signingStyle</key><string>manual</string>
     <key>signingCertificate</key><string>Apple Distribution</string>
     <key>provisioningProfiles</key>
     <dict><key>dev.adrez.gameforge</key><string>gameforge-build</string></dict>
   </dict></plist>
   PLIST

   xcodebuild -exportArchive \
     -archivePath build/GameForge.xcarchive \
     -exportOptionsPlist build/exportOptions.plist \
     -exportPath build/ipa
   ```

5. Keep the existing `publishing.app_store_connect` block (auth: integration,
   `submit_to_testflight: true`) — publishing is independent of the signing
   pre-check and uploads `build/ipa/*.ipa` to TestFlight. Then the owner
   installs from TestFlight on the iPhone (AdrezGame → App Store Connect
   Users internal group, account holder is the tester).

### Cert-count caveat

Apple caps Apple Distribution certificates (3). The plan above creates a new
one per build. After the FIRST successful build, persist the p12 once —
simplest reliable option: add it (base64) to a Codemagic environment variable
group and have subsequent builds import it instead of creating a new cert (and
create only the profile per build). Alternatively implement the env-var-group
persistence from the start. Do not let the workflow create a cert
unconditionally on every run.

### Alternative fix (UI, ~2 minutes, zero code)

In Codemagic web UI, open the gameforge app → app settings → complete the
Apple Developer Portal / code signing selection (choose the
`vildsvar-app-store-connect` key integration and the existing Apple
Distribution certificate). This replicates how Vildsvar is configured. If you
do this, restore `environment.ios_signing` + `xcode-project use-profiles` in
`gameforge-testflight` and delete the manual-signing approach.

## Known quirks on the current local Mac

- Command Line Tools were deleted during a repair attempt and the reinstall
  was canceled → **`swift`/`git`/`xcrun` are broken locally**. Do not rely on
  local Swift compilation. To restore: run `xcode-select --install`
  (GUI) or `sudo rm -rf /Library/Developer/CommandLineTools` first if a
  partial install exists. Until then use `gh api` for all git operations.
- The local clone may be behind `origin/main` (remote commits were made via
  the GitHub Contents API while git was broken). After CLT repair:
  `git pull --rebase`.
- `brew`/`xcodegen` still work locally; CI and Codemagic verify all Swift.
- `swiftlint` is not installed locally (CI runs it).
- The debug workflow `gameforge-debug-signing` in `codemagic.yaml` can be
  deleted once the testflight workflow is green.

## Working verification loop for the next agent

1. Push to GitHub (gh api or git once repaired) — CI runs lint + tests +
   unsigned build on every push. Keep it green.
2. For signing iterations, edit `codemagic.yaml`, commit, then:

   ```bash
   set -a; source ~/chameleon-ios/.env.local; set +a
   curl -s -X POST -H "Content-Type: application/json" \
     -H "x-auth-token: $CODEMAGIC_API_TOKEN" \
     -d '{"appId": "6a983f614174f1fe53ef6630", "workflowId": "gameforge-debug-signing", "branch": "main"}' \
     https://api.codemagic.io/builds
   ```

3. Build status: `GET https://api.codemagic.io/builds/<BUILD_ID>` (header
   `x-auth-token: $CODEMAGIC_API_TOKEN`). Step logs:
   `GET /builds/<id>/step/<stepId>`; artifacts: `build.artefacts[].url`
   (zip, download with the same header).
4. When green on `gameforge-testflight`: `./scripts/trigger-testflight.sh`
   and wait for the owner to see the build in TestFlight on the iPhone.
