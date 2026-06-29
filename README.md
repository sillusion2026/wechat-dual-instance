# WeChat Dual Instance for macOS

macOS 上的 **微信 4.x 一键双开** 工具。一条命令完成：复制两份微信副本、改 Bundle ID、ad-hoc 签名、注册后台同步、注册开机自启。再不必每次手动启动。

| 实例 | 显示名 | Bundle ID | 路径 |
|---|---|---|---|
| 1 | **WeChat** | `com.tencent.xinWeChat1` | `~/Applications/WeChat.app` |
| 2 | **微信2** | `com.tencent.xinWeChat2` | `~/Applications/WeChat2.app` |

每个实例独占 sandbox container，登录态、聊天记录、文件完全隔离。后台代理监听 `/Applications/WeChat.app/Contents/Info.plist`，App Store 升级系统微信时自动把两份副本也同步到新版，全程零网络请求。

---

## ✨ 特性

- 🚀 **一键部署**：`bash install.sh` 完成所有事情（含自动退出运行中的微信）
- 🌅 **开机自启**：登录 macOS 后自动同时启动 `WeChat` + `微信2`
- 🔁 **自动同步升级**：App Store 升级系统微信后秒级响应，自动 patch 重建两份副本
- 🛡️ **完全隔离**：两个独立的 sandbox container，互不可见对方数据
- 🌐 **零网络依赖**：脚本不联网、不下载、不解析任何官网页面
- 🔒 **零 root 操作**：全程用户级权限，SIP 保持开启
- 🗑️ **一键卸载**：`bash uninstall.sh` 完整清理

---

## 📋 系统要求

| 项 | 要求 |
|---|---|
| 操作系统 | macOS 12 (Monterey) 及以上 |
| 微信 | WeChat 4.x，位于 `/Applications/WeChat.app`（App Store 或官方 DMG 均可） |
| 磁盘空间 | 约 2.6 GB（两份副本） |
| 权限 | 普通用户，不需要 sudo |
| SIP | 可保持开启 |

---

## 🚀 一键部署

```bash
# 1. 克隆仓库
git clone https://github.com/sillusion2026/wechat-dual-instance.git
cd wechat-dual-instance

# 2. 一键安装（约 60–90 秒）
bash install.sh
```

仅此而已。`install.sh` 会自动：

1. 检测正在运行的微信，10 秒倒计时后强制退出（Ctrl-C 可中止）
2. 从 `/Applications/WeChat.app` 复制两份到 `~/Applications/` 并 patch 成独立身份
3. 注册后台同步代理（监听系统微信升级）
4. 注册开机自启代理（下次登录起自动启动两个实例）

完成提示：

```
=============== 部署完成 ===============
系统微信 (未改动):  /Applications/WeChat.app  (4.1.8, com.tencent.xinWeChat)
实例 1 (主):       ~/Applications/WeChat.app  (4.1.8, com.tencent.xinWeChat1, 显示名 WeChat)
实例 2 (副):       ~/Applications/WeChat2.app (4.1.8, com.tencent.xinWeChat2, 显示名 微信2)
同步代理:          ~/Library/LaunchAgents/com.sillusion.wechat-dual-instance-updater.plist
自启代理:          ~/Library/LaunchAgents/com.sillusion.wechat-dual-instance-autolaunch.plist
日志目录:          ~/.wechat-dual-instance/logs/
```

### 立即启动（不等下次登录）

```bash
bash wechat-sandbox.sh
```

首次启动时分别扫码登录两个账号即可。之后每次开机都会自动启动。

---

## ⚙️ install.sh 可选参数

| 参数 | 作用 |
|---|---|
| `--no-autostart` | 不注册开机自启代理（只装双开 + 同步代理） |
| `--skip-autoquit` | 跳过强制退出微信的步骤（适合微信已经退出的场景） |
| `--skip-agent` | 不注册任何 launchd 代理（仅重建两份副本） |

示例：装双开但不要开机自启：
```bash
bash install.sh --no-autostart
```

---

## 🎯 日常使用

### 想立即看到两个微信窗口

```bash
bash wechat-sandbox.sh
```

或：从 Finder 打开 `~/Applications/`，双击 `WeChat.app` 和 `WeChat2.app`。

### 把图标固定到 Dock

打开 Finder → `Cmd+Shift+G` → 输入 `~/Applications` → 把 `WeChat.app` 和 `WeChat2.app` 拖到 Dock。之后 Dock 上能看到 **WeChat** 和 **微信2** 两个图标，双击即用。

### 想退出自动启动

```bash
launchctl bootout "gui/$(id -u)" ~/Library/LaunchAgents/com.sillusion.wechat-dual-instance-autolaunch.plist
rm ~/Library/LaunchAgents/com.sillusion.wechat-dual-instance-autolaunch.plist
```

或者重装时加 `--no-autostart`：
```bash
bash install.sh --no-autostart
```

### 想再次启用自动启动

```bash
bash install.sh
```

---

## 🔄 自动升级机制

后台代理 `com.sillusion.wechat-dual-instance-updater` 会持续守护：

