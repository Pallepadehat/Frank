import AppKit
import SwiftUI

// Draws Frank's app icon from his real face code: he peeks up from the bottom of a sky, looking at a mouse
// pointer. Writes the iPhone icon (full-bleed square) and the Mac icon (rounded square with a shadow) at every
// size the asset catalogs need. Run through scripts/make-icons.sh.

struct IconArt: View {
    var body: some View {
        Canvas { ctx, size in
            let u = size.width / 1024
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Color(hex: 0x6FBDFF), Color(hex: 0xD6EEFF)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            // A soft glow of sunlight behind the pointer.
            ctx.fill(Path(ellipseIn: CGRect(x: 420 * u, y: -260 * u, width: 900 * u, height: 900 * u)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(0.55), .white.opacity(0)]),
                                           center: CGPoint(x: 870 * u, y: 190 * u), startRadius: 0, endRadius: 450 * u))

            // The mouse pointer he's watching.
            var arrow = ctx
            arrow.translateBy(x: 640 * u, y: 70 * u)
            arrow.rotate(by: .degrees(-18))
            arrow.scaleBy(x: 3.2 * u, y: 3.2 * u)
            var pointer = Path()
            pointer.addLines([CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 72), CGPoint(x: 17, y: 56), CGPoint(x: 29, y: 82),
                              CGPoint(x: 41, y: 77), CGPoint(x: 29, y: 52), CGPoint(x: 52, y: 52)])
            pointer.closeSubpath()
            var shadow = arrow
            shadow.addFilter(.shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4))
            shadow.fill(pointer, with: .color(.white))
            arrow.stroke(pointer, with: .color(Color(hex: Palette.fur4)), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
            arrow.fill(pointer, with: .color(.white))

            // Frank, peeking up and looking at it.
            var face = ctx
            let s = u * 1.22
            face.translateBy(x: size.width / 2 - 422 * s, y: size.height - 450 * s)
            face.scaleBy(x: s, y: s)
            let frame = FaceAnimator.Frame(gaze: CGPoint(x: 0.55, y: -0.7), mood: .listening, talk: 0, closed: 0, breathe: 0,
                                           time: 1, pupil: 1.12, browLift: 14, browTilt: 0.05, lean: 0, hop: 0, blush: 0.45, squint: 0)
            FaceView.drawHead(frame, in: &face)
        }
    }
}

@MainActor func render(_ size: CGFloat) -> CGImage {
    let renderer = ImageRenderer(content: IconArt().frame(width: 1024, height: 1024))
    renderer.scale = size / 1024
    return renderer.cgImage!
}

func write(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

/// The iPhone icon: the art edge to edge, with no transparency.
func phoneIcon(_ art: CGImage) -> CGImage {
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(art, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    return ctx.makeImage()!
}

/// The Mac icon: the art in macOS's rounded square (824 of 1024, like Apple's template) with a soft shadow.
func macIcon(_ art: CGImage, size: Int) -> CGImage {
    let k = CGFloat(size) / 1024
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let tile = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185 * k, cornerHeight: 185 * k, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.draw(art, in: tile)
    return ctx.makeImage()!
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let args = CommandLine.arguments
            let phoneSet = args[1], macSet = args[2]
            write(phoneIcon(render(1024)), to: "\(phoneSet)/AppIcon.png")
            for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
                let pixels = points * scale
                let suffix = scale == 2 ? "@2x" : ""
                write(macIcon(render(CGFloat(pixels)), size: pixels), to: "\(macSet)/icon_\(points)x\(points)\(suffix).png")
            }
        }
    }
}
