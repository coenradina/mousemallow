// mousemallow: a menu bar app that decorates the macOS cursor with a themed
// ring, ears, glow and particle trail, grows it when you circle the mouse,
// and warps it to the center of the main screen with a global hotkey.

import AppKit
import SwiftUI
import Carbon.HIToolbox
import ServiceManagement
import Combine
import QuartzCore

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

func circlePath(_ r: CGFloat, center c: CGPoint = .zero) -> CGPath {
    CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
}

// MARK: - Options

enum ParticleKind: String, CaseIterable, Identifiable {
    case themeDefault, none, mallows, sparkles, hearts, stars, bubbles, petals, confetti
    var id: String { rawValue }
    var label: String {
        switch self {
        case .themeDefault: "Theme default"
        case .none: "None"
        case .mallows: "☁️ Mini mallows"
        case .sparkles: "✨ Sparkles"
        case .hearts: "💗 Hearts"
        case .stars: "⭐️ Stars"
        case .bubbles: "🫧 Bubbles"
        case .petals: "🌸 Petals"
        case .confetti: "🎉 Confetti"
        }
    }
    /// Upward is positive. Hearts and bubbles float, confetti falls.
    var gravity: CGFloat {
        switch self {
        case .hearts: 40
        case .bubbles: 60
        case .mallows: -70
        case .stars: -30
        case .petals: -50
        case .confetti: -160
        default: 0
        }
    }
    var spin: CGFloat {
        switch self {
        case .hearts: 0.8
        case .bubbles: 0
        case .mallows: 2
        default: 4
        }
    }
}

enum EarStyle: String, CaseIterable, Identifiable {
    case none, mouse, cat, bunny, bow
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "None"
        case .mouse: "🐭 Mouse"
        case .cat: "🐱 Cat"
        case .bunny: "🐰 Bunny"
        case .bow: "🎀 Bow"
        }
    }
}

enum RingStyle: String, CaseIterable, Identifiable {
    case ring, double, dotted, soft
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ring: "Ring"
        case .double: "Double"
        case .dotted: "Dotted"
        case .soft: "Soft blob"
        }
    }
}

struct Theme: Identifiable {
    let id: String
    let name: String
    let icon: String
    let palette: [NSColor]
    let particle: ParticleKind
    var outline: NSColor = Brand.ink
    var sticker: NSColor = Brand.berryMilk   // offset shadow, like the logo
    var cycles = false                        // ring color drifts through the palette

    var primary: NSColor { palette[0] }
    var secondary: NSColor { palette.count > 1 ? palette[1] : palette[0] }

    static let all: [Theme] = [
        Theme(id: "marshmallow", name: "Marshmallow", icon: "☁️",
              palette: [Brand.cream, Brand.blush], particle: .mallows),
        Theme(id: "berry", name: "Berry Milk", icon: "🍓",
              palette: [Brand.berryMilk, Brand.marshmallow], particle: .hearts, sticker: Brand.lavender),
        Theme(id: "lavender", name: "Lavender Haze", icon: "💜",
              palette: [Brand.lavender, Brand.berryMilk], particle: .sparkles),
        Theme(id: "mint", name: "Mint Mallow", icon: "🌿",
              palette: [Brand.mint, Brand.marshmallow], particle: .petals),
        Theme(id: "cotton", name: "Cotton Candy", icon: "🍬",
              palette: [Brand.berryMilk, Brand.lavender], particle: .bubbles, sticker: Brand.mint),
        Theme(id: "ink", name: "Ink Night", icon: "🌙",
              palette: [Brand.ink, Brand.lavender], particle: .stars,
              outline: Brand.marshmallow, sticker: Brand.lavender),
        Theme(id: "mix", name: "Mallow Mix", icon: "🍡",
              palette: [Brand.berryMilk, Brand.lavender, Brand.mint, Brand.marshmallow],
              particle: .confetti, cycles: true),
    ]
}

// MARK: - Preferences (saved in UserDefaults)

