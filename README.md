# WeChat Dual Instance for macOS

A multi-instance launcher for **WeChat 4.x on macOS**. It creates an isolated clone of `WeChat.app`, changes the clone's bundle identity, and lets the original WeChat and the cloned WeChat run side by side with separate data containers.

## How It Works

WeChat 4.x checks the app Bundle ID to detect an existing instance. This setup avoids that single-instance check by:

1. Copying `/Applications/WeChat.app` to `/Applications/WeChat2.app`
2. Changing the clone's `CFBundleIdentifier` to `com.tencent.xinWeChat2`
3. Removing the original signature and re-signing the clone with an ad-hoc signature
4. Letting macOS assign a separate sandbox container to the cloned Bundle ID

The two WeChat instances do not share login sessions or local data.

## Quick Start

```bash
# 1. First-time setup. Takes about 30 seconds and requires about 1.3 GB of disk space.
bash install.sh

# 2. Launch the second WeChat instance.
bash wechat-sandbox.sh
```

After the new window appears, scan the QR code to log into the second WeChat account.

**Note**: When the original WeChat app is updated, the clone is not updated automatically. Re-run `install.sh` to refresh the clone.

## Files

| File | Purpose |
|---|---|
| `install.sh` | First-time setup: clones `WeChat.app`, changes the Bundle ID, and re-signs the clone |
| `wechat-sandbox.sh` | Daily launcher: starts the second WeChat instance |
| `uninstall.sh` | Full cleanup: removes the clone and its associated data |

## Uninstall

```bash
bash uninstall.sh
```

The original `/Applications/WeChat.app` and its data are not changed.

## Notes

- **Mini Programs may be limited**: ad-hoc signing removes some entitlements, so certain WeChat Mini Programs may not work normally.
- **Manual refresh after WeChat updates**: the clone stays on the old version until `install.sh` is run again.
- **Data is fully isolated**: each instance has its own login session and local data.
- **Two instances by default**: to run more than two instances, create additional clones with different Bundle IDs.

## Requirements

- macOS
- WeChat 4.x, either the App Store version or the official DMG version
- SIP can remain enabled
