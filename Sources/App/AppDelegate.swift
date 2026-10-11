import Cocoa
import FinderSync
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate,
                       UNUserNotificationCenterDelegate, NSWindowDelegate {

    private var window: NSWindow?
    private var statusDot: NSView?
    private var statusLabel: NSTextField?
    private var statusTimer: Timer?
    private var autostartCheckbox: NSButton?

    /// 收到多少次 `copypath://` 唤起。为 0 说明是用户手动打开的，才弹设置窗口。
    private var urlCallCount = 0

    /// 由 LaunchAgent 以 `--background` 拉起：后台常驻，永不主动弹窗。
    private let isBackgroundAgent = CommandLine.arguments.contains(LoginItem.backgroundArgument)

    /// 带 `--debug-log` 启动时把关键事件写进 ~/Library/Logs/CopyPath.log。
    /// 后台程序没有界面，出问题只能靠日志。
    private let isDebugLogging = CommandLine.arguments.contains("--debug-log")

    private func log(_ message: String) {
        guard isDebugLogging else { return }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CopyPath.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) [pid \(ProcessInfo.processInfo.processIdentifier)] \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        log("启动，参数=\(CommandLine.arguments.dropFirst().joined(separator: " "))"
            + "，后台模式=\(isBackgroundAgent)")

        // 被 URL scheme 唤起时不要弹设置窗口。等一小会儿看有没有收到 open(_:)。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            if self.urlCallCount == 0 && !self.isBackgroundAgent {
                self.showSettingsWindow()
            }
        }
    }

    /// 扩展通过 `copypath://notify?count=&first=` 把结果送进来。
    func application(_ application: NSApplication, open urls: [URL]) {
        log("收到 URL: \(urls.map(\.absoluteString).joined(separator: ", "))")
        for url in urls where url.scheme == "copypath" {
            urlCallCount += 1
            presentNotification(for: url)
        }
    }

    /// 后台常驻程序：关掉设置窗口只是收起窗口，进程继续跑。
    /// 真要退出用菜单里的「退出」(⌘Q)。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// 用户在 Finder 里再次双击 App 时，把设置窗口调出来。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showSettingsWindow() }
        return true
    }

    // MARK: - 通知

    private func presentNotification(for url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let count = Int(items.first { $0.name == "count" }?.value ?? "1") ?? 1
        let first = items.first { $0.name == "first" }?.value ?? ""

        let title = count == 1 ? "已复制路径" : "已复制 \(count) 个路径"
        let body = count == 1 ? first : first + (count > 1 ? "\n…" : "")

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            self.log("通知授权状态=\(settings.authorizationStatus.rawValue)")
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.deliver(center, title: title, body: body)
            case .notDetermined:
                center.requestAuthorization(options: [.alert]) { granted, _ in
                    if granted { self.deliver(center, title: title, body: body) }
                }
            default:
                // 用户关了通知权限：剪贴板已经写好了，静默跳过。
                break
            }
        }
    }

    private func deliver(_ center: UNUserNotificationCenter, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        center.add(request) { error in
            if let error {
                self.log("通知投递失败: \(error.localizedDescription)")
            } else {
                self.log("通知已投递: \(title)")
            }
        }
    }

    /// App 在前台时也把横幅显示出来。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    // MARK: - 设置窗口

    private func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)

        // 已经开过就把它调到前面，别重建一遍。
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 396),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "复制绝对路径"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 26, left: 28, bottom: 26, right: 28)

        let title = NSTextField(labelWithString: "复制绝对路径")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        stack.addArrangedSubview(title)

        let subtitle = NSTextField(wrappingLabelWithString:
            "在 Finder 里右键点击任意文件或文件夹，选择「复制绝对路径」，\n路径就会进入剪贴板并弹出通知。")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitle)
        stack.setCustomSpacing(22, after: subtitle)

        // 状态行
        let statusRow = NSStackView()
        statusRow.orientation = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .centerY

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 10).isActive = true
        statusRow.addArrangedSubview(dot)
        statusDot = dot

        let label = NSTextField(labelWithString: "正在检查扩展状态…")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        statusRow.addArrangedSubview(label)
        statusLabel = label

        stack.addArrangedSubview(statusRow)
        stack.setCustomSpacing(22, after: statusRow)

        let buttonRow = NSStackView(views: [
            makeButton(title: "打开扩展设置…", action: #selector(openExtensionSettings)),
            makeButton(title: "重新注册扩展", action: #selector(reregisterExtension)),
            makeButton(title: "在 Finder 中试用", action: #selector(openDownloads)),
        ])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        stack.addArrangedSubview(buttonRow)
        stack.setCustomSpacing(18, after: buttonRow)

        // 开机自启动
        let checkbox = NSButton(checkboxWithTitle: "开机自动启动（后台运行，不弹窗口）",
                                target: self,
                                action: #selector(toggleAutostart(_:)))
        checkbox.state = LoginItem.isEnabled ? .on : .off
        stack.addArrangedSubview(checkbox)
        autostartCheckbox = checkbox
        stack.setCustomSpacing(20, after: checkbox)

        let hint = NSTextField(wrappingLabelWithString:
            "提示：若菜单项没出现，到「系统设置 → 通用 → 登录项与扩展 → 文件提供程序」\n勾选「复制绝对路径」，然后点上面的「重新注册扩展」。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(hint)

        window.contentView = stack
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
        ])

        buildMenu()
        refreshStatus()

        // 用户在的时候把通知权限问清楚，免得第一次复制时弹不出来。
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }

        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 复制绝对路径",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    // MARK: - 状态

    private func refreshStatus() {
        let enabled = FIFinderSyncController.isExtensionEnabled
        statusDot?.layer?.backgroundColor =
            (enabled ? NSColor.systemGreen : NSColor.systemOrange).cgColor
        statusLabel?.stringValue = enabled
            ? "扩展已启用，右键菜单可用"
            : "扩展尚未启用，请到系统设置里勾选"
        statusLabel?.textColor = enabled ? .labelColor : .secondaryLabelColor
    }

    // MARK: - 动作

    @objc private func toggleAutostart(_ sender: NSButton) {
        do {
            if sender.state == .on {
                try LoginItem.enable()
            } else {
                try LoginItem.disable()
            }
        } catch {
            // 失败就把勾选状态拨回去，别让界面骗人。
            sender.state = sender.state == .on ? .off : .on
            let alert = NSAlert()
            alert.messageText = "设置开机启动失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// 窗口关掉后收起 Dock 图标，回到纯后台状态。
    func windowWillClose(_ notification: Notification) {
        statusTimer?.invalidate()
        statusTimer = nil
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func openExtensionSettings() {
        // 不同 macOS 版本的系统设置锚点不一样，逐个尝试。
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
            "x-apple.systempreferences:com.apple.preferences.extensions",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }

    @objc private func reregisterExtension() {
        guard let appex = Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("CopyPathFinder.appex") else { return }

        let id = Bundle(path: appex.path)?.bundleIdentifier ?? "com.mroeidea.copypath.finder"

        run("/usr/bin/pluginkit", ["-a", appex.path])
        run("/usr/bin/pluginkit", ["-e", "use", "-i", id])
        run("/usr/bin/killall", ["Finder"])

        refreshStatus()

        let alert = NSAlert()
        alert.messageText = "已重新注册"
        alert.informativeText = "Finder 已重启，现在右键点击任意文件试试。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func openDownloads() {
        let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    private func run(_ launchPath: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            NSLog("CopyPath: 执行 \(launchPath) 失败: \(error)")
            return -1
        }
    }
}
