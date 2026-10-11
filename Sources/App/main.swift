import Cocoa

// 已经在运行就不再起第二个实例：launchd 开机拉起和 URL scheme 唤起都可能撞车。
let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.mroeidea.copypath"
let currentPID = ProcessInfo.processInfo.processIdentifier
let isDuplicate = NSRunningApplication
    .runningApplications(withBundleIdentifier: bundleIdentifier)
    .contains { $0.processIdentifier != currentPID }

if isDuplicate {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
