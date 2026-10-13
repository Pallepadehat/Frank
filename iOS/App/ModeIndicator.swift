import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Shows which mode he's in: a solid border hugging the screen's own rounded corners (blue while he listens),
/// plus a small label in the corner. Asleep (just following your mouse) shows nothing at all. No glows.
struct ModeIndicator: View {
    let state: LiveVoice.State

    private struct Look {
        let color: Color
        let label: String
        let icon: String
        let border: CGFloat   // 0 = no border
        let pulse: Double     // pulses per second (opacity only)
    }

    private static let blue = Color(hex: 0x4F8BFF)

    private var look: Look {
        switch state {
        case .asleep:    return Look(color: .clear, label: "", icon: "", border: 0, pulse: 0)
        case .waking:    return Look(color: Color(hex: 0xFFD66B), label: "Waking up", icon: "sun.max.fill", border: 6, pulse: 1.6)
        case .listening: return Look(color: Self.blue, label: "Listening · hold to ask", icon: "ear", border: 10, pulse: 0)
        case .asking:    return Look(color: Self.blue, label: "I'm all ears", icon: "mic.fill", border: 16, pulse: 1.2)
        case .thinking:  return Look(color: Color(hex: 0xC79BFF), label: "Thinking", icon: "sparkles", border: 8, pulse: 1.1)
        case .speaking:  return Look(color: Color(hex: 0xFF9AD0), label: "Replying", icon: "bubble.left.fill", border: 8, pulse: 0)
        }
    }

    /// The phone screen's own corner radius, so the border lines up with the glass.
    private static let screenCornerRadius: CGFloat = {
        #if canImport(UIKit)
        if let radius = UIScreen.main.value(forKey: "_displayCornerRadius") as? CGFloat, radius > 0 { return radius }
        #endif
        return 55
    }()

    var body: some View {
        let look = look
        TimelineView(.animation(paused: look.pulse == 0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let wave = look.pulse > 0 ? 0.5 + 0.5 * sin(t * look.pulse * 2 * .pi) : 1
            ZStack(alignment: .topLeading) {
                if look.border > 0 {
                    RoundedRectangle(cornerRadius: Self.screenCornerRadius, style: .continuous)
                        .strokeBorder(look.color, lineWidth: look.border)
                        .opacity(look.pulse > 0 ? 0.65 + 0.35 * wave : 1)
                }
                if state != .asleep {
                    Label(look.label, systemImage: look.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(Capsule().fill(look.color))
                        .padding(.top, 14 + look.border)
                        .padding(.leading, 24 + look.border)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: state)
    }
}
