#!/usr/bin/env bash
#
# Builds SpaceStation and packages it as a .dmg for distribution.
#
#   scripts/release.sh              Signed with your Developer ID certificate and notarized by Apple
#                                   (needs a paid Apple Developer Program membership; see docs/RELEASING.md)
#   scripts/release.sh --unsigned   Unsigned build and .dmg, for the free route (users must use
#                                   System Settings > Privacy & Security > Open Anyway on first launch)
#
# Environment for the signed route:
#   DEVELOPER_ID_APPLICATION  Full name of your certificate, e.g.
#                             "Developer ID Application: Gregory Carter (ABCDE12345)"
#   NOTARY_PROFILE            Name of a notarytool keychain profile, created once with:
#                             xcrun notarytool store-credentials "<name>" --apple-id <id> --team-id <TEAMID>
#
# Output goes to dist/: SpaceStation-<version>.dmg and a .sha256 checksum file.

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="SpaceStation"
BUILD_DIR="build/release"
DIST_DIR="dist"
MODE="signed"
ALLOW_DIRTY=0

for arg in "$@"; do
  case "$arg" in
    --unsigned) MODE="unsigned" ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight
step "Checking prerequisites"
for tool in xcodebuild hdiutil codesign shasum ditto; do
  command -v "$tool" >/dev/null || fail "$tool not found"
done

if [[ "$ALLOW_DIRTY" -eq 0 && -n "$(git status --porcelain)" ]]; then
  fail "Uncommitted changes. Commit or stash them (or pass --allow-dirty), so the release matches a commit."
fi

if command -v xcodegen >/dev/null; then
  xcodegen generate >/dev/null
  git diff --quiet -- SpaceStation.xcodeproj SpaceStation/Info.plist \
    || fail "SpaceStation.xcodeproj is out of date with project.yml. Run 'xcodegen generate' and commit."
else
  echo "(xcodegen not installed: skipping the project-is-up-to-date check)"
fi

SIGN_ARGS=()
if [[ "$MODE" == "signed" ]]; then
  command -v xcrun >/dev/null || fail "xcrun not found"
  [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]] || fail "Set DEVELOPER_ID_APPLICATION, e.g. \"Developer ID Application: Your Name (TEAMID)\". See docs/RELEASING.md."
  [[ -n "${NOTARY_PROFILE:-}" ]] || fail "Set NOTARY_PROFILE to your notarytool keychain profile name. See docs/RELEASING.md."
  security find-identity -v -p codesigning | grep -F "$DEVELOPER_ID_APPLICATION" >/dev/null \
    || fail "Certificate not found in your keychain: $DEVELOPER_ID_APPLICATION"
  TEAM_ID="$(sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p' <<<"$DEVELOPER_ID_APPLICATION")"
  [[ -n "$TEAM_ID" ]] || fail "Could not read the 10-character Team ID from: $DEVELOPER_ID_APPLICATION"
  # Developer ID needs a secure timestamp; hardened runtime is already on in project.yml.
  SIGN_ARGS=(
    CODE_SIGN_STYLE=Manual
    "CODE_SIGN_IDENTITY=$DEVELOPER_ID_APPLICATION"
    "DEVELOPMENT_TEAM=$TEAM_ID"
    "OTHER_CODE_SIGN_FLAGS=--timestamp"
  )
else
  SIGN_ARGS=(CODE_SIGNING_ALLOWED=NO)
fi

# -------------------------------------------------------------------- build
step "Building $APP_NAME (Release, $MODE)"
rm -rf "$BUILD_DIR"
xcodebuild -quiet \
  -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$BUILD_DIR" \
  "${SIGN_ARGS[@]}" build

APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || fail "Build did not produce $APP"
VERSION="$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)"
echo "Version $VERSION"

# ------------------------------------------------------- sign and notarize
notarize() { # <file> : submit, wait, and fail with Apple's log if not accepted
  local file="$1" output
  output="$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || true
  echo "$output"
  if ! grep -q "status: Accepted" <<<"$output"; then
    local id
    id="$(sed -n 's/^ *id: \([0-9a-f-]\{36\}\).*/\1/p' <<<"$output" | head -1)"
    [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" || true
    fail "Notarization of $(basename "$file") was not accepted."
  fi
}

if [[ "$MODE" == "unsigned" ]]; then
  # CODE_SIGNING_ALLOWED=NO leaves only the linker's stub signature: no bundle identifier, no bound
  # Info.plist and no sealed resources. macOS 27 can't attach an Accessibility grant to that, so the
  # app can't be allowed at all. A proper ad-hoc signature fixes that (the permission is still
  # forgotten on each update, because an ad-hoc requirement is the build's hash).
  step "Ad-hoc signing the app"
  codesign --force --deep --sign - --options runtime \
    --identifier "$(defaults read "$PWD/$APP/Contents/Info" CFBundleIdentifier)" \
    --entitlements SpaceStation/SpaceStation.entitlements "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
fi

if [[ "$MODE" == "signed" ]]; then
  step "Verifying the signature"
  codesign --verify --deep --strict --verbose=2 "$APP"
  details="$(codesign -dvv "$APP" 2>&1)"
  grep -q "Authority=Developer ID Application" <<<"$details" || fail "App is not signed with a Developer ID Application certificate."
  grep -q "flags=.*runtime" <<<"$details" || fail "Hardened Runtime is not enabled (required for notarization)."
  grep -q "Timestamp=" <<<"$details" || fail "No secure timestamp on the signature."

  step "Notarizing the app (this usually takes a few minutes)"
  ZIP="$BUILD_DIR/$APP_NAME-notarize.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarize "$ZIP"
  step "Stapling the notarization ticket to the app"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

# --------------------------------------------------------------------- dmg
step "Creating the disk image"
mkdir -p "$DIST_DIR"
SUFFIX=""
[[ "$MODE" == "unsigned" ]] && SUFFIX="-unsigned"
DMG="$DIST_DIR/$APP_NAME-$VERSION$SUFFIX.dmg"
STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

if [[ "$MODE" == "signed" ]]; then
  step "Signing, notarizing and stapling the disk image"
  codesign --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$DMG"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"

  step "Final Gatekeeper check (what a user's Mac will decide)"
  spctl --assess --type execute --verbose=2 "$APP"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

# ---------------------------------------------------------------- checksum
step "Checksum"
( cd "$DIST_DIR" && shasum -a 256 "$(basename "$DMG")" | tee "$(basename "$DMG").sha256" )

step "Done: $DMG"
if [[ "$MODE" == "signed" ]]; then
  cat <<NEXT

Next:
  1. Test it: download the .dmg from a browser on another Mac (so it is quarantined) and open the app.
  2. git tag v$VERSION && git push origin v$VERSION
  3. gh release create v$VERSION "$DMG" "$DMG.sha256" --title "SpaceStation $VERSION" --notes "..."
NEXT
else
  cat <<NEXT

This build is NOT signed or notarized. On first launch macOS will block it; people must click
'Open Anyway' in System Settings > Privacy & Security, and will need to re-allow Accessibility after
every update. Say so in the release notes. See docs/RELEASING.md for the signed route.
NEXT
fi
