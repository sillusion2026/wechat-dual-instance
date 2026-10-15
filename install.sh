#!/bin/bash
# One-click installer for WeChat sandbox on macOS.
# - Auto-quits running sandbox WeChat (system /Applications/WeChat is untouched)
# - Builds ONE managed copy at ~/Applications/WeChat Sandbox.app
#   * bundle id : com.tencent.xinWeChat2 (preserves any existing sandbox login)
#   * executable: WeChat2 (distinct from system WeChat for clean pgrep)
#   * display   : 微信沙盒 (en/Base: WeChat Sandbox)
# - Registers a background sync agent (mirrors App Store upgrades)
# - Registers a login auto-launch agent (starts sandbox at login)
set -euo pipefail

SYSTEM_SOURCE="/Applications/WeChat.app"
MANAGED_DIR="$HOME/Applications"
SANDBOX="$MANAGED_DIR/WeChat Sandbox.app"
LEGACY_SANDBOX="$MANAGED_DIR/WeChat.app"     # previous sandbox path
LEGACY_CLONE="$MANAGED_DIR/WeChat2.app"      # from older dual-managed setup
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
CACHE_DIR="$STATE_DIR/cache"

SANDBOX_BUNDLE_ID="com.tencent.xinWeChat2"
SANDBOX_EXECUTABLE="WeChat2"
SANDBOX_DISPLAY="WeChat Sandbox"
SANDBOX_DISPLAY_ZH="微信沙盒"
SANDBOX_SUFFIX="sandbox2"

SKIP_AGENT_SETUP=0
SKIP_AUTOQUIT=0
NO_AUTOSTART=0
for arg in "$@"; do
    case "$arg" in
        --skip-agent)    SKIP_AGENT_SETUP=1 ;;
        --skip-autoquit) SKIP_AUTOQUIT=1 ;;
        --no-autostart)  NO_AUTOSTART=1 ;;
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

find_apple_development_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | grep -E 'Apple Development' \
        | head -1 \
        | sed -n 's/.*"\([^"]*\)".*/\1/p'
}

sign_bundle() {
    local bundle="$1"
    # Re-applying the original App Store sandbox entitlements onto a
    # re-signed clone hard-crashes WeChat 4.1.8 on macOS 26.x.
    # Keep the clone minimally patched and let codesign regenerate the
    # signature without reusing the original entitlements blob.
    #
    # Prefer a real Apple Development identity: ad-hoc signed apps have no
    # TeamID, so macOS 26 denies them notification/badge permission and the
    # Dock badge never appears. Falls back to ad-hoc when no cert exists.
    local signer=""
    signer="$(find_apple_development_identity || true)"
    if [ -n "$signer" ]; then
        if codesign --force --deep -s "$signer" "$bundle" 2>/dev/null; then
            echo "    已用 Apple Development 证书签名: $signer"
            return 0
        fi
        echo "    ⚠️  证书签名失败，回退 ad-hoc 签名。"
    fi
    codesign --force --deep -s - "$bundle" 2>/dev/null
}

patch_bundle() {
    local bundle="$1"
    local bid="$2"
    local exec="$3"
    local display="$4"
    local display_zh="$5"
    local plist="$bundle/Contents/Info.plist"

    # Strip the original signature so we can modify the bundle freely.
    codesign --remove-signature "$bundle" 2>/dev/null || true

    if [ -f "$bundle/Contents/MacOS/WeChat" ]; then
        mv "$bundle/Contents/MacOS/WeChat" "$bundle/Contents/MacOS/$exec"
    fi
    plutil -replace CFBundleIdentifier    -string "$bid"     "$plist"
    plutil -replace CFBundleExecutable    -string "$exec"    "$plist"
    plutil -replace CFBundleDisplayName   -string "$display" "$plist"
    plutil -replace CFBundleName          -string "$display" "$plist"
    plutil -replace CFBundleGetInfoString -string "$display" "$plist"

    patch_localized_name "$bundle/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" "$display_zh"
    patch_localized_name "$bundle/Contents/Resources/en.lproj/InfoPlist.strings" "$display"
    patch_localized_name "$bundle/Contents/Resources/Base.lproj/InfoPlist.strings" "$display"
    patch_localized_name "$bundle/Contents/MacOS/WeChatAppEx.app/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" "$display_zh"
    patch_localized_name "$bundle/Contents/MacOS/WeChatAppEx.app/Contents/Resources/en.lproj/InfoPlist.strings" "$display"
    patch_localized_name "$bundle/Contents/MacOS/WeChatAppEx.app/Contents/Resources/Base.lproj/InfoPlist.strings" "$display"
    patch_nested_bundle_ids "$bundle" "$bid"
    remove_bundle_url_types "$plist"

    sign_bundle "$bundle"
}

