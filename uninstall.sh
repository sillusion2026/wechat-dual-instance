#!/bin/bash
# Remove all dual-instance artifacts: managed apps, containers, agents, state.
set -euo pipefail

MANAGED_DIR="$HOME/Applications"
ORIGINAL="$MANAGED_DIR/WeChat.app"
CLONE="$MANAGED_DIR/WeChat2.app"
CONTAINER1="$HOME/Library/Containers/com.tencent.xinWeChat1"
CONTAINER2="$HOME/Library/Containers/com.tencent.xinWeChat2"
STATE_DIR="$HOME/.wechat-dual-instance"
UPDATER_AGENT="$HOME/Library/LaunchAgents/com.sillusion.wechat-dual-instance-updater.plist"
AUTOLAUNCH_AGENT="$HOME/Library/LaunchAgents/com.sillusion.wechat-dual-instance-autolaunch.plist"

echo "=== WeChat Dual-Instance Uninstaller ==="
echo

echo ">>> 退出运行中的管理实例 ..."
pkill -x WeChat1 WeChat2 >/dev/null 2>&1 || true

echo ">>> 卸载 launchd 代理 ..."
launchctl bootout "gui/$(id -u)" "$UPDATER_AGENT"    >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)" "$AUTOLAUNCH_AGENT" >/dev/null 2>&1 || true
rm -f "$UPDATER_AGENT" "$AUTOLAUNCH_AGENT"

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