@MainActor
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private static let d = UserDefaults.standard

    @Published var themeID: String { didSet { Self.d.set(themeID, forKey: "themeID") } }
    @Published var customPrimaryHex: String { didSet { Self.d.set(customPrimaryHex, forKey: "customPrimaryHex") } }
    @Published var customSecondaryHex: String { didSet { Self.d.set(customSecondaryHex, forKey: "customSecondaryHex") } }
    @Published var ringStyle: RingStyle { didSet { Self.d.set(ringStyle.rawValue, forKey: "ringStyle") } }
    @Published var ears: EarStyle { didSet { Self.d.set(ears.rawValue, forKey: "ears") } }
    @Published var particle: ParticleKind { didSet { Self.d.set(particle.rawValue, forKey: "particle") } }
    @Published var size: Double { didSet { Self.d.set(size, forKey: "size") } }
    @Published var opacity: Double { didSet { Self.d.set(opacity, forKey: "opacity") } }
    @Published var trailAmount: Double { didSet { Self.d.set(trailAmount, forKey: "trailAmount") } }
    @Published var glow: Bool { didSet { Self.d.set(glow, forKey: "glow") } }
    @Published var outline: Bool { didSet { Self.d.set(outline, forKey: "outline") } }
    @Published var sticker: Bool { didSet { Self.d.set(sticker, forKey: "sticker") } }
    @Published var wiggle: Bool { didSet { Self.d.set(wiggle, forKey: "wiggle") } }
    @Published var clickRipple: Bool { didSet { Self.d.set(clickRipple, forKey: "clickRipple") } }
    @Published var shakeToFind: Bool { didSet { Self.d.set(shakeToFind, forKey: "shakeToFind") } }
    @Published var shakeSensitivity: Double { didSet { Self.d.set(shakeSensitivity, forKey: "shakeSensitivity") } }
    @Published var hideWhenIdle: Bool { didSet { Self.d.set(hideWhenIdle, forKey: "hideWhenIdle") } }
    @Published var paused: Bool { didSet { Self.d.set(paused, forKey: "paused") } }
    @Published var hotKeyCode: Int { didSet { Self.d.set(hotKeyCode, forKey: "hotKeyCode") } }
    @Published var hotKeyMods: Int { didSet { Self.d.set(hotKeyMods, forKey: "hotKeyMods") } }
    @Published var hotKeyLabel: String { didSet { Self.d.set(hotKeyLabel, forKey: "hotKeyLabel") } }
    @Published var hotKeyFailed = false

    private init() {
        let d = Self.d
        themeID = d.string(forKey: "themeID") ?? "marshmallow"
        customPrimaryHex = d.string(forKey: "customPrimaryHex") ?? Brand.berryMilk.hexString
        customSecondaryHex = d.string(forKey: "customSecondaryHex") ?? Brand.mint.hexString
        ringStyle = RingStyle(rawValue: d.string(forKey: "ringStyle") ?? "") ?? .ring
        ears = EarStyle(rawValue: d.string(forKey: "ears") ?? "") ?? .mouse
        particle = ParticleKind(rawValue: d.string(forKey: "particle") ?? "") ?? .themeDefault
        size = d.object(forKey: "size") as? Double ?? 1.0
        opacity = d.object(forKey: "opacity") as? Double ?? 1.0
        trailAmount = d.object(forKey: "trailAmount") as? Double ?? 1.0
        glow = d.object(forKey: "glow") as? Bool ?? true
        outline = d.object(forKey: "outline") as? Bool ?? true
        sticker = d.object(forKey: "sticker") as? Bool ?? true
        wiggle = d.object(forKey: "wiggle") as? Bool ?? true
        clickRipple = d.object(forKey: "clickRipple") as? Bool ?? true
        shakeToFind = d.object(forKey: "shakeToFind") as? Bool ?? true
        shakeSensitivity = d.object(forKey: "shakeSensitivity") as? Double ?? 0.5
        hideWhenIdle = d.object(forKey: "hideWhenIdle") as? Bool ?? false
        paused = d.object(forKey: "paused") as? Bool ?? false
        hotKeyCode = d.object(forKey: "hotKeyCode") as? Int ?? kVK_ANSI_C
        hotKeyMods = d.object(forKey: "hotKeyMods") as? Int ?? (controlKey | optionKey)
        hotKeyLabel = d.string(forKey: "hotKeyLabel") ?? "⌃⌥C"
    }

    var customTheme: Theme {
        let a = NSColor(hex: customPrimaryHex), b = NSColor(hex: customSecondaryHex)
        return Theme(id: "custom", name: "My Colors", icon: "🖍️", palette: [a, b], particle: .sparkles, sticker: b)
    }

    var allThemes: [Theme] { Theme.all + [customTheme] }

    var theme: Theme {
        themeID == "custom" ? customTheme : (Theme.all.first { $0.id == themeID } ?? Theme.all[0])
    }

    var particleKind: ParticleKind { particle == .themeDefault ? theme.particle : particle }
}

// MARK: - Particle images
//
// Shapes are white with a dark gray rim. The emitter tints them with the theme
// color, so the rim becomes a darker shade of the same color: an outline that
// keeps pale particles visible on white pages, like the logo's ink outline.

enum ParticleArt {
    static var cache: [ParticleKind: CGImage] = [:]
    static let rim = NSColor(white: 0.32, alpha: 1)

