import SwiftUI

/// A faint speaker button in the top-right corner of his face. Tap it for the chirp volume, a test hi,
/// and which Mac to pair with.
struct SoundButton: View {
    @ObservedObject var link: MacLink
    @ObservedObject var live: LiveVoice
    @State private var volume = 1.0
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Image(systemName: speakerIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.06)).frame(width: 34, height: 34))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sound")
        .popover(isPresented: $open, arrowEdge: .top) {
            panel
                .presentationCompactAdaptation(.popover)
                .preferredColorScheme(.dark)
                .tint(Color(hex: Palette.fur1))
        }
        .padding(.top, 10)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .onAppear { volume = live.volume }
    }

    private var speakerIcon: String {
        volume < 0.01 ? "speaker.slash.fill" : volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("Chirp Volume") {
                Text(volume, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .font(.subheadline)
            Slider(value: Binding(get: { volume }, set: { volume = $0; live.volume = $0 }), in: 0...1) {
                Text("Chirp Volume")
            } minimumValueLabel: {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
            } maximumValueLabel: {
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }
            Button(live.state == .asleep ? "Wake Him Up" : "Say Hi") { live.sayHi() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!link.connected)
            if link.macs.count > 1 {
                Divider()
                Picker("Mac", selection: Binding(get: { link.currentMac ?? "" }, set: { link.choose($0) })) {
                    ForEach(link.macs, id: \.self) { Text($0).tag($0) }
                }
            }
            if !link.connected {
                Text("Connect to your Mac to talk to him.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 280)
    }
}
