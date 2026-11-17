// Draws the 1024×1024 app icon: stacked browser windows on a gradient tile.
// Usage: swift scripts/make_icon.swift <out.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Background tile (macOS icon grid: 824 px body, ~185 px corner radius).
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
rgb(0x1E1B4B).setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [rgb(0x312E81), rgb(0x4F46E5), rgb(0x06B6D4)])!.draw(in: tilePath, angle: -55)

// One browser window card.
func card(_ r: NSRect, alpha: CGFloat, front: Bool) {
    let body = NSBezierPath(roundedRect: r, xRadius: 46, yRadius: 46)
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(front ? 0.35 : 0.18)
    s.shadowBlurRadius = 30
    s.shadowOffset = NSSize(width: 0, height: -10)
    s.set()
    NSColor.white.withAlphaComponent(alpha).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Title bar.
    let bar = NSRect(x: r.minX, y: r.maxY - 92, width: r.width, height: 92)
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    (front ? rgb(0xE0E7FF) : NSColor.white.withAlphaComponent(alpha * 0.6)).setFill()
    bar.fill()
    NSGraphicsContext.restoreGraphicsState()

    let dots: [UInt32] = [0xFF5F57, 0xFEBC2E, 0x28C840]
    for (i, c) in dots.enumerated() {
        let d = NSRect(x: r.minX + 40 + CGFloat(i) * 44, y: bar.midY - 15, width: 30, height: 30)
        (front ? rgb(c) : NSColor.white.withAlphaComponent(alpha)).setFill()
        NSBezierPath(ovalIn: d).fill()
    }
}

card(NSRect(x: 300, y: 430, width: 500, height: 380), alpha: 0.28, front: false)
card(NSRect(x: 250, y: 345, width: 520, height: 400), alpha: 0.5, front: false)
let front = NSRect(x: 196, y: 220, width: 560, height: 440)
card(front, alpha: 1, front: true)

// Fingerprint-style arcs inside the front window = "separate identity".
let center = NSPoint(x: front.midX, y: front.minY + 110)
rgb(0x4F46E5).setStroke()
// Arcs open at the bottom, with uneven ends, like the ridges of a fingertip.
let ends: [(Double, Double)] = [(10, 170), (-15, 195), (-30, 200), (-5, 215)]
for (i, radius) in [34.0, 72.0, 110.0, 148.0].enumerated() {
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius,
                  startAngle: CGFloat(ends[i].0), endAngle: CGFloat(ends[i].1))
    arc.lineWidth = 20
    arc.lineCapStyle = .round
    arc.stroke()
}
let dot = NSBezierPath(ovalIn: NSRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24))
rgb(0x4F46E5).setFill()
dot.fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
