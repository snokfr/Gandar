#!/usr/bin/env bash
#
# Builds the Windows release and puts it somewhere fixed.
#
# `flutter build windows` writes to build/windows/x64/runner/Release/, which is
# wiped by `flutter clean` and awkward to point anyone at. This script copies
# the finished bundle to dist/Gandar/, so "the app" always means
# dist/Gandar/Gandar.exe no matter how many times the build directory changes.
#
# The whole bundle is copied, not just the executable: gandar.exe loads
# flutter_windows.dll, the mpv libraries and everything under data/ from its own
# directory, and an exe on its own crashes on launch.
#
#   ./tool/build_release.sh          # build and refresh dist/Gandar/
#   ./tool/build_release.sh --zip    # also write dist/gandar-windows-x64.zip
#
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is not on PATH. See docs/building.md." >&2
  exit 1
fi

RELEASE_DIR="build/windows/x64/runner/Release"
DEST="dist/Gandar"

echo "==> Building the Windows release"
# A stale Release directory keeps plugins that are no longer dependencies (a
# removed plugin's DLL lingers and gets copied out), so clear it first.
rm -rf "$RELEASE_DIR"
flutter build windows --release

if [ ! -f "$RELEASE_DIR/gandar.exe" ]; then
  echo "Build did not produce $RELEASE_DIR/gandar.exe" >&2
  exit 1
fi

echo "==> Copying the bundle to $DEST"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$RELEASE_DIR"/. "$DEST"/

# Ship it under the product's own name; nothing in the bundle refers back to the
# executable's filename, so this is only ever a rename.
mv "$DEST/gandar.exe" "$DEST/Gandar.exe"

echo
echo "Release build: $DEST/Gandar.exe"
du -sh "$DEST" | awk '{print "Bundle size:  " $1}'

if [ "${1:-}" = "--zip" ]; then
  ZIP="dist/gandar-windows-x64.zip"
  rm -f "$ZIP"
  if command -v powershell >/dev/null 2>&1; then
    (cd dist && powershell -NoProfile -Command \
      "Compress-Archive -Path 'Gandar/*' -DestinationPath 'gandar-windows-x64.zip' -Force")
  else
    (cd dist && zip -qr "gandar-windows-x64.zip" Gandar)
  fi
  echo "Archive:      $ZIP"
fi
