// Renders brand assets into a folder:
//   logo.png        mark + wordmark on marshmallow
//   mark.png        the mark alone, transparent
//   icon_1024.png   app icon source
//   menubar.png     the menu bar icon at 8x, for checking
// Build: swiftc -parse-as-library Sources/Brand.swift Tools/render_assets.swift -o render_assets

import AppKit

func bitmap(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    draw(g.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

/// Draws "mousemallow" centered on `centerX` with a sparkle cut out of the first "o".
func drawWordmark(_ ctx: CGContext, centerX: CGFloat, baseline: CGFloat, size: CGFloat, background: NSColor) {
    let font = roundedFont(size, .bold)
    let kern = size * 0.01
    let str = NSAttributedString(string: "mousemallow",
                                 attributes: [.font: font, .foregroundColor: Brand.ink, .kern: kern])
    let line = CTLineCreateWithAttributedString(str)
    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    let x0 = centerX - width / 2
    ctx.textPosition = CGPoint(x: x0, y: baseline)
    CTLineDraw(line, ctx)

    let a = CTLineGetOffsetForStringIndex(line, 1, nil)
    let b = CTLineGetOffsetForStringIndex(line, 2, nil)
    let c = CGPoint(x: x0 + (a + b - kern) / 2, y: baseline + font.xHeight / 2)
    ctx.setFillColor(background.cgColor)
    ctx.addPath(Brand.sparkle(center: c, radius: font.xHeight * 0.4, plump: 0.3))
    ctx.fillPath()
}

func drawText(_ s: String, centerX: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight,
              color: NSColor = Brand.ink) {
    let a = NSAttributedString(string: s, attributes: [.font: roundedFont(size, weight), .foregroundColor: color])
    a.draw(at: NSPoint(x: centerX - a.size().width / 2, y: y))
}

/// A static picture of the cursor decoration (ring, mouse ears, outline, sticker shadow).
func drawCursorPreview(_ ctx: CGContext, center c: CGPoint, scale s: CGFloat,
                       primary: NSColor, secondary: NSColor, outline: NSColor, sticker: NSColor) {
    let R = 20 * s
    let stick = CGSize(width: 1.6 * s, height: -2.2 * s)
    func circle(_ p: CGPoint, _ r: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r), transform: nil)
    }
    let ears = [(124.0, 1.12, 0.54), (58.0, 1.08, 0.45)].map { (a, d, r) -> (CGPoint, CGFloat) in
        let q = polar(a, R * d)
        return (CGPoint(x: c.x + q.x, y: c.y + q.y), R * r)
    }

    // Ears, clipped to outside the ring.
    ctx.saveGState()
    ctx.addRect(ctx.boundingBoxOfClipPath)
    ctx.addPath(circle(c, R))
    ctx.clip(using: .evenOdd)
    for (p, r) in ears {
        ctx.setFillColor(sticker.cgColor)
        ctx.addPath(circle(CGPoint(x: p.x + stick.width, y: p.y + stick.height), r + 1.3 * s))
        ctx.fillPath()
    }
    for (p, r) in ears {
        ctx.setFillColor(primary.cgColor)
        ctx.setStrokeColor(outline.cgColor)
        ctx.setLineWidth(2.6 * s)
        ctx.addPath(circle(p, r))
        ctx.drawPath(using: .fillStroke)
        ctx.setFillColor(secondary.cgColor)
        ctx.addPath(circle(p, r * 0.55))
        ctx.fillPath()
    }
    ctx.restoreGState()

    // Ring: sticker, ink outline, color stroke, faint fill.
    ctx.setStrokeColor(sticker.cgColor)
    ctx.setLineWidth(7.2 * s)
    ctx.addPath(circle(CGPoint(x: c.x + stick.width, y: c.y + stick.height), R))
    ctx.strokePath()
    ctx.setFillColor(primary.withAlphaComponent(0.18).cgColor)
    ctx.addPath(circle(c, R))
    ctx.fillPath()
    ctx.setStrokeColor(outline.cgColor)
    ctx.setLineWidth(7.2 * s)
    ctx.addPath(circle(c, R))
    ctx.strokePath()
    ctx.setStrokeColor(primary.cgColor)
    ctx.setLineWidth(4 * s)
    ctx.addPath(circle(c, R))
    ctx.strokePath()

    // The system arrow, tip at the center.
    let arrow = CGMutablePath()
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, -17), (4, -13.2), (7, -19.6), (10, -18.4), (7.1, -12.1), (12.4, -12.1)]
    for (i, q) in pts.enumerated() {
        let p = CGPoint(x: c.x + q.0 * s, y: c.y + q.1 * s)
        if i == 0 { arrow.move(to: p) } else { arrow.addLine(to: p) }
    }
    arrow.closeSubpath()
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(1.6 * s)
    ctx.addPath(arrow)
    ctx.strokePath()
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.addPath(arrow)
    ctx.fillPath()
}