    static func image(_ kind: ParticleKind) -> CGImage? {
        if let c = cache[kind] { return c }
        let s: CGFloat = 48
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let r = NSRect(x: 0, y: 0, width: s, height: s)
        let c = NSPoint(x: s / 2, y: s / 2)

        func outlined(_ p: NSBezierPath) {
            p.lineJoinStyle = .round
            p.lineWidth = 5
            rim.setStroke()
            p.stroke()
            NSColor.white.setFill()
            p.fill()
        }

        switch kind {
        case .hearts:
            outlined(heart(in: r.insetBy(dx: 8, dy: 9)))
        case .stars:
            outlined(NSBezierPath(cgPath: star(center: c, outer: 19, inner: 9, points: 5)))
        case .sparkles:
            outlined(NSBezierPath(cgPath: Brand.sparkle(center: c, radius: 20, plump: 0.24)))
        case .bubbles:
            let p = NSBezierPath(ovalIn: r.insetBy(dx: 8, dy: 8))
            p.lineWidth = 7
            rim.setStroke()
            p.stroke()
            NSColor.white.withAlphaComponent(0.3).setFill()
            p.fill()
            p.lineWidth = 3
            NSColor.white.setStroke()
            p.stroke()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: 15, y: 26, width: 7, height: 7)).fill()
        case .mallows:
            // A little marshmallow seen from the side: body plus a top face.
            outlined(NSBezierPath(roundedRect: NSRect(x: 9, y: 11, width: 30, height: 24), xRadius: 9, yRadius: 9))
            let top = NSBezierPath(ovalIn: NSRect(x: 12, y: 25, width: 24, height: 9))
            top.lineWidth = 2
            rim.withAlphaComponent(0.6).setStroke()
            top.stroke()
        case .petals:
            outlined(NSBezierPath(ovalIn: NSRect(x: 16, y: 7, width: 16, height: 34)))
        case .confetti:
            outlined(NSBezierPath(roundedRect: NSRect(x: 17, y: 9, width: 14, height: 30), xRadius: 4, yRadius: 4))
        case .none, .themeDefault:
            outlined(NSBezierPath(ovalIn: r.insetBy(dx: 13, dy: 13)))
        }
        NSGraphicsContext.restoreGraphicsState()
        let img = rep.cgImage
        cache[kind] = img
        return img
    }

    static func heart(in r: NSRect) -> NSBezierPath {
        let p = NSBezierPath()
        let x = r.minX, y = r.minY, w = r.width, h = r.height
        p.move(to: NSPoint(x: x + w / 2, y: y))
        p.curve(to: NSPoint(x: x, y: y + h * 0.66),
                controlPoint1: NSPoint(x: x + w * 0.32, y: y + h * 0.2),
                controlPoint2: NSPoint(x: x, y: y + h * 0.42))
        p.appendArc(withCenter: NSPoint(x: x + w * 0.25, y: y + h * 0.66), radius: w * 0.25,
                    startAngle: 180, endAngle: 0, clockwise: true)
        p.appendArc(withCenter: NSPoint(x: x + w * 0.75, y: y + h * 0.66), radius: w * 0.25,
                    startAngle: 180, endAngle: 0, clockwise: true)
        p.curve(to: NSPoint(x: x + w / 2, y: y),
                controlPoint1: NSPoint(x: x + w, y: y + h * 0.42),
                controlPoint2: NSPoint(x: x + w * 0.68, y: y + h * 0.2))
        p.close()
        return p
    }

    static func star(center c: NSPoint, outer: CGFloat, inner: CGFloat, points: Int) -> CGPath {
        let p = CGMutablePath()
        for i in 0..<(points * 2) {
            let r = i.isMultiple(of: 2) ? outer : inner
            let q = polar(90 + CGFloat(i) * 180 / CGFloat(points), r)
            let pt = CGPoint(x: c.x + q.x, y: c.y + q.y)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - One overlay window per screen

@MainActor
final class CursorScene {
    let screen: NSScreen
    let frame: CGRect
    let window: NSWindow
    let root = CALayer()
    let emitter = CAEmitterLayer()
    let container = CALayer()   // follows the cursor, scales and leans
    let breather = CALayer()    // gentle idle "breathing"
    let glow = CAGradientLayer()
    let ringBack = CAShapeLayer()   // ink outline and sticker shadow behind the ring
    let ring = CAShapeLayer()
    let ring2 = CAShapeLayer()
    let ears = CAShapeLayer()
    let earsInner = CAShapeLayer()
    var radius: CGFloat = 20
    var style: RingStyle = .ring

    init(screen: NSScreen) {
        self.screen = screen
        frame = screen.frame
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.layer = root
        view.wantsLayer = true
        window.contentView = view
        window.setFrame(frame, display: false)

        let scale = screen.backingScaleFactor
        root.contentsScale = scale

        emitter.frame = CGRect(origin: .zero, size: frame.size)
        emitter.emitterShape = .point
        emitter.renderMode = .unordered
        emitter.birthRate = 0
        emitter.beginTime = CACurrentMediaTime()
        root.addSublayer(emitter)

        container.bounds = .zero
        root.addSublayer(container)
        container.addSublayer(breather)

        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.zPosition = -2
        ringBack.zPosition = -0.2
        ring.zPosition = 0
        ring2.zPosition = 0.5
        for l in [glow, ears, earsInner, ringBack, ring2, ring] as [CALayer] {
            l.contentsScale = scale * 2.5   // stay crisp when the ring grows
            breather.addSublayer(l)
        }

        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = 0.95
        breathe.toValue = 1.05
        breathe.duration = 1.3
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        breathe.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 24, preferred: 20)
        breather.add(breathe, forKey: "breathe")

        window.orderFrontRegardless()
    }

    func apply(_ p: Prefs) {
        let t = p.theme
        let s = CGFloat(p.size)
        let R = 20 * s
        radius = R
        style = p.ringStyle

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        ring.path = circlePath(R)
        ring.lineWidth = 4 * s
        ring.lineCap = .round
        ring.lineDashPattern = nil
        ring.lineDashPhase = 0
        ring2.isHidden = true
        ring2.lineDashPattern = nil
        ring2.lineDashPhase = 0
        ring2.fillColor = nil
        ringBack.path = ring.path
        ringBack.fillColor = nil
        ringBack.lineCap = .round
        ringBack.lineDashPattern = nil
        for l in [ring, ring2, ringBack] { l.removeAnimation(forKey: "spin") }

        switch p.ringStyle {
        case .ring, .soft:
            break
        case .double:
            ring2.isHidden = false
            ring2.path = circlePath(R - 5 * s)
            ring2.lineWidth = 2 * s
        case .dotted:
            let circumference = 2 * .pi * R
            var n = (circumference / (8 * s)).rounded()
            if Int(n) % 2 == 1 { n += 1 }
            let gap = circumference / n
            ring.lineWidth = 5 * s
            ring.lineDashPattern = [0, NSNumber(value: Double(gap * 2))]
            ring2.isHidden = false
            ring2.path = ring.path
            ring2.lineWidth = 5 * s
            ring2.lineCap = .round
            ring2.lineDashPattern = [0, NSNumber(value: Double(gap * 2))]
            ring2.lineDashPhase = gap
            ringBack.lineDashPattern = [0, NSNumber(value: Double(gap))]
            for l in [ring, ring2, ringBack] {
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0
                spin.toValue = -2 * Double.pi
                spin.duration = 6
                spin.repeatCount = .infinity
                spin.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 24)
                l.add(spin, forKey: "spin")
            }
        }

        // Outline: a wider ink stroke behind the ring, so only its edges show.
        ringBack.isHidden = !p.outline
        ringBack.strokeColor = t.outline.cgColor
        ringBack.lineWidth = p.ringStyle == .soft ? 2.5 * s : ring.lineWidth + 3.2 * s

        // Sticker shadow: a flat offset copy in the theme's sticker color.
        let stickerTarget: CALayer = p.outline ? ringBack : ring
        for l in [ring, ringBack, ears] as [CALayer] {
            l.shadowOpacity = 0
        }
        for l in [stickerTarget, ears] {
            l.shadowColor = t.sticker.cgColor
            l.shadowOffset = CGSize(width: 1.6 * s, height: -2.2 * s)
            l.shadowRadius = 0
            l.shadowOpacity = p.sticker ? 1 : 0
        }

        let G = R * (p.ringStyle == .soft ? 5.2 : 4.4)
        glow.bounds = CGRect(x: 0, y: 0, width: G, height: G)
        glow.position = .zero
        glow.isHidden = !(p.glow || p.ringStyle == .soft)

        let (outer, inner) = earPaths(p.ears, R)
        ears.path = outer
        earsInner.path = inner
        ears.isHidden = outer == nil
        earsInner.isHidden = inner == nil
        ears.strokeColor = t.outline.cgColor
        ears.lineWidth = p.outline ? 2.6 * s : 0
        ears.lineJoin = .round
        let earsOnTop = p.ears == .bow
        ears.zPosition = earsOnTop ? 1 : -1
        earsInner.zPosition = earsOnTop ? 1.5 : -0.5
        // Ears behind the ring: cut away anything inside it.
        if earsOnTop {
            ears.mask = nil
            earsInner.mask = nil
        } else {
            for l in [ears, earsInner] {
                let m = CAShapeLayer()
                let cut = CGMutablePath()
                cut.addRect(CGRect(x: -6 * R, y: -6 * R, width: 12 * R, height: 12 * R))
                cut.addPath(circlePath(R))
                m.path = cut
                m.fillRule = .evenOdd
                l.mask = m
            }
        }

        recolor(t.primary, t.secondary)
        configureEmitter(theme: t, kind: p.particleKind, size: s)

        CATransaction.commit()
    }

    func recolor(_ primary: NSColor, _ secondary: NSColor) {
        switch style {
        case .soft:
            ring.strokeColor = nil
            ring.fillColor = primary.withAlphaComponent(0.55).cgColor
        default:
            ring.strokeColor = primary.cgColor
            ring.fillColor = primary.withAlphaComponent(0.18).cgColor
        }
        ring2.strokeColor = secondary.cgColor
        ears.fillColor = primary.cgColor
        earsInner.fillColor = secondary.cgColor
        let strong: CGFloat = style == .soft ? 0.6 : 0.45
        glow.colors = [primary.withAlphaComponent(strong).cgColor,
                       primary.withAlphaComponent(strong * 0.4).cgColor,
                       primary.withAlphaComponent(0).cgColor]
        glow.locations = [0, 0.4, 1]
    }

    func earPaths(_ style: EarStyle, _ R: CGFloat) -> (CGPath?, CGPath?) {
        switch style {
        case .none:
            return (nil, nil)
        case .mouse:
            // Two round ears, the left one a little bigger, like the logo.
            let o = CGMutablePath(), i = CGMutablePath()
            for (angle, dist, r): (CGFloat, CGFloat, CGFloat) in [(124, 1.12, 0.54), (58, 1.08, 0.45)] {
                let c = polar(angle, R * dist)
                o.addPath(circlePath(R * r, center: c))
                i.addPath(circlePath(R * r * 0.55, center: c))
            }
            return (o, i)
        case .cat:
            let o = CGMutablePath(), i = CGMutablePath()
            for c: CGFloat in [128, 52] {
                let b1 = polar(c - 24, R * 0.9), b2 = polar(c + 24, R * 0.9), tip = polar(c, R * 1.85)
                o.move(to: b1)
                o.addArc(tangent1End: tip, tangent2End: b2, radius: R * 0.18)
                o.addLine(to: b2)
                o.closeSubpath()
                let cen = CGPoint(x: (b1.x + b2.x + tip.x) / 3, y: (b1.y + b2.y + tip.y) / 3)
                func shrink(_ p: CGPoint) -> CGPoint {
                    CGPoint(x: cen.x + (p.x - cen.x) * 0.5, y: cen.y + (p.y - cen.y) * 0.5)
                }
                i.move(to: shrink(b1))
                i.addArc(tangent1End: shrink(tip), tangent2End: shrink(b2), radius: R * 0.08)
                i.addLine(to: shrink(b2))
                i.closeSubpath()
            }
            return (o, i)
        case .bunny:
            let o = CGMutablePath(), i = CGMutablePath()
            for c: CGFloat in [106, 74] {
                let center = polar(c, R * 1.7)
                let t = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: (c - 90) * .pi / 180)
                let w = R * 0.62, h = R * 1.5
                o.addEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), transform: t)
                let iw = w * 0.45, ih = h * 0.7
                i.addEllipse(in: CGRect(x: -iw / 2, y: -ih / 2 - h * 0.05, width: iw, height: ih), transform: t)
            }
            return (o, i)
        case .bow:
            let o = CGMutablePath(), i = CGMutablePath()
            let c = polar(48, R * 1.02)
            let w = R * 0.85, h = R * 0.56
            for (dx, rot): (CGFloat, CGFloat) in [(-0.38, 0.35), (0.38, -0.35)] {
                let t = CGAffineTransform(translationX: c.x + dx * R, y: c.y).rotated(by: rot)
                o.addEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), transform: t)
            }
            i.addPath(circlePath(R * 0.2, center: c))
            return (o, i)
        }
    }

    func configureEmitter(theme: Theme, kind: ParticleKind, size s: CGFloat) {
        guard kind != .none, let img = ParticleArt.image(kind) else {
            emitter.emitterCells = nil
            return
        }
        let palette = theme.palette
        emitter.emitterCells = palette.enumerated().map { idx, color in
            let c = CAEmitterCell()
            c.name = "p\(idx)"
            c.contents = img
            c.birthRate = Float(45) / Float(palette.count)
            c.lifetime = 0.95
            c.lifetimeRange = 0.35
            c.velocity = 35
            c.velocityRange = 30
            c.emissionRange = .pi * 2
            c.scale = 0.34 * s
            c.scaleRange = 0.12 * s
            c.scaleSpeed = -0.28 * s
            c.alphaSpeed = -1.0
            c.spinRange = kind.spin
            c.yAcceleration = kind.gravity
            c.color = color.cgColor
            return c
        }
    }

    func update(point p: CGPoint, scale: CGFloat, rotation: CGFloat, opacity: Double,
                birth: Double, colors: (NSColor, NSColor)?) {
        let inside = frame.contains(p)
        let near = frame.insetBy(dx: -150, dy: -150).contains(p)
        let local = CGPoint(x: p.x - frame.minX, y: p.y - frame.minY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.isHidden = !near
        if near {
            container.position = local
            container.transform = CATransform3DRotate(CATransform3DMakeScale(scale, scale, 1), rotation, 0, 0, 1)
            container.opacity = Float(opacity)
            if let c = colors { recolor(c.0, c.1) }
        }
        emitter.emitterPosition = local
        emitter.birthRate = Float(inside ? birth : 0)
        CATransaction.commit()
    }

    /// Expanding circle that fades out. Used for clicks, summoning and "found it!".
    func ping(at p: CGPoint, color: NSColor, toScale: CGFloat, duration: CFTimeInterval, width: CGFloat) {
        guard frame.contains(p) else { return }
        let l = CAShapeLayer()
        l.path = circlePath(radius)
        l.fillColor = nil
        l.strokeColor = color.cgColor
        l.lineWidth = width
        l.contentsScale = screen.backingScaleFactor * 2
        l.position = CGPoint(x: p.x - frame.minX, y: p.y - frame.minY)
        l.opacity = 0
        root.addSublayer(l)

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.4
        grow.toValue = toScale
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)

        CATransaction.begin()
        CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
        l.add(group, forKey: "ping")
        CATransaction.commit()
    }
}

