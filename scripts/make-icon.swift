// Generates assets/AppIcon.icns: a teal rounded square with the app's circular-arrows mark.
// Run from the repository root: swift scripts/make-icon.swift
import AppKit

let sizes: [(name: String, pixels: Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
    ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)
]
let iconset = URL(fileURLWithPath: "assets/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let side = CGFloat(pixels)
    // macOS icons leave a transparent margin around the shape.
    let inset = side * 0.08
    let box = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let shape = NSBezierPath(roundedRect: box, xRadius: box.width * 0.225, yRadius: box.width * 0.225)
    let gradient = NSGradient(starting: NSColor(red: 0.13, green: 0.58, blue: 0.48, alpha: 1), ending: NSColor(red: 0.06, green: 0.36, blue: 0.30, alpha: 1))!
    gradient.draw(in: shape, angle: -90)
    let symbol = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: box.width * 0.5, weight: .semibold))!
    let tinted = NSImage(size: symbol.size, flipped: false) { rect in
        symbol.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    let target = NSSize(width: box.width * 0.62, height: box.width * 0.62 * symbol.size.height / symbol.size.width)
    let origin = NSPoint(x: box.midX - target.width / 2, y: box.midY - target.height / 2)
    tinted.draw(in: NSRect(origin: origin, size: target), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for entry in sizes {
    try render(pixels: entry.pixels).write(to: iconset.appendingPathComponent("icon_\(entry.name).png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "assets/AppIcon.icns"]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
try FileManager.default.removeItem(at: iconset)
print("Wrote assets/AppIcon.icns")
