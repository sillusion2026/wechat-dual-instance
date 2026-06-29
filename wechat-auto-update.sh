#!/bin/bash
# Local sync updater: mirror /Applications/WeChat.app into ~/Applications and
# rebuild WeChat2.app whenever the App Store (or user) refreshes the system
# WeChat. No network, no DMG downloads, no codesign verification — relies on
# Apple/Tencent's own update channel for the system binary.
set -euo pipefail

SYSTEM_SOURCE="/Applications/WeChat.app"
MANAGED_DIR="$HOME/Applications"
ORIGINAL="$MANAGED_DIR/WeChat.app"
CLONE="$MANAGED_DIR/WeChat2.app"
STATE_DIR="$HOME/.wechat-dual-instance"
LOG_DIR="$STATE_DIR/logs"
CACHE_DIR="$STATE_DIR/cache"
LOCK_DIR="$STATE_DIR/update.lock"
STATE_FILE="$STATE_DIR/state.env"
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="$INSTALLER_DIR/install.sh"
BACKUP_PATH=""
CHECK_ONLY=0
HOLDS_LOCK=0

if [ "${1:-}" = "--check-only" ]; then
    CHECK_ONLY=1
fi

mkdir -p "$LOG_DIR" "$CACHE_DIR"

log() {
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] $*" | tee -a "$LOG_DIR/update.log"
}

cleanup() {
    [ "$HOLDS_LOCK" -eq 1 ] && rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
}

rollback_on_error() {
    local exit_code=$?
    if [ "$exit_code" -ne 0 ] && [ -n "$BACKUP_PATH" ] && [ -d "$BACKUP_PATH" ]; then
        log "Sync failed. Restoring previous managed app from backup."
        rm -rf "$ORIGINAL" >/dev/null 2>&1 || true
        mv "$BACKUP_PATH" "$ORIGINAL" >/dev/null 2>&1 || true
    fi
    return "$exit_code"
}

trap rollback_on_error ERR
trap cleanup EXIT

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log "Another sync process is already running. Skip."
    exit 0
fi
HOLDS_LOCK=1

version_ge() {
    awk -v a="$1" -v b="$2" '
        function normalize(v, parts, count, i) {
            count = split(v, parts, ".")
            for (i = count + 1; i <= 4; i++) {
                parts[i] = 0
            }
            return parts[1] " " parts[2] " " parts[3] " " parts[4]
        }
        BEGIN {
            split(normalize(a), aa, " ")
            split(normalize(b), bb, " ")
            for (i = 1; i <= 4; i++) {
                if ((aa[i] + 0) > (bb[i] + 0)) exit 0
                if ((aa[i] + 0) < (bb[i] + 0)) exit 1
            }
            exit 0
        }
    '
}

get_version() {
    local app_path="$1"
    if [ -d "$app_path" ]; then
        /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist" 2>/dev/null || echo "0.0.0"
    else
        echo "0.0.0"
    fi
}

write_state() {
    cat > "$STATE_FILE" <<EOF
LAST_CHECK_TS=$(date +%s)
SYSTEM_VERSION=$1
MANAGED_VERSION=$2
CLONE_VERSION=$3
LAST_RESULT=$4
EOF
}

if [ ! -d "$SYSTEM_SOURCE" ]; then
    log "System WeChat not present at $SYSTEM_SOURCE. Nothing to sync."
    write_state "0.0.0" "$(get_version "$ORIGINAL")" "$(get_version "$CLONE")" "system_missing"
    exit 0
fi

system_version="$(get_version "$SYSTEM_SOURCE")"
managed_version="$(get_version "$ORIGINAL")"
clone_version="$(get_version "$CLONE")"

needs_managed_sync=0
if [ ! -d "$ORIGINAL" ]; then
    needs_managed_sync=1
elif ! version_ge "$managed_version" "$system_version"; then
    needs_managed_sync=1
fi

needs_clone_rebuild=0
if [ ! -d "$CLONE" ] || [ "$clone_version" != "$system_version" ]; then
    needs_clone_rebuild=1
fi

if [ "$needs_managed_sync" -eq 0 ] && [ "$needs_clone_rebuild" -eq 0 ]; then
    log "Up to date: system=$system_version managed=$managed_version clone=$clone_version"
    write_state "$system_version" "$managed_version" "$clone_version" "up_to_date"
    exit 0
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
    if [ "$needs_managed_sync" -eq 1 ]; then
        result="sync_needed"
    else
        result="clone_rebuild_needed"
    fi
    log "Check-only: system=$system_version managed=$managed_version clone=$clone_version → $result"
    write_state "$system_version" "$managed_version" "$clone_version" "$result"
    exit 0
fi

if pgrep -x "WeChat1" >/dev/null 2>&1 || pgrep -x "WeChat2" >/dev/null 2>&1; then
    log "Managed WeChat running. Postpone. system=$system_version managed=$managed_version clone=$clone_version"
    write_state "$system_version" "$managed_version" "$clone_version" "postponed_running"
    exit 0
fi

if [ "$needs_managed_sync" -eq 1 ] && [ -d "$ORIGINAL" ]; then
    BACKUP_PATH="$CACHE_DIR/WeChat.app.backup.$(date +%s)"
    log "Backing up current managed app to $BACKUP_PATH"
    cp -R "$ORIGINAL" "$BACKUP_PATH"
fi

log "Rebuilding managed instances via install.sh --skip-agent"
bash "$INSTALL_SCRIPT" --skip-agent

if [ -n "$BACKUP_PATH" ]; then
    rm -rf "$BACKUP_PATH"
    BACKUP_PATH=""
fi

new_managed="$(get_version "$ORIGINAL")"
new_clone="$(get_version "$CLONE")"
write_state "$system_version" "$new_managed" "$new_clone" "synced"
log "Sync complete: system=$system_version managed=$new_managed clone=$new_clone"
