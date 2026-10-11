# 复制绝对路径 (CopyPath)

一个 macOS 小工具：在 **Finder 右键菜单第一层**加一项「复制绝对路径」，
点击后把选中文件/文件夹的绝对路径写进剪贴板，并弹一条通知。

```
Finder 右键菜单
────────────────
打开
打开方式 ▸
复制绝对路径        ← 这一项是本工具加的
移到废纸篓
显示简介
...
```

- 多选时每行一个路径，按选中顺序排列
- 右键点在文件夹空白处 → 复制当前文件夹自身的路径
- **后台常驻**：无 Dock 图标、不占前台，只在通知横幅里露脸
- **开机自启**：登录后在后台静默启动，不弹任何窗口
- 全程本地运行，不联网

## 安装

```bash
make install
```

脚本会：编译 → 装到 `/Applications/CopyPath.app` → 刷新图标缓存 → 注册 Finder 扩展 →
写入开机自启 → 重启 Finder → 打开 App 的设置窗口。

> **首次运行需要手动启用扩展**：在打开的设置窗口里点「打开扩展设置…」，
> 在「系统设置 → 通用 → 登录项与扩展 → 文件提供程序」里勾选 **复制绝对路径**，
> 然后回到 App 点「重新注册扩展」。

首次弹出通知时，系统会问是否允许通知，选「允许」。

## 卸载

```bash
make uninstall
```

会一并删掉 `~/Library/LaunchAgents/com.mroeidea.copypath.agent.plist`。

## 其他命令

| 命令 | 作用 |
| --- | --- |
| `make build` | 只构建到 `./build/CopyPath.app`，不安装 |
| `make icon` | 重新生成 `Resources/AppIcon.icns` |
| `make clean` | 删除构建产物 |

## 实现方式

一个 App 内嵌一个 Finder 同步扩展（`FIFinderSync`）：

```
CopyPath.app
├── Contents/MacOS/CopyPath                  主程序（后台常驻 + 弹通知）
└── Contents/PlugIns/CopyPathFinder.appex
    └── Contents/MacOS/CopyPathFinder        扩展（右键菜单 + 写剪贴板）
```

数据流：

```
右键点击 → 扩展 menu(for:) 提供菜单项
        → 扩展 copyAbsolutePath() 读 selectedItemURLs()
        → 写 NSPasteboard
        → NSWorkspace.open(copypath://notify?..., activates: false) 唤醒主程序
        → 主程序 UNUserNotificationCenter 弹通知（横幅显示 App 图标）
```

### 后台与开机自启

主程序是 `LSUIElement`（`type="UIElement"`），没有 Dock 图标、不进前台。
开机自启不用 `SMAppService`，而是写一个 LaunchAgent：

`~/Library/LaunchAgents/com.mroeidea.copypath.agent.plist`

```xml
<key>ProgramArguments</key>
<array>
    <string>/Applications/CopyPath.app/Contents/MacOS/CopyPath</string>
    <string>--background</string>
</array>
<key>RunAtLoad</key><true/>
<key>LimitLoadToSessionType</key><string>Aqua</string>
```

- `--background` 让主程序知道自己是后台常驻，**永不主动弹设置窗口**
- `LimitLoadToSessionType=Aqua` 保证只在图形登录会话里加载
- 不用 `SMAppService` 是因为 ad-hoc 签名下它的注册行为不保证；
  LaunchAgent 只是一个 plist 文件，可控、好排查、卸载干净

设置窗口里有个「开机自动启动」勾选框，随时可以开关。
关掉设置窗口只是收起窗口，进程继续在后台跑；要彻底退出用菜单的「退出」(⌘Q)。

### 两个实例的问题

`launchd` 拉起和 URL scheme 唤起都可能撞车，所以 `main.swift` 在启动前先查重：

```swift
let isDuplicate = NSRunningApplication
    .runningApplications(withBundleIdentifier: bundleIdentifier)
    .contains { $0.processIdentifier != currentPID }
if isDuplicate { exit(0) }
```

### 为什么通知要绕一圈给主程序发

`UNUserNotificationCenter.current()` 在 App Extension 里会直接抛 Objective-C 异常，
进程 `abort()`（本项目实测崩溃过，崩溃栈在
`+[UNUserNotificationCenter currentNotificationCenter]`）。
所以扩展只负责写剪贴板，通知交给主程序，通过自定义 URL scheme 转发。

`NSWorkspace.open` 用 `activates = false`，避免把后台程序拽到前台抢焦点。

### 排查问题

带 `--debug-log` 启动会把关键事件写进 `~/Library/Logs/CopyPath.log`：

```bash
/Applications/CopyPath.app/Contents/MacOS/CopyPath --background --debug-log
```

```
2026-09-08T12:41:11Z [pid 73095] 启动，参数=--background --debug-log，后台模式=true
2026-09-08T12:41:14Z [pid 73095] 收到 URL: copypath://notify?count=2&first=/Users/...
2026-09-08T12:41:14Z [pid 73095] 通知授权状态=2
2026-09-08T12:41:14Z [pid 73095] 通知已投递: 已复制 2 个路径
```

## 不需要 Xcode

只用 Command Line Tools 的 `swiftc` 手工组装 bundle：

- 扩展编译成 `MH_EXECUTE`，入口点用 `-Xlinker -e -Xlinker _NSExtensionMain`
  （真实 appex 就是这个形态，用 `-bundle` 会让 `ld` 忽略 `-e`）
- `NSExtensionPrincipalClass` 指向 `@objc(CopyPathFinderSync)` 暴露的类名
- 扩展 ad-hoc 签名（`codesign -s -`）+ `com.apple.security.app-sandbox`
- `pluginkit -a` 注册、`pluginkit -e use` 启用
- `lsregister -f` 刷新 LaunchServices 缓存，保证通知横幅显示正确图标

实测 ad-hoc 签名下扩展能正常加载运行。

## 已知限制

- 扩展监控的是 `/`，外接磁盘、网络卷也在范围内；但 **iCloud 云盘、部分第三方同步目录**
  的右键菜单可能不出现菜单项，这是 Finder 扩展本身的限制
- 只编译了 arm64（Apple Silicon）
- 最低系统要求 macOS 13

## 目录结构

```
Sources/App/          主程序
  main.swift            入口 + 实例去重
  AppDelegate.swift     设置窗口、通知、URL 处理
  LoginItem.swift       开机自启的 LaunchAgent 读写
Sources/FinderExt/    Finder 扩展
Resources/            Info.plist、entitlements、图标
Tools/make-icon.swift 图标生成脚本
build.sh              构建
install.sh            构建 + 安装 + 注册 + 开机自启
uninstall.sh          卸载
```
---

## 支持

如果这个项目帮到了你，可以请我喝杯咖啡（完全自愿）：**https://ko-fi.com/colome**

更多项目：**https://github.com/SourceAn**
