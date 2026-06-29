#!/bin/bash
# One-click installer for WeChat dual-instance on macOS.
# - Auto-quits running WeChat (with countdown, Ctrl-C aborts)
# - Builds two managed copies with distinct bundle IDs (WeChat + 微信2)
# - Registers a background sync agent (mirrors App Store upgrades)
# - Registers a login auto-launch agent (starts both instances at login)
set -euo pipefail

SYSTEM_SOURCE="/Applications/WeChat.app"
MANAGED_DIR="$HOME/Applications"
ORIGINAL="$MANAGED_DIR/WeChat.app"
CLONE="$MANAGED_DIR/WeChat2.app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATER_SCRIPT="$SCRIPT_DIR/wechat-auto-update.sh"
SANDBOX_SCRIPT="$SCRIPT_DIR/wechat-sandbox.sh"
UPDATER_TEMPLATE="$SCRIPT_DIR/com.sillusion.wechat-dual-instance-updater.plist.template"
AUTOLAUNCH_TEMPLATE="$SCRIPT_DIR/com.sillusion.wechat-dual-instance-autolaunch.plist.template"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
UPDATER_AGENT="$LAUNCH_AGENTS_DIR/com.sillusion.wechat-dual-instance-updater.plist"
AUTOLAUNCH_AGENT="$LAUNCH_AGENTS_DIR/com.sillusion.wechat-dual-instance-autolaunch.plist"
STATE_DIR="$HOME/.wechat-dual-instance"
LOG_DIR="$STATE_DIR/logs"

SKIP_AGENT_SETUP=0
SKIP_AUTOQUIT=0
NO_AUTOSTART=0
for arg in "$@"; do
    case "$arg" in
        --skip-agent)   SKIP_AGENT_SETUP=1 ;;
        --skip-autoquit) SKIP_AUTOQUIT=1 ;;
        --no-autostart) NO_AUTOSTART=1 ;;
    esac
done

get_version() {
    local app_path="$1"
    if [ -d "$app_path" ]; then
        /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist" 2>/dev/null || echo "0.0.0"
    else
        echo "0.0.0"
    fi
}

# Patch a freshly copied WeChat.app bundle to a distinct identity.
# Args: bundle_path  bundle_id  executable_name  display_name
patch_bundle() {
    local bundle="$1"
    local bid="$2"
    local exec="$3"
    local display="$4"
    local plist="$bundle/Contents/Info.plist"

    if [ -f "$bundle/Contents/MacOS/WeChat" ]; then
        mv "$bundle/Contents/MacOS/WeChat" "$bundle/Contents/MacOS/$exec"
    fi
    plutil -replace CFBundleIdentifier    -string "$bid"     "$plist"
    plutil -replace CFBundleExecutable    -string "$exec"    "$plist"
    plutil -replace CFBundleDisplayName   -string "$display" "$plist"
    plutil -replace CFBundleName          -string "$display" "$plist"
    plutil -replace CFBundleGetInfoString -string "$display" "$plist"
    codesign --remove-signature "$bundle" 2>/dev/null || true
    codesign --force --deep -s - "$bundle" 2>/dev/null
}

render_plist() {
    # Substitute __SCRIPT_PATH__ and __LOG_PATH__ in a plist template.
    # Args: template_path  output_path  script_path  log_path
    python3 - "$1" "$2" "$3" "$4" <<'PY'
from pathlib import Path
import sys
src = Path(sys.argv[1]).read_text()
src = src.replace("__SCRIPT_PATH__", sys.argv[3])
src = src.replace("__LOG_PATH__",    sys.argv[4])
Path(sys.argv[2]).write_text(src)
PY
}

# --- preflight ----------------------------------------------------------------
if [ ! -d "$SYSTEM_SOURCE" ]; then
    echo "ERROR: $SYSTEM_SOURCE 不存在。请先从 App Store 或微信官网安装 WeChat 4.x。"
    exit 1
fi

mkdir -p "$LAUNCH_AGENTS_DIR" "$LOG_DIR" "$MANAGED_DIR"
chmod +x "$UPDATER_SCRIPT" "$SANDBOX_SCRIPT"

echo "=== WeChat Dual-Instance Installer (one-click) ==="
echo

# --- auto-quit running WeChat -------------------------------------------------
RUNNING=()
for name in WeChat WeChat1 WeChat2; do
    if pgrep -x "$name" >/dev/null 2>&1; then
        RUNNING+=("$name")
    fi
done

