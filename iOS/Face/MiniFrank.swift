import SwiftUI

/// A tiny Frank: his head with horns, a woolly top, googly eyes and a muzzle. `asleep` closes his eyes.
struct MiniFrank: View {
    var asleep = false

    var body: some View {
        Canvas { ctx, size in MiniFrank.draw(in: &ctx, size: size, asleep: asleep) }
    }

    static func draw(in ctx: inout GraphicsContext, size: CGSize, asleep: Bool) {
        let w = size.width, h = size.height
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: x * w - r * w, y: y * h - r * w, width: 2 * r * w, height: 2 * r * w))
        }

        for side in [0.0, 1.0] {
            func x(_ v: CGFloat) -> CGFloat { side == 0 ? v : 1 - v }
            let horn = Bison.sweep(at(x(0.3), 0.34), at(x(0.08), 0.36), at(x(0.02), 0.2), at(x(0.08), 0.04)) { t in
                w * (0.13 * (1 - t) + 0.04 * t)
            }
            ctx.fill(horn, with: .linearGradient(Gradient(colors: [Color(hex: Palette.horn), Color(hex: Palette.horn), Color(hex: Palette.hornTip)]),
                                                 startPoint: at(x(0.2), 0.34), endPoint: at(x(0.08), 0.04)))
        }

        let head = CGRect(x: 0.1 * w, y: 0.2 * h, width: 0.8 * w, height: 0.8 * h)
        ctx.fill(BlobShape.path(in: head), with: .linearGradient(BlobShape.gradient, startPoint: at(0.3, 0.2), endPoint: at(0.7, 1)))

        var wool = Path()
        for (x, y, r) in [(0.27, 0.32, 0.1), (0.39, 0.22, 0.12), (0.52, 0.2, 0.13), (0.65, 0.23, 0.12),
                          (0.75, 0.32, 0.1), (0.51, 0.34, 0.09)] as [(CGFloat, CGFloat, CGFloat)] {
            wool.addPath(circle(x, y, r))
        }
        ctx.fill(wool, with: .linearGradient(Gradient(colors: [Color(hex: Palette.woolLight), Color(hex: Palette.wool)]),
                                             startPoint: at(0.5, 0.08), endPoint: at(0.5, 0.42)))

        for x in [0.35, 0.65] as [CGFloat] {
            if asleep {
                var lid = Path()
                lid.move(to: at(x - 0.08, 0.56))
                lid.addQuadCurve(to: at(x + 0.08, 0.56), control: at(x, 0.62))
                ctx.stroke(lid, with: .color(Color(hex: Palette.ink)), style: StrokeStyle(lineWidth: max(1.5, w * 0.035), lineCap: .round))
            } else {
                ctx.fill(circle(x, 0.55, 0.1), with: .color(.white))
                ctx.fill(circle(x + 0.015, 0.565, 0.05), with: .color(Color(hex: Palette.ink)))
            }
        }

        let muzzle = CGRect(x: 0.29 * w, y: 0.7 * h, width: 0.42 * w, height: 0.28 * h)
        ctx.fill(Path(ellipseIn: muzzle), with: .color(Color(hex: Palette.muzzle)))
        for x in [0.43, 0.57] as [CGFloat] {
            ctx.fill(Path(ellipseIn: CGRect(x: (x - 0.03) * w, y: 0.77 * h, width: 0.06 * w, height: 0.045 * h)),
                     with: .color(Color(hex: Palette.nose)))
        }
    }
}
