// 產生 App 圖示：黑底、白字「密」。
// 用法：swift tools/make_icon.swift <輸出 .iconset 資料夾>
import AppKit
import CoreText

let glyph = "密"

/// macOS 圖示外形（近似 Apple 的連續圓角方形，使用 n=5 的超橢圓）
func squirclePath(in rect: CGRect, n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)

    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext
    let k = CGFloat(pixels) / 1024          // 以 1024 為基準縮放
    ctx.scaleBy(x: k, y: k)

    // 圖示本體 824×824，四周留白（Apple 圖示規範）
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squirclePath(in: body)

    // 底部陰影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                  color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 黑色底（上方帶極淡的高光，增加層次但仍是黑底）
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [NSColor(white: 0.13, alpha: 1).cgColor, NSColor(white: 0.0, alpha: 1).cgColor] as CFArray,
        locations: [0, 0.75])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: body.maxY),
                           end: CGPoint(x: 512, y: body.minY), options: [])
    ctx.restoreGState()

    // 細邊框
    ctx.addPath(shape)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
    ctx.setLineWidth(3)
    ctx.strokePath()

    // 白色「密」，以實際字形輪廓置中
    let font = NSFont(name: "PingFangTC-Semibold", size: 510) ?? NSFont.systemFont(ofSize: 510, weight: .semibold)
    let attributed = NSAttributedString(string: glyph, attributes: [
        .font: font, .foregroundColor: NSColor.white,
    ])
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: body.midX - bounds.midX, y: body.midY - bounds.midY)
    CTLineDraw(line, ctx)

    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("用法：swift make_icon.swift <輸出.iconset>\n".utf8))
    exit(1)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: outDir)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for v in variants {
    try render(pixels: v.pixels).write(to: outDir.appendingPathComponent("\(v.name).png"))
}
print("✅ 已產生 \(variants.count) 張圖示 → \(outDir.path)")
