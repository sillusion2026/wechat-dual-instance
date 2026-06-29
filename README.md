# WeChat Dual Instance for macOS

macOS 上的 **微信 4.x 双开/三开** 工具。通过为每个副本分配独立的 Bundle ID 与可执行文件名，绕开 macOS LaunchServices 的"单实例"路由，让你同时跑多个互不干扰的微信账号。

附带一个 launchd 后台代理：**App Store 升级系统微信时，自动把两份用户级副本也同步到新版**，全程无网络请求、无 DMG 下载、无需手动操作。

---

## ✨ 核心特性

- 🔀 **真双开/三开**：系统微信 + WeChat1 + WeChat2 三个独立账号同时在线
- 🛡️ **完全隔离**：每个实例独占一个 sandbox container，登录态、聊天记录、文件互不可见
- 🔁 **自动同步升级**：App Store 推新版后，秒级监听 + 1 小时兜底，自动 patch 重建两份副本
- 🌐 **零网络依赖**：不联网、不下载、不解析任何官网页面
- 🔒 **零 root 操作**：全部操作在用户目录内完成，SIP 保持开启
- 🔁 **可一键卸载**：`bash uninstall.sh` 完整清理

---

## 📋 系统要求

| 项 | 要求 |
|---|---|
| 操作系统 | macOS 12 (Monterey) 及以上 |
| 微信版本 | WeChat 4.x（App Store 或官方 DMG 均可） |
| 系统微信位置 | 必须位于 `/Applications/WeChat.app` |
| 磁盘空间 | 约 2.6 GB（两份微信副本） |
| 权限 | 普通用户即可，不需要 sudo |
| SIP | 可保持开启 |

---

## 🚀 快速开始

### 1. 克隆仓库

```bash
git clone https://github.com/sillusion2026/wechat-dual-instance.git
cd wechat-dual-instance
```

### 2. 首次安装（约 60–90 秒）

```bash
bash install.sh
```

安装过程会：
1. 从 `/Applications/WeChat.app` 复制两份到 `~/Applications/WeChat.app` 和 `~/Applications/WeChat2.app`
2. 给每份分别打上独立的 Bundle ID（`com.tencent.xinWeChat1` / `com.tencent.xinWeChat2`）和可执行文件名（`WeChat1` / `WeChat2`）
3. 用 ad-hoc 签名重新签名
4. 注册 launchd 后台同步代理 `com.sillusion.wechat-dual-instance-updater`

安装完成后你会看到：

```
=== Done ===
System (untouched):   /Applications/WeChat.app  (4.1.8, com.tencent.xinWeChat)
Managed instance 1:   ~/Applications/WeChat.app  (4.1.8, com.tencent.xinWeChat1)
Managed instance 2:   ~/Applications/WeChat2.app (4.1.8, com.tencent.xinWeChat2)
LaunchAgent:          ~/Library/LaunchAgents/com.sillusion.wechat-dual-instance-updater.plist
```

### 3. 启动双开

```bash
bash wechat-sandbox.sh
```

会同时启动 `WeChat1` 和 `WeChat2` 两个独立实例。首次启动时需要**分别扫码登录**两个账号。

---

## 🎯 日常使用

### 三个实例怎么启动

| 想跑哪个 | 启动方式 |
|---|---|
| 系统微信（主账号） | 从 Dock / Spotlight / Launchpad 双击微信图标，或 `open /Applications/WeChat.app` |
| WeChat1 + WeChat2 | `bash ~/wechat-dual-instance/wechat-sandbox.sh` |
| 想全开 3 个 | 先 `wechat-sandbox.sh` 启动 1 和 2，再从 Dock 打开系统微信 |

三者**任意组合都可以同时跑**。

### 把 WeChat1 / WeChat2 加到 Dock

打开 Finder → 前往文件夹 → 输入 `~/Applications` → 把 `WeChat.app` 和 `WeChat2.app` 拖到 Dock。之后双击 Dock 图标即可启动，不必每次都跑命令。

