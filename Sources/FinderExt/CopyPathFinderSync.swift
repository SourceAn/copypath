// CopyPathFinderSync.swift
// Finder 同步扩展：在 Finder 右键菜单顶层加入「复制绝对路径」。
//
// 扩展负责写剪贴板（快、无依赖）；通知交给主 App 弹，
// 因为 UNUserNotificationCenter 在 App Extension 里会抛异常直接崩溃。

import Cocoa
import FinderSync

@objc(CopyPathFinderSync)
final class CopyPathFinderSync: FIFinderSync {

    override init() {
        super.init()

        // 监控整个文件系统，这样在任何目录（含外接磁盘）右键都能出现菜单项。
        // 必须在 init 里设置，否则 Finder 不会调用 menu(for:)。
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: - 工具栏按钮（可选，Finder 工具栏里也能点）

    override var toolbarItemName: String { "复制绝对路径" }
    override var toolbarItemToolTip: String { "复制所选文件/文件夹的绝对路径" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "复制绝对路径")
            ?? NSImage(named: NSImage.folderName)!
    }

    // MARK: - 右键菜单

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")

        let title: String
        switch menuKind {
        case .contextualMenuForItems:      title = "复制绝对路径"
        case .contextualMenuForContainer:  title = "复制当前文件夹的绝对路径"
        case .contextualMenuForSidebar:    title = "复制绝对路径"
        case .toolbarItemMenu:             title = "复制绝对路径"
        @unknown default:                  title = "复制绝对路径"
        }

        let item = NSMenuItem(title: title,
                              action: #selector(copyAbsolutePath(_:)),
                              keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        menu.addItem(item)
        return menu
    }

    // MARK: - 动作

    @objc private func copyAbsolutePath(_ sender: AnyObject?) {
        let controller = FIFinderSyncController.default()

        var urls = controller.selectedItemURLs() ?? []
        if urls.isEmpty, let target = controller.targetedURL() {
            // 右键点在文件夹空白处：把该文件夹自身作为目标。
            urls = [target]
        }
        guard !urls.isEmpty else { return }

        // 去重后保持原顺序。
        var seen = Set<String>()
        let paths = urls.map { $0.path }.filter { seen.insert($0).inserted }
        let text = paths.joined(separator: "\n")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 请主 App 弹通知。失败也无所谓，剪贴板已经写好了。
        Notifier.post(copied: paths)
    }
}

// MARK: - 通知（通过自定义 URL scheme 转发给主 App）

private enum Notifier {

    private static let scheme = "copypath"

    static func post(copied paths: [String]) {
        guard let first = paths.first else { return }

        var components = URLComponents()
        components.scheme = scheme
        components.host = "notify"
        components.queryItems = [
            URLQueryItem(name: "count", value: String(paths.count)),
            // 只带预览，避免超长路径撑爆 URL。
            URLQueryItem(name: "first", value: String(first.prefix(500))),
        ]
        guard let url = components.url else { return }

        // activates = false：别把主程序拽到前台，它只是去弹个通知。
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            if let error {
                NSLog("CopyPath: 通知主程序失败 — \(error.localizedDescription)")
            }
        }
    }
}
