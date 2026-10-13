import AppKit
import FrankShared

/// The little blueberry blob with eyes for the menu bar.
enum MenuIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: true) { rect in
            let body = NSBezierPath(ovalIn: NSRect(x: 1, y: 2, width: 20, height: 16))
            NSGradient(colors: Palette.gradient.map { NSColor(hex: $0) })?.draw(in: body, angle: -60)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: 5, y: 6, width: 5.5, height: 5.5)).fill()
            NSBezierPath(ovalIn: NSRect(x: 11.5, y: 6, width: 5.5, height: 5.5)).fill()
            NSColor(hex: Palette.ink).setFill()
            NSBezierPath(ovalIn: NSRect(x: 6.3, y: 6.8, width: 3, height: 3)).fill()
            NSBezierPath(ovalIn: NSRect(x: 12.8, y: 6.8, width: 3, height: 3)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