⚠️ **注意**：拖入 Dock 的 `~/Applications/WeChat.app`（实例 1）在 Dock 上显示名字可能是 `WeChat1`。

---

## 🔄 自动升级（你完全无需操心）

后台代理 `com.sillusion.wechat-dual-instance-updater` 会自动处理升级：

```
App Store 静默升级 /Applications/WeChat.app  （macOS 自动）
   ↓
launchd WatchPaths 秒级触发 (监听 /Applications/WeChat.app/Contents/Info.plist)
   ↓
代理检查：system version > managed version ?
   ↓
等待 WeChat1 + WeChat2 都退出
   ↓
自动重跑 install.sh --skip-agent → 重建两份副本 + 重签名
   ↓
下次启动即新版
```

三个触发器一起兜底：

| 触发器 | 频率 | 用途 |
|---|---|---|
| `WatchPaths` | 秒级 | 系统微信被升级时立即响应 |
| `StartInterval` | 1 小时 | 防 WatchPaths 偶发失活 |
| `RunAtLoad` | 登录时一次 | 长时间关机后开机自检 |

### 手动查看同步状态

```bash
cat ~/.wechat-dual-instance/state.env
```

返回类似：
```
LAST_CHECK_TS=1782711193
SYSTEM_VERSION=4.1.8
MANAGED_VERSION=4.1.8
CLONE_VERSION=4.1.8
LAST_RESULT=up_to_date
```

可能的 `LAST_RESULT` 值：
- `up_to_date` — 三个版本一致，无需同步
- `sync_needed` / `clone_rebuild_needed` — 检测到差异，等微信退出后同步
- `postponed_running` — 管理实例正在运行，已推迟
- `synced` — 刚刚完成一次同步
- `system_missing` — `/Applications/WeChat.app` 不存在

### 手动立即触发一次同步

```bash
launchctl kickstart -k gui/$(id -u)/com.sillusion.wechat-dual-instance-updater
```

或前台运行查看完整日志：

```bash
bash ~/wechat-dual-instance/wechat-auto-update.sh
```

### 查看同步日志

```bash
tail -f ~/.wechat-dual-instance/logs/update.log
```

---

## 🗑️ 卸载

```bash
bash uninstall.sh
```

会清理：
- `~/Applications/WeChat.app`（管理副本 1）
- `~/Applications/WeChat2.app`（管理副本 2）
- `~/Library/Containers/com.tencent.xinWeChat1`（实例 1 的数据）
- `~/Library/Containers/com.tencent.xinWeChat2`（实例 2 的数据）
- `~/Library/LaunchAgents/com.sillusion.wechat-dual-instance-updater.plist`（后台代理）
- `~/.wechat-dual-instance/`（日志和状态目录）

**完全不会动**系统的 `/Applications/WeChat.app` 和主账号 `com.tencent.xinWeChat` 容器。

---

## 🔧 故障排查

### 启动后只看到一个微信窗口

最常见原因：你把系统微信和某个管理副本同时打开了，且它们 Bundle ID 冲突。

排查：
```bash
ps -axo pid,command | grep -E '/(WeChat|WeChat1|WeChat2)( |$)' | grep -v grep | grep -v Helper
```

如果只看到一行进程，说明某个实例没启起来。检查日志：
```bash
tail -50 ~/.wechat-dual-instance/logs/update.log
```

强制重装（会保留 WeChat2 登录态）：
```bash
osascript -e 'tell application "WeChat" to quit' 2>/dev/null
pkill -9 -x WeChat WeChat1 WeChat2 2>/dev/null
bash install.sh
```

### 小程序打不开

ad-hoc 签名会移除部分 entitlements，部分小程序（尤其是依赖 WeChat 官方授权的）会异常。在系统微信里使用这些小程序即可，受影响的只是管理副本。

### 后台代理状态查询

```bash
launchctl list | grep wechat-dual
```

输出格式：`<PID> <ExitCode> com.sillusion.wechat-dual-instance-updater`
- PID 为数字：已加载并跑过一次
- ExitCode = 0：上次正常退出
- ExitCode ≠ 0：上次有问题，查 `~/.wechat-dual-instance/logs/update.log`