// MARK: - Overlay controller: tracks the mouse and drives every scene

@MainActor
final class Overlay: NSObject {
    let prefs = Prefs.shared
    var scenes: [CursorScene] = []
    var timer: Timer?
    var clickMonitor: Any?

    var lastTime = CACurrentMediaTime()
    var lastPos = NSEvent.mouseLocation
    var vel = CGPoint.zero
    var history: [(t: CFTimeInterval, p: CGPoint)] = []
    var boost: CGFloat = 0
    var shakeHold: CFTimeInterval = 0
    var summonUntil: CFTimeInterval = 0
    var burstUntil: CFTimeInterval = 0
    var lastPing: CFTimeInterval = 0
    var lastMove = CACurrentMediaTime()
    var idleAlpha: CGFloat = 1
    var lean: CGFloat = 0
    var squish: CGFloat = 0
    var lastBirth: Double = 0
    var needsRefresh = true
    var fastTimer = true
    var lastActive = CACurrentMediaTime()

    func start() {
        rebuildScenes()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        setTimer(fast: true)
        // Mouse clicks can be observed globally without Accessibility permission.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.clicked() }
        }
    }

    /// 120 Hz while something is happening, 20 Hz at rest (saves battery).
    func setTimer(fast: Bool) {
        if timer != nil && fast == fastTimer { return }
        fastTimer = fast
        timer?.invalidate()
        let t = Timer(timeInterval: fast ? 1.0 / 120 : 1.0 / 20, target: self, selector: #selector(tick),
                      userInfo: nil, repeats: true)
        t.tolerance = fast ? 0 : 0.01
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc func screensChanged() { rebuildScenes() }

    func rebuildScenes() {
        for s in scenes { s.window.orderOut(nil) }
        scenes = NSScreen.screens.map { CursorScene(screen: $0) }
        applyPrefs()
    }

    func applyPrefs() {
        for s in scenes {
            s.apply(prefs)
            if prefs.paused { s.window.orderOut(nil) } else { s.window.orderFrontRegardless() }
        }
        needsRefresh = true
    }

    var currentColors: (NSColor, NSColor) {
        let t = prefs.theme
        guard t.cycles else { return (t.primary, t.secondary) }
        let pal = t.palette
        let n = pal.count
        func at(_ v: Double) -> NSColor {
            let i = Int(floor(v)) % n
            return pal[i].blended(withFraction: v - floor(v), of: pal[(i + 1) % n]) ?? pal[i]
        }
        let x = CACurrentMediaTime() * 0.35
        return (at(x), at(x + Double(n) / 2))
    }

    func pingAll(scale: CGFloat, duration: CFTimeInterval, width: CGFloat, double: Bool) {
        let p = NSEvent.mouseLocation
        let (a, b) = currentColors
        let first = a == Brand.cream ? Brand.berryMilk : a   // keep pale ripples visible
        for s in scenes { s.ping(at: p, color: first, toScale: scale, duration: duration, width: width) }
        guard double else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            for s in self.scenes { s.ping(at: p, color: b, toScale: scale, duration: duration, width: width) }
        }
    }

    func clicked() {
        guard !prefs.paused else { return }
        squish = 1
        lastMove = CACurrentMediaTime()
        if prefs.clickRipple { pingAll(scale: 2.2, duration: 0.4, width: 2.5, double: false) }
    }

    /// Warp the cursor to the center of the main display (the one with the menu bar).
    func summon() {
        let b = CGDisplayBounds(CGMainDisplayID())
        CGWarpMouseCursorPosition(CGPoint(x: b.midX, y: b.midY))
        CGAssociateMouseAndMouseCursorPosition(1)
        let mainHeight = NSScreen.screens.first?.frame.height ?? b.height
        lastPos = CGPoint(x: b.midX, y: mainHeight - b.midY)
        history.removeAll()
        vel = .zero
        let now = CACurrentMediaTime()
        summonUntil = now + 0.9
        burstUntil = now + 0.25
        lastMove = now
        needsRefresh = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.pingAll(scale: 7, duration: 0.8, width: 3, double: true)
        }
    }

    @objc func tick() {
        guard !prefs.paused else { return }
        let now = CACurrentMediaTime()
        let dt = clamp(now - lastTime, 1.0 / 480, 0.1)
        lastTime = now

        let p = NSEvent.mouseLocation
        let dx = p.x - lastPos.x, dy = p.y - lastPos.y
        let moved = hypot(dx, dy)
        lastPos = p
        let k = min(1, dt * 14)
        vel.x += (dx / dt - vel.x) * k
        vel.y += (dy / dt - vel.y) * k
        // Snap tiny velocities to zero so the idle check below can skip frames.
        if abs(vel.x) < 1 { vel.x = 0 }
        if abs(vel.y) < 1 { vel.y = 0 }

        if moved > 0.3 {
            lastMove = now
            history.append((now, p))
        }
        while let f = history.first, now - f.t > 0.45 { history.removeFirst() }

        // Circling or shaking: lots of travel, little net displacement.
        if prefs.shakeToFind, history.count > 4 {
            var path: CGFloat = 0
            for i in 1..<history.count {
                path += hypot(history[i].p.x - history[i - 1].p.x, history[i].p.y - history[i - 1].p.y)
            }
            let net = hypot(history.last!.p.x - history.first!.p.x, history.last!.p.y - history.first!.p.y)
            let need = 1100 - 700 * prefs.shakeSensitivity
            if path > need && net < path * 0.55 {
                if boost < 0.25 && now - lastPing > 0.8 {
                    lastPing = now
                    pingAll(scale: 5, duration: 0.6, width: 3, double: true)
                }
                shakeHold = now
            }
        }

        let wantBoost = (now - shakeHold < 0.4) || now < summonUntil
        boost += ((wantBoost ? 1 : 0) - boost) * min(1, dt * (wantBoost ? 7 : 2))
        if boost < 0.001 { boost = 0 }
        squish = squish < 0.001 ? 0 : squish * (1 - min(1, dt * 10))

        let idleTarget: CGFloat = (prefs.hideWhenIdle && now - lastMove > 2.5 && boost == 0) ? 0 : 1
        idleAlpha += (idleTarget - idleAlpha) * min(1, dt * (idleTarget > idleAlpha ? 16 : 1.8))
        if abs(idleTarget - idleAlpha) < 0.002 { idleAlpha = idleTarget }

        let leanTarget = prefs.wiggle ? clamp(-vel.x / 3000, -0.4, 0.4) : 0
        lean += (leanTarget - lean) * min(1, dt * 10)
        if abs(lean - leanTarget) < 0.0005 { lean = leanTarget }

        let speed = hypot(vel.x, vel.y)
        var birth = prefs.trailAmount * (moved > 0.3 ? min(1.0, Double(speed) / 700) : 0)
        birth += prefs.trailAmount * Double(boost) * 1.2
        if now < burstUntil { birth += 8 }

        let cycling = prefs.theme.cycles
        let busy = moved > 0.01 || boost > 0 || squish > 0 || lean != leanTarget || lean != 0
            || idleAlpha != idleTarget || cycling || needsRefresh || birth > 0 || lastBirth > 0
        guard busy else {
            // Nothing changed: skip the frame, and poll slowly after a short rest.
            if fastTimer && now - lastActive > 0.6 { setTimer(fast: false) }
            return
        }
        lastActive = now
        if !fastTimer { setTimer(fast: true) }
        needsRefresh = false
        lastBirth = birth

        let scale = (1 + boost * 2.3) * (1 - squish * 0.22)
        let colors: (NSColor, NSColor)? = cycling ? currentColors : nil
        for s in scenes {
            s.update(point: p, scale: scale, rotation: lean, opacity: prefs.opacity * Double(idleAlpha),
                     birth: birth, colors: colors)
        }
    }
}

