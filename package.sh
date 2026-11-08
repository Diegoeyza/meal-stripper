#!/usr/bin/env bash
# Build shareable bundles into dist/:
#   buff-stripper-<version>.zip   REFramework mod (flat) + install notes
#   MealStripper-<version>.zip    REFramework mod, game-folder layout (Nexus/Vortex)
set -euo pipefail
cd "$(dirname "$0")"

command -v zip >/dev/null || { echo "error: 'zip' is required" >&2; exit 1; }

MOD_VERSION="$(sed -n 's/^local VERSION = "\([^"]*\)".*/\1/p' \
  reframework/buff_stripper.lua | head -1)"
DIST="dist"

rm -rf "$DIST"
mkdir -p "$DIST"

# 1) Flat bundle: the Lua file + install notes.
mkdir -p "$DIST/flat"
cp reframework/buff_stripper.lua "$DIST/flat/buff_stripper.lua"
cp reframework/INSTALL.txt "$DIST/flat/INSTALL.txt"
( cd "$DIST/flat" \
    && zip -q "../buff-stripper-${MOD_VERSION}.zip" buff_stripper.lua INSTALL.txt )
rm -rf "$DIST/flat"

# 2) Nexus/Vortex bundle: laid out for the game folder so it extracts straight
#    into <game>\ (reframework\autorun\buff_stripper.lua) or installs via Vortex.
mkdir -p "$DIST/nexus/reframework/autorun"
cp reframework/buff_stripper.lua "$DIST/nexus/reframework/autorun/buff_stripper.lua"
cp packaging/nexus/README.txt "$DIST/nexus/README.txt"
( cd "$DIST/nexus" && zip -q -r "../MealStripper-${MOD_VERSION}.zip" . )
rm -rf "$DIST/nexus"

echo "Built into $DIST/:"
ls -1 "$DIST"