patch_localized_name() {
    local strings_file="$1"
    local display="$2"

    if [ ! -f "$strings_file" ]; then
        return 0
    fi

    plutil -convert xml1 "$strings_file" >/dev/null 2>&1 || true
    plutil -replace CFBundleDisplayName -string "$display" "$strings_file" 2>/dev/null || true
    plutil -replace CFBundleName -string "$display" "$strings_file" 2>/dev/null || true
    plutil -convert binary1 "$strings_file" >/dev/null 2>&1 || true
}

remove_bundle_url_types() {
    local plist="$1"
    plutil -remove CFBundleURLTypes "$plist" >/dev/null 2>&1 || true
}

rewrite_bundle_id() {
    local plist="$1"
    local new_id="$2"

    [ -f "$plist" ] || return 0
    plutil -convert xml1 "$plist" >/dev/null 2>&1 || true
    plutil -replace CFBundleIdentifier -string "$new_id" "$plist" >/dev/null 2>&1 || true
    plutil -convert binary1 "$plist" >/dev/null 2>&1 || true
}

patch_nested_bundle_ids() {
    local bundle="$1"
    local top_bundle_id="$2"
    local nested_root="$bundle/Contents/MacOS/WeChatAppEx.app/Contents"

    rewrite_bundle_id "$nested_root/Info.plist" "com.tencent.flue.WeChatAppEx.$SANDBOX_SUFFIX"
    rewrite_bundle_id "$nested_root/Frameworks/WeChatAppEx Framework.framework/Versions/C/Helpers/WeChatAppEx Helper.app/Contents/Info.plist" "com.tencent.flue.helper.$SANDBOX_SUFFIX"
    rewrite_bundle_id "$nested_root/Frameworks/WeChatAppEx Framework.framework/Versions/C/Helpers/WeChatAppEx Helper (GPU).app/Contents/Info.plist" "com.tencent.flue.helper.gpu.$SANDBOX_SUFFIX"
    rewrite_bundle_id "$nested_root/Frameworks/WeChatAppEx Framework.framework/Versions/C/Helpers/WeChatAppEx Helper (Plugin).app/Contents/Info.plist" "com.tencent.flue.helper.plugin.$SANDBOX_SUFFIX"
    rewrite_bundle_id "$nested_root/Frameworks/WeChatAppEx Framework.framework/Versions/C/Helpers/WeChatAppEx Helper (Renderer).app/Contents/Info.plist" "com.tencent.flue.helper.renderer.$SANDBOX_SUFFIX"
    rewrite_bundle_id "$nested_root/Frameworks/WeChatAppEx Framework.framework/Versions/C/Helpers/WeApp.app/Contents/Info.plist" "com.tencent.flue.WeApp.$SANDBOX_SUFFIX"
    rewrite_bundle_id "$bundle/Contents/PlugIns/WeChatFileProviderExtension.appex/Contents/Info.plist" "$top_bundle_id.WeChatFileProviderExtension"
    rewrite_bundle_id "$bundle/Contents/PlugIns/WeChatMacShare.appex/Contents/Info.plist" "$top_bundle_id.WeChatMacShare"
}

