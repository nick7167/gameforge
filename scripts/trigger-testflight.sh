#!/usr/bin/env bash
# Trigger a signed GameForge build on Codemagic and stream its status.
#
# Credentials: .env/codemagic.env (CODEMAGIC_API_TOKEN) — see .env/README.md
#
# Usage: ./scripts/trigger-testflight.sh [branch]

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRANCH="${1:-main}"
APP_ID="6a983f614174f1fe53ef6630"
WORKFLOW="gameforge-testflight"

# shellcheck source=.env/codemagic.env
set -a
source "$REPO_DIR/.env/codemagic.env"
set +a

if [ -z "${CODEMAGIC_API_TOKEN:-}" ]; then
  echo "ERROR: CODEMAGIC_API_TOKEN is empty."
  echo "Paste your token into $REPO_DIR/.env/codemagic.env (see .env/README.md)."
  exit 1
fi

BUILD_ID=$(curl -s -X POST -H "Content-Type: application/json" -H "x-auth-token: $CODEMAGIC_API_TOKEN" \
  -d "{\"appId\": \"$APP_ID\", \"workflowId\": \"$WORKFLOW\", \"branch\": \"$BRANCH\"}" \
  https://api.codemagic.io/builds | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('buildId') or d)")

echo "Build queued: $BUILD_ID"
echo "Watch: https://codemagic.io/builds/$BUILD_ID"

while true; do
  sleep 30
  RESULT=$(curl -s -H "x-auth-token: $CODEMAGIC_API_TOKEN" "https://api.codemagic.io/builds/$BUILD_ID")
  STATUS=$(echo "$RESULT" | python3 -c "import json,sys; b=json.load(sys.stdin).get('build', {}); print(b.get('status') or 'building')")
  MESSAGE=$(echo "$RESULT" | python3 -c "import json,sys; b=json.load(sys.stdin).get('build', {}); print(b.get('message') or '')")
  echo "[$(date +%H:%M:%S)] $STATUS $MESSAGE"
  case "$STATUS" in
    finished)
      echo "BUILD SUCCEEDED — IPA uploaded to TestFlight (allow 5-30 min for processing)."
      exit 0
      ;;
    failed)
      echo "BUILD FAILED: $MESSAGE"
      exit 1
      ;;
  esac
done
