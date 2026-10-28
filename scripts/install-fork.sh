#!/usr/bin/env bash
# Builds our fork of Coucou and installs it in /Applications, signed with our own
# Apple Development certificate so macOS keeps its permissions from one build to
# the next.
#
# Release, optimized, but without PHONE_LINK: the iPhone link needs iCloud and
# Louis's Developer ID profile, and CloudKit crashes the app at launch without
# them. Coucou's preferences (same bundle id) are kept.
#
#   ./scripts/install-fork.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="fr.louisraille.NotchBuddy"
DERIVED="${TMPDIR:-/tmp}/coucou-fork-build"
BUILT="${DERIVED}/Build/Products/Release/Coucou.app"
IDENTITY="${COUCOU_SIGN_IDENTITY:-Apple Development}"
TARGET="/Applications/Coucou.app"

echo "Building (Release, without the iPhone link)..."
cd "${REPO_ROOT}/NotchBuddy"
xcodegen >/dev/null
xcodebuild -scheme NotchBuddy -configuration Release -derivedDataPath "${DERIVED}" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO SWIFT_ACTIVE_COMPILATION_CONDITIONS="" \
  -quiet build
# xcodegen rewrites the project for this Xcode: keep the tree as it was.
git -C "${REPO_ROOT}" checkout -q -- NotchBuddy/NotchBuddy.xcodeproj
rm -rf "${REPO_ROOT}/NotchBuddy/NotchBuddy.xcodeproj/project.xcworkspace/xcshareddata"

echo "Signing with \"${IDENTITY}\"..."
codesign --force --deep --options runtime --timestamp=none \
  --entitlements "${REPO_ROOT}/NotchBuddy/Resources/Coucou.entitlements" \
  --sign "${IDENTITY}" "${BUILT}"
codesign --verify --deep --strict "${BUILT}"

echo "Installing in ${TARGET}..."
osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
for _ in $(seq 1 10); do pgrep -f "${TARGET}/Contents/MacOS/Coucou" >/dev/null || break; sleep 1; done
rm -rf "${TARGET}"
cp -R "${BUILT}" "${TARGET}"
open "${TARGET}"
echo "Done."
