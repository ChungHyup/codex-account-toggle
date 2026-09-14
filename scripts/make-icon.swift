// Generates the original Codex Account Toggle icon from vector geometry.
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
    // Original mark: two offset account toggles, moving in opposite directions.
    // Drawn from geometry, with no third-party icon or artwork embedded.
    func lane(x: CGFloat, y: CGFloat, knobRight: Bool) {
        let track = NSRect(x: side*x, y: side*y, width: side*0.54, height: side*0.205)
        NSColor(white: 1, alpha: 0.16).setFill()
        NSBezierPath(roundedRect: track, xRadius: track.height/2, yRadius: track.height/2).fill()
        let diameter = side*0.155
        let knobX = knobRight ? track.maxX - diameter - side*0.025 : track.minX + side*0.025
        NSColor(red: 0.92, green: 1, blue: 0.97, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: knobX, y: track.midY-diameter/2, width: diameter, height: diameter)).fill()
        let center = NSPoint(x: knobRight ? track.minX+side*0.14 : track.maxX-side*0.14, y: track.midY)
        let direction: CGFloat = knobRight ? 1 : -1
        let arrow = NSBezierPath()
        arrow.lineWidth = side*0.025
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.move(to: NSPoint(x: center.x-direction*side*0.045, y: center.y))
        arrow.line(to: NSPoint(x: center.x+direction*side*0.045, y: center.y))
        arrow.move(to: NSPoint(x: center.x, y: center.y+side*0.045))
        arrow.line(to: NSPoint(x: center.x+direction*side*0.045, y: center.y))
        arrow.line(to: NSPoint(x: center.x, y: center.y-side*0.045))
        NSColor(white: 1, alpha: 0.9).setStroke()
        arrow.stroke()
    }
    lane(x: 0.19, y: 0.53, knobRight: true)
    lane(x: 0.27, y: 0.265, knobRight: false)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try render(pixels: 1024).write(to: URL(fileURLWithPath: "assets/logo.png"))

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
