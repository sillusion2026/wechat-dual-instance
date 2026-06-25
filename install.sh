#!/bin/bash
# One-time setup: clone WeChat.app, change its bundle ID, and re-sign.
# After this, wechat-sandbox.sh can launch both instances side by side.
set -e

ORIGINAL="/Applications/WeChat.app"
CLONE="/Applications/WeChat2.app"

if [ ! -d "$ORIGINAL" ]; then
    echo "ERROR: $ORIGINAL not found. Install WeChat first."
    exit 1
fi

echo "=== WeChat Dual-Instance Installer ==="
echo

# ── 1) Clone the .app bundle ──────────────────────────────────────────
if [ -d "$CLONE" ]; then
    echo ">>> Removing existing $CLONE ..."
    rm -rf "$CLONE"
fi

echo ">>> Copying $ORIGINAL → $CLONE  (this takes ~30 seconds) ..."
cp -R "$ORIGINAL" "$CLONE"

# ── 2) Rename executable (avoids process-name-based detection) ────────
PLIST="$CLONE/Contents/Info.plist"
echo ">>> Renaming executable WeChat → WeChat2 ..."
mv "$CLONE/Contents/MacOS/WeChat" "$CLONE/Contents/MacOS/WeChat2"

# ── 3) Rewrite bundle identity ────────────────────────────────────────
echo ">>> Patching bundle ID ..."
plutil -replace CFBundleIdentifier   -string "com.tencent.xinWeChat2" "$PLIST"
plutil -replace CFBundleExecutable   -string "WeChat2"                "$PLIST"
plutil -replace CFBundleDisplayName  -string "WeChat2"                "$PLIST"
plutil -replace CFBundleName         -string "WeChat2"                "$PLIST"
plutil -replace CFBundleGetInfoString -string "WeChat2"               "$PLIST"

# ── 4) Strip original signature, re-sign ad-hoc ───────────────────────
echo ">>> Removing original signature ..."
codesign --remove-signature "$CLONE" 2>/dev/null || true

echo ">>> Re-signing with ad-hoc identity ..."
codesign --force --deep -s - "$CLONE" 2>/dev/null

# ── 5) Verify ─────────────────────────────────────────────────────────
echo
echo "=== Done ==="
echo "Verified bundle ID: $(plutil -p "$PLIST" | grep CFBundleIdentifier | awk -F'"' '{print $4}')"
echo "Disk usage:         $(du -sh "$CLONE" | awk '{print $1}')"
echo
echo "Now run:  bash $(dirname "$0")/wechat-sandbox.sh"
