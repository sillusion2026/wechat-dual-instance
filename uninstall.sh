#!/bin/bash
# Remove the cloned WeChat and all its data
set -e

CLONE="/Applications/WeChat2.app"
CONTAINER="$HOME/Library/Containers/com.tencent.xinWeChat2"

echo "=== WeChat Dual-Instance Uninstaller ==="
echo

if [ -d "$CLONE" ]; then
    echo ">>> Removing $CLONE ..."
    rm -rf "$CLONE"
    echo "    Done."
else
    echo "    $CLONE not present, skipping."
fi

if [ -d "$CONTAINER" ]; then
    echo ">>> Removing $CONTAINER ..."
    rm -rf "$CONTAINER" 2>/dev/null || {
        echo "    Container is protected by macOS. Trying with Finder ..."
        osascript -e "tell application \"Finder\" to delete POSIX file \"$CONTAINER\"" 2>/dev/null || true
    }
    echo "    Done."
else
    echo "    $CONTAINER not present, skipping."
fi

echo
echo "=== Uninstall complete ==="
echo "Your original /Applications/WeChat.app and its data are untouched."
