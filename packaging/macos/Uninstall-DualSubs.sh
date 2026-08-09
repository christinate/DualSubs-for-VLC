#!/bin/bash
set -euo pipefail

SUPPORT_DIR="/Library/Application Support/DualSubs for VLC"
STATE_DIR="$SUPPORT_DIR/State"
BACKUP_ROOT="$STATE_DIR/backup"
INSTALL_MANIFEST="$STATE_DIR/install-manifest.tsv"
TARGET_APP_FILE="$STATE_DIR/target-app.txt"
WARNINGS_FILE="$SUPPORT_DIR/uninstall-report.txt"
INFO_FILE="$SUPPORT_DIR/dualsubs-info.env"

compute_sha256() {
  shasum -a 256 "$1" | awk '{print toupper($1)}'
}

ensure_vlc_closed() {
  if pgrep -x VLC >/dev/null 2>&1 || pgrep -f "/VLC.app/Contents/MacOS/VLC" >/dev/null 2>&1; then
    echo "Close VLC before uninstalling DualSubs." >&2
    exit 1
  fi
}

if [[ ! -f "$INSTALL_MANIFEST" ]]; then
  echo "DualSubs install manifest not found at $INSTALL_MANIFEST" >&2
  exit 1
fi

if [[ ! -f "$TARGET_APP_FILE" ]]; then
  echo "DualSubs target app record not found at $TARGET_APP_FILE" >&2
  exit 1
fi

TARGET_APP="$(cat "$TARGET_APP_FILE")"
ensure_vlc_closed

tmp_warnings="$(mktemp /tmp/dualsubs-macos-uninstall.XXXXXX)"
trap 'rm -f "$tmp_warnings"' EXIT
had_warnings=0

while IFS=$'\t' read -r relative_path original_hash installed_hash; do
  [[ -n "$relative_path" ]] || continue

  target_path="$TARGET_APP/$relative_path"
  backup_path="$BACKUP_ROOT/$relative_path"

  if [[ ! -f "$backup_path" ]]; then
    printf 'Backup missing for %s; skipped restore.\n' "$relative_path" >> "$tmp_warnings"
    had_warnings=1
    continue
  fi

  if [[ ! -f "$target_path" ]]; then
    printf 'Target file missing for %s; skipped restore.\n' "$relative_path" >> "$tmp_warnings"
    had_warnings=1
    continue
  fi

  current_hash="$(compute_sha256 "$target_path")"

  if [[ "$current_hash" == "$installed_hash" ]]; then
    cp -p "$backup_path" "$target_path"
    restored_hash="$(compute_sha256 "$target_path")"
    if [[ "$restored_hash" != "$original_hash" ]]; then
      echo "Post-uninstall verification failed for $relative_path" >&2
      exit 1
    fi
    continue
  fi

  if [[ "$current_hash" == "$original_hash" ]]; then
    continue
  fi

  printf 'Skipped %s because the current file no longer matches the DualSubs payload.\n' "$relative_path" >> "$tmp_warnings"
  had_warnings=1
done < "$INSTALL_MANIFEST"

if [[ "$had_warnings" -eq 0 ]]; then
  rm -f "$WARNINGS_FILE"

  package_id="org.dualsubs.vlc.overlay"
  if [[ -f "$INFO_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$INFO_FILE"
    package_id="${PACKAGE_ID:-$package_id}"
  fi

  if command -v pkgutil >/dev/null 2>&1; then
    pkgutil --forget "$package_id" >/dev/null 2>&1 || true
  fi

  (
    sleep 1
    rm -rf "$SUPPORT_DIR"
  ) >/dev/null 2>&1 &

  echo "DualSubs files restored cleanly."
else
  mv "$tmp_warnings" "$WARNINGS_FILE"
  trap - EXIT
  echo "DualSubs uninstalled with warnings. Report saved to $WARNINGS_FILE"
fi
