// Brand colors and the mousemallow mark (a mouse-eared cursor with a face).
// Shared by the app and by Tools/brand.swift, which renders the logo and icon.

import AppKit

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        if s.count == 6 { s += "FF" }
        let v = UInt64(s, radix: 16) ?? 0xFFFFFFFF
        self.init(srgbRed: CGFloat((v >> 24) & 0xFF) / 255,
                  green: CGFloat((v >> 16) & 0xFF) / 255,
                  blue: CGFloat((v >> 8) & 0xFF) / 255,
                  alpha: CGFloat(v & 0xFF) / 255)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}

func polar(_ degrees: CGFloat, _ r: CGFloat) -> CGPoint {
    let a = degrees * .pi / 180
    return CGPoint(x: cos(a) * r, y: sin(a) * r)
}

enum Brand {
    static let marshmallow = NSColor(hex: "#F6EAF0")
    static let berryMilk = NSColor(hex: "#DDB4CC")
    static let lavender = NSColor(hex: "#C7B8E8")
    static let mint = NSColor(hex: "#A8CBB7")
    static let ink = NSColor(hex: "#4B4552")
    // Two helpers outside the core palette: the mark's body and small pink details.
    static let cream = NSColor(hex: "#FFFBFD")
    static let blush = NSColor(hex: "#E8A9C6")

    /// Four-point sparkle with concave sides.
    static func sparkle(center c: CGPoint, radius r: CGFloat, plump: CGFloat = 0.22) -> CGPath {
        let p = CGMutablePath()
        for i in 0..<4 {
            let tip = polar(90 - CGFloat(i) * 90, r)
            let next = polar(90 - CGFloat(i + 1) * 90, r)
            let mid = polar(45 - CGFloat(i) * 90, r * plump)
            let m = CGPoint(x: c.x + mid.x, y: c.y + mid.y)
            if i == 0 { p.move(to: CGPoint(x: c.x + tip.x, y: c.y + tip.y)) }
            p.addCurve(to: CGPoint(x: c.x + next.x, y: c.y + next.y), control1: m, control2: m)
        }
        p.closeSubpath()
        return p
    }
}

enum MouseMark {
    /// Design space is y-down, roughly 110 × 126 units including the shadow and sparkle.
    static let bounds = CGRect(x: 0, y: -5, width: 110, height: 126)

    static func roundedPolygon(_ pts: [(CGFloat, CGFloat, CGFloat)]) -> CGPath {
        let n = pts.count
        func pt(_ i: Int) -> CGPoint { let q = pts[(i + n) % n]; return CGPoint(x: q.0, y: q.1) }
        let p = CGMutablePath()
        let a = pt(n - 1), b = pt(0)
        p.move(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
        for i in 0..<n {
            p.addArc(tangent1End: pt(i), tangent2End: pt(i + 1), radius: pts[i].2)
        }
        p.closeSubpath()
        return p
    }

    // Arrow outline as (x, y, corner radius), clockwise from the top-left.
    static let body = roundedPolygon([
        (7, 22, 4), (64, 34, 4), (100, 69, 7), (69, 78, 3),
        (80, 99, 9), (56, 111, 9), (42, 85, 3), (14, 97, 9),
    ])
    static let ears: [(center: CGPoint, r: CGFloat)] = [
        (CGPoint(x: 22, y: 17), 16.5),
        (CGPoint(x: 57, y: 24), 13.5),
    ]

    static func circle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
    }

    static var silhouette: [CGPath] { [body] + ears.map { circle($0.center, $0.r) } }

    struct Style {
        var fill: NSColor = Brand.cream
        var ink: NSColor = Brand.ink
        var pink: NSColor? = Brand.blush
        var shadow: NSColor? = Brand.berryMilk
        var sparkle: NSColor? = Brand.lavender
        var lineWidth: CGFloat = 4.2
        var template = false

        static let brand = Style()
        static let plain = Style(sparkle: nil)
        /// Single-color outline with a cut-out body, for the menu bar.
        static let menuBar = Style(fill: .black, ink: .black, pink: nil, shadow: nil, sparkle: nil,
                                   lineWidth: 8, template: true)
    }