// MARK: - Global hotkey (Carbon, needs no Accessibility permission)

let functionKeyNames: [Int: String] = [
    kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
    kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
    kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
]

func carbonMods(_ f: NSEvent.ModifierFlags) -> Int {
    var m = 0
    if f.contains(.command) { m |= cmdKey }
    if f.contains(.option) { m |= optionKey }
    if f.contains(.control) { m |= controlKey }
    if f.contains(.shift) { m |= shiftKey }
    return m
}

func shortcutLabel(_ e: NSEvent) -> String {
    let f = e.modifierFlags
    var s = ""
    if f.contains(.control) { s += "⌃" }
    if f.contains(.option) { s += "⌥" }
    if f.contains(.shift) { s += "⇧" }
    if f.contains(.command) { s += "⌘" }
    let code = Int(e.keyCode)
    if let fn = functionKeyNames[code] { return s + fn }
    switch code {
    case kVK_Space: return s + "Space"
    case kVK_Return: return s + "↩"
    case kVK_Tab: return s + "⇥"
    case kVK_Delete: return s + "⌫"
    case kVK_LeftArrow: return s + "←"
    case kVK_RightArrow: return s + "→"
    case kVK_UpArrow: return s + "↑"
    case kVK_DownArrow: return s + "↓"
    default: return s + (e.charactersIgnoringModifiers?.uppercased() ?? "?")
    }
}