render_plist() {
    # Args: template_path  output_path  script_path  log_path
    # Pure bash on purpose: /usr/bin/python3 is a CLT shim that pops a
    # Command Line Tools install dialog on machines without dev tools,
    # which would stall a one-click install.
    local template="$1" output="$2" script_path="$3" log_path="$4"
    local line
    : > "$output"
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line//__SCRIPT_PATH__/$script_path}"
        line="${line//__LOG_PATH__/$log_path}"
        printf '%s\n' "$line" >> "$output"
    done < "$template"
}

# lsregister -u needs the bundle to still exist on disk: pointing it at an
# already-deleted path fails with -10814 and leaves the stale record behind.
# So unregister BEFORE removing the directory, and register the fresh copy
# AFTER patching.
unregister_legacy_launch_services() {
    local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    "$lsregister" -u "$SANDBOX" >/dev/null 2>&1 || true
    "$lsregister" -u "$LEGACY_SANDBOX" >/dev/null 2>&1 || true
    "$lsregister" -u "$LEGACY_CLONE" >/dev/null 2>&1 || true
}

register_sandbox_launch_services() {
    local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    "$lsregister" -f "$SANDBOX" >/dev/null 2>&1 || true
}

cleanup_legacy_login_items() {
    osascript -e "
      tell application \"System Events\"
        try
          delete (every login item whose path is \"$LEGACY_SANDBOX\")
        end try
        try
          delete (every login item whose path is \"$LEGACY_CLONE\")
        end try
      end tell" >/dev/null 2>&1 || true
}

# --- preflight ----------------------------------------------------------------
if [ ! -d "$SYSTEM_SOURCE" ]; then
    echo "ERROR: $SYSTEM_SOURCE 不存在。请先从 App Store 或微信官网安装 WeChat 4.x。"
    exit 1
fi

mkdir -p "$LAUNCH_AGENTS_DIR" "$LOG_DIR" "$CACHE_DIR" "$MANAGED_DIR"
chmod +x "$UPDATER_SCRIPT" "$SANDBOX_SCRIPT"

echo "=== WeChat Sandbox Installer (one-click) ==="
echo

# --- auto-quit running sandbox WeChat (system WeChat NOT touched) -------------
RUNNING=()
for name in WeChat1 WeChat2; do
    if pgrep -x "$name" >/dev/null 2>&1; then
        RUNNING+=("$name")
    fi
done

if [ "${#RUNNING[@]}" -gt 0 ] && [ "$SKIP_AUTOQUIT" -eq 0 ]; then
    echo ">>> 检测到运行中的沙盒微信进程: ${RUNNING[*]}（本机 /Applications/WeChat.app 不受影响）"
    echo ">>> 10 秒后将强制退出沙盒。按 Ctrl-C 中止安装。"
    for i in 10 9 8 7 6 5 4 3 2 1; do
        printf "\r    倒计时: %2d 秒 " "$i"
        sleep 1
    done
    printf "\r    正在退出沙盒微信...    \n"
    pkill -TERM -x WeChat1 WeChat2 >/dev/null 2>&1 || true
    sleep 2
    pkill -9 -x WeChat1 WeChat2 >/dev/null 2>&1 || true
    sleep 1
fi

# --- rebuild the single sandbox copy ------------------------------------------
SYSTEM_VERSION="$(get_version "$SYSTEM_SOURCE")"

# Unregister FIRST: lsregister refuses to drop a record once the bundle is gone.
echo ">>> 注销旧沙盒在 Launch Services 的注册 ..."
unregister_legacy_launch_services
cleanup_legacy_login_items

if [ -d "$SANDBOX" ]; then
    echo ">>> 删除旧的 $SANDBOX ..."
    rm -rf "$SANDBOX"
fi
if [ -d "$LEGACY_SANDBOX" ]; then
    echo ">>> 删除历史遗留的 $LEGACY_SANDBOX ..."
    rm -rf "$LEGACY_SANDBOX"
fi
if [ -d "$LEGACY_CLONE" ]; then
    echo ">>> 删除历史遗留的 $LEGACY_CLONE ..."
    rm -rf "$LEGACY_CLONE"
fi

echo ">>> 复制 $SYSTEM_SOURCE → $SANDBOX  (约 30 秒)..."
cp -R "$SYSTEM_SOURCE" "$SANDBOX"

echo ">>> Patch 沙盒 → bundle=$SANDBOX_BUNDLE_ID / exec=$SANDBOX_EXECUTABLE / 显示名=$SANDBOX_DISPLAY_ZH ..."
patch_bundle "$SANDBOX" "$SANDBOX_BUNDLE_ID" "$SANDBOX_EXECUTABLE" "$SANDBOX_DISPLAY" "$SANDBOX_DISPLAY_ZH"

# Register the rebuilt bundle so Finder/Dock pick up the new display name.
register_sandbox_launch_services

# --- register background sync agent -------------------------------------------
if [ "$SKIP_AGENT_SETUP" -eq 0 ]; then
    echo ">>> 安装后台同步代理 (com.sillusion.wechat-dual-instance-updater) ..."
    render_plist "$UPDATER_TEMPLATE" "$UPDATER_AGENT" "$UPDATER_SCRIPT" "$LOG_DIR/launchd.log"
    launchctl bootout "gui/$(id -u)" "$UPDATER_AGENT" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$UPDATER_AGENT"
    launchctl kickstart "gui/$(id -u)/com.sillusion.wechat-dual-instance-updater" >/dev/null 2>&1 || true
fi

# --- register login auto-launch (launchd agent + System Settings login item) ---
if [ "$NO_AUTOSTART" -eq 0 ] && [ "$SKIP_AGENT_SETUP" -eq 0 ]; then
    echo ">>> 安装开机自启代理 (launchd) ..."
    render_plist "$AUTOLAUNCH_TEMPLATE" "$AUTOLAUNCH_AGENT" "$SANDBOX_SCRIPT" "$LOG_DIR/autolaunch.log"
    launchctl bootout "gui/$(id -u)" "$AUTOLAUNCH_AGENT" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$AUTOLAUNCH_AGENT"

    echo ">>> 注册到系统登录项 (System Settings → 登录项与扩展) ..."
    # Remove any previous entry first to avoid duplicates.
    osascript -e "
      tell application \"System Events\"
        try
          delete (every login item whose path is \"$SANDBOX\")
        end try
      end tell" >/dev/null 2>&1 || true
    osascript -e "
      tell application \"System Events\"
        make login item at end with properties {path:\"$SANDBOX\", hidden:false}
      end tell" 2>/dev/null && \
        echo "    已添加到系统登录项。" || \
        echo "    ⚠️  添加登录项失败（可能需要在 系统设置 → 隐私与安全性 → 自动化 里允许终端控制 System Events）。launchd 自启代理仍在生效，不影响开机自启。"
fi

# --- done ---------------------------------------------------------------------
echo
echo "=============== 部署完成 ==============="
echo "本机微信 (未改动):  $SYSTEM_SOURCE  ($SYSTEM_VERSION, com.tencent.xinWeChat, 显示名 微信)"
echo "沙盒微信:          $SANDBOX  ($(get_version "$SANDBOX"), $SANDBOX_BUNDLE_ID, 显示名 $SANDBOX_DISPLAY)"
if [ "$SKIP_AGENT_SETUP" -eq 0 ]; then
    echo "同步代理:          $UPDATER_AGENT"
    if [ "$NO_AUTOSTART" -eq 0 ]; then
        echo "自启代理:          $AUTOLAUNCH_AGENT (下次登录自动启动沙盒)"
    fi
fi
echo "日志目录:          $LOG_DIR/"
echo
echo "现在立即启动沙盒:   bash $SANDBOX_SCRIPT"
echo "本机微信照常用:     从 Dock / Spotlight 打开"