@main
struct BrandTool {
    static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets"

        // Logo: 1536 × 1024 card, same layout as the sketch.
        save(bitmap(1536, 1024) { ctx in
            ctx.setFillColor(Brand.marshmallow.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 1536, height: 1024))
            MouseMark.draw(in: ctx, rect: CGRect(x: 568, y: 360, width: 400, height: 460))
            drawWordmark(ctx, centerX: 768, baseline: 210, size: 150, background: Brand.marshmallow)
        }, "\(out)/logo.png")

        save(bitmap(512, 512) { ctx in
            MouseMark.draw(in: ctx, rect: CGRect(x: 16, y: 16, width: 480, height: 480))
        }, "\(out)/mark.png")

        // App icon: marshmallow squircle with a soft berry fade at the bottom.
        save(bitmap(1024, 1024) { ctx in
            let squircle = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                                  cornerWidth: 185, cornerHeight: 185, transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24,
                          color: Brand.ink.withAlphaComponent(0.25).cgColor)
            ctx.addPath(squircle)
            ctx.setFillColor(Brand.marshmallow.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(squircle)
            ctx.clip()
            let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                  colors: [NSColor(hex: "#FBF4F8").cgColor, NSColor(hex: "#F0D9E6").cgColor] as CFArray,
                                  locations: [0, 1])!
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
            ctx.restoreGState()
            MouseMark.draw(in: ctx, rect: CGRect(x: 222, y: 200, width: 580, height: 620))
        }, "\(out)/icon_1024.png")

        // Palette swatches.
        let swatches: [(String, NSColor)] = [("Marshmallow", Brand.marshmallow), ("Berry milk", Brand.berryMilk),
                                             ("Lavender", Brand.lavender), ("Mint", Brand.mint), ("Ink", Brand.ink)]
        save(bitmap(1600, 340) { ctx in
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 1600, height: 340))
            for (i, (name, color)) in swatches.enumerated() {
                let x = 60 + CGFloat(i) * 300
                let r = CGRect(x: x, y: 120, width: 260, height: 170)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: 28, cornerHeight: 28, transform: nil))
                ctx.setFillColor(color.cgColor)
                ctx.setStrokeColor(Brand.ink.withAlphaComponent(0.12).cgColor)
                ctx.setLineWidth(2)
                ctx.drawPath(using: .fillStroke)
                drawText(name, centerX: r.midX, y: 62, size: 32, weight: .bold)
                drawText(color.hexString, centerX: r.midX, y: 22, size: 26, weight: .medium,
                         color: Brand.ink.withAlphaComponent(0.6))
            }
        }, "\(out)/palette.png")

        // Theme previews: each theme's cursor on a light and a dark strip.
        let themes: [(String, NSColor, NSColor, NSColor, NSColor)] = [
            ("Marshmallow", Brand.cream, Brand.blush, Brand.ink, Brand.berryMilk),
            ("Berry Milk", Brand.berryMilk, Brand.marshmallow, Brand.ink, Brand.lavender),
            ("Lavender Haze", Brand.lavender, Brand.berryMilk, Brand.ink, Brand.berryMilk),
            ("Mint Mallow", Brand.mint, Brand.marshmallow, Brand.ink, Brand.berryMilk),
            ("Cotton Candy", Brand.berryMilk, Brand.lavender, Brand.ink, Brand.mint),
            ("Ink Night", Brand.ink, Brand.lavender, Brand.marshmallow, Brand.lavender),
            ("Mallow Mix", Brand.mint, Brand.lavender, Brand.ink, Brand.berryMilk),
        ]
        let colW: CGFloat = 230
        save(bitmap(Int(colW) * themes.count, 560) { ctx in
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 290, width: colW * CGFloat(themes.count), height: 270))
            ctx.setFillColor(NSColor(hex: "#2B2730").cgColor)
            ctx.fill(CGRect(x: 0, y: 60, width: colW * CGFloat(themes.count), height: 230))
            ctx.setFillColor(Brand.marshmallow.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: colW * CGFloat(themes.count), height: 60))
            for (i, t) in themes.enumerated() {
                let cx = colW * (CGFloat(i) + 0.5)
                for cy: CGFloat in [410, 170] {
                    drawCursorPreview(ctx, center: CGPoint(x: cx, y: cy), scale: 2.6,
                                      primary: t.1, secondary: t.2, outline: t.3, sticker: t.4)
                }
                drawText(t.0, centerX: cx, y: 16, size: 24, weight: .bold)
            }
        }, "\(out)/themes.png")

        save(bitmap(144, 144) { ctx in
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 144, height: 144))
            MouseMark.draw(in: ctx, rect: CGRect(x: 0, y: 0, width: 144, height: 144), style: .menuBar)
        }, "\(out)/menubar.png")
    }
}