@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    var action: (() -> Void)?
    var suspended = false
    private var ref: EventHotKeyRef?
    private var registered: (Int, Int)?
    private var handlerInstalled = false

    func unregister() {
        if let r = ref { UnregisterEventHotKey(r) }
        ref = nil
        registered = nil
    }

    func registerFromPrefs() {
        let p = Prefs.shared
        guard !suspended else { return }
        if let r = registered, r == (p.hotKeyCode, p.hotKeyMods) { return }
        unregister()
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                Task { @MainActor in HotKeyCenter.shared.action?() }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x4D4D4C57), id: 1)   // 'MMLW'
        let status = RegisterEventHotKey(UInt32(p.hotKeyCode), UInt32(p.hotKeyMods), id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            registered = (p.hotKeyCode, p.hotKeyMods)
            if p.hotKeyFailed { p.hotKeyFailed = false }
        } else {
            ref = nil
            if !p.hotKeyFailed { p.hotKeyFailed = true }
        }
    }
}

// MARK: - Settings window (SwiftUI)

extension Color {
    static let ink = Color(nsColor: Brand.ink)
    static let marshmallow = Color(nsColor: Brand.marshmallow)
    static let blush = Color(nsColor: Brand.blush)
}

struct ThemeChip: View {
    let theme: Theme
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Color(nsColor: theme.sticker)).frame(width: 20, height: 20).offset(x: 9, y: 2)
                Circle().fill(Color(nsColor: theme.secondary)).frame(width: 20, height: 20).offset(x: 5)
                    .overlay(Circle().stroke(Color(nsColor: theme.outline), lineWidth: 1.5).offset(x: 5))
                Circle().fill(Color(nsColor: theme.primary)).frame(width: 22, height: 22).offset(x: -4)
                    .overlay(Circle().stroke(Color(nsColor: theme.outline), lineWidth: 1.5).offset(x: -4))
            }
            .frame(width: 36)
            Text("\(theme.icon) \(theme.name)").font(.system(.callout, design: .rounded)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(selected ? 1 : 0.55)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.ink : .clear, lineWidth: 2))
        .contentShape(Rectangle())
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            Slider(value: $value, in: range)
        }
    }
}