if [ "${#RUNNING[@]}" -gt 0 ] && [ "$SKIP_AUTOQUIT" -eq 0 ]; then
    echo ">>> 检测到运行中的微信进程: ${RUNNING[*]}"
    echo ">>> 10 秒后将强制退出。按 Ctrl-C 中止安装。"
    for i in 10 9 8 7 6 5 4 3 2 1; do
        printf "\r    倒计时: %2d 秒 " "$i"
        sleep 1
    done
    printf "\r    正在退出微信...        \n"
    osascript -e 'tell application "WeChat" to quit' >/dev/null 2>&1 || true
    sleep 2
    pkill -TERM -x WeChat WeChat1 WeChat2 >/dev/null 2>&1 || true
    sleep 2
    pkill -9 -x WeChat WeChat1 WeChat2 >/dev/null 2>&1 || true
    sleep 1
fi

# --- rebuild managed copies from virgin system bundle -------------------------
SYSTEM_VERSION="$(get_version "$SYSTEM_SOURCE")"

if [ -d "$ORIGINAL" ]; then
    echo ">>> 删除旧的 $ORIGINAL ..."
    rm -rf "$ORIGINAL"
fi
if [ -d "$CLONE" ]; then
    echo ">>> 删除旧的 $CLONE ..."
    rm -rf "$CLONE"
fi

echo ">>> 复制 $SYSTEM_SOURCE → $ORIGINAL  (约 30 秒)..."
cp -R "$SYSTEM_SOURCE" "$ORIGINAL"

echo ">>> 复制 $SYSTEM_SOURCE → $CLONE     (约 30 秒)..."
cp -R "$SYSTEM_SOURCE" "$CLONE"

echo ">>> Patch 实例 1 → bundle=com.tencent.xinWeChat1 / exec=WeChat1 / 显示名=WeChat ..."
patch_bundle "$ORIGINAL" "com.tencent.xinWeChat1" "WeChat1" "WeChat"

echo ">>> Patch 实例 2 → bundle=com.tencent.xinWeChat2 / exec=WeChat2 / 显示名=微信2 ..."
patch_bundle "$CLONE"    "com.tencent.xinWeChat2" "WeChat2" "微信2"

# --- register background sync agent -------------------------------------------
if [ "$SKIP_AGENT_SETUP" -eq 0 ]; then
    echo ">>> 安装后台同步代理 (com.sillusion.wechat-dual-instance-updater) ..."
    render_plist "$UPDATER_TEMPLATE" "$UPDATER_AGENT" "$UPDATER_SCRIPT" "$LOG_DIR/launchd.log"
    launchctl bootout "gui/$(id -u)" "$UPDATER_AGENT" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$UPDATER_AGENT"
    launchctl kickstart "gui/$(id -u)/com.sillusion.wechat-dual-instance-updater" >/dev/null 2>&1 || true
fi

# --- register login auto-launch agent -----------------------------------------
if [ "$NO_AUTOSTART" -eq 0 ] && [ "$SKIP_AGENT_SETUP" -eq 0 ]; then
    echo ">>> 安装开机自启代理 (com.sillusion.wechat-dual-instance-autolaunch) ..."
    render_plist "$AUTOLAUNCH_TEMPLATE" "$AUTOLAUNCH_AGENT" "$SANDBOX_SCRIPT" "$LOG_DIR/autolaunch.log"
    launchctl bootout "gui/$(id -u)" "$AUTOLAUNCH_AGENT" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$AUTOLAUNCH_AGENT"
fi

# --- done ---------------------------------------------------------------------
echo
echo "=============== 部署完成 ==============="
echo "系统微信 (未改动):  $SYSTEM_SOURCE  ($SYSTEM_VERSION, com.tencent.xinWeChat)"
echo "实例 1 (主):       $ORIGINAL  ($(get_version "$ORIGINAL"), com.tencent.xinWeChat1, 显示名 WeChat)"
echo "实例 2 (副):       $CLONE     ($(get_version "$CLONE"), com.tencent.xinWeChat2, 显示名 微信2)"
if [ "$SKIP_AGENT_SETUP" -eq 0 ]; then
    echo "同步代理:          $UPDATER_AGENT"
    if [ "$NO_AUTOSTART" -eq 0 ]; then
        echo "自启代理:          $AUTOLAUNCH_AGENT (下次登录会自动启动双开)"
    fi
fi
echo "日志目录:          $LOG_DIR/"
echo
echo "现在立即启动:  bash $SANDBOX_SCRIPT"
