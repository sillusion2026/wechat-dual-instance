#!/bin/bash
# Local sync updater for the sandbox WeChat.
# Mirrors /Applications/WeChat.app into ~/Applications/WeChat.app whenever
# the App Store (or user) refreshes the system binary. No network, no DMG
# downloads — relies on the system's own update channel.
set -euo pipefail

SYSTEM_SOURCE="/Applications/WeChat.app"
MANAGED_DIR="$HOME/Applications"
SANDBOX="$MANAGED_DIR/WeChat.app"
SANDBOX_EXECUTABLE="WeChat2"
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
        log "Sync failed. Restoring previous sandbox app from backup."
        rm -rf "$SANDBOX" >/dev/null 2>&1 || true
        mv "$BACKUP_PATH" "$SANDBOX" >/dev/null 2>&1 || true
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
LAST_RESULT=$3
EOF
}

if [ ! -d "$SYSTEM_SOURCE" ]; then
    log "System WeChat not present at $SYSTEM_SOURCE. Nothing to sync."
    write_state "0.0.0" "$(get_version "$SANDBOX")" "system_missing"
    exit 0
fi

system_version="$(get_version "$SYSTEM_SOURCE")"
managed_version="$(get_version "$SANDBOX")"

needs_sync=0
if [ ! -d "$SANDBOX" ]; then
    needs_sync=1
elif ! version_ge "$managed_version" "$system_version"; then
    needs_sync=1
fi

if [ "$needs_sync" -eq 0 ]; then
    log "Up to date: system=$system_version sandbox=$managed_version"
    write_state "$system_version" "$managed_version" "up_to_date"
    exit 0
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
    log "Check-only: system=$system_version sandbox=$managed_version → sync_needed"
    write_state "$system_version" "$managed_version" "sync_needed"
    exit 0
fi

# Note: pgrep WeChat2 only — we intentionally do NOT block on the system
# WeChat (executable name "WeChat") because the sync replaces the sandbox
# bundle only, not /Applications/WeChat.app.
if pgrep -x "$SANDBOX_EXECUTABLE" >/dev/null 2>&1; then
    log "Sandbox WeChat running. Postpone. system=$system_version sandbox=$managed_version"
    write_state "$system_version" "$managed_version" "postponed_running"
    exit 0
fi

if [ -d "$SANDBOX" ]; then
    BACKUP_PATH="$CACHE_DIR/WeChat.app.backup.$(date +%s)"
    log "Backing up current sandbox app to $BACKUP_PATH"
    cp -R "$SANDBOX" "$BACKUP_PATH"
fi

log "Rebuilding sandbox via install.sh --skip-agent --skip-autoquit"
bash "$INSTALL_SCRIPT" --skip-agent --skip-autoquit

if [ -n "$BACKUP_PATH" ]; then
    rm -rf "$BACKUP_PATH"
    BACKUP_PATH=""
fi

new_managed="$(get_version "$SANDBOX")"
write_state "$system_version" "$new_managed" "synced"
log "Sync complete: system=$system_version sandbox=$new_managed"