struct HotKeyRecorder: View {
    @ObservedObject var prefs: Prefs
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Button(action: { recording ? stop() : start() }) {
                Text(recording ? "Press a shortcut…" : prefs.hotKeyLabel)
                    .frame(minWidth: 130)
            }
            if recording {
                Text("Esc to cancel").font(.caption2).foregroundStyle(.secondary)
            } else if prefs.hotKeyFailed {
                Text("Another app uses this one, try a different shortcut")
                    .font(.caption2).foregroundStyle(.red)
            }
        }
    }

    func start() {
        recording = true
        HotKeyCenter.shared.suspended = true
        HotKeyCenter.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let code = Int(e.keyCode)
            if code == kVK_Escape { stop(); return nil }
            let f = e.modifierFlags.intersection([.command, .option, .control, .shift])
            if f.subtracting(.shift).isEmpty && functionKeyNames[code] == nil {
                NSSound.beep()   // need ⌃, ⌥ or ⌘ unless it's an F-key
                return nil
            }
            prefs.hotKeyCode = code
            prefs.hotKeyMods = carbonMods(f)
            prefs.hotKeyLabel = shortcutLabel(e)
            stop()
            return nil
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = false
        HotKeyCenter.shared.suspended = false
        HotKeyCenter.shared.registerFromPrefs()
    }
}

struct SettingsView: View {
    @ObservedObject var prefs = Prefs.shared
    let summon: () -> Void
    @State private var loginOn = SMAppService.mainApp.status == .enabled
    @State private var loginNote: String?
    private let logo = MouseMark.image(size: 72)
    private let wordmark = Wordmark.image(size: 30)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(nsImage: logo)
                    VStack(alignment: .leading, spacing: 2) {
                        Image(nsImage: wordmark).accessibilityLabel("mousemallow")
                        Text("make your cursor a little cuter ♡")
                            .font(.system(.callout, design: .rounded)).foregroundStyle(Color.ink.opacity(0.65))
                    }
                }

                section("Theme") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                        ForEach(prefs.allThemes) { t in
                            ThemeChip(theme: t, selected: prefs.themeID == t.id)
                                .onTapGesture { prefs.themeID = t.id }
                        }
                    }
                    if prefs.themeID == "custom" {
                        HStack(spacing: 24) {
                            ColorPicker("Main color", selection: colorBinding(\.customPrimaryHex), supportsOpacity: false)
                            ColorPicker("Accent color", selection: colorBinding(\.customSecondaryHex), supportsOpacity: false)
                        }
                        .padding(.top, 4)
                    }
                }

                section("Look") {
                    Picker("Ring", selection: $prefs.ringStyle) {
                        ForEach(RingStyle.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    Picker("Ears", selection: $prefs.ears) {
                        ForEach(EarStyle.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    LabeledSlider(title: "Size", value: $prefs.size, range: 0.6...2.4)
                    LabeledSlider(title: "Opacity", value: $prefs.opacity, range: 0.3...1)
                    Toggle("Ink outline (easier to see on white pages)", isOn: $prefs.outline)
                    Toggle("Sticker shadow", isOn: $prefs.sticker)
                    Toggle("Soft glow", isOn: $prefs.glow)
                    Toggle("Lean into turns", isOn: $prefs.wiggle)
                    Toggle("Ripple when I click", isOn: $prefs.clickRipple)
                }

                section("Trail") {
                    Picker("Particles", selection: $prefs.particle) {
                        ForEach(ParticleKind.allCases) { Text($0.label).tag($0) }
                    }
                    LabeledSlider(title: "Amount", value: $prefs.trailAmount, range: 0...3)
                }

                section("Finding your cursor") {
                    Toggle("Grow big when I circle or shake the mouse", isOn: $prefs.shakeToFind)
                    LabeledSlider(title: "Sensitivity", value: $prefs.shakeSensitivity, range: 0...1)
                        .disabled(!prefs.shakeToFind)
                    Toggle("Fade out when the mouse sits still", isOn: $prefs.hideWhenIdle)
                    HStack(alignment: .top) {
                        Text("Summon to the center of the main screen")
                        Spacer()
                        HotKeyRecorder(prefs: prefs)
                    }
                    Button("Try summoning now", action: summon)
                }

                section("General") {
                    Toggle("Open at login", isOn: Binding(get: { loginOn }, set: setLogin))
                    if let n = loginNote { Text(n).font(.caption).foregroundStyle(.secondary) }
                    Toggle("Pause mousemallow", isOn: $prefs.paused)
                }
            }
            .padding(20)
        }
        .foregroundStyle(Color.ink)
        .tint(Color.blush)
        .background(Color.marshmallow)
        .frame(width: 500, height: 740)
    }

    func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(.headline, design: .rounded))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.6)))
    }

    func colorBinding(_ kp: ReferenceWritableKeyPath<Prefs, String>) -> Binding<Color> {
        Binding(get: { Color(nsColor: NSColor(hex: prefs[keyPath: kp])) },
                set: { prefs[keyPath: kp] = NSColor($0).hexString })
    }

    func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginNote = nil
        } catch {
            loginNote = error.localizedDescription
        }
        let status = SMAppService.mainApp.status
        loginOn = status == .enabled
        if status == .requiresApproval {
            loginNote = "Allow mousemallow in System Settings → General → Login Items."
        }
    }
}

