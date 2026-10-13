import SwiftUI

/// Frank's bison bits: the woolly cap and mane, horns, ears and muzzle. Everything is in head coordinates
/// (the 820 × 700 head rect, origin at its top-left), so the face can move them all together.
enum Bison {
    /// Where the top of the head is at a given x (the head outline's top edge).
    static func topEdge(_ x: CGFloat) -> CGFloat {
        let left = CGSize(width: 426, height: 406), right = CGSize(width: 394, height: 392)
        if x < left.width {
            let u = min(1, (left.width - x) / left.width)
            return left.height * (1 - sqrt(1 - u * u))
        }
        let u = min(1, (x - left.width) / right.width)
        return right.height * (1 - sqrt(1 - u * u))
    }

    /// Where the side of the head is at a given height.
    static func sideEdge(_ y: CGFloat, right: Bool) -> CGFloat {
        let r = right ? CGSize(width: 394, height: 392) : CGSize(width: 426, height: 406)
        let v = max(0, 1 - y / r.height)
        let inset = r.width * (1 - sqrt(1 - v * v))
        return right ? 820 - inset : inset
    }

    /// A curl of wool: where it sits and how big it is.
    struct Curl {
        var center: CGPoint
        var radius: CGFloat
    }

    /// The big shaggy mop on top of his head, with a forelock falling between the eyes. `lift` bobs it with the brows.
    static func cap(lift: CGFloat) -> [Curl] {
        var curls: [Curl] = []
        let overEye: (CGFloat) -> Bool = { (212...358).contains($0) || (462...608).contains($0) }
        // Along the top of the head, spilling over the outline so the silhouette looks shaggy.
        for (i, x) in stride(from: 112.0, through: 708.0, by: 30.0).enumerated() {
            let wobble = CGFloat(abs(sin(Double(i) * 1.9)))
            let r = overEye(x) ? 26 + 4 * wobble : 34 + 9 * wobble
            curls.append(Curl(center: CGPoint(x: x, y: topEdge(x) - (overEye(x) ? 2 : 6) - lift * 0.25), radius: r))
        }
        // More wool underneath, thick in the middle and out by the horns, thin over the eyes.
        for x in stride(from: 124.0, through: 696.0, by: 32.0) {
            let depth: CGFloat = overEye(x) ? 16 : (358...462).contains(x) ? 34 : 40
            curls.append(Curl(center: CGPoint(x: x, y: topEdge(x) + depth - lift * 0.3), radius: overEye(x) ? 20 : 30))
        }
        // Out by the horns the wool hangs lower.
        for (x, y, r) in [(142.0, 112.0, 34.0), (112.0, 138.0, 30.0), (176.0, 98.0, 28.0)] as [(CGFloat, CGFloat, CGFloat)] {
            curls.append(Curl(center: CGPoint(x: x, y: y - lift * 0.3), radius: r))
            curls.append(Curl(center: CGPoint(x: 820 - x, y: y + 4 - lift * 0.3), radius: r))
        }
        // The forelock: a woolly tuft hanging down between his eyes.
        let tuft: [(CGFloat, CGFloat, CGFloat)] = [(410, 56, 50), (378, 98, 36), (442, 98, 36), (410, 128, 34),
                                                   (386, 156, 24), (434, 158, 25), (410, 176, 18)]
        for (x, y, r) in tuft {
            curls.append(Curl(center: CGPoint(x: x, y: y - lift * 0.35), radius: r))
        }
        return curls
    }

    /// Shaggy fur down both sides of his face.
    static var mane: [Curl] {
        var curls: [Curl] = []
        for (i, y) in stride(from: 236.0, through: 436.0, by: 40.0).enumerated() {
            let r = 44 + 8 * abs(sin(Double(i) * 2.3))
            curls.append(Curl(center: CGPoint(x: sideEdge(y, right: false) + 2, y: y), radius: r))
            curls.append(Curl(center: CGPoint(x: sideEdge(y, right: true) - 2, y: y + 14), radius: r))
        }
        return curls
    }

