# WeChat Sandbox for macOS

macOS 上的 **微信 4.x 双开** 工具 —— 一条命令完成部署，本机原版微信 + 一个沙盒副本，登录两个账号同时在线。

| 实例 | 显示名 | Bundle ID | 路径 | 启动方式 |
|---|---|---|---|---|
| 本机微信 | **微信** | `com.tencent.xinWeChat` | `/Applications/WeChat.app` | Dock / Spotlight 双击 |
| 沙盒微信 | **WeChat** | `com.tencent.xinWeChat2` | `~/Applications/WeChat.app` | 开机自启 / `wechat-sandbox.sh` |

沙盒副本独占自己的 sandbox container（`~/Library/Containers/com.tencent.xinWeChat2/`），与本机微信的登录态、聊天记录、文件完全互不可见。

后台代理监听 `/Applications/WeChat.app/Contents/Info.plist`，App Store 升级本机微信时自动同步沙盒副本，全程零网络请求、零 DMG 下载。

---

## ✨ 特性

- 🚀 **一键部署**：`bash install.sh` 完成所有事情
- 🌅 **开机自启**：登录 macOS 后自动启动沙盒微信（双重保障：launchd 代理 + 系统登录项，可在 `系统设置 → 通用 → 登录项与扩展` 看到并管理）
- 🔁 **自动同步升级**：App Store 升级本机微信时，沙盒副本自动同步到新版
- 🛡️ **完全隔离**：本机微信 + 沙盒微信各自独立 sandbox container
- 🌐 **零网络依赖**：脚本本身从不联网
- 🔒 **零 root 操作**：全程用户级权限，SIP 保持开启
- 🗑️ **一键卸载**：`bash uninstall.sh` 完整清理

---

## 📋 系统要求

| 项 | 要求 |
|---|---|
| 操作系统 | macOS 12 (Monterey) 及以上 |
| 微信 | WeChat 4.x，位于 `/Applications/WeChat.app`（App Store 或官方 DMG） |
| 磁盘空间 | 约 1.3 GB（沙盒副本） |
| 权限 | 普通用户，不需要 sudo |
| SIP | 可保持开启 |

---

## 🚀 一键部署

```bash
git clone https://github.com/sillusion2026/wechat-dual-instance.git
cd wechat-dual-instance
bash install.sh
```

仅此而已。`install.sh` 会自动：

1. 检测正在运行的**沙盒**微信进程（`WeChat1` / `WeChat2`），10 秒倒计时后强制退出（**本机 `/Applications/WeChat.app`（进程名 `WeChat`）不受影响**）
2. 删掉旧的 `~/Applications/WeChat.app`，如果有旧版遗留的 `~/Applications/WeChat2.app` 也一并清理
3. 从 `/Applications/WeChat.app` 完整复制到 `~/Applications/WeChat.app`，改 Bundle ID → `com.tencent.xinWeChat2`，改可执行文件 → `WeChat2`，改显示名 → `WeChat`，ad-hoc 重签名
4. 注册后台同步代理 `com.sillusion.wechat-dual-instance-updater`（监听本机微信升级）
5. 注册开机自启代理 `com.sillusion.wechat-dual-instance-autolaunch`（下次登录自动启动沙盒）

完成提示：

```
=============== 部署完成 ===============
本机微信 (未改动):  /Applications/WeChat.app  (4.1.8, com.tencent.xinWeChat, 显示名 微信)
沙盒微信:          ~/Applications/WeChat.app  (4.1.8, com.tencent.xinWeChat2, 显示名 WeChat)
同步代理:          ~/Library/LaunchAgents/com.sillusion.wechat-dual-instance-updater.plist
自启代理:          ~/Library/LaunchAgents/com.sillusion.wechat-dual-instance-autolaunch.plist
日志目录:          ~/.wechat-dual-instance/logs/
```

### 立即启动沙盒（不等下次登录）

```bash
bash wechat-sandbox.sh
```

首次启动需要扫码登录沙盒账号。之后每次开机自动启动，本机微信也照常从 Dock 启动。

沙盒启动后的输出示例：

```
>>> 沙盒微信已启动 (PID 30812)
```

如果沙盒已经在运行（比如自启代理已经拉起来了），再跑 `wechat-sandbox.sh` 不会重复启动，只是做一次同步状态检查。

---

## ⚙️ install.sh 可选参数

| 参数 | 作用 |
|---|---|
| `--no-autostart` | 不注册开机自启代理（仅装沙盒 + 同步代理） |
| `--skip-autoquit` | 跳过强制退出沙盒微信（适合沙盒已退出的场景） |
| `--skip-agent` | 不注册任何 launchd 代理（仅重建沙盒副本） |

