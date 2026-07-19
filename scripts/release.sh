#!/usr/bin/env bash

set -euo pipefail

TARGET="${1:-all}"
APP_NAME="Seekarr"
APP_SLUG="seekarr"

case "$TARGET" in
  android|ios|macos|all)
    ;;
  *)
    printf 'Usage: scripts/release.sh [android|ios|macos|all]\n' >&2
    exit 1
    ;;
esac

VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: *//;s/+.*//')

if [[ -z "$VERSION" ]]; then
  printf 'Failed to read version from pubspec.yaml\n' >&2
  exit 1
fi

DIST_DIR="dist/${VERSION}"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

printf '==> Running flutter analyze...\n'
flutter analyze --fatal-infos

printf '==> Checking dart format...\n'
dart format --output=none --set-exit-if-changed .

printf '==> Running flutter test...\n'
flutter test

if [[ "$TARGET" == "android" || "$TARGET" == "all" ]]; then
  printf '==> Building Android APK...\n'
  flutter build apk --release
  cp build/app/outputs/flutter-apk/app-release.apk "$DIST_DIR/${APP_SLUG}-${VERSION}.apk"
fi

if [[ "$TARGET" == "ios" || "$TARGET" == "all" ]]; then
  if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'iOS releases can only be built on macOS\n' >&2
    exit 1
  fi

  printf '==> Building iOS IPA (unsigned, for sideloading)...\n'
  flutter build ios --release --no-codesign

  APP_PATH="build/ios/iphoneos/Runner.app"
  IPA_PATH="$DIST_DIR/${APP_SLUG}-${VERSION}.ipa"

  if [[ ! -d "$APP_PATH" ]]; then
    printf 'Missing iOS app bundle at %s\n' "$APP_PATH" >&2
    exit 1
  fi

  IPA_WORK_DIR=$(mktemp -d)
  mkdir -p "$IPA_WORK_DIR/Payload"
  cp -r "$APP_PATH" "$IPA_WORK_DIR/Payload/"
  (cd "$IPA_WORK_DIR" && zip -qr - Payload/) > "$IPA_PATH"
  rm -rf "$IPA_WORK_DIR"

  printf '==> IPA pronto per il sideload: %s\n' "$IPA_PATH"
fi

if [[ "$TARGET" == "macos" || "$TARGET" == "all" ]]; then
  if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'macOS releases can only be built on macOS\n' >&2
    exit 1
  fi

  printf '==> Building macOS release...\n'
  flutter build macos --release

  APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
  DMG_STEM="$DIST_DIR/${APP_SLUG}-${VERSION}"
  DMG_PATH="${DMG_STEM}.dmg"
  DMG_WORK_DIR=$(mktemp -d)
  DMG_STAGING_DIR="$DMG_WORK_DIR/staging"
  DMG_RW_PATH="$DMG_WORK_DIR/${APP_SLUG}-${VERSION}-rw.dmg"
  DMG_DEVICE=""
  DMG_MOUNT_DIR=""
  DMG_VOLUME_NAME=""
  VOLUME_NAME="${APP_NAME} ${VERSION}"

  cleanup() {
    if [[ -n "$DMG_DEVICE" ]]; then
      hdiutil detach "$DMG_DEVICE" -quiet || true
    fi

    rm -rf "$DMG_WORK_DIR"
  }

  trap cleanup EXIT

  if [[ ! -d "$APP_PATH" ]]; then
    printf 'Missing macOS app bundle at %s\n' "$APP_PATH" >&2
    exit 1
  fi

  mkdir -p "$DMG_STAGING_DIR"
  ditto "$APP_PATH" "$DMG_STAGING_DIR/${APP_NAME}.app"
  ln -s /Applications "$DMG_STAGING_DIR/Applications"

  printf '==> Creating writable DMG...\n'
  hdiutil create -quiet -fs HFS+ -volname "$VOLUME_NAME" -srcfolder "$DMG_STAGING_DIR" -ov -format UDRW "$DMG_RW_PATH"

  printf '==> Customizing DMG window...\n'
  ATTACH_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_RW_PATH")
  DMG_DEVICE=$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/Apple_HFS/ { print $1; exit }')
  DMG_MOUNT_DIR=$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/Apple_HFS/ { sub(/^.*Apple_HFS[[:space:]]*/, ""); print; exit }')
  DMG_VOLUME_NAME=$(basename "$DMG_MOUNT_DIR")
  sleep 1

  if ! osascript <<EOF
tell application "Finder"
  tell disk "${DMG_VOLUME_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 660, 420}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 14
    set background color of viewOptions to {7967, 12079, 16705}
    set position of item "${APP_NAME}.app" of container window to {170, 170}
    set position of item "Applications" of container window to {430, 170}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
EOF
  then
    printf 'Warning: Finder customization failed, continuing with default DMG layout\n' >&2
  fi

  bless --folder "$DMG_MOUNT_DIR" --openfolder "$DMG_MOUNT_DIR" >/dev/null 2>&1 || true
  sync
  hdiutil detach "$DMG_DEVICE" -quiet
  DMG_DEVICE=""

  printf '==> Compressing DMG...\n'
  hdiutil convert "$DMG_RW_PATH" -quiet -format UDZO -o "$DMG_STEM"
fi

printf '\n==> Release artifacts for v%s:\n' "$VERSION"
ls -lh "$DIST_DIR/"
