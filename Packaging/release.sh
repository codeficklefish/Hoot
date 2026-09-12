#!/bin/bash
# Produces a Hoot.dmg that other people's Macs will actually open.
#
# Gatekeeper blocks anything that isn't signed with a Developer ID *and*
# notarized by Apple: the user sees "Apple cannot check it for malicious
# software" and, in practice, deletes it. This script does the full sequence —
# sign with hardened runtime, notarize, staple the ticket, package.
#
# What you need first (one-off):
#   1. Apple Developer Program membership ($99/year)
#   2. A "Developer ID Application" certificate in your login keychain
#   3. An app-specific password for notarization, stored once with:
#        xcrun notarytool store-credentials "hoot-notary" \
#          --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PW
#
# Then:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=hoot-notary ./Packaging/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Hoot.app"
DMG="build/Hoot.dmg"
STAGING="build/dmg-staging"

# Refusing by default is the point: a DMG that looks finished and is refused
# by Gatekeeper wastes the time of everyone who downloads it. ALLOW_UNSIGNED
# is the deliberate exception — it produces the same disk image without the
# signature, for a release that says so in its own notes.
UNSIGNED="${ALLOW_UNSIGNED:-}"

if [ -z "${SIGN_IDENTITY:-}" ] && [ -z "$UNSIGNED" ]; then
  echo "SIGN_IDENTITY is not set."
  echo "Without it the build is ad-hoc signed and will not open on other Macs."
  echo "Find yours with:  security find-identity -v -p codesigning"
  echo ""
  echo "To build one anyway, knowing Gatekeeper will refuse it:"
  echo "  ALLOW_UNSIGNED=1 ./Packaging/release.sh"
  exit 1
fi

if [ -n "$UNSIGNED" ]; then
  echo "==> Building WITHOUT a Developer ID"
  echo "    Gatekeeper will refuse this on other Macs. They will need"
  echo "    System Settings -> Privacy & Security -> Open Anyway."
  ./Packaging/build-app.sh release
else
  echo "==> Building and signing"
  SIGN_IDENTITY="$SIGN_IDENTITY" ./Packaging/build-app.sh release

  echo "==> Verifying the signature Gatekeeper will see"
  codesign --verify --deep --strict --verbose=2 "$APP"
fi

echo "==> Staging disk image"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
# The familiar drag-to-install gesture.
ln -s /Applications "$STAGING/Applications"

echo "==> Building $DMG"
hdiutil create -volname "Hoot" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

if [ -n "$UNSIGNED" ]; then
  echo ""
  echo "==> Built $DMG, unsigned and not notarized."
  echo "    Say so in the release notes, with the Open Anyway steps."
  ls -lh "$DMG" | awk '{print "    " $5, $NF}'
  exit 0
fi

# The disk image is signed too, so it isn't flagged before it's even opened.
codesign --force --sign "$SIGN_IDENTITY" "$DMG"

if [ -z "${NOTARY_PROFILE:-}" ]; then
  echo ""
  echo "==> Built $DMG, but NOT notarized (NOTARY_PROFILE unset)."
  echo "    Gatekeeper will still refuse it on other Macs."
  exit 0
fi

echo "==> Sending to Apple for notarization (usually a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

# Stapling attaches the ticket so the app opens even without a network.
echo "==> Stapling the ticket"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo ""
echo "==> Done: $DMG"
echo "    Confirm it passes as a stranger's Mac would see it:"
echo "      spctl -a -t open --context context:primary-signature -vv $DMG"
