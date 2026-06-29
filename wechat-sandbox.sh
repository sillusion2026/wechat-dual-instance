#!/bin/bash
# Sandbox WeChat launcher: kicks the sync agent, then opens the managed copy.
# The system /Applications/WeChat.app is launched separately by the user.
set -euo pipefail

SANDBOX="$HOME/Applications/WeChat.app"
SANDBOX_EXECUTABLE="WeChat2"
STATE_FILE="$HOME/.wechat-dual-instance/state.env"
LABEL="com.sillusion.wechat-dual-instance-updater"

if [ ! -d "$SANDBOX" ]; then
    echo "ERROR: $SANDBOX 不存在。先跑 install.sh。"
    exit 1
fi

launchctl kickstart "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true

if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    . "$STATE_FILE"
    case "${LAST_RESULT:-}" in
        postponed_running)
            echo ">>> 同步已排队，沙盒退出后会自动执行。"
            ;;
        synced)
            echo ">>> 沙盒已同步到最新版: ${MANAGED_VERSION:-unknown}"
            ;;
        sync_needed)
            echo ">>> 本机微信版本与沙盒不一致 (system=${SYSTEM_VERSION:-?} sandbox=${MANAGED_VERSION:-?})，沙盒退出后会自动同步。"
            ;;
    esac
fi

if ! pgrep -x "$SANDBOX_EXECUTABLE" >/dev/null 2>&1; then
    open "$SANDBOX"
    sleep 3
fi

COUNT=$(pgrep -x "$SANDBOX_EXECUTABLE" 2>/dev/null | wc -l | tr -d ' ')
if [ "$COUNT" -ge 1 ]; then
    echo ">>> 沙盒微信已启动 (PID $(pgrep -x "$SANDBOX_EXECUTABLE" | head -1))"
else
    echo ">>> 沙盒未能启动。查看 ~/.wechat-dual-instance/logs/update.log"
fi
