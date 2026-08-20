#!/bin/bash
# Builds Hoot.app — a real macOS bundle, which is what makes the app icon,
# LSUIElement (no Dock icon) and user notifications work. Notifications in
# particular refuse to run from a bare SwiftPM binary.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Hoot.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/Hoot" "$APP/Contents/MacOS/Hoot" 2>/dev/null || cp "$BIN/Owl" "$APP/Contents/MacOS/Hoot"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Artwork goes in Contents/Resources, where a macOS app bundle expects it.
# (SwiftPM also emits a .bundle beside the binary, but that lookup path sits
# outside the sandbox container, so it can't be relied on in a shipped app.)
cp Sources/Hoot/Resources/*.png "$APP/Contents/Resources/" 2>/dev/null || true

# Sign with the sandbox entitlements.
#
# SIGN_IDENTITY selects who signs. Unset, it is an ad-hoc signature: fine for
# running on this Mac, but Gatekeeper will refuse it on anyone else's. Set it
# to a "Developer ID Application: ..." identity to produce a build that can be
# notarized and distributed — see Packaging/release.sh.
IDENTITY="${SIGN_IDENTITY:--}"
SIGN_ARGS=(--force --deep --sign "$IDENTITY" --entitlements Packaging/Hoot.entitlements)

# The hardened runtime is required for notarization, and cannot be used with
# an ad-hoc signature.
if [ "$IDENTITY" != "-" ]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi

codesign "${SIGN_ARGS[@]}" "$APP" >/dev/null 2>&1 \
  || echo "   (codesign failed - app will run unsandboxed)"

if [ "$IDENTITY" = "-" ]; then
  echo "==> Signed ad-hoc (this Mac only). Set SIGN_IDENTITY to distribute."
else
  echo "==> Signed with: $IDENTITY (hardened runtime)"
fi

echo "==> Entitlements:"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -oE 'com\.apple\.security\.[a-z.-]+' | sed 's/^/     /'

echo "==> Done: $APP"