    /// Draws a clump of wool: one mass, lit from above, with a soft shadow and a little lit crescent on each bump.
    static func drawWool(_ curls: [Curl], light: UInt32 = Palette.woolLight, dark: UInt32 = Palette.wool,
                         in ctx: inout GraphicsContext, origin o: CGPoint) {
        var mass = Path()
        for c in curls {
            mass.addEllipse(in: CGRect(x: o.x + c.center.x - c.radius, y: o.y + c.center.y - c.radius,
                                       width: c.radius * 2, height: c.radius * 2))
        }
        let top = curls.map { $0.center.y - $0.radius }.min() ?? 0
        let bottom = curls.map { $0.center.y + $0.radius }.max() ?? 1
        ctx.fill(mass, with: .linearGradient(Gradient(colors: [Color(hex: light), Color(hex: dark)]),
                                             startPoint: CGPoint(x: 0, y: o.y + top),
                                             endPoint: CGPoint(x: 0, y: o.y + top + (bottom - top) * 0.75)))
        // Each bump gets a soft light on its upper left and a shadow underneath, so the wool looks fluffy.
        var curl = ctx
        curl.clip(to: mass)
        for c in curls {
            let center = CGPoint(x: o.x + c.center.x, y: o.y + c.center.y)
            curl.fill(Path(ellipseIn: CGRect(x: center.x - c.radius, y: center.y - c.radius * 0.2, width: c.radius * 2, height: c.radius * 1.3)),
                      with: .radialGradient(Gradient(colors: [Color(hex: dark).opacity(0.55), Color(hex: dark).opacity(0)]),
                                            center: CGPoint(x: center.x, y: center.y + c.radius * 0.75),
                                            startRadius: 0, endRadius: c.radius * 0.9))
            let glint = CGPoint(x: center.x - c.radius * 0.3, y: center.y - c.radius * 0.38)
            curl.fill(Path(ellipseIn: CGRect(x: glint.x - c.radius * 0.6, y: glint.y - c.radius * 0.45, width: c.radius * 1.2, height: c.radius * 0.9)),
                      with: .radialGradient(Gradient(colors: [Color(hex: Palette.fur3).opacity(0.55), Color(hex: Palette.fur3).opacity(0)]),
                                            center: glint, startRadius: 0, endRadius: c.radius * 0.6))
        }
    }

