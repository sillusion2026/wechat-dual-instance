#!/bin/bash
# WeChat 4.x dual-instance launcher with background updater kickstart.
set -euo pipefail

ORIGINAL="$HOME/Applications/WeChat.app"
CLONE="$HOME/Applications/WeChat2.app"
SYSTEM_SOURCE="/Applications/WeChat.app"
STATE_FILE="$HOME/.wechat-dual-instance/state.env"
LABEL="com.sillusion.wechat-dual-instance-updater"

if [ ! -d "$ORIGINAL" ]; then
    echo "ERROR: $ORIGINAL not found."
    echo "Run install.sh first to create the managed WeChat app."
    exit 1
fi

if [ ! -d "$CLONE" ]; then
    echo "ERROR: $CLONE not found."
    echo "Run install.sh first to create the isolated clone."
    exit 1
fi

launchctl kickstart "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true

if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    . "$STATE_FILE"
    case "${LAST_RESULT:-}" in
        postponed_running)
            echo ">>> Sync is queued and will run after both WeChat instances exit."
            ;;
        synced)
            echo ">>> Sync completed. Managed version: ${MANAGED_VERSION:-unknown}"
            ;;
        sync_needed|clone_rebuild_needed)
            echo ">>> System WeChat differs from managed copy (system=${SYSTEM_VERSION:-?} managed=${MANAGED_VERSION:-?} clone=${CLONE_VERSION:-?}). Sync will run after both WeChat instances exit."
            ;;
    esac
fi

ORIG_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ORIGINAL/Contents/Info.plist" 2>/dev/null || echo "unknown")
CLONE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CLONE/Contents/Info.plist" 2>/dev/null || echo "unknown")
if [ "$ORIG_VERSION" != "$CLONE_VERSION" ]; then
    echo "WARNING: clone version $CLONE_VERSION differs from original version $ORIG_VERSION."
    echo "Background updater will rebuild the clone when WeChat is not running."
    echo
fi

if ! pgrep -x WeChat1 >/dev/null 2>&1; then
    open "$ORIGINAL"
    sleep 2
fi

if ! pgrep -x WeChat2 >/dev/null 2>&1; then
    open "$CLONE"
    sleep 3
fi

INST1=$(pgrep -x WeChat1 2>/dev/null | wc -l | tr -d ' ')
INST2=$(pgrep -x WeChat2 2>/dev/null | wc -l | tr -d ' ')
echo ">>> WeChat1 instance(s): $INST1 — WeChat2 instance(s): $INST2"
if [ "$INST1" -ge 1 ] && [ "$INST2" -ge 1 ]; then
    echo ">>> Both managed WeChat instances are running. Scan QR codes as needed."
else
    echo ">>> One or both instances failed to start. Check ~/.wechat-dual-instance/logs/update.log if a sync is in progress."
fi

if [ -d "$SYSTEM_SOURCE" ]; then
    SYSTEM_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SYSTEM_SOURCE/Contents/Info.plist" 2>/dev/null || echo "unknown")
    if [ "$SYSTEM_VERSION" != "$ORIG_VERSION" ]; then
        echo ">>> Managed WeChat version is $ORIG_VERSION; system /Applications/WeChat.app remains $SYSTEM_VERSION."
    fi
fi
