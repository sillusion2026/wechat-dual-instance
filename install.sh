#!/bin/bash
# Setup WeChat1.app + WeChat2.app and register a launchd sync agent.
# Both managed copies get distinct bundle IDs so neither collides with the
# system /Applications/WeChat.app under LaunchServices.
set -euo pipefail

SYSTEM_SOURCE="/Applications/WeChat.app"
MANAGED_DIR="$HOME/Applications"
ORIGINAL="$MANAGED_DIR/WeChat.app"
CLONE="$MANAGED_DIR/WeChat2.app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATER_SCRIPT="$SCRIPT_DIR/wechat-auto-update.sh"
PLIST_TEMPLATE="$SCRIPT_DIR/com.sillusion.wechat-dual-instance-updater.plist.template"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT="$LAUNCH_AGENTS_DIR/com.sillusion.wechat-dual-instance-updater.plist"
STATE_DIR="$HOME/.wechat-dual-instance"
LOG_DIR="$STATE_DIR/logs"

ORIG_PLIST="$ORIGINAL/Contents/Info.plist"
CLONE_PLIST="$CLONE/Contents/Info.plist"

SKIP_AGENT_SETUP=0
if [ "${1:-}" = "--skip-agent" ]; then
    SKIP_AGENT_SETUP=1
fi

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

if [ ! -d "$SYSTEM_SOURCE" ]; then
    echo "ERROR: $SYSTEM_SOURCE not found. Install WeChat from the App Store or official DMG first."
    exit 1
fi

mkdir -p "$LAUNCH_AGENTS_DIR" "$LOG_DIR" "$MANAGED_DIR"
chmod +x "$UPDATER_SCRIPT"

echo "=== WeChat Dual-Instance Installer ==="
echo

SYSTEM_VERSION="$(get_version "$SYSTEM_SOURCE")"
MANAGED_VERSION="$(get_version "$ORIGINAL")"

# Always rebuild both managed copies from the virgin system bundle so we
# never carry forward stale patches or signatures from a previous install.
if [ -d "$ORIGINAL" ]; then
    echo ">>> Removing existing $ORIGINAL ..."
    rm -rf "$ORIGINAL"
fi
if [ -d "$CLONE" ]; then
    echo ">>> Removing existing $CLONE ..."
    rm -rf "$CLONE"
fi

echo ">>> Copying $SYSTEM_SOURCE → $ORIGINAL  (~30s) ..."
cp -R "$SYSTEM_SOURCE" "$ORIGINAL"

echo ">>> Copying $SYSTEM_SOURCE → $CLONE     (~30s) ..."
cp -R "$SYSTEM_SOURCE" "$CLONE"

echo ">>> Patching $ORIGINAL → com.tencent.xinWeChat1 / WeChat1 ..."
patch_bundle "$ORIGINAL" "com.tencent.xinWeChat1" "WeChat1" "WeChat1"

echo ">>> Patching $CLONE    → com.tencent.xinWeChat2 / WeChat2 ..."
patch_bundle "$CLONE"    "com.tencent.xinWeChat2" "WeChat2" "WeChat2"

if [ "$SKIP_AGENT_SETUP" -eq 0 ]; then
    echo ">>> Installing background sync agent ..."
    python3 - "$PLIST_TEMPLATE" "$LAUNCH_AGENT" "$UPDATER_SCRIPT" "$LOG_DIR/launchd.log" <<'PY'
from pathlib import Path
import sys

template_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
script_path = sys.argv[3]
log_path = sys.argv[4]

content = template_path.read_text()
content = content.replace("__SCRIPT_PATH__", script_path)
content = content.replace("__LOG_PATH__", log_path)
output_path.write_text(content)
PY

    launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT"
    launchctl kickstart "gui/$(id -u)/com.sillusion.wechat-dual-instance-updater" >/dev/null 2>&1 || true
fi

echo
echo "=== Done ==="
echo "System (untouched):   $SYSTEM_SOURCE  ($SYSTEM_VERSION, com.tencent.xinWeChat)"
echo "Managed instance 1:   $ORIGINAL  ($(get_version "$ORIGINAL"), com.tencent.xinWeChat1)"
echo "Managed instance 2:   $CLONE     ($(get_version "$CLONE"), com.tencent.xinWeChat2)"
if [ "$SKIP_AGENT_SETUP" -eq 0 ]; then
    echo "LaunchAgent:          $LAUNCH_AGENT"
fi
echo "Sync log:             $LOG_DIR/update.log"
echo
echo "Now run:  bash $SCRIPT_DIR/wechat-sandbox.sh"