    /// Draws the mark centered in `rect` of a y-up context.
    static func draw(in ctx: CGContext, rect: CGRect, style: Style = .brand) {
        let s = min(rect.width / bounds.width, rect.height / bounds.height)
        ctx.saveGState()
        ctx.translateBy(x: rect.midX - bounds.width * s / 2, y: rect.midY + bounds.height * s / 2)
        ctx.scaleBy(x: s, y: -s)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)

        let shapes = silhouette
        let lw = style.lineWidth

        if let sh = style.shadow {
            ctx.saveGState()
            ctx.translateBy(x: 4, y: 5)
            ctx.setFillColor(sh.cgColor)
            ctx.setStrokeColor(sh.cgColor)
            ctx.setLineWidth(lw * 2)
            for p in shapes { ctx.addPath(p); ctx.drawPath(using: .fillStroke) }
            ctx.restoreGState()
        }

        // Stroke every shape at double width, then fill on top: only the outer
        // outline of the union survives, so ears and body read as one shape.
        ctx.setStrokeColor(style.ink.cgColor)
        ctx.setLineWidth(lw * 2)
        for p in shapes { ctx.addPath(p); ctx.strokePath() }
        if style.template { ctx.setBlendMode(.clear) }
        ctx.setFillColor(style.fill.cgColor)
        for p in shapes { ctx.addPath(p); ctx.fillPath() }
        ctx.setBlendMode(.normal)

        if let pink = style.pink {
            ctx.setFillColor(pink.cgColor)
            ctx.addPath(circle(CGPoint(x: 22.5, y: 18.5), 8.2))
            ctx.addPath(circle(CGPoint(x: 57.5, y: 25.5), 6.6))
            ctx.fillPath()
        }

        // Face: pill eyes, "w" mouth, blush dashes.
        let eyeW: CGFloat = style.template ? 7 : 3.9
        let eyeH: CGFloat = style.template ? 12 : 7.6
        ctx.setFillColor(style.ink.cgColor)
        for x: CGFloat in [33, 57] {
            ctx.addPath(CGPath(roundedRect: CGRect(x: x - eyeW / 2, y: 50 - eyeH / 2, width: eyeW, height: eyeH),
                               cornerWidth: eyeW / 2, cornerHeight: eyeW / 2, transform: nil))
        }
        ctx.fillPath()

        if !style.template {
            let mouth = CGMutablePath()
            mouth.move(to: CGPoint(x: 40.6, y: 53))
            mouth.addQuadCurve(to: CGPoint(x: 45, y: 53), control: CGPoint(x: 42.8, y: 57.6))
            mouth.addQuadCurve(to: CGPoint(x: 49.4, y: 53), control: CGPoint(x: 47.2, y: 57.6))
            ctx.setStrokeColor(style.ink.cgColor)
            ctx.setLineWidth(1.9)
            ctx.addPath(mouth)
            ctx.strokePath()

            if let pink = style.pink {
                ctx.setStrokeColor(pink.cgColor)
                ctx.setLineWidth(2.3)
                for (x, dir) in [(CGFloat(21.5), CGFloat(1)), (CGFloat(68.5), CGFloat(-1))] {
                    for y: CGFloat in [52.5, 58] {
                        ctx.move(to: CGPoint(x: x - 2.6, y: y + 0.5 * dir))
                        ctx.addLine(to: CGPoint(x: x + 2.6, y: y - 0.5 * dir))
                    }
                }
                ctx.strokePath()
            }
        }

        if let sp = style.sparkle {
            ctx.setFillColor(sp.cgColor)
            ctx.addPath(Brand.sparkle(center: CGPoint(x: 99, y: 21), radius: 10, plump: 0.3))
            ctx.fillPath()
        }

        ctx.restoreGState()
    }

    /// The mark as an NSImage (for SwiftUI and the menu bar).
    static func image(size: CGFloat, style: Style = .brand) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            if let ctx = NSGraphicsContext.current?.cgContext { draw(in: ctx, rect: r, style: style) }
            return true
        }
        img.isTemplate = style.template
        return img
    }
}
