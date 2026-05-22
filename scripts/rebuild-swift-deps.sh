#!/usr/bin/env bash
# Rebuild Swift-based native deps from source for the current architecture.
# Run after `yarn install` when building on Apple Silicon.
# These packages publish pre-built Intel binaries to npm; running this script
# replaces them with binaries compiled natively for the host arch.

set -euo pipefail

ARCH=$(uname -m)
NODE_MODULES="$(cd "$(dirname "$0")/.." && pwd)/node_modules"

echo "Host architecture: $ARCH"

rebuild_swift_package() {
  local pkg_dir="$NODE_MODULES/$1"
  local binary_name="$2"
  local output_path="$3"

  if [ ! -d "$pkg_dir" ]; then
    echo "  SKIP $1 (not installed)"
    return
  fi

  echo "  Building $1..."
  (
    cd "$pkg_dir"
    swift build --configuration=release 2>&1
    local built=".build/release/$binary_name"
    if [ -f "$built" ]; then
      cp "$built" "$output_path"
      echo "  OK $1 -> $output_path ($(file "$output_path" | grep -o 'arm64\|x86_64'))"
    else
      echo "  FAIL $1: binary not found at $built"
      exit 1
    fi
  )
}

echo "Rebuilding Swift native deps..."

rebuild_swift_package "macos-audio-devices"           "audio-devices"   "$NODE_MODULES/macos-audio-devices/audio-devices"
rebuild_swift_package "mac-open-with"                 "open-with"       "$NODE_MODULES/mac-open-with/open-with"
rebuild_swift_package "mac-windows"                   "MacWindows"      "$NODE_MODULES/mac-windows/scripts/MacWindows"

# mac-windows also ships ActivateWindow
if [ -d "$NODE_MODULES/mac-windows" ]; then
  (
    cd "$NODE_MODULES/mac-windows"
    built=".build/release/ActivateWindow"
    if [ -f "$built" ]; then
      cp "$built" "scripts/ActivateWindow"
      echo "  OK mac-windows/ActivateWindow ($(file scripts/ActivateWindow | grep -o 'arm64\|x86_64'))"
    fi
  )
fi

# node-mac-app-icon: check what build system it uses
if [ -d "$NODE_MODULES/node-mac-app-icon" ]; then
  echo "  Checking node-mac-app-icon build system..."
  if [ -f "$NODE_MODULES/node-mac-app-icon/Package.swift" ]; then
    rebuild_swift_package "node-mac-app-icon" "run" "$NODE_MODULES/node-mac-app-icon/run"
  elif [ -f "$NODE_MODULES/node-mac-app-icon/binding.gyp" ]; then
    echo "  node-mac-app-icon uses node-gyp (handled by electron-builder install-app-deps)"
  else
    echo "  WARN node-mac-app-icon: unknown build system, skipping"
  fi
fi

echo "Done. Verify results:"
for f in \
  "$NODE_MODULES/macos-audio-devices/audio-devices" \
  "$NODE_MODULES/mac-open-with/open-with" \
  "$NODE_MODULES/mac-windows/scripts/MacWindows" \
  "$NODE_MODULES/mac-windows/scripts/ActivateWindow" \
  "$NODE_MODULES/node-mac-app-icon/run"; do
  if [ -f "$f" ]; then
    echo "  $(file "$f" | sed 's|.*/node_modules/||')"
  fi
done
