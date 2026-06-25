#!/bin/bash
# WeChat 4.x dual-instance launcher
# Relies on a bundle-ID-cloned WeChat2.app created by install.sh
set -e

ORIGINAL="/Applications/WeChat.app"
CLONE="/Applications/WeChat2.app"

if [ ! -d "$CLONE" ]; then
    echo "ERROR: $CLONE not found."
    echo "Run install.sh first to create the isolated clone."
    exit 1
fi

CLONE_AGE=$(stat -f %m "$CLONE" 2>/dev/null)
ORIG_AGE=$(stat -f %m "$ORIGINAL" 2>/dev/null)
if [ "$CLONE_AGE" -lt "$ORIG_AGE" ] 2>/dev/null; then
    echo "WARNING: $ORIGINAL is newer than $CLONE."
    echo "The clone may be out of date. Re-run install.sh to refresh."
    echo
fi

open "$CLONE"
sleep 3

COUNT=$(pgrep -x 'WeChat|WeChat2' 2>/dev/null | wc -l | tr -d ' ')
echo ">>> $COUNT WeChat instance(s) running."
if [ "$COUNT" -ge 2 ]; then
    echo ">>> Scan the QR code on the new window to log into your second account."
else
    echo ">>> Second instance may have failed to start. Re-run install.sh to refresh the clone."
fi
