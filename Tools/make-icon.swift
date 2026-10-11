// 生成 AppIcon.iconset —— 蓝色圆角底 + 白色剪贴板符号。
// 用法: swift Tools/make-icon.swift <输出目录>

import AppKit

_ = NSApplication.shared

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
                    ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

/// 把 SF Symbol 染成指定颜色，方便直接画。
func tinted(_ symbol: NSImage, color: NSColor) -> NSImage {
    let result = NSImage(size: symbol.size)
    result.lockFocus()
    color.set()
    NSRect(origin: .zero, size: symbol.size).fill()
    symbol.draw(in: NSRect(origin: .zero, size: symbol.size),
                from: .zero, operation: .destinationIn, fraction: 1.0)
    result.unlockFocus()
    return result
}

func render(size: Int) -> Data? {
    let s = CGFloat(size)

    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: size, pixelsHigh: size,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // 圆角底：macOS 图标习惯用 ~22.5% 的圆角半径
    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let background = NSBezierPath(roundedRect: rect, xRadius: s * 0.225, yRadius: s * 0.225)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.60, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.13, green: 0.33, blue: 0.86, alpha: 1),
    ])
    gradient?.draw(in: background, angle: -90)

    // 白色剪贴板符号
    if let symbol = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: s * 0.44, weight: .regular)
        if let configured = symbol.withSymbolConfiguration(config) {
            let white = tinted(configured, color: .white)
            let glyph = s * 0.58
            let box = NSRect(x: (s - glyph) / 2, y: (s - glyph) / 2, width: glyph, height: glyph)
            white.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// iconset 需要的档位：(像素尺寸, 文件名)
let variants: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (size, name) in variants {
    guard let png = render(size: size) else {
        FileHandle.standardError.write(Data("渲染 \(name) 失败\n".utf8))
        exit(1)
    }
    try png.write(to: outputDir.appendingPathComponent(name))
}

print("已生成 \(variants.count) 个尺寸 → \(outputDir.path)")
