import AppKit
import FrankShared

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let c = Palette.rgb(hex)
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
    }
}
