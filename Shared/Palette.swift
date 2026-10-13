import Foundation

/// Frank the bison's colors, as 0xRRGGBB.
public enum Palette {
    public static let fur1: UInt32 = 0xD9A16A  // sunlit caramel
    public static let fur2: UInt32 = 0xB16F3D
    public static let fur3: UInt32 = 0x874C27
    public static let fur4: UInt32 = 0x56301A  // deep chestnut
    public static let wool: UInt32 = 0x2E1A0F       // his shaggy cap and mane
    public static let woolLight: UInt32 = 0x5A3720
    public static let horn: UInt32 = 0xF4E8D2
    public static let hornTip: UInt32 = 0x46352A
    public static let earInner: UInt32 = 0xD59A7C
    public static let muzzle: UInt32 = 0x3F2517
    public static let muzzleLight: UInt32 = 0x6B4429
    public static let nose: UInt32 = 0x1F1009      // brows, nostrils and mouth
    public static let ink: UInt32 = 0x17120F
    public static let inkSoft: UInt32 = 0xC7B7A7
    public static let panel: UInt32 = 0x241C17

    public static let gradient: [UInt32] = [fur1, fur2, fur3, fur4]
    public static let gradientStops: [Double] = [0, 0.34, 0.68, 1]

    public static func rgb(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}
