#!/bin/zsh
# Trigger a signed GameForge build on Codemagic and stream its status.
#
# Requires: ~/chameleon-ios/.env.local (CODEMAGIC_API_TOKEN)
#
# Usage: ./scripts/trigger-testflight.sh [branch]

set -euo pipefail

BRANCH="${1:-main}"
APP_ID="6a983f614174f1fe53ef6630"
WORKFLOW="gameforge-testflight"

set -a
source "$HOME/chameleon-ios/.env.local"
set +a

BUILD_ID=$(curl -s -X POST -H "Content-Type: application/json" -H "x-auth-token: $CODEMAGIC_API_TOKEN" \
  -d "{\"appId\": \"$APP_ID\", \"workflowId\": \"$WORKFLOW\", \"branch\": \"$BRANCH\"}" \
  https://api.codemagic.io/builds | python3 -c "import json,sys; print(json.load(sys.stdin)['buildId'])")

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
