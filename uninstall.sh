#!/bin/bash
# Remove the cloned WeChat, updater agent, and associated data.
set -euo pipefail

MANAGED_DIR="$HOME/Applications"
ORIGINAL="$MANAGED_DIR/WeChat.app"
CLONE="$MANAGED_DIR/WeChat2.app"
CONTAINER1="$HOME/Library/Containers/com.tencent.xinWeChat1"
CONTAINER2="$HOME/Library/Containers/com.tencent.xinWeChat2"
STATE_DIR="$HOME/.wechat-dual-instance"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.sillusion.wechat-dual-instance-updater.plist"

echo "=== WeChat Dual-Instance Uninstaller ==="
echo

echo ">>> Unloading background updater ..."
launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
rm -f "$LAUNCH_AGENT"

if [ -d "$CLONE" ]; then
    echo ">>> Removing $CLONE ..."
    rm -rf "$CLONE"
    echo "    Done."
else
    echo "    $CLONE not present, skipping."
fi

if [ -d "$ORIGINAL" ]; then
    echo ">>> Removing managed original $ORIGINAL ..."
    rm -rf "$ORIGINAL"
    echo "    Done."
else
    echo "    $ORIGINAL not present, skipping."
fi

if [ -d "$CONTAINER1" ]; then
    echo ">>> Removing $CONTAINER1 ..."
    rm -rf "$CONTAINER1" 2>/dev/null || {
        echo "    Container is protected by macOS. Trying with Finder ..."
        osascript -e "tell application \"Finder\" to delete POSIX file \"$CONTAINER1\"" 2>/dev/null || true
    }
    echo "    Done."
else
    echo "    $CONTAINER1 not present, skipping."
fi

if [ -d "$CONTAINER2" ]; then
    echo ">>> Removing $CONTAINER2 ..."
    rm -rf "$CONTAINER2" 2>/dev/null || {
        echo "    Container is protected by macOS. Trying with Finder ..."
        osascript -e "tell application \"Finder\" to delete POSIX file \"$CONTAINER2\"" 2>/dev/null || true
    }
    echo "    Done."
else
    echo "    $CONTAINER2 not present, skipping."
fi

if [ -d "$STATE_DIR" ]; then
    echo ">>> Removing updater state at $STATE_DIR ..."
    rm -rf "$STATE_DIR"
    echo "    Done."
fi

echo
echo "=== Uninstall complete ==="
echo "Your system /Applications/WeChat.app and its data are untouched."
