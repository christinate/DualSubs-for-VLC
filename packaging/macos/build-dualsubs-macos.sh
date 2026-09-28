#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$ROOT_DIR/upstream/vlc-3.0.24"
BUILD_DIR="${1:-$SRC_DIR/build-macos-dualsubs}"
HOST_ARCH="$(uname -m 2>/dev/null || echo x86_64)"
case "$HOST_ARCH" in
  arm64|aarch64)
    DEFAULT_ARCH="aarch64"
    ;;
  x86_64|amd64)
    DEFAULT_ARCH="x86_64"
    ;;
  *)
    DEFAULT_ARCH="$HOST_ARCH"
    ;;
esac
ARCH="${ARCH:-$DEFAULT_ARCH}"
JOBS="${JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || echo 8)}"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "VLC source tree not found at $SRC_DIR" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "[build] Building VLC for macOS for architecture $ARCH on a $HOST_ARCH device"
bash "$SRC_DIR/extras/package/macosx/build.sh" -c -a "$ARCH" -j "$JOBS"

echo
echo "macOS build completed in $BUILD_DIR"
