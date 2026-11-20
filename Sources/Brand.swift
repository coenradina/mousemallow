// Brand colors, the mousemallow mark (a chubby cursor-shaped mouse seen from above)
// and the wordmark. Shared by the app and by Tools/render_assets.swift.

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
    /// Design space is y-down with the nose near the origin. Includes the whiskers,
    /// ears, sticker shadow and sparkles.
    static let bounds = CGRect(x: -28, y: -26, width: 126, height: 150)

    /// Chubby arrow with puffy sides and a short tail.
    static let body: CGPath = {
        let p = CGMutablePath()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        p.move(to: pt(-0.5, 9))
        // Left side, puffing out toward the belly.
        p.addCurve(to: pt(-2, 84), control1: pt(-4, 35), control2: pt(-7.5, 62))
        p.addCurve(to: pt(12, 98), control1: pt(0, 95), control2: pt(5, 100))
        p.addCurve(to: pt(29, 85), control1: pt(18, 95), control2: pt(24, 90))
        // Short tail, angled along the body like a cursor stalk.
        p.addCurve(to: pt(38, 104), control1: pt(32, 92), control2: pt(35, 99))
        p.addCurve(to: pt(51, 99), control1: pt(41, 111), control2: pt(51.5, 107.5))
        p.addCurve(to: pt(45, 80), control1: pt(50.5, 92), control2: pt(48, 86))
        p.addCurve(to: pt(72, 78), control1: pt(54, 78), control2: pt(63, 80))
        p.addCurve(to: pt(78, 64), control1: pt(81, 77), control2: pt(83, 70))
        // Back, puffing out toward the upper right, then the tip.
        p.addCurve(to: pt(6, 2), control1: pt(60, 40), control2: pt(30, 13))
        p.addCurve(to: pt(-0.5, 9), control1: pt(2, -1), control2: pt(-1, 3))
        p.closeSubpath()
        return p
    }()

    // Body axis: `u` runs from the nose toward the tail, `n` across it.
    static let u = CGPoint(x: 0.42, y: 0.907)
    static let n = CGPoint(x: 0.907, y: -0.42)
    static func at(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
        CGPoint(x: u.x * along + n.x * across, y: u.y * along + n.y * across)
    }
    static let axisAngle = atan2(u.y, u.x)

    static let nose = at(7, 0)
    static let eyes = [at(32, -8), at(32, 8)]

    /// Each ear is a circle tucked behind the body edge, so only a half-moon shows.
    /// The pink inner circle is clipped to the part outside the body.
    static let ears: [(outer: CGPath, inner: CGPath)] = {
        let r: CGFloat = 14.5
        let edges: [(CGPoint, CGPoint)] = [
            (CGPoint(x: -5.4, y: 56), CGPoint(x: -1, y: -0.05)),     // point on the edge, outward direction
            (CGPoint(x: 48, y: 31.8), CGPoint(x: 0.653, y: -0.757)),
        ]
        return edges.map { e, o in
            let c = CGPoint(x: e.x + o.x * r * 0.12, y: e.y + o.y * r * 0.12)
            let ic = CGPoint(x: c.x + o.x * r * 0.2, y: c.y + o.y * r * 0.2)
            return (circle(c, r), circle(ic, r * 0.62))
        }
    }()

    /// Four short rays fanning out from the nose, like a "click" icon.
    static let whiskers: [(CGPoint, CGPoint)] = {
        let outward = axisAngle + .pi
        return [(-66.0, 9.0), (-26.0, 11.0), (26.0, 11.0), (66.0, 9.0)].map { (deg: CGFloat, len: CGFloat) in
            let a = outward + deg * .pi / 180
            let d = CGPoint(x: cos(a), y: sin(a))
            let start: CGFloat = 9
            return (CGPoint(x: nose.x + d.x * start, y: nose.y + d.y * start),
                    CGPoint(x: nose.x + d.x * (start + len), y: nose.y + d.y * (start + len)))
        }
    }()

    static func circle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
    }
    static func oval(_ c: CGPoint, _ along: CGFloat, _ across: CGFloat) -> CGPath {
        var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: axisAngle)
        return CGPath(ellipseIn: CGRect(x: -along, y: -across, width: 2 * along, height: 2 * across), transform: &t)
    }

    static var silhouette: [CGPath] { [body] + ears.map(\.outer) }

    struct Style {
        var fill: NSColor = Brand.cream
        var ink: NSColor = Brand.ink
        var pink: NSColor? = Brand.blush
        var shadow: NSColor? = Brand.berryMilk
        var sparkles: [NSColor]? = [Brand.lavender, Brand.mint]
        var lineWidth: CGFloat = 4.2
        var whiskers = true
        var template = false

        static let brand = Style()
        static let plain = Style(sparkles: nil)
        /// Single-color outline with a cut-out body and no whiskers, for the menu bar.
        static let menuBar = Style(fill: .black, ink: .black, pink: nil, shadow: nil, sparkles: nil,
                                   lineWidth: 8, whiskers: false, template: true)
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
        // outline of the union survives, so the ears and body read as one shape.
        ctx.setStrokeColor(style.ink.cgColor)
        ctx.setLineWidth(lw * 2)
        for p in shapes { ctx.addPath(p); ctx.strokePath() }
        if style.template { ctx.setBlendMode(.clear) }
        ctx.setFillColor(style.fill.cgColor)
        for p in shapes { ctx.addPath(p); ctx.fillPath() }
        ctx.setBlendMode(.normal)

        if let pink = style.pink {
            ctx.saveGState()
            ctx.addRect(bounds.insetBy(dx: -50, dy: -50))
            ctx.addPath(body)
            ctx.clip(using: .evenOdd)
            ctx.setFillColor(pink.cgColor)
            for ear in ears { ctx.addPath(ear.inner) }
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Eyes: ovals along the body axis with a white highlight.
        ctx.setFillColor(style.ink.cgColor)
        for e in eyes { ctx.addPath(style.template ? oval(e, 6, 4.6) : oval(e, 5.6, 4.2)) }
        ctx.fillPath()
        if !style.template {
            ctx.setFillColor(NSColor.white.cgColor)
            for e in eyes { ctx.addPath(circle(CGPoint(x: e.x - u.x * 2.1, y: e.y - u.y * 2.1), 1.6)) }
            ctx.fillPath()
        }

        // Nose at the tip of the arrow.
        ctx.setFillColor((style.pink ?? style.ink).cgColor)
        ctx.setStrokeColor(style.ink.cgColor)
        ctx.setLineWidth(1.8)
        ctx.addPath(circle(nose, style.template ? 5 : 4.4))
        ctx.drawPath(using: style.template ? .fill : .fillStroke)

        if style.whiskers {
            ctx.setStrokeColor(style.ink.cgColor)
            ctx.setLineWidth(2.4)
            for (a, b) in whiskers { ctx.move(to: a); ctx.addLine(to: b) }
            ctx.strokePath()
        }

        if let sp = style.sparkles {
            let spots: [(CGPoint, CGFloat)] = [(CGPoint(x: 84, y: 20), 10), (CGPoint(x: 70, y: 3), 4.5)]
            for (color, spot) in zip(sp, spots) {
                ctx.setFillColor(color.cgColor)
                ctx.addPath(Brand.sparkle(center: spot.0, radius: spot.1, plump: 0.3))
                ctx.fillPath()
            }
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

/// "mousemallow" set in Sniglet Regular, thickened, with a round two-bowl "w"
/// and a sparkle cut out of the first "o".
enum Wordmark {
    /// Where Sniglet-Regular.ttf lives. The app finds it in its bundle; the asset tool sets it.
    static var fontURL: URL? = Bundle.main.url(forResource: "Sniglet-Regular", withExtension: "ttf")

    static let text = "mousemallow"
    static let weight: CGFloat = 0.035    // extra stroke on each side, as a fraction of the size
    static let tracking: CGFloat = 0.015

    static func font(size: CGFloat) -> CTFont {
        if let url = fontURL,
           let d = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first {
            return CTFontCreateWithFontDescriptor(d, size, nil)
        }
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
    }

    /// Two "u" bowls sharing a shorter middle stem, as an outline path.
    static func roundW(size: CGFloat) -> (path: CGPath, advance: CGFloat) {
        let sw = size * 0.1                      // Sniglet Regular's stem
        let top = size * 0.515 - sw / 2, bottom = -size * 0.012 + sw / 2
        let bowl = size * 0.32, r = bowl / 2
        let l = size * 0.03 + sw / 2, m = l + bowl, rt = m + bowl
        let midTop = bottom + (top - bottom) * 0.7
        let p = CGMutablePath()
        p.move(to: CGPoint(x: l, y: top))
        p.addArc(center: CGPoint(x: l + r, y: bottom + r), radius: r, startAngle: .pi, endAngle: 0, clockwise: false)
        p.addLine(to: CGPoint(x: m, y: midTop))
        p.move(to: CGPoint(x: m, y: bottom + r))
        p.addArc(center: CGPoint(x: m + r, y: bottom + r), radius: r, startAngle: .pi, endAngle: 0, clockwise: false)
        p.addLine(to: CGPoint(x: rt, y: top))
        let outline = p.copy(strokingWithWidth: sw, lineCap: .round, lineJoin: .round, miterLimit: 1)
        return (outline, rt + sw / 2 + size * 0.03)
    }

    /// Glyph outlines with the baseline at y = 0 and the left edge at x = 0, the total
    /// width, and the sparkle to cut out.
    static func layout(size: CGFloat) -> (glyphs: CGPath, width: CGFloat, sparkle: CGPath) {
        let font = font(size: size)
        let bold = size * weight
        let custom = fontURL != nil
        let path = CGMutablePath()
        var x: CGFloat = 0
        var sparkleCenter = CGPoint.zero
        for (i, ch) in text.enumerated() {
            var glyphPath: CGPath?
            var advance: CGFloat = 0
            if ch == "w" && custom {
                (glyphPath, advance) = roundW(size: size)
            } else {
                var c = Array(String(ch).utf16), g: CGGlyph = 0
                CTFontGetGlyphsForCharacters(font, &c, &g, 1)
                var a = CGSize.zero
                CTFontGetAdvancesForGlyphs(font, .horizontal, [g], &a, 1)
                glyphPath = CTFontCreatePathForGlyph(font, g, nil)
                advance = a.width
            }
            advance += 2 * bold
            if let gp = glyphPath { path.addPath(gp, transform: CGAffineTransform(translationX: x + bold, y: 0)) }
            if i == 1 { sparkleCenter = CGPoint(x: x + advance / 2, y: CTFontGetXHeight(font) / 2) }
            x += advance + (i < text.count - 1 ? size * tracking : 0)
        }
        let sparkle = Brand.sparkle(center: sparkleCenter, radius: size * 0.24, plump: 0.3)
        return (path, x, sparkle)
    }

    /// Draws the wordmark centered on `centerX`. The sparkle is cut out, so the background shows through.
    static func draw(in ctx: CGContext, centerX: CGFloat, baseline: CGFloat, size: CGFloat, color: NSColor = Brand.ink) {
        let (glyphs, width, sparkle) = layout(size: size)
        ctx.saveGState()
        ctx.translateBy(x: centerX - width / 2, y: baseline)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setLineJoin(.round)
        ctx.setFillColor(color.cgColor)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(2 * size * weight)
        ctx.addPath(glyphs)
        ctx.drawPath(using: .fillStroke)
        ctx.setBlendMode(.clear)
        ctx.addPath(sparkle)
        ctx.fillPath()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// The wordmark as an NSImage of the given font size.
    static func image(size: CGFloat, color: NSColor = Brand.ink) -> NSImage {
        let width = layout(size: size).width
        let ascent = size * 0.8, descent = size * 0.06   // Sniglet's "l" reaches about 0.77 em
        return NSImage(size: NSSize(width: ceil(width + 2 * size * weight), height: ceil(ascent + descent)),
                       flipped: false) { r in
            if let ctx = NSGraphicsContext.current?.cgContext {
                draw(in: ctx, centerX: r.midX, baseline: descent, size: size, color: color)
            }
            return true
        }
    }
}
