import AppKit
import FrankShared

/// Frank's little head for the menu bar: horns, woolly top and googly eyes.
enum MenuIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: true) { _ in
            NSColor(hex: Palette.horn).setStroke()
            for side in [0.0, 1.0] {
                func x(_ v: CGFloat) -> CGFloat { side == 0 ? v : 22 - v }
                let horn = NSBezierPath()
                horn.move(to: NSPoint(x: x(6), y: 7))
                horn.curve(to: NSPoint(x: x(1.6), y: 1.2), controlPoint1: NSPoint(x: x(2.2), y: 7.4), controlPoint2: NSPoint(x: x(1.2), y: 4.5))
                horn.lineWidth = 2.2
                horn.lineCapStyle = .round
                horn.stroke()
            }
            let head = NSBezierPath(ovalIn: NSRect(x: 2.5, y: 4, width: 17, height: 14))
            NSGradient(colors: Palette.gradient.map { NSColor(hex: $0) })?.draw(in: head, angle: -60)
            NSColor(hex: Palette.wool).setFill()
            for (x, y, r) in [(7.2, 5.2, 2.6), (11, 3.8, 3.1), (14.8, 5.2, 2.6)] as [(CGFloat, CGFloat, CGFloat)] {
                NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
            }
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: 5.5, y: 8, width: 5, height: 5)).fill()
            NSBezierPath(ovalIn: NSRect(x: 11.5, y: 8, width: 5, height: 5)).fill()
            NSColor(hex: Palette.ink).setFill()
            NSBezierPath(ovalIn: NSRect(x: 6.8, y: 9, width: 2.7, height: 2.7)).fill()
            NSBezierPath(ovalIn: NSRect(x: 12.8, y: 9, width: 2.7, height: 2.7)).fill()
            NSColor(hex: Palette.muzzle).setFill()
            NSBezierPath(ovalIn: NSRect(x: 8, y: 13.6, width: 6, height: 4)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