    /// A shape swept along a cubic curve, with its width at each point from `width(t)`. Built from
    /// overlapping circles, so tight bends never fold over themselves.
    static func sweep(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint, width: (CGFloat) -> CGFloat) -> Path {
        var path = Path()
        let steps = 72
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps), u = 1 - t
            let p = CGPoint(x: u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p3.x,
                            y: u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p3.y)
            let r = max(0.5, width(t) / 2)
            path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        return path
    }

    /// One horn: out from under the wool, sideways, then curving up to a dark tip.
    static func drawHorn(right: Bool, in ctx: inout GraphicsContext, origin o: CGPoint) {
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + (right ? 820 - x : x), y: o.y + y) }
        let p0 = at(166, 82), c1 = at(84, 116), c2 = at(4, 96), p3 = at(30, -30)
        let horn = sweep(p0, c1, c2, p3) { t in 78 * pow(1 - t, 0.7) + 14 * t }
        ctx.fill(horn, with: .linearGradient(Gradient(stops: [.init(color: Color(hex: Palette.horn), location: 0),
                                                              .init(color: Color(hex: Palette.horn), location: 0.5),
                                                              .init(color: Color(hex: Palette.hornTip), location: 0.95)]),
                                             startPoint: at(100, 110), endPoint: at(30, -26)))
        // A shaded underside and a shine along the top make it round.
        var inside = ctx
        inside.clip(to: horn)
        let under = sweep(at(166, 114), at(78, 144), at(-14, 112), at(10, -30)) { _ in 36 }
        inside.fill(under, with: .color(Color(hex: Palette.hornTip).opacity(0.28)))
        var shine = Path()
        shine.move(to: at(120, 92))
        shine.addCurve(to: at(40, 4), control1: at(70, 98), control2: at(36, 60))
        inside.stroke(shine, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
    }

    /// One ear, sticking out sideways and drooping a little. Drawn behind the head.
    static func drawEar(right: Bool, droop: CGFloat, in ctx: inout GraphicsContext, origin o: CGPoint) {
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + (right ? 820 - x : x), y: o.y + y) }
        let ear = sweep(at(132, 146), at(92, 140), at(44, 150 + droop * 0.4), at(4, 176 + droop)) { t in
            62 * sin(.pi * (0.1 + 0.74 * t)) + 8
        }
        ctx.fill(ear, with: .linearGradient(Gradient(colors: [Color(hex: Palette.fur3), Color(hex: Palette.fur4)]),
                                            startPoint: at(130, 140), endPoint: at(0, 180)))
        let inner = sweep(at(112, 152), at(84, 148), at(46, 156 + droop * 0.4), at(16, 174 + droop)) { t in
            32 * sin(.pi * (0.12 + 0.72 * t)) + 4
        }
        ctx.fill(inner, with: .color(Color(hex: Palette.earInner)))
    }

    /// The broad muzzle at the bottom of his face, with nostrils that flare as he talks.
    static func drawMuzzle(talk: CGFloat, happy: Bool, in ctx: inout GraphicsContext, origin o: CGPoint) {
        let muzzle = CGRect(x: o.x + 410 - 146, y: o.y + 238 - talk * 4, width: 292, height: 200)
        let shape = Path(ellipseIn: muzzle)
        ctx.fill(shape, with: .linearGradient(Gradient(colors: [Color(hex: Palette.muzzleLight), Color(hex: Palette.muzzle)]),
                                              startPoint: CGPoint(x: muzzle.midX, y: muzzle.minY),
                                              endPoint: CGPoint(x: muzzle.midX, y: muzzle.minY + 120)))
        // Nostrils: two dark, slanted commas.
        let flare = 1 + talk * 0.25
        for side in [-1.0, 1.0] {
            var nostril = ctx
            nostril.translateBy(x: muzzle.midX + side * 50, y: muzzle.minY + 48)
            nostril.rotate(by: .radians(side * 0.42))
            let w = 40 * flare, h = 24 * flare
            nostril.fill(Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h)), with: .color(Color(hex: Palette.nose)))
            nostril.fill(Path(ellipseIn: CGRect(x: -w / 2 + 4, y: -h / 2 - 3, width: w - 8, height: h * 0.45)),
                         with: .color(Color(hex: Palette.muzzleLight).opacity(0.5)))
        }

        // His mouth: a soft smile line that opens up when he talks.
        let mouthY = muzzle.minY + 88
        if talk > 0.08 {
            let w = 64 - talk * 10, h = 14 + talk * 40
            let mouth = Path(roundedRect: CGRect(x: muzzle.midX - w / 2, y: mouthY - h * 0.45, width: w, height: h), cornerRadius: min(w, h) / 2)
            ctx.fill(mouth, with: .color(Color(hex: Palette.nose)))
            var inMouth = ctx
            inMouth.clip(to: mouth)
            inMouth.fill(Path(ellipseIn: CGRect(x: muzzle.midX - w * 0.32, y: mouthY + h * 0.1, width: w * 0.64, height: h * 0.6)),
                         with: .color(Color(hex: 0xE07B7B)))
        } else {
            var smile = Path()
            let width: CGFloat = happy ? 92 : 64
            smile.move(to: CGPoint(x: muzzle.midX - width / 2, y: mouthY))
            smile.addQuadCurve(to: CGPoint(x: muzzle.midX + width / 2, y: mouthY),
                               control: CGPoint(x: muzzle.midX, y: mouthY + (happy ? 34 : 18)))
            ctx.stroke(smile, with: .color(Color(hex: Palette.nose)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
        }
    }
}
