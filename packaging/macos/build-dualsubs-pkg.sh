#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$ROOT_DIR/upstream/vlc-3.0.23"
BUILD_ROOT="$ROOT_DIR/packaging/macos/build-pkg"
OUTPUT_ROOT="$ROOT_DIR/packaging/macos/dist"
SUPPORT_DIR_REL="Library/Application Support/DualSubs for VLC"
DUALSUBS_VERSION="${DUALSUBS_VERSION:-0.1.0}"
VLC_VERSION="${VLC_VERSION:-3.0.23}"
PACKAGE_ID="${PACKAGE_ID:-org.dualsubs.vlc.overlay}"
SOURCE_APP="${1:-}"

find_source_app() {
  local candidate

  if [[ -n "$SOURCE_APP" ]]; then
    if [[ -d "$SOURCE_APP" ]]; then
      printf '%s\n' "$SOURCE_APP"
      return 0
    fi
    echo "Specified VLC.app not found: $SOURCE_APP" >&2
    return 1
  fi

  shopt -s nullglob
  for candidate in \
    "$SRC_DIR"/build-macos-dualsubs/VLC.app \
    "$SRC_DIR"/build-macos-dualsubs-*/VLC.app
  do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  shopt -u nullglob

  echo "Unable to locate a built VLC.app under $SRC_DIR" >&2
  return 1
}

compute_sha256() {
  shasum -a 256 "$1" | awk '{print toupper($1)}'
}

stage_file() {
  local source_app="$1"
  local payload_root="$2"
  local relative_path="$3"
  local source_path="$source_app/$relative_path"
  local destination_path="$payload_root/$relative_path"

  if [[ ! -f "$source_path" ]]; then
    echo "Missing source payload file: $source_path" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$destination_path")"
  cp -p "$source_path" "$destination_path"
}

stage_matching_libs() {
  local source_app="$1"
  local payload_root="$2"
  local pattern="$3"
  local found=0
  local lib_path

  while IFS= read -r lib_path; do
    found=1
    local relative_path="${lib_path#"$source_app"/}"
    stage_file "$source_app" "$payload_root" "$relative_path"
  done < <(find "$source_app/Contents/MacOS/lib" -maxdepth 1 -type f -name "$pattern" | sort)

  if [[ "$found" -eq 0 ]]; then
    echo "No matching files found for Contents/MacOS/lib/$pattern" >&2
    exit 1
  fi
}

SOURCE_APP="$(find_source_app)"
PACKAGE_NAME="DualSubs-for-VLC-${VLC_VERSION}-macOS-Overlay.pkg"
OUTPUT_PKG="$OUTPUT_ROOT/$PACKAGE_NAME"
PKG_ROOT="$BUILD_ROOT/root"
PAYLOAD_ROOT="$BUILD_ROOT/payload"
RESOURCES_ROOT="$PKG_ROOT/$SUPPORT_DIR_REL/Resources"
SCRIPTS_ROOT="$BUILD_ROOT/scripts"
POSTINSTALL_SCRIPT="$SCRIPTS_ROOT/postinstall"
PAYLOAD_TAR="$RESOURCES_ROOT/DualSubs-Payload.tar.gz"
PAYLOAD_MANIFEST="$RESOURCES_ROOT/payload-manifest.tsv"

rm -rf "$BUILD_ROOT"
mkdir -p "$PAYLOAD_ROOT" "$RESOURCES_ROOT" "$SCRIPTS_ROOT" "$OUTPUT_ROOT"

stage_file "$SOURCE_APP" "$PAYLOAD_ROOT" "Contents/MacOS/VLC"
stage_matching_libs "$SOURCE_APP" "$PAYLOAD_ROOT" "libvlc*.dylib"
stage_matching_libs "$SOURCE_APP" "$PAYLOAD_ROOT" "libvlccore*.dylib"

for relative_path in \
  "Contents/MacOS/plugins/libmacosx_plugin.dylib" \
  "Contents/MacOS/plugins/liblibass_plugin.dylib" \
  "Contents/MacOS/plugins/libsubsdec_plugin.dylib" \
  "Contents/MacOS/plugins/libsubstx3g_plugin.dylib" \
  "Contents/MacOS/plugins/libttml_plugin.dylib" \
  "Contents/MacOS/plugins/libwebvtt_plugin.dylib" \
  "Contents/MacOS/plugins/plugins.dat"
do
  stage_file "$SOURCE_APP" "$PAYLOAD_ROOT" "$relative_path"
done

find "$PAYLOAD_ROOT" -type f | sort | while IFS= read -r file_path; do
  relative_path="${file_path#"$PAYLOAD_ROOT"/}"
  printf '%s\t%s\n' "$relative_path" "$(compute_sha256 "$file_path")"
done > "$PAYLOAD_MANIFEST"

(cd "$PAYLOAD_ROOT" && tar -czf "$PAYLOAD_TAR" .)

cp "$ROOT_DIR/packaging/macos/Install-DualSubs.sh" "$PKG_ROOT/$SUPPORT_DIR_REL/Install-DualSubs.sh"
cp "$ROOT_DIR/packaging/macos/Uninstall-DualSubs.sh" "$PKG_ROOT/$SUPPORT_DIR_REL/Uninstall-DualSubs.sh"
cp "$ROOT_DIR/packaging/macos/Uninstall DualSubs.command" "$PKG_ROOT/$SUPPORT_DIR_REL/Uninstall DualSubs.command"

cat > "$PKG_ROOT/$SUPPORT_DIR_REL/dualsubs-info.env" <<EOF
DUALSUBS_VERSION=$DUALSUBS_VERSION
VLC_VERSION=$VLC_VERSION
PACKAGE_ID=$PACKAGE_ID
EOF

chmod 755 \
  "$PKG_ROOT/$SUPPORT_DIR_REL/Install-DualSubs.sh" \
  "$PKG_ROOT/$SUPPORT_DIR_REL/Uninstall-DualSubs.sh" \
  "$PKG_ROOT/$SUPPORT_DIR_REL/Uninstall DualSubs.command"

cat > "$POSTINSTALL_SCRIPT" <<'EOF'
#!/bin/bash
set -euo pipefail
"/Library/Application Support/DualSubs for VLC/Install-DualSubs.sh"
EOF
chmod 755 "$POSTINSTALL_SCRIPT"

pkgbuild \
  --root "$PKG_ROOT" \
  --install-location / \
  --identifier "$PACKAGE_ID" \
  --version "$DUALSUBS_VERSION" \
  --scripts "$SCRIPTS_ROOT" \
  "$OUTPUT_PKG"

echo
echo "macOS pkg created at $OUTPUT_PKG"
