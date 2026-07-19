#!/usr/bin/env bash
#
# Fully uninstall Seekarr on macOS and clear all persisted data so a fresh
# DMG install restarts onboarding.
#
# Sandbox container directories (~/Library/Containers/<bundle-id>) cannot be
# removed even with sudo because containermanagerd protects its metadata
# plist. That's fine: the container directory itself is just a marker. The
# actual app data lives in UserDefaults and the Keychain, which this script
# clears via `defaults delete` and `security delete-generic-password`.

set -euo pipefail

APP_NAME="Seekarr"
APP_PATH="/Applications/${APP_NAME}.app"

# Bundle IDs that have shipped over the app's history. Clear them all so
# stale data from older builds (e.g. the pre-rename `labs.matthw.seekarr`)
# doesn't survive a reinstall.
BUNDLE_IDS=(
  "com.labs.matthw.seekarr"
  "labs.dev.matthw.seekarr"
  "labs.matthw.seekarr"
)

printf '==> Quitting %s if running...\n' "$APP_NAME"
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1

printf '==> Removing %s...\n' "$APP_PATH"
if [[ -d "$APP_PATH" ]]; then
  rm -rf "$APP_PATH"
  printf '  removed: %s\n' "$APP_PATH"
else
  printf '  not present\n'
fi

printf '==> Clearing UserDefaults for all known bundle IDs...\n'
for id in "${BUNDLE_IDS[@]}"; do
  if defaults read "$id" >/dev/null 2>&1; then
    defaults delete "$id"
    printf '  cleared defaults: %s\n' "$id"
  else
    printf '  no defaults: %s\n' "$id"
  fi
done

printf '==> Deleting keychain entries...\n'
for id in "${BUNDLE_IDS[@]}"; do
  if security delete-generic-password -s "$id" >/dev/null 2>&1; then
    printf '  removed keychain: %s\n' "$id"
  else
    printf '  no keychain: %s\n' "$id"
  fi
done

printf '\n==> Done. Install the new DMG by opening it and dragging %s.app to /Applications.\n' "$APP_NAME"
printf '    Onboarding will start fresh.\n'
