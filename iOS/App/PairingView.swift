import SwiftUI

/// Shown until the phone finds the Mac: Frank asleep, and how to wake him up.
struct PairingView: View {
    var onPlay: () -> Void

    var body: some View {
        HStack(spacing: 56) {
            SleepyFrank()
                .frame(width: 220, height: 200)

            VStack(alignment: .leading, spacing: 14) {
                Text("Wake me up from your Mac")
                    .font(.fredoka(32))
                    .foregroundStyle(Color(hex: 0xFAF4EE))
                Text("Open Frank in your Mac's menu bar. Keep both on the same Wi-Fi and I'll find it.")
                    .font(.plexSans(16))
                    .foregroundStyle(Color(hex: Palette.inkSoft))
                    .frame(maxWidth: 380, alignment: .leading)
                HStack(spacing: 10) {
                    ProgressView().tint(Color(hex: Palette.fur1))
                    Text("Looking for your Mac")
                        .font(.plexMono(13))
                        .foregroundStyle(Color(hex: Palette.inkSoft))
                }
                .padding(.top, 4)
                Button(action: onPlay) {
                    Text("Play without the Mac")
                        .font(.plexSans(15).weight(.semibold))
                        .foregroundStyle(Color(hex: 0xFAF4EE))
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Color(hex: Palette.panel), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 72)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

private struct SleepyFrank: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                MiniFrank(asleep: true)
                Text("z").font(.fredoka(26)).foregroundStyle(Color(hex: Palette.fur2))
                    .offset(x: 110, y: -95 - 4 * sin(t * 1.5))
                Text("z").font(.fredoka(18)).foregroundStyle(Color(hex: Palette.fur3))
                    .offset(x: 128, y: -122 - 4 * sin(t * 1.5 + 1))
            }
            .scaleEffect(1 + 0.02 * sin(t * 1.1), anchor: .bottom)
        }
    }
}
