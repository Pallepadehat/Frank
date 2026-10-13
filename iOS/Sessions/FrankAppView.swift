import SwiftUI

/// Frank's own app screen: start or end a session, his ears and sound, and past sessions with their transcripts.
/// Opened from the faint button in the top-right corner of his face.
struct FrankAppView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var live: LiveVoice
    @ObservedObject var link: MacLink
    @ObservedObject var library: ModelLibrary
    var onClose: () -> Void
    @State private var volume = 1.0
    @State private var showEars = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        MiniFrank()
                            .frame(width: 52, height: 47)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Frank")
                                .font(.title2.bold())
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(link.connected ? .green : .secondary)
                                    .frame(width: 8, height: 8)
                                Text(link.connected ? (link.macName ?? link.currentMac ?? "Mac") : "Looking for your Mac…")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Button(role: live.state == .asleep ? nil : .destructive) {
                        let starting = live.state == .asleep
                        if starting && library.activeSpeechModel == nil { showEars = true; return }
                        live.toggle()
                        if starting { onClose() }  // back to his face when starting
                    } label: {
                        Label(live.state == .asleep ? "Start Session" : "End Session",
                              systemImage: live.state == .asleep ? "play.fill" : "stop.fill")
                    }
                    .disabled(!link.connected && live.state == .asleep)
                } footer: {
                    Text(live.state == .asleep
                         ? "He listens for the whole session. Hold his face to ask something; let go and he answers."
                         : "Session running. Hold his face to ask; everything you say is saved here.")
                }

                Section("Settings") {
                    NavigationLink {
                        EarsView(library: library)
                    } label: {
                        LabeledContent {
                            Text(library.activeSpeechModel?.name ?? "Not Set Up")
                                .foregroundStyle(library.activeSpeechModel == nil ? .orange : .secondary)
                        } label: {
                            Label("Ears", systemImage: "ear")
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Chirp Volume", systemImage: "speaker.wave.2")
                        Slider(value: Binding(get: { volume }, set: { volume = $0; live.volume = $0 }), in: 0...1) {
                            Text("Chirp Volume")
                        } minimumValueLabel: {
                            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                        }
                    }
                    if link.macs.count > 1 {
                        Picker(selection: Binding(get: { link.currentMac ?? "" }, set: { link.choose($0) })) {
                            ForEach(link.macs, id: \.self) { Text($0).tag($0) }
                        } label: {
                            Label("Mac", systemImage: "desktopcomputer")
                        }
                    }
                }

                Section("Sessions") {
                    if store.sessions.isEmpty {
                        ContentUnavailableView("No Sessions Yet", systemImage: "text.bubble",
                                               description: Text("Start one and your transcript and his replies show up here."))
                    } else {
                        ForEach(store.sessions) { session in
                            NavigationLink(value: session.id) {
                                SessionRow(session: session, live: session.id == store.currentID)
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { store.sessions[$0].id }.forEach(store.delete)
                        }
                    }
                }
            }
            .navigationTitle("Frank")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                SessionDetailView(store: store, id: id)
            }
            .navigationDestination(isPresented: $showEars) {
                EarsView(library: library)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Color(hex: Palette.fur1))
        .onAppear {
            volume = live.volume
            #if DEBUG
            if UserDefaults.standard.string(forKey: "FrankScreen") == "ears" { showEars = true }
            #endif
        }
    }
}

struct SessionRow: View {
    let session: FrankSession
    let live: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(session.started.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                if live {
                    Text("LIVE")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                }
                Spacer()
                Text(Self.duration(session.duration))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(session.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