重新加载代理：
```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.sillusion.wechat-dual-instance-updater.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.sillusion.wechat-dual-instance-updater.plist
```

---

## 🧬 工作原理（技术细节）

WeChat 4.x 通过 `CFBundleIdentifier` 检测"已存在的同款 App"以拒绝二次启动。本工具的做法：

1. 把 `/Applications/WeChat.app` 完整复制到 `~/Applications/` 下两份
2. **每份的 `CFBundleIdentifier` 改成不同值**（`com.tencent.xinWeChat1` / `com.tencent.xinWeChat2`），与系统版的 `com.tencent.xinWeChat` 三者互不相同
3. **每份的可执行文件 (`Contents/MacOS/WeChat`) 改名**（`WeChat1` / `WeChat2`），防止微信通过进程名检测
4. **移除原 Tencent 签名，用 ad-hoc 重新签名**，让 Gatekeeper 接受修改过的 bundle
5. macOS 看到三个不同的 Bundle ID，自动为它们各自分配独立的 `~/Library/Containers/<bundle-id>/` sandbox

最终结果：三个完全平行的 WeChat 安装，互相看不到对方的登录态、聊天记录、文件。

### 同步代理的设计

```
+-----------------------+    cp -R + patch + sign     +-------------------------+
| /Applications/WeChat  | -------------------------->  | ~/Applications/WeChat   |
| (com.tencent.xinWeChat|                              | (com.tencent.xinWeChat1)|
| 由 App Store 升级)    |                              +-------------------------+
+-----------------------+
        |
        | (Info.plist 变化触发)                        +-------------------------+
        +--> launchd WatchPaths --> wechat-auto-update | ~/Applications/WeChat2  |
                                       --skip-agent    | (com.tencent.xinWeChat2)|
                                                       +-------------------------+
```

- **代理脚本完全不联网**，所有版本判断基于本地 `CFBundleShortVersionString` 比较
- 升级动作仅在 WeChat1 / WeChat2 都退出时执行（避免破坏正在运行的 app）
- 系统微信运行**不会**阻塞同步（它使用的是不同的 bundle）

---

## 📁 文件结构

| 文件 | 作用 |
|---|---|
| `install.sh` | 安装/重装：从系统微信复制两份并 patch，注册同步代理 |
| `wechat-sandbox.sh` | 日常启动：唤起代理同步检查 + 打开 WeChat1 / WeChat2 |
| `wechat-auto-update.sh` | 同步代理：检测系统微信版本变化时调用 install.sh 重建副本 |
| `com.sillusion.wechat-dual-instance-updater.plist.template` | launchd 配置模板（RunAtLoad + 1h 间隔 + WatchPaths） |
| `uninstall.sh` | 完全清理：副本、容器、代理、日志 |

---

## 🔐 安全说明

- **不修改系统目录**：所有操作仅写入 `~/Applications/`、`~/Library/`、`~/.wechat-dual-instance/`
- **不需要 sudo**：全程用户级权限
- **不联网**：脚本本身从不发起任何网络请求
- **不绕过签名校验**：仅对自己的副本做 ad-hoc 重签名，系统微信签名链完整保留
- **可审计**：所有逻辑都在本仓库的 5 个 shell 脚本里，约 300 行可读代码

---

## ⚠️ 已知限制

| 限制 | 说明 | 影响 |
|---|---|---|
| 部分小程序无法运行 | ad-hoc 签名移除了某些 entitlements | 在系统微信里用即可 |
| 不支持超过 3 个实例 | 当前仅创建 2 份管理副本 | 可手动复制 install.sh 修改 patch 一份 WeChat3 |
| 不支持微信 3.x | Bundle ID 检测逻辑不同 | 请升级到 4.x |

---

## 📝 许可

本项目仅供个人学习与日常多账号管理使用。不得用于商业用途、不得用于规避微信安全策略的恶意场景。本项目与腾讯公司无关。
