#!/bin/zsh
# Repairs the corrupted Command Line Tools installation on this Mac so that
# `swift build` / `swift test` work locally.
#
# Two known problems, both requiring sudo:
#   1. Duplicate SwiftBridging modulemap breaks Foundation importation.
#   2. libPackageDescription.dylib is missing core symbols (broken SPM manifests).
#
# Fix 1 is a one-line removal. Fix 2 requires reinstalling CLT; the removal
# below is enough for most local work, but a clean reinstall is recommended:
#   sudo rm -rf /Library/Developer/CommandLineTools
#   xcode-select --install        (or install via Software Update)
#
# Run with: ./scripts/fix-local-clt.sh

set -euo pipefail

CLT_SWIFT_INCLUDE="/Library/Developer/CommandLineTools/usr/include/swift"

if [[ -f "$CLT_SWIFT_INCLUDE/bridging.modulemap" && -f "$CLT_SWIFT_INCLUDE/module.modulemap" ]]; then
  echo "Removing duplicate SwiftBridging modulemap (requires sudo)..."
  sudo rm "$CLT_SWIFT_INCLUDE/bridging.modulemap"
  echo "Done. Local swift compilation should work again."
else
  echo "No duplicate modulemap found — CLT may already be fixed."
fi

echo ""
echo "For a fully clean toolchain (fixes swift test too), run:"
echo "  sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install"
