import Foundation

/// 开机自启动：往 ~/Library/LaunchAgents 里放一个 LaunchAgent。
///
/// 没用 `SMAppService.mainApp` 是因为 ad-hoc 签名下它的注册行为不保证，
/// 而 LaunchAgent 只依赖一个 plist 文件，可控、好排查、卸载干净。
enum LoginItem {

    static let label = "com.mroeidea.copypath.agent"

    /// 以这个参数启动时表示是后台常驻，不弹设置窗口。
    static let backgroundArgument = "--background"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func enable() throws {
        guard let executable = Bundle.main.executableURL?.path else {
            throw LoginItemError.executableNotFound
        }

        let contents: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, backgroundArgument],
            "RunAtLoad": true,
            // 只在图形登录会话里加载，否则可能在登录窗口阶段就起来。
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: contents,
                                                      format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: plistURL)

        // 不调 launchctl bootstrap：launchd 下次登录会自动加载 ~/Library/LaunchAgents，
        // 而 App 此刻本来就在运行，立刻再拉一份只会起一个重复实例。
    }

    static func disable() throws {
        try? FileManager.default.removeItem(at: plistURL)
    }
}

enum LoginItemError: LocalizedError {
    case executableNotFound

    var errorDescription: String? {
        switch self {
        case .executableNotFound: return "找不到 App 可执行文件路径"
        }
    }
}