---

## 🎯 日常使用

### 同时跑两个微信

| 想要的实例 | 启动方式 |
|---|---|
| 本机微信（主账号 / 显示名 "微信"） | 从 Dock 或 Spotlight 双击微信图标 |
| 沙盒微信（显示名 "WeChat"） | 开机自启已经拉起；或 `bash wechat-sandbox.sh`；或从 Finder 打开 `~/Applications/WeChat.app` |

### 把沙盒图标固定到 Dock

打开 Finder → `Cmd+Shift+G` → 输入 `~/Applications` → 把 `WeChat.app` 拖到 Dock。之后 Dock 上能看到 **WeChat** 图标，双击即用。

### 退出开机自启

两种方式任选其一：

**方式 A — 从系统设置关闭（推荐）：**

打开 `系统设置 → 通用 → 登录项与扩展`，找到 `WeChat`，点一下然后点 `-` 移除。

**方式 B — 命令行：**

```bash
launchctl bootout "gui/$(id -u)" ~/Library/LaunchAgents/com.sillusion.wechat-dual-instance-autolaunch.plist
rm ~/Library/LaunchAgents/com.sillusion.wechat-dual-instance-autolaunch.plist
osascript -e '
  tell application "System Events"
    try
      delete (every login item whose path is "'"$HOME"'/Applications/WeChat.app")
    end try
  end tell' 2>/dev/null
```

或重装时加 `--no-autostart`：
```bash
bash install.sh --no-autostart
```

### 重新启用自动启动

```bash
bash install.sh
```

---

## 🔄 自动升级机制

后台代理 `com.sillusion.wechat-dual-instance-updater` 持续守护：

```
App Store 静默升级 /Applications/WeChat.app   ← macOS 自动
   ↓
launchd WatchPaths 秒级触发                   ← 监听 /Applications/WeChat.app/Contents/Info.plist
   ↓
代理检查 system version > sandbox version
   ↓
等待沙盒微信 (WeChat2 进程) 退出 — 本机微信运行不阻塞同步
   ↓
自动重跑 install.sh --skip-agent --skip-autoquit → 重建沙盒副本
   ↓
下次启动即新版
```

三重触发器互为兜底：

| 触发器 | 频率 | 作用 |
|---|---|---|
| `WatchPaths` | 秒级 | 系统微信被升级时立即响应 |
| `StartInterval` | 1 小时 | 防 WatchPaths 偶发失活 |
| `RunAtLoad` | 登录时一次 | 长时间关机后开机自检 |

### 手动查看同步状态

```bash
cat ~/.wechat-dual-instance/state.env
```

返回示例：
```
LAST_CHECK_TS=1782714632
SYSTEM_VERSION=4.1.8
MANAGED_VERSION=4.1.8
LAST_RESULT=up_to_date
```

`LAST_RESULT` 可能值：

| 值 | 含义 |
|---|---|
| `up_to_date` | 系统和沙盒版本一致 |
| `sync_needed` | 检测到差异，等沙盒退出后同步 |
| `postponed_running` | 沙盒在跑，已推迟 |
| `synced` | 刚完成一次同步 |
| `system_missing` | `/Applications/WeChat.app` 不存在 |

### 手动立即触发一次同步

```bash
launchctl kickstart -k gui/$(id -u)/com.sillusion.wechat-dual-instance-updater
```

或前台运行看完整日志：

```bash
bash wechat-auto-update.sh
```

仅检查不执行（dry-run）：

```bash
bash wechat-auto-update.sh --check-only
cat ~/.wechat-dual-instance/state.env   # 查看结果
```

### 看日志

```bash
tail -f ~/.wechat-dual-instance/logs/update.log       # 同步代理日志
tail -f ~/.wechat-dual-instance/logs/autolaunch.log   # 开机自启日志
```

---

## 🗑️ 卸载

```bash
bash uninstall.sh
```

会清理：

- `~/Applications/WeChat.app`（沙盒副本）
- `~/Applications/WeChat2.app`（历史遗留，如果存在）
- `~/Library/Containers/com.tencent.xinWeChat2`（沙盒数据）
- `~/Library/Containers/com.tencent.xinWeChat1`（历史遗留，如果存在）
- 两个 launchd 代理（`com.sillusion.wechat-dual-instance-updater` + `com.sillusion.wechat-dual-instance-autolaunch`）
- `~/.wechat-dual-instance/` 状态目录

