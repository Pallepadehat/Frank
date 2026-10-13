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

/// The cursor's body, drawn once (gradient, shine, white rim, soft glow) and then just moved around.
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
            ctx.setShadow(offset: .zero, blur: 30 * k, color: NSColor(hex: Palette.berry2, alpha: 0.7).cgColor)
        } else {
            ctx.setShadow(offset: .zero, blur: 16 * k, color: NSColor(hex: Palette.berry4, alpha: 0.45).cgColor)
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
    }
}
