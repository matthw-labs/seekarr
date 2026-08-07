#!/usr/bin/env bash
#
# Fully uninstall Cupola on macOS and clear all persisted data so a fresh
# DMG install restarts onboarding.
#
# Sandbox container directories (~/Library/Containers/<bundle-id>) cannot be
# removed even with sudo because containermanagerd protects its metadata
# plist. That's fine: the container directory itself is just a marker. The
# actual app data lives in UserDefaults and the Keychain, which this script
# clears via `defaults delete` and `security delete-generic-password`.

set -euo pipefail

APP_NAME="Cupola"
APP_PATH="/Applications/${APP_NAME}.app"

# App bundles that have shipped under a different name than the current one.
# The 2026-08 rebrand from Seekarr to Cupola changed the bundle filename
# itself (not just the identifier), so a Cupola install does not overwrite
# Seekarr.app — it sits in /Applications alongside it until removed by name.
LEGACY_APP_PATHS=(
  "/Applications/Seekarr.app"
)

# Bundle IDs that have shipped over the app's history, newest first. Clear
# them all so stale data from older builds — the pre-rebrand
# `com.labs.matthw.seekarr` and its two predecessors — doesn't survive a
# reinstall. Append-only: the rebrand is exactly the moment this data is
# most likely to be orphaned, not a trigger to prune the list.
BUNDLE_IDS=(
  "com.matthwlabs.cupola"
  "com.labs.matthw.seekarr"
  "labs.dev.matthw.seekarr"
  "labs.matthw.seekarr"
)

printf '==> Quitting %s if running...\n' "$APP_NAME"
pkill -x "$APP_NAME" 2>/dev/null || true
pkill -x "Seekarr" 2>/dev/null || true
sleep 1

printf '==> Removing %s...\n' "$APP_PATH"
if [[ -d "$APP_PATH" ]]; then
  rm -rf "$APP_PATH"
  printf '  removed: %s\n' "$APP_PATH"
else
  printf '  not present\n'
fi

printf '==> Removing legacy app bundles...\n'
for legacy_path in "${LEGACY_APP_PATHS[@]}"; do
  if [[ -d "$legacy_path" ]]; then
    rm -rf "$legacy_path"
    printf '  removed: %s\n' "$legacy_path"
  else
    printf '  not present: %s\n' "$legacy_path"
  fi
done

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
