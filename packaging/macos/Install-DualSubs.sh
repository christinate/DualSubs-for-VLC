#!/bin/bash
set -euo pipefail

SUPPORT_DIR="/Library/Application Support/DualSubs for VLC"
RESOURCES_DIR="$SUPPORT_DIR/Resources"
STATE_DIR="$SUPPORT_DIR/State"
BACKUP_ROOT="$STATE_DIR/backup"
PAYLOAD_TAR="$RESOURCES_DIR/DualSubs-Payload.tar.gz"
PAYLOAD_MANIFEST="$RESOURCES_DIR/payload-manifest.tsv"
INSTALL_MANIFEST="$STATE_DIR/install-manifest.tsv"
TARGET_APP_FILE="$STATE_DIR/target-app.txt"
TARGET_APP="${DUALSUBS_TARGET_APP:-/Applications/VLC.app}"

compute_sha256() {
  shasum -a 256 "$1" | awk '{print toupper($1)}'
}

ensure_target_app() {
  if [[ ! -f "$TARGET_APP/Contents/MacOS/VLC" ]]; then
    echo "Expected VLC.app at $TARGET_APP" >&2
    exit 1
  fi
}

ensure_vlc_closed() {
  if pgrep -x VLC >/dev/null 2>&1 || pgrep -f "/VLC.app/Contents/MacOS/VLC" >/dev/null 2>&1; then
    echo "Close VLC before installing DualSubs." >&2
    exit 1
  fi
}

ensure_target_app
ensure_vlc_closed

if [[ ! -f "$PAYLOAD_TAR" ]]; then
  echo "Missing payload archive: $PAYLOAD_TAR" >&2
  exit 1
fi

if [[ ! -f "$PAYLOAD_MANIFEST" ]]; then
  echo "Missing payload manifest: $PAYLOAD_MANIFEST" >&2
  exit 1
fi

tmp_root="$(mktemp -d /tmp/dualsubs-macos-install.XXXXXX)"
trap 'rm -rf "$tmp_root"' EXIT

mkdir -p "$STATE_DIR" "$BACKUP_ROOT"
tar -xzf "$PAYLOAD_TAR" -C "$tmp_root"

: > "$INSTALL_MANIFEST"
printf '%s\n' "$TARGET_APP" > "$TARGET_APP_FILE"

while IFS=$'\t' read -r relative_path expected_hash; do
  [[ -n "$relative_path" ]] || continue

  target_path="$TARGET_APP/$relative_path"
  payload_path="$tmp_root/$relative_path"
  backup_path="$BACKUP_ROOT/$relative_path"

  if [[ ! -f "$payload_path" ]]; then
    echo "Payload entry is missing: $relative_path" >&2
    exit 1
  fi

  if [[ ! -f "$target_path" ]]; then
    echo "Target VLC file is missing: $target_path" >&2
    exit 1
  fi

  payload_hash="$(compute_sha256 "$payload_path")"
  if [[ "$payload_hash" != "$expected_hash" ]]; then
    echo "Payload hash mismatch for $relative_path" >&2
    exit 1
  fi

  current_hash="$(compute_sha256 "$target_path")"

  if [[ -f "$backup_path" ]]; then
    backup_hash="$(compute_sha256 "$backup_path")"
    if [[ "$current_hash" != "$payload_hash" && "$current_hash" != "$backup_hash" ]]; then
      echo "Cannot safely replace $relative_path because the current file no longer matches either the backup or the DualSubs payload." >&2
      exit 1
    fi
  else
    mkdir -p "$(dirname "$backup_path")"
    cp -p "$target_path" "$backup_path"
    backup_hash="$(compute_sha256 "$backup_path")"
  fi

  if [[ "$current_hash" != "$payload_hash" ]]; then
    mkdir -p "$(dirname "$target_path")"
    cp -p "$payload_path" "$target_path"
  fi

  installed_hash="$(compute_sha256 "$target_path")"
  if [[ "$installed_hash" != "$payload_hash" ]]; then
    echo "Post-install verification failed for $relative_path" >&2
    exit 1
  fi

  printf '%s\t%s\t%s\n' "$relative_path" "$backup_hash" "$payload_hash" >> "$INSTALL_MANIFEST"
done < "$PAYLOAD_MANIFEST"

echo "DualSubs overlay installation completed successfully for $TARGET_APP"
