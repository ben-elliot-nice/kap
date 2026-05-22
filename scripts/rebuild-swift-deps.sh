#!/usr/bin/env bash
# Rebuild Swift-based native deps from source for the current architecture.
# Run after `yarn install` when building on Apple Silicon.
#
# These packages publish pre-built Intel binaries to npm (source not included).
# This script clones each package's GitHub repo, compiles for the host arch,
# and replaces the Intel binary in node_modules.
#
# Requirements: swift, git

set -euo pipefail

ARCH=$(uname -m)
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NODE_MODULES="$REPO_ROOT/node_modules"
BUILD_DIR="$(mktemp -d)/kap-swift-deps"

echo "Host architecture: $ARCH"
echo "Build dir: $BUILD_DIR"
mkdir -p "$BUILD_DIR"

clone_and_build() {
  local name="$1"
  local repo="$2"
  local subdir="${3:-}"       # subdirectory within repo to build from (optional)
  local binary_name="$4"
  local output_path="$5"
  local extra_flags="${6:-}"  # extra swift build flags

  echo "  Building $name..."
  local src="$BUILD_DIR/$name"
  git clone --depth=1 --quiet "https://github.com/$repo.git" "$src"

  if [ -n "$subdir" ]; then
    src="$src/$subdir"
  fi

  (
    cd "$src"
    # Init submodules if present
    if [ -f ".gitmodules" ]; then
      git submodule update --init --quiet
      # Build from submodule dir if it has Package.swift
      local sub
      sub=$(git submodule status | awk '{print $2}' | head -1)
      if [ -n "$sub" ] && [ -f "$sub/Package.swift" ]; then
        cd "$sub"
      fi
    fi
    swift build --configuration=release $extra_flags 2>&1 | grep -E "error:|Build complete|warning: " || true
    # Swift places output in arch-specific dir on newer toolchains
    local built
    built=$(find .build -name "$binary_name" -not -path "*/dSYM/*" -type f 2>/dev/null | head -1)
    if [ -z "$built" ]; then
      echo "  FAIL $name: binary '$binary_name' not found after build"
      exit 1
    fi
    cp "$built" "$output_path"
    echo "  OK $name ($(file "$output_path" | grep -o 'arm64\|x86_64\|universal'))"
  )
}

echo "Rebuilding Swift native deps..."

clone_and_build "macos-audio-devices" \
  "karaggeorge/macos-audio-devices" "" \
  "audio-devices" "$NODE_MODULES/macos-audio-devices/audio-devices"

clone_and_build "mac-open-with" \
  "karaggeorge/mac-open-with" "" \
  "open-with" "$NODE_MODULES/mac-open-with/open-with"

clone_and_build "mac-windows-MacWindows" \
  "karaggeorge/mac-windows" "swift/MacWindows" \
  "mac-windows" "$NODE_MODULES/mac-windows/scripts/MacWindows"

clone_and_build "mac-windows-ActivateWindow" \
  "karaggeorge/mac-windows" "swift/ActivateWindow" \
  "activate-window" "$NODE_MODULES/mac-windows/scripts/ActivateWindow"

# node-mac-app-icon uses a submodule; -static-stdlib is deprecated in modern Swift
clone_and_build "node-mac-app-icon" \
  "sallar/node-mac-app-icon" "" \
  "GetAppIcon" "$NODE_MODULES/node-mac-app-icon/run"

echo ""
echo "Done. Results:"
for f in \
  "$NODE_MODULES/macos-audio-devices/audio-devices" \
  "$NODE_MODULES/mac-open-with/open-with" \
  "$NODE_MODULES/mac-windows/scripts/MacWindows" \
  "$NODE_MODULES/mac-windows/scripts/ActivateWindow" \
  "$NODE_MODULES/node-mac-app-icon/run"; do
  if [ -f "$f" ]; then
    echo "  $(file "$f" | grep -oE 'arm64|x86_64|universal') — ${f##*/node_modules/}"
  else
    echo "  MISSING — ${f##*/node_modules/}"
  fi
done

rm -rf "$BUILD_DIR"
