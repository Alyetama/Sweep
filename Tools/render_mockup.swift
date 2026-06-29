import AppKit

// Composites a captured app-window PNG (transparent rounded corners) onto a
// branded teal→violet "wallpaper" to produce the hero mockup used on the
// GitHub Pages site and in the README.
// Usage: swift render_mockup.swift <window.png> <out.png>

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: render_mockup <window.png> <out.png>\n".utf8)); exit(2)
}
let inPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]

guard let winImg = NSImage(contentsOfFile: inPath),
      let win = winImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("cannot load \(inPath)\n".utf8)); exit(1)
}
let ww = CGFloat(win.width), wh = CGFloat(win.height)

let padX: CGFloat = 140, padTop: CGFloat = 110, padBottom: CGFloat = 170
let W = Int(ww + padX * 2), H = Int(wh + padTop + padBottom)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}

// Background: deep violet (top-left) → teal (bottom-right), matching the icon.
if let g = CGGradient(colorsSpace: space,
                      colors: [rgb(0.36, 0.27, 0.78), rgb(0.12, 0.66, 0.78)] as CFArray,
                      locations: [0, 1]) {
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
}

// Soft white glow behind the window so it lifts off the wallpaper.
let cx = CGFloat(W) / 2, cy = CGFloat(H) - padTop - wh * 0.30
if let rg = CGGradient(colorsSpace: space,
                       colors: [rgb(1, 1, 1, 0.22), rgb(1, 1, 1, 0)] as CFArray,
                       locations: [0, 1]) {
    ctx.drawRadialGradient(rg, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cy), endRadius: CGFloat(W) * 0.6, options: [])
}

// Gentle edge vignette for depth.
let center = CGPoint(x: CGFloat(W) / 2, y: CGFloat(H) / 2)
if let vg = CGGradient(colorsSpace: space,
                       colors: [rgb(0, 0, 0, 0), rgb(0, 0, 0, 0.20)] as CFArray,
                       locations: [0.6, 1]) {
    ctx.drawRadialGradient(vg, startCenter: center, startRadius: CGFloat(H) * 0.35,
                           endCenter: center, endRadius: CGFloat(W) * 0.72,
                           options: [.drawsAfterEndLocation])
}

// The app window, with a large soft drop shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -46), blur: 110, color: rgb(0.04, 0.03, 0.16, 0.55))
ctx.draw(win, in: CGRect(x: padX, y: padBottom, width: ww, height: wh))
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
do { try data.write(to: URL(fileURLWithPath: outPath)) }
catch { FileHandle.standardError.write(Data("write failed: \(error)\n".utf8)); exit(1) }
