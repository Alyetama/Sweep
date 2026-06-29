import AppKit

// Renders a 1024×1024 PNG app-icon glyph: a rounded teal→indigo gradient tile
// with a white broom sweeping a trail of sparkles — "uninstall / clean up".
// Usage: swift render_icon.swift <out.png>

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}

let full = CGRect(x: 0, y: 0, width: S, height: S)
let tile = full.insetBy(dx: 44, dy: 44)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 205, cornerHeight: 205, transform: nil)

// --- Background: teal → indigo gradient with a soft top sheen.
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
if let grad = CGGradient(colorsSpace: space,
                         colors: [rgb(0.20, 0.83, 0.74), rgb(0.36, 0.42, 1.0)] as CFArray,
                         locations: [0, 1]) {
    ctx.drawLinearGradient(grad, start: CGPoint(x: 150, y: Double(S) - 100),
                           end: CGPoint(x: Double(S) - 150, y: 100), options: [])
}
if let sheen = CGGradient(colorsSpace: space,
                          colors: [rgb(1, 1, 1, 0.18), rgb(1, 1, 1, 0)] as CFArray,
                          locations: [0, 1]) {
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: Double(S)),
                           end: CGPoint(x: 0, y: Double(S) * 0.5), options: [])
}
ctx.restoreGState()

let white = rgb(1, 1, 1)
let whiteSoft = rgb(0.90, 0.93, 0.99)

// A concave 4-point "sparkle" star centered at c with outer radius r.
func sparkle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
    let i = r * 0.30 // how far the concave control points sit from center
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + i, y: c.y + i))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + i, y: c.y - i))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - i, y: c.y - i))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - i, y: c.y + i))
    p.closeSubpath()
    return p
}

// --- Sparkle trail (drawn first so the broom sweeps "over" them).
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: rgb(0.06, 0.10, 0.30, 0.30))
ctx.setFillColor(white)
ctx.addPath(sparkle(CGPoint(x: 318, y: 388), 78)); ctx.fillPath()
ctx.setFillColor(rgb(1, 1, 1, 0.92))
ctx.addPath(sparkle(CGPoint(x: 250, y: 268), 48)); ctx.fillPath()
ctx.setFillColor(rgb(1, 1, 1, 0.80))
ctx.addPath(sparkle(CGPoint(x: 404, y: 250), 36)); ctx.fillPath()
ctx.restoreGState()

// --- Broom, drawn in a frame rotated -45° so the handle points up-right and the
//     brush hangs down-left over the sparkles.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 46, color: rgb(0.06, 0.10, 0.30, 0.38))
ctx.translateBy(x: 540, y: 560)
ctx.rotate(by: -.pi / 4)

// Handle: thick rounded white line going "up" in the rotated frame.
ctx.setLineCap(.round)
ctx.setLineWidth(54)
ctx.setStrokeColor(white)
ctx.beginPath()
ctx.move(to: CGPoint(x: 0, y: 20))
ctx.addLine(to: CGPoint(x: 0, y: 290))
ctx.strokePath()

// Brush body: a rounded trapezoid widening as it hangs "down".
let brush = CGMutablePath()
brush.move(to: CGPoint(x: -78, y: -10))
brush.addLine(to: CGPoint(x: 78, y: -10))
brush.addCurve(to: CGPoint(x: 150, y: -250),
               control1: CGPoint(x: 120, y: -110), control2: CGPoint(x: 150, y: -180))
brush.addCurve(to: CGPoint(x: -150, y: -250),
               control1: CGPoint(x: 60, y: -300), control2: CGPoint(x: -60, y: -300))
brush.addCurve(to: CGPoint(x: -78, y: -10),
               control1: CGPoint(x: -150, y: -180), control2: CGPoint(x: -120, y: -110))
brush.closeSubpath()
ctx.addPath(brush)
ctx.setFillColor(white)
ctx.fillPath()

// Ferrule: a soft band where the handle meets the bristles.
ctx.setShadow(offset: .zero, blur: 0, color: rgb(0, 0, 0, 0))
let band = CGPath(roundedRect: CGRect(x: -92, y: -8, width: 184, height: 70),
                  cornerWidth: 22, cornerHeight: 22, transform: nil)
ctx.addPath(band)
ctx.setFillColor(whiteSoft)
ctx.fillPath()

// Bristle slits: thin gradient-colored lines fanning down through the brush.
ctx.saveGState()
ctx.addPath(brush); ctx.clip()
ctx.setLineCap(.round)
ctx.setLineWidth(16)
ctx.setStrokeColor(rgb(0.30, 0.45, 0.96, 0.55))
for (topX, botX) in [(-58.0, -110.0), (-20.0, -38.0), (20.0, 38.0), (58.0, 110.0)] {
    ctx.beginPath()
    ctx.move(to: CGPoint(x: topX, y: -70))
    ctx.addLine(to: CGPoint(x: botX, y: -252))
    ctx.strokePath()
}
ctx.restoreGState()

ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try data.write(to: URL(fileURLWithPath: out))
} catch {
    FileHandle.standardError.write(Data("render_icon: \(error)\n".utf8))
    exit(1)
}