**完全不动** `/Applications/WeChat.app` 与主账号 `com.tencent.xinWeChat` 容器。

---

## 🔧 故障排查

### 沙盒没启动

```bash
ps -axo pid,command | grep -E '/WeChat2( |$)' | grep -v grep | grep -v Helper
```

期望看到一行 `~/Applications/WeChat.app/Contents/MacOS/WeChat2`。如果没有：
```bash
tail -50 ~/.wechat-dual-instance/logs/update.log
bash install.sh
```

### 开机后没自动启动沙盒

```bash
launchctl list | grep wechat-dual
```

应该看到两行：
```
<PID>  <Exit>  com.sillusion.wechat-dual-instance-updater
<PID>  <Exit>  com.sillusion.wechat-dual-instance-autolaunch
```

如果缺失某行：
```bash
bash install.sh
```

如果 ExitCode ≠ 0，看日志：
```bash
cat ~/.wechat-dual-instance/logs/autolaunch.log
```

### 沙盒微信里小程序打不开

ad-hoc 签名移除部分 entitlements，部分小程序异常。在本机微信使用即可。

### App Store 升级了但沙盒没更新

确认沙盒已退出（同步代理会推迟到沙盒进程消失）：
```bash
pkill -x WeChat2
```
等几秒，代理自动触发；或手动：
```bash
launchctl kickstart -k gui/$(id -u)/com.sillusion.wechat-dual-instance-updater
```

---

## 🧬 工作原理

WeChat 4.x 通过 `CFBundleIdentifier` 检测"是否存在同款实例"。本工具让沙盒副本有不同的 Bundle ID：

1. 把 `/Applications/WeChat.app` 完整复制一份到 `~/Applications/WeChat.app`
2. 改写副本的 `CFBundleIdentifier` 为 `com.tencent.xinWeChat2`（与本机的 `com.tencent.xinWeChat` 不同）
3. 改写 `CFBundleExecutable` 为 `WeChat2`（防止微信通过进程名检测）
4. 改写 `CFBundleDisplayName` 为 `WeChat`（Dock/Finder 显示用）
5. 移除原 Tencent 签名，重新做 ad-hoc 签名
6. macOS 看到两个不同 Bundle ID 的安装，自动分别分配 sandbox container

```
+---------------------------+    cp -R + patch + sign    +-------------------------+
| /Applications/WeChat.app  | --------------------------> | ~/Applications/WeChat.app|
| com.tencent.xinWeChat     |                             | com.tencent.xinWeChat2  |
| Dock 显示：微信            |                             | Dock 显示：WeChat        |
| 进程名：WeChat             |                             | 进程名：WeChat2         |
+---------------------------+                             +-------------------------+
        |
        | (Info.plist 变化 → WatchPaths 秒级触发)
        +--> wechat-auto-update.sh --> 重新同步沙盒
```

---

## 📁 文件结构

| 文件 | 作用 |
|---|---|
| `install.sh` | 一键部署：复制 + patch + 注册两个 launchd 代理 |
| `wechat-sandbox.sh` | 启动沙盒微信 + 唤起同步检查 |
| `wechat-auto-update.sh` | 后台同步代理：本机微信变化时调用 install.sh 重建沙盒 |
| `com.sillusion.wechat-dual-instance-updater.plist.template` | 同步代理 launchd 配置（RunAtLoad + 1h + WatchPaths） |
| `com.sillusion.wechat-dual-instance-autolaunch.plist.template` | 开机自启代理 launchd 配置（RunAtLoad） |
| `uninstall.sh` | 完全清理 |

---

## 🔐 安全说明

- 不修改系统目录：仅写入 `~/Applications/`、`~/Library/`、`~/.wechat-dual-instance/`
- 不需要 sudo
- 不联网：脚本本身从不发起任何网络请求
- 仅对沙盒副本做 ad-hoc 重签名，本机微信签名链完整保留
- 可审计：所有逻辑约 300 行 shell 脚本

---

## ⚠️ 已知限制

| 限制 | 说明 |
|---|---|
| 沙盒里部分小程序无法运行 | ad-hoc 签名移除了某些 entitlements，在本机微信使用即可 |
| 仅支持 1 个沙盒 | 如需更多沙盒，可手动复制 install.sh 修改 bundle id 再 patch 一份 |
| 不支持微信 3.x | Bundle ID 检测逻辑不同，请升级 4.x |

---

## 📝 许可

本项目仅供个人学习与日常多账号管理使用。不得用于商业用途，与腾讯公司无关。
