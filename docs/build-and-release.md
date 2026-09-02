# Build & release runbook

## Where things build

| Stage | Where | Trigger |
|---|---|---|
| Lint, GameCore tests, app build + smoke tests | GitHub Actions (`macos-26`) | every push / PR |
| Signed IPA → TestFlight | Codemagic (`mac_mini_m2`, Xcode 26.6) | manual API trigger |

No Xcode is needed on the local Mac. All Swift verification runs in CI.

## Verifying a change (agent loop)

1. Commit to a branch, push to GitHub.
2. `gh run watch` — wait for `lint`, `gamecore-tests`, `app-build-test`.
3. Merge to `main` when green.

## Shipping to the phone

1. Trigger the Codemagic workflow:

```bash
set -a; source ~/chameleon-ios/.env.local; set +a
curl -s -X POST -H "Content-Type: application/json" -H "x-auth-token: $CODEMAGIC_API_TOKEN" \
  -d '{"appId": "<APP_ID>", "workflowId": "gameforge-testflight", "branch": "main"}' \
  https://api.codemagic.io/builds
```

`<APP_ID>` is the Codemagic application ID (list with
`GET https://api.codemagic.io/apps`). Poll
`GET https://api.codemagic.io/builds/<BUILD_ID>` for status; the status
field moves `queued → building → finished` (`status: true` = success).

2. The finished build is uploaded to TestFlight automatically
   (`submit_to_testflight: true`).
3. The owner installs from TestFlight on their iPhone. Processing in
   TestFlight can take 5–30 minutes after upload.

## Credentials (deliberately outside this repository)

- `~/chameleon-ios/.env.local` — `CODEMAGIC_API_TOKEN`,
  `APP_STORE_CONNECT_ISSUER_ID`
- `~/Desktop/vigtigt/AuthKey_2VNDM98D75 - ...p8` — App Store Connect API
  key (key ID `2VNDM98D75`)

Never commit or print these. The Codemagic App Store Connect integration
(reused from the Vildsvar project, same Apple account) holds the signing
certificate; `xcode-project use-profiles` fetches/generates profiles for
`dev.adrez.gameforge` automatically.

## App Store Connect entities

- App ID: `dev.adrez.gameforge` (explicit, registered via ASC API,
  bundle-ID ID `K4G2H6JYJJ`)
- Distribution profile: `gameforge-appstore` (created via ASC API, linked
  to the Apple Distribution cert valid until 2027-09-01)
- App record: **NOT created yet** — the ASC API key cannot create app
  records (`CREATE` is not allowed for its role). One-time manual step by
  the account holder, see "One-time manual setup" below.
- Internal TestFlight group: "App Store Connect Users" (created
  automatically with the app record)

## One-time manual setup (account holder, ~5 minutes)

1. Open [App Store Connect](https://appstoreconnect.apple.com) → My Apps → `+` New App:
   - Name: `GameForge` (placeholder; if taken, any unique working name)
   - Primary language: English (U.S.) (or Danish)
   - Bundle ID: `dev.adrez.gameforge`
   - SKU: `GAMEFORGE-IOS-001`
2. Trigger a Codemagic build (see "Shipping to the phone"); it now
   uploads to TestFlight automatically.
3. On the iPhone: open TestFlight → the build appears under the account
   holder's Apple ID automatically (internal tester via the default
   "App Store Connect Users" group).


## Versioning

- `MARKETING_VERSION` lives in `project.yml` (currently `0.1.0`).
- `CURRENT_PROJECT_VERSION` (build number) comes from Codemagic's
  `$BUILD_NUMBER` at archive time; no manual bump needed.

## Renaming the game

See the checklist in `AGENTS.md`.
