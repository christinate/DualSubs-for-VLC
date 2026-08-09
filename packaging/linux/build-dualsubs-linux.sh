#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$ROOT_DIR/upstream/vlc-3.0.23"
BUILD_DIR="${1:-$SRC_DIR/build-linux-dualsubs}"
JOBS="${JOBS:-$(command -v nproc >/dev/null 2>&1 && nproc || echo 4)}"
CC_BIN="${CC:-gcc}"
HOST_TRIPLET="${HOST_TRIPLET:-$("$CC_BIN" -dumpmachine)}"
CONTRIB_BUILD_DIR="$SRC_DIR/contrib/contrib-$HOST_TRIPLET"
CONTRIB_INSTALL_DIR="$SRC_DIR/contrib/$HOST_TRIPLET"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "VLC source tree not found at $SRC_DIR" >&2
  exit 1
fi

# DualSubs only needs playback-side functionality, so we skip git-backed
# encoder contribs on minimal hosts unless the caller explicitly re-enables them.
contrib_bootstrap_args=(--host="$HOST_TRIPLET" --disable-x264 --disable-x26410b)
if [[ -n "${CONTRIB_BOOTSTRAP_FLAGS:-}" ]]; then
  read -r -a contrib_bootstrap_extra <<<"${CONTRIB_BOOTSTRAP_FLAGS}"
  contrib_bootstrap_args+=("${contrib_bootstrap_extra[@]}")
fi

configure_args=(--with-contrib="$CONTRIB_INSTALL_DIR" --enable-qt --disable-alsa --disable-vnc --disable-vcd --disable-chromaprint)
if [[ -n "${EXTRA_CONFIGURE_FLAGS:-}" ]]; then
  read -r -a extra_configure_args <<<"${EXTRA_CONFIGURE_FLAGS}"
  configure_args+=("${extra_configure_args[@]}")
fi

echo "[build] Bootstrapping extras/tools with $JOBS jobs"
(
  cd "$SRC_DIR/extras/tools"
  ./bootstrap
  # flex and bison need the freshly built GNU m4 on minimal hosts.
  make -j1 .buildm4 .buildbison .buildflex
  make -j"$JOBS" --output-sync=recurse
)

export PATH="$SRC_DIR/extras/tools/build/bin:$PATH"

if [[ ! -f "$SRC_DIR/extras/tools/build/share/aclocal/pkg.m4" ]]; then
  mkdir -p "$SRC_DIR/extras/tools/build/share/aclocal"
  for candidate in \
    "$SRC_DIR/extras/tools/pkgconfig/pkg.m4" \
    "$(aclocal --print-ac-dir 2>/dev/null)/pkg.m4" \
    "/usr/share/aclocal/pkg.m4"
  do
    if [[ -f "$candidate" ]]; then
      cp "$candidate" "$SRC_DIR/extras/tools/build/share/aclocal/pkg.m4"
      break
    fi
  done
fi

echo "[build] Building contribs for $HOST_TRIPLET"
mkdir -p "$CONTRIB_BUILD_DIR"
(
  cd "$CONTRIB_BUILD_DIR"
  ../bootstrap "${contrib_bootstrap_args[@]}"
  make list
  if [[ -n "${CONTRIB_PREBUILT_URL:-}" ]]; then
    make prebuilt PREBUILT_URL="$CONTRIB_PREBUILT_URL"
  else
    make -j"$JOBS" --output-sync=recurse fetch
    make -j"$JOBS" --output-sync=recurse
  fi
)

if [[ ! -f "$SRC_DIR/configure" ]]; then
  echo "Bootstrapping VLC autotools..." >&2
  (cd "$SRC_DIR" && ./bootstrap)
fi

export PKG_CONFIG_PATH="$CONTRIB_INSTALL_DIR/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

# VLC's configure probes some contrib packages without --static, which drops
# private crypto deps needed later when plugins link against static contrib libs.
if [[ -z "${GNUTLS_LIBS:-}" ]]; then
  gnutls_static_libs="$(pkg-config --static --libs gnutls 2>/dev/null || true)"
  if [[ -n "$gnutls_static_libs" ]]; then
    export GNUTLS_LIBS="$gnutls_static_libs"
  fi
fi

if [[ -z "${SRT_LIBS:-}" ]]; then
  srt_static_libs="$(pkg-config --static --libs srt 2>/dev/null || true)"
  if [[ -n "$srt_static_libs" ]]; then
    export SRT_LIBS="$srt_static_libs"
  fi
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "[build] Configuring VLC in $BUILD_DIR"
"$SRC_DIR/configure" "${configure_args[@]}"

echo "[build] Running make -j$JOBS"
make -j"$JOBS"

echo
echo "Linux build completed in $BUILD_DIR"
