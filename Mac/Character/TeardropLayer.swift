import AppKit
import QuartzCore
import FrankShared

enum Teardrop {
    /// A square with three fully rounded corners and one sharp one (the tip) at the origin. y down.
    static func path(size s: CGFloat, tipRadius r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let big = s / 2
        path.move(to: CGPoint(x: r, y: 0))
        path.addArc(tangent1End: CGPoint(x: s, y: 0), tangent2End: CGPoint(x: s, y: s), radius: big)
        path.addArc(tangent1End: CGPoint(x: s, y: s), tangent2End: CGPoint(x: 0, y: s), radius: big)
        path.addArc(tangent1End: CGPoint(x: 0, y: s), tangent2End: CGPoint(x: 0, y: 0), radius: big)
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: s, y: 0), radius: r)
        path.closeSubpath()
        return path
    }

    static func star(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<8 {
            let r = i % 2 == 0 ? radius : radius * 0.4
            let a = CGFloat(i) * .pi / 4 - .pi / 2
            let p = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

/// The cursor's body, drawn once (fur gradient, shine, white rim, horns and wool, soft glow) and then just moved around.
final class TeardropLayer: CALayer {
    var side: CGFloat = 72
    var glow = true
    var padding: CGFloat { side * 0.45 }

    override init() {
        super.init()
        needsDisplayOnBoundsChange = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? TeardropLayer {
            side = other.side
            glow = other.glow
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(in ctx: CGContext) {
        let s = side, k = s / 96
        // Draw top-down (y down) so the art matches the rest of the app's coordinates.
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: padding, y: padding)
        let path = Teardrop.path(size: s, tipRadius: 6 * k)

        ctx.saveGState()
        if glow {
            ctx.setShadow(offset: .zero, blur: 30 * k, color: NSColor(hex: Palette.fur2, alpha: 0.7).cgColor)
        } else {
            ctx.setShadow(offset: .zero, blur: 16 * k, color: NSColor(hex: Palette.fur4, alpha: 0.45).cgColor)
        }
        ctx.addPath(path)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = Palette.gradient.map { NSColor(hex: $0).cgColor } as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: Palette.gradientStops.map { CGFloat($0) }) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0.25 * s, y: 0.067 * s), end: CGPoint(x: 0.75 * s, y: 0.933 * s),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        let shine = [NSColor(white: 1, alpha: 0.55).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: shine, locations: [0, 1]) {
            let c = CGPoint(x: 0.3 * s, y: 0.24 * s)
            ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: 0.38 * s, options: [])
        }
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(8 * k)  // half is clipped away, leaving a 4 pt rim
        ctx.strokePath()
        ctx.restoreGState()

        drawBisonTop(in: ctx, k: k)
    }

    /// Frank's horns and woolly top, on the cursor's head, each with the same white rim as the body.
    private func drawBisonTop(in ctx: CGContext, k: CGFloat) {
        let rim = 3 * k
        // Horns: short, curving up and out, ivory with dark tips. In the 96-unit design, y down.
        let horns = [(base: CGPoint(x: 36, y: 16), bend: CGPoint(x: 14, y: 18), tip: CGPoint(x: 14, y: -6)),
                     (base: CGPoint(x: 80, y: 24), bend: CGPoint(x: 102, y: 26), tip: CGPoint(x: 104, y: 2))]
        for horn in horns {
            ctx.addPath(Self.sweep(horn.base, horn.bend, horn.tip, k: k, from: 15 + 2 * rim / k, to: 5 + 2 * rim / k))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()
        }
        for horn in horns {
            let path = Self.sweep(horn.base, horn.bend, horn.tip, k: k, from: 15, to: 5)
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.setFillColor(NSColor(hex: Palette.horn).cgColor)
            ctx.fill(path.boundingBoxOfPath)
            ctx.setFillColor(NSColor(hex: Palette.hornTip).cgColor)
            ctx.fillEllipse(in: CGRect(x: (horn.tip.x - 6) * k, y: (horn.tip.y - 6) * k, width: 12 * k, height: 12 * k))
            ctx.restoreGState()
        }

        // A shaggy tuft of dark wool across the top of his head.
        let curls: [(CGFloat, CGFloat, CGFloat)] = [(34, 12, 9), (45, 7, 11), (57, 6, 11), (69, 9, 10), (79, 16, 9),
                                                    (52, 16, 8), (64, 17, 8), (57, 26, 6)]
        ctx.setFillColor(NSColor.white.cgColor)
        for (x, y, r) in curls {
            ctx.fillEllipse(in: CGRect(x: (x - r) * k - rim, y: (y - r) * k - rim, width: 2 * r * k + 2 * rim, height: 2 * r * k + 2 * rim))
        }
        let wool = CGMutablePath()
        for (x, y, r) in curls { wool.addEllipse(in: CGRect(x: (x - r) * k, y: (y - r) * k, width: 2 * r * k, height: 2 * r * k)) }
        ctx.saveGState()
        ctx.addPath(wool)
        ctx.clip()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [NSColor(hex: Palette.woolLight).cgColor, NSColor(hex: Palette.wool).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: -4 * k), end: CGPoint(x: 0, y: 30 * k), options: [])
        }
        ctx.restoreGState()
    }

    /// A horn shape along a quadratic curve, tapering from `w0` to `w1` (design units), as overlapping circles.
    private static func sweep(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, k: CGFloat, from w0: CGFloat, to w1: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0...24 {
            let t = CGFloat(i) / 24, u = 1 - t
            let x = u * u * a.x + 2 * u * t * c.x + t * t * b.x
            let y = u * u * a.y + 2 * u * t * c.y + t * t * b.y
            let r = (w0 + (w1 - w0) * t) / 2
            path.addEllipse(in: CGRect(x: (x - r) * k, y: (y - r) * k, width: 2 * r * k, height: 2 * r * k))
        }
        return path
    }
}
