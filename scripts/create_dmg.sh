#!/bin/bash
set -euo pipefail

# Build a styled DMG installer for MDViewer.
# Used by both `make dmg` and CI (release.yml).
#
# Usage: scripts/create_dmg.sh <app_path> <output_dmg>

APP_PATH="${1:?Usage: scripts/create_dmg.sh <app_path> <output_dmg>}"
DMG_OUTPUT="${2:?Usage: scripts/create_dmg.sh <app_path> <output_dmg>}"

command -v create-dmg >/dev/null || { echo "Error: create-dmg not found. Install via: brew install create-dmg"; exit 1; }

create-dmg \
  --volname "MDViewer" \
  --background "docs/dmg-background.png" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --text-size 16 \
  --icon "MDViewer.app" 165 205 \
  --app-drop-link 495 205 \
  --hide-extension "MDViewer.app" \
  --no-internet-enable \
  "$DMG_OUTPUT" \
  "$APP_PATH"