```
App Store 静默升级 /Applications/WeChat.app   ← macOS 自动
   ↓
launchd WatchPaths 秒级触发                   ← 监听系统微信 Info.plist
   ↓
代理检查 system version > managed version
   ↓
等待 WeChat 与 微信2 都退出
   ↓
自动重跑 install.sh --skip-agent 重建两份副本
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
LAST_CHECK_TS=1782711193
SYSTEM_VERSION=4.1.8
MANAGED_VERSION=4.1.8
CLONE_VERSION=4.1.8
LAST_RESULT=up_to_date
```

`LAST_RESULT` 可能值：

| 值 | 含义 |
|---|---|
| `up_to_date` | 三个版本一致，无需同步 |
| `sync_needed` / `clone_rebuild_needed` | 检测到差异，等微信退出后同步 |
| `postponed_running` | 实例在跑，已推迟 |
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

- `~/Applications/WeChat.app`、`~/Applications/WeChat2.app`
- `~/Library/Containers/com.tencent.xinWeChat1`、`~/Library/Containers/com.tencent.xinWeChat2`
- 两个 launchd 代理（同步 + 自启）
- `~/.wechat-dual-instance/` 状态目录

**完全不动**系统 `/Applications/WeChat.app` 和主账号 `com.tencent.xinWeChat` 容器。

---

## 🔧 故障排查

### 启动后只看到一个微信窗口

排查正在运行的进程：
```bash
ps -axo pid,command | grep -E '/(WeChat1|WeChat2)( |$)' | grep -v grep | grep -v Helper
```

期望看到两行（PID 不同）。如果只有一行，可能：
- 某个实例没启起来：`tail -50 ~/.wechat-dual-instance/logs/update.log`
- 强制重装：`bash install.sh`

### 开机后没有自动启动

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

### 小程序打不开

ad-hoc 签名移除部分 entitlements，部分小程序异常。在系统微信里使用即可，受影响仅限管理副本。

### App Store 升级了但管理副本没更新

确认两个管理副本都已退出（同步代理会推迟到它们完全退出）：
```bash
pkill -x WeChat1 WeChat2
```
等几秒，代理会自动触发；或手动 kickstart：
```bash
launchctl kickstart -k gui/$(id -u)/com.sillusion.wechat-dual-instance-updater
```

---

## 🧬 工作原理

WeChat 4.x 通过 `CFBundleIdentifier` 判断"是否已存在同款实例"。本工具让两份副本各自有独立的 Bundle ID：

1. 把 `/Applications/WeChat.app` 完整复制到 `~/Applications/` 下两份
2. 改写每份的 `CFBundleIdentifier`、`CFBundleExecutable`、`CFBundleDisplayName`
3. 移除原 Tencent 签名，重新做 ad-hoc 签名
4. macOS 看到三个不同 Bundle ID（系统版 + 实例 1 + 实例 2），分别分配独立 sandbox

```
+---------------------------+    cp -R + patch + sign    +----------------------------+
| /Applications/WeChat.app  | --------------------------> | ~/Applications/WeChat.app  |
| com.tencent.xinWeChat     |                             | com.tencent.xinWeChat1     |
| 由 App Store 升级          |                             | 显示名 WeChat              |
+---------------------------+                             +----------------------------+
        |
        | (Info.plist 变化 → WatchPaths 秒级触发)         +----------------------------+
        +--> wechat-auto-update.sh --skip-agent ------>  | ~/Applications/WeChat2.app |
                                                         | com.tencent.xinWeChat2     |
                                                         | 显示名 微信2                |
                                                         +----------------------------+
```

---

## 📁 文件结构

| 文件 | 作用 |
|---|---|
| `install.sh` | 一键部署：复制 + patch + 注册两个 launchd 代理 |
| `wechat-sandbox.sh` | 启动 WeChat + 微信2，同时唤起同步检查 |
| `wechat-auto-update.sh` | 后台同步代理：系统微信变化时调用 install.sh 重建副本 |
| `com.sillusion.wechat-dual-instance-updater.plist.template` | 同步代理 launchd 配置（RunAtLoad + 1h + WatchPaths） |
| `com.sillusion.wechat-dual-instance-autolaunch.plist.template` | 开机自启代理 launchd 配置（RunAtLoad） |
| `uninstall.sh` | 完全清理 |

---

## 🔐 安全说明

- 不修改系统目录：仅写入 `~/Applications/`、`~/Library/`、`~/.wechat-dual-instance/`
- 不需要 sudo
- 不联网：脚本本身从不发起任何网络请求
- 仅对自己的副本做 ad-hoc 重签名，系统微信签名链完整保留
- 可审计：所有逻辑约 350 行 shell 脚本

---

## ⚠️ 已知限制

| 限制 | 说明 |
|---|---|
| 部分小程序无法运行 | ad-hoc 签名移除了某些 entitlements，在系统微信使用即可 |
| 仅支持 2 个实例 | 如需更多，可手动复制 install.sh 修改 patch 一份 WeChat3 |
| 不支持微信 3.x | Bundle ID 检测逻辑不同，请升级 4.x |

---

## 📝 许可

本项目仅供个人学习与日常多账号管理使用。不得用于商业用途，与腾讯公司无关。
