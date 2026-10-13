import SwiftUI

/// Shown until the phone finds the Mac: Frank asleep, and how to wake him up.
struct PairingView: View {
    var onPlay: () -> Void

    var body: some View {
        HStack(spacing: 56) {
            SleepyFrank()
                .frame(width: 220, height: 200)

            VStack(alignment: .leading, spacing: 12) {
                Text("Wake Me Up from Your Mac")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("Open Frank in your Mac's menu bar. Keep both on the same Wi-Fi and I'll find it.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 400, alignment: .leading)
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Looking for your Mac…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
                Button("Play Without the Mac", action: onPlay)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 72)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .tint(Color(hex: Palette.fur1))
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
