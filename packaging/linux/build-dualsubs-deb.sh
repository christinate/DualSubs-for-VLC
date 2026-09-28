#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$ROOT_DIR/upstream/vlc-3.0.24"
BUILD_DIR="${1:-$SRC_DIR/build-linux-dualsubs}"
BUILD_ROOT="$ROOT_DIR/packaging/linux/build-deb"
OUTPUT_ROOT="$ROOT_DIR/packaging/linux/dist"
INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/vlc-dualsubs}"
STAGE_PREFIX="${STAGE_PREFIX:-/usr/local}"
DUALSUBS_VERSION="${DUALSUBS_VERSION:-0.2.0}"
VLC_VERSION="${VLC_VERSION:-3.0.24}"
PACKAGE_VERSION="${PACKAGE_VERSION:-${VLC_VERSION}+dualsubs${DUALSUBS_VERSION}-1}"
PACKAGE_NAME="${PACKAGE_NAME:-vlc-dualsubs}"
ARCH="${ARCH:-$(dpkg --print-architecture)}"
PACKAGE_ROOT="$BUILD_ROOT/root"
STAGE_ROOT="$BUILD_ROOT/stage-root"
CONTROL_DIR="$PACKAGE_ROOT/DEBIAN"
OUTPUT_DEB="$OUTPUT_ROOT/${PACKAGE_NAME}_${PACKAGE_VERSION}_${ARCH}.deb"

compute_dependencies() {
  local install_root="$1"
  local -a elf_files=()
  local -a dependencies=()
  local dependency
  local depends_output
  local file_path
  local joined_dependencies=""
  local shlib_output

  if ! command -v dpkg-shlibdeps >/dev/null 2>&1; then
    return 0
  fi

  while IFS= read -r -d '' file_path; do
    if file "$file_path" | grep -q 'ELF'; then
      elf_files+=("$file_path")
    fi
  done < <(find "$install_root" -type f -print0)

  if [[ "${#elf_files[@]}" -eq 0 ]]; then
    return 0
  fi

  if ! shlib_output="$(
    cd "$BUILD_ROOT"
    dpkg-shlibdeps -O -S"$PACKAGE_ROOT" \
      -l"$install_root/lib" \
      -l"$install_root/lib/vlc" \
      "${elf_files[@]}"
  )"; then
    echo "dpkg-shlibdeps failed while resolving package dependencies." >&2
    return 1
  fi

  depends_output="$(printf '%s\n' "$shlib_output" | sed -n 's/^shlibs:Depends=//p')"
  IFS=',' read -r -a dependencies <<<"$depends_output"
  for dependency in "${dependencies[@]}"; do
    dependency="${dependency#"${dependency%%[![:space:]]*}"}"
    case "$dependency" in
      libvlc5*|libvlccore9*)
        continue
        ;;
    esac
    if [[ -n "$dependency" ]]; then
      [[ -z "$joined_dependencies" ]] || joined_dependencies+=", "
      joined_dependencies+="$dependency"
    fi
  done

  printf '%s\n' "$joined_dependencies"
}

if [[ ! -f "$BUILD_DIR/Makefile" ]]; then
  echo "Expected Linux build directory at $BUILD_DIR" >&2
  exit 1
fi

rm -rf "$BUILD_ROOT"
mkdir -p "$CONTROL_DIR" "$OUTPUT_ROOT" "$STAGE_ROOT"

make -C "$BUILD_DIR" install \
  DESTDIR="$STAGE_ROOT" \
  prefix="$STAGE_PREFIX" \
  exec_prefix="$STAGE_PREFIX" \
  bindir="$STAGE_PREFIX/bin" \
  libdir="$STAGE_PREFIX/lib" \
  datadir="$STAGE_PREFIX/share" \
  pkglibdir="$STAGE_PREFIX/lib/vlc"

if [[ ! -x "$STAGE_ROOT$STAGE_PREFIX/bin/vlc" ]]; then
  echo "Installed VLC binary was not staged at $STAGE_ROOT$STAGE_PREFIX/bin/vlc" >&2
  exit 1
fi

mkdir -p "$PACKAGE_ROOT$(dirname "$INSTALL_PREFIX")"
mv "$STAGE_ROOT$STAGE_PREFIX" "$PACKAGE_ROOT$INSTALL_PREFIX"

mkdir -p \
  "$PACKAGE_ROOT/usr/bin" \
  "$PACKAGE_ROOT/usr/share/applications" \
  "$PACKAGE_ROOT/usr/share/icons/hicolor/512x512/apps"

cat > "$PACKAGE_ROOT/usr/bin/vlc-dualsubs" <<EOF
#!/bin/sh
INSTALL_ROOT="$INSTALL_PREFIX"
export LD_LIBRARY_PATH="\$INSTALL_ROOT/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export VLC_PLUGIN_PATH="\$INSTALL_ROOT/lib/vlc/plugins"
export VLC_DATA_PATH="\$INSTALL_ROOT/share"
export XDG_DATA_DIRS="\$INSTALL_ROOT/share\${XDG_DATA_DIRS:+:\$XDG_DATA_DIRS}"
exec "\$INSTALL_ROOT/bin/vlc" "\$@"
EOF
chmod 755 "$PACKAGE_ROOT/usr/bin/vlc-dualsubs"

cat > "$PACKAGE_ROOT/usr/share/applications/vlc-dualsubs.desktop" <<'EOF'
[Desktop Entry]
Name=VLC DualSubs
Comment=VLC media player with DualSubs support
Exec=vlc-dualsubs %U
Icon=vlc-dualsubs
Terminal=false
Type=Application
Categories=AudioVideo;Player;
MimeType=audio/mpeg;audio/x-mpeg;video/mp4;video/x-matroska;video/x-msvideo;application/x-mpegURL;
StartupNotify=true
EOF

cp "$ROOT_DIR/assets/branding/dualsubs-icon.png" "$PACKAGE_ROOT/usr/share/icons/hicolor/512x512/apps/vlc-dualsubs.png"

mkdir -p "$BUILD_ROOT/debian"
cat > "$BUILD_ROOT/debian/control" <<EOF
Source: $PACKAGE_NAME
Section: video
Priority: optional
Maintainer: DualSubs Open Source Contributors
Standards-Version: 4.6.2

Package: $PACKAGE_NAME
Architecture: any
Description: VLC with DualSubs support
 VLC build installed separately under $INSTALL_PREFIX.
EOF

depends_line="$(compute_dependencies "$PACKAGE_ROOT$INSTALL_PREFIX")"

{
  echo "Package: $PACKAGE_NAME"
  echo "Version: $PACKAGE_VERSION"
  echo "Section: video"
  echo "Priority: optional"
  echo "Architecture: $ARCH"
  echo "Maintainer: DualSubs Open Source Contributors"
  if [[ -n "$depends_line" ]]; then
    echo "Depends: $depends_line"
  fi
  echo "Description: VLC with DualSubs installed separately under $INSTALL_PREFIX"
  echo " This package keeps the system VLC install untouched and adds a separate"
  echo " vlc-dualsubs launcher that runs the DualSubs-enabled build."
} > "$CONTROL_DIR/control"

cat > "$CONTROL_DIR/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
EOF

cat > "$CONTROL_DIR/postrm" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
EOF

chmod 755 "$CONTROL_DIR/postinst" "$CONTROL_DIR/postrm"
dpkg-deb --build "$PACKAGE_ROOT" "$OUTPUT_DEB"

echo
echo "Linux deb created at $OUTPUT_DEB"