// MARK: - App delegate and menu bar

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let prefs = Prefs.shared
    let overlay = Overlay()
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    var bag = Set<AnyCancellable>()
    var applyPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = MouseMark.image(size: 18, style: .menuBar)
        statusItem.button?.toolTip = "mousemallow"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()

        overlay.start()
        HotKeyCenter.shared.action = { [weak self] in self?.overlay.summon() }
        HotKeyCenter.shared.registerFromPrefs()

        prefs.objectWillChange
            .sink { [weak self] _ in self?.scheduleApply() }
            .store(in: &bag)

        if !UserDefaults.standard.bool(forKey: "didOnboard") {
            UserDefaults.standard.set(true, forKey: "didOnboard")
            openSettings()
        }
    }

    func scheduleApply() {
        guard !applyPending else { return }
        applyPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyPending = false
            self.overlay.applyPrefs()
            self.updateStatusIcon()
            HotKeyCenter.shared.registerFromPrefs()
        }
    }

    func updateStatusIcon() {
        statusItem.button?.appearsDisabled = prefs.paused
    }

    // ⌘W and ⌘Q in the settings window need a main menu, even for a menu bar app.
    func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit mousemallow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let p = prefs

        menu.addItem(item("Summon cursor to center   \(p.hotKeyLabel)", #selector(summon)))
        menu.addItem(.separator())

        let header = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for t in p.allThemes {
            menu.addItem(item("\(t.icon)  \(t.name)", #selector(pickTheme(_:)), rep: t.id, on: p.themeID == t.id))
        }
        menu.addItem(.separator())

        menu.addItem(submenu("Trail", ParticleKind.allCases.map { ($0.label, $0.rawValue) },
                             current: p.particle.rawValue, #selector(pickParticle(_:))))
        menu.addItem(submenu("Ears", EarStyle.allCases.map { ($0.label, $0.rawValue) },
                             current: p.ears.rawValue, #selector(pickEars(_:))))
        menu.addItem(submenu("Ring", RingStyle.allCases.map { ($0.label, $0.rawValue) },
                             current: p.ringStyle.rawValue, #selector(pickRing(_:))))
        let sizes: [(String, String)] = [("Small", "0.75"), ("Medium", "1.0"), ("Large", "1.4"), ("Huge", "1.9")]
        let currentSize = sizes.min { abs(Double($0.1)! - p.size) < abs(Double($1.1)! - p.size) }?.1 ?? "1.0"
        menu.addItem(submenu("Size", sizes, current: currentSize, #selector(pickSize(_:))))

        menu.addItem(item("Grow when I circle the mouse", #selector(toggleShake), on: p.shakeToFind))
        menu.addItem(item("Fade when still", #selector(toggleIdle), on: p.hideWhenIdle))
        menu.addItem(.separator())
        menu.addItem(item("Pause", #selector(togglePause), on: p.paused))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit mousemallow", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    func item(_ title: String, _ action: Selector, key: String = "", rep: Any? = nil,
              on: Bool = false, target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = target ?? self
        i.representedObject = rep
        i.state = on ? .on : .off
        return i
    }

    func submenu(_ title: String, _ options: [(String, String)], current: String, _ action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (label, value) in options {
            sub.addItem(item(label, action, rep: value, on: value == current))
        }
        parent.submenu = sub
        return parent
    }

    @objc func summon() { overlay.summon() }
    @objc func pickTheme(_ s: NSMenuItem) { if let id = s.representedObject as? String { prefs.themeID = id } }
    @objc func pickParticle(_ s: NSMenuItem) {
        if let v = s.representedObject as? String, let k = ParticleKind(rawValue: v) { prefs.particle = k }
    }
    @objc func pickEars(_ s: NSMenuItem) {
        if let v = s.representedObject as? String, let k = EarStyle(rawValue: v) { prefs.ears = k }
    }
    @objc func pickRing(_ s: NSMenuItem) {
        if let v = s.representedObject as? String, let k = RingStyle(rawValue: v) { prefs.ringStyle = k }
    }
    @objc func pickSize(_ s: NSMenuItem) {
        if let v = s.representedObject as? String, let d = Double(v) { prefs.size = d }
    }
    @objc func toggleShake() { prefs.shakeToFind.toggle() }
    @objc func toggleIdle() { prefs.hideWhenIdle.toggle() }
    @objc func togglePause() { prefs.paused.toggle() }

    @objc func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(summon: { [weak self] in self?.overlay.summon() }))
            let w = NSWindow(contentViewController: host)
            w.title = "mousemallow"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.appearance = NSAppearance(named: .aqua)   // the brand palette is designed for light
            w.backgroundColor = Brand.marshmallow
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
