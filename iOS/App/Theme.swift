import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let c = Palette.rgb(hex)
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: opacity)
    }
}

extension Font {
    /// Rounded display face from the design. Falls back to SF Rounded until Fredoka is bundled.
    static func fredoka(_ size: CGFloat) -> Font {
        UIFontCheck.has("Fredoka") ? .custom("Fredoka", size: size).weight(.bold) : .system(size: size, weight: .bold, design: .rounded)
    }

    static func plexSans(_ size: CGFloat) -> Font {
        UIFontCheck.has("IBM Plex Sans") ? .custom("IBM Plex Sans", size: size) : .system(size: size)
    }

    static func plexMono(_ size: CGFloat) -> Font {
        UIFontCheck.has("IBM Plex Mono") ? .custom("IBM Plex Mono", size: size) : .system(size: size, design: .monospaced)
    }
}

enum UIFontCheck {
    private static let families: Set<String> = {
        #if canImport(UIKit)
        return Set(UIFont.familyNames)
        #else
        return []
        #endif
    }()

    static func has(_ family: String) -> Bool { families.contains(family) }
}
