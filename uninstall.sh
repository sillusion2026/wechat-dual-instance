#!/bin/bash
# Remove all sandbox artifacts: managed app, container, agents, state.
# The system /Applications/WeChat.app and com.tencent.xinWeChat container
# are NOT touched.
set -euo pipefail

MANAGED_DIR="$HOME/Applications"
SANDBOX="$MANAGED_DIR/WeChat.app"
LEGACY_CLONE="$MANAGED_DIR/WeChat2.app"
CONTAINER1="$HOME/Library/Containers/com.tencent.xinWeChat1"  # legacy
CONTAINER2="$HOME/Library/Containers/com.tencent.xinWeChat2"  # current sandbox
STATE_DIR="$HOME/.wechat-dual-instance"
UPDATER_AGENT="$HOME/Library/LaunchAgents/com.sillusion.wechat-dual-instance-updater.plist"
AUTOLAUNCH_AGENT="$HOME/Library/LaunchAgents/com.sillusion.wechat-dual-instance-autolaunch.plist"

remove_container() {
    local path="$1"
    if [ -d "$path" ]; then
        echo ">>> 删除 $path ..."
        rm -rf "$path" 2>/dev/null || {
            echo "    macOS 保护，尝试用 Finder 删除 ..."
            osascript -e "tell application \"Finder\" to delete POSIX file \"$path\"" 2>/dev/null || true
        }
        echo "    完成。"
    else
        echo "    $path 不存在，跳过。"
    fi
}

echo "=== WeChat Sandbox Uninstaller ==="
echo

echo ">>> 退出运行中的沙盒微信 ..."
pkill -x WeChat1 WeChat2 >/dev/null 2>&1 || true
sleep 1

echo ">>> 卸载 launchd 代理 ..."
launchctl bootout "gui/$(id -u)" "$UPDATER_AGENT"    >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)" "$AUTOLAUNCH_AGENT" >/dev/null 2>&1 || true
rm -f "$UPDATER_AGENT" "$AUTOLAUNCH_AGENT"

echo ">>> 移出系统登录项 ..."
osascript -e "
  tell application \"System Events\"
    try
      delete (every login item whose path is \"$SANDBOX\")
    end try
  end tell" >/dev/null 2>&1 || true
echo "    完成。"

if [ -d "$SANDBOX" ]; then
    echo ">>> 删除 $SANDBOX ..."
    rm -rf "$SANDBOX"
    echo "    完成。"
fi

if [ -d "$LEGACY_CLONE" ]; then
    echo ">>> 删除历史遗留 $LEGACY_CLONE ..."
    rm -rf "$LEGACY_CLONE"
    echo "    完成。"
fi

remove_container "$CONTAINER1"
remove_container "$CONTAINER2"

if [ -d "$STATE_DIR" ]; then
    echo ">>> 删除 $STATE_DIR ..."
    rm -rf "$STATE_DIR"
    echo "    完成。"
fi

echo
echo "=== 卸载完成 ==="
echo "本机 /Applications/WeChat.app 与主账号数据未受影响。"
