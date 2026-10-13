import SwiftUI

/// Frank's own app screen: start or end a session, see past sessions and their transcripts, and settings.
/// Opened from the faint button in the top-right corner of his face.
struct FrankAppView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var live: LiveVoice
    @ObservedObject var link: MacLink
    var onClose: () -> Void
    @State private var volume = 1.0

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 300)
                    .background(Color(hex: Palette.panel).opacity(0.6))
                sessionList
            }
            .background(Color.black)
            .navigationDestination(for: UUID.self) { id in
                SessionDetailView(store: store, id: id)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .tint(Color(hex: Palette.berry1))
        .onAppear { volume = live.volume }
    }

    // MARK: Left: who he is, start/end, settings

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    MiniFrank()
                        .frame(width: 54, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Frank")
                            .font(.fredoka(28))
                            .foregroundStyle(.white)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(link.connected ? Color(hex: 0x5BE49B) : Color(hex: Palette.inkSoft).opacity(0.5))
                                .frame(width: 7, height: 7)
                            Text(link.connected ? (link.macName ?? link.currentMac ?? "Mac") : "Looking for your Mac")
                                .font(.plexSans(12))
                                .foregroundStyle(Color(hex: Palette.inkSoft))
                                .lineLimit(1)
                        }
                    }
                }

                Button {
                    let starting = live.state == .asleep
                    live.toggle()
                    if starting { onClose() }  // back to his face when starting
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: live.state == .asleep ? "play.fill" : "stop.fill")
                        Text(live.state == .asleep ? "Start session" : "End session")
                    }
                    .font(.fredoka(18))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background {
                        if live.state == .asleep {
                            RoundedRectangle(cornerRadius: 16).fill(BlobShape.linear)
                        } else {
                            RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0xE5547A))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!link.connected && live.state == .asleep)
                .opacity(!link.connected && live.state == .asleep ? 0.5 : 1)

                Text(live.state == .asleep
                     ? "He listens the whole session. Hold his face to ask something, let go and he answers."
                     : "Session running. Hold his face to ask; everything you say is saved here.")
                    .font(.plexSans(12))
                    .foregroundStyle(Color(hex: Palette.inkSoft))

                Divider().overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 8) {
                    label("Chirp volume")
                    Slider(value: Binding(get: { volume }, set: { volume = $0; live.volume = $0 }), in: 0...1)
                }

                if link.macs.count > 1 {
                    VStack(alignment: .leading, spacing: 4) {
                        label("Mac")
                        ForEach(link.macs, id: \.self) { name in
                            Button { link.choose(name) } label: {
                                HStack {
                                    Text(name).font(.plexSans(14)).foregroundStyle(.white).lineLimit(1)
                                    Spacer()
                                    if name == link.currentMac {
                                        Image(systemName: link.connected ? "checkmark" : "ellipsis")
                                            .foregroundStyle(Color(hex: Palette.berry2))
                                    }
                                }
                                .frame(minHeight: 34)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button(action: onClose) {
                    HStack(spacing: 8) {
                        Image(systemName: "face.smiling")
                        Text("Back to his face")
                    }
                    .font(.plexSans(15).weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(22)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.plexMono(11))
            .textCase(.uppercase)
            .foregroundStyle(Color(hex: Palette.inkSoft))
    }

    // MARK: Right: sessions

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sessions")
                    .font(.fredoka(24))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(store.sessions.count)")
                    .font(.plexMono(13))
                    .foregroundStyle(Color(hex: Palette.inkSoft))
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 8)

            if store.sessions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 34))
                        .foregroundStyle(Color(hex: Palette.berry2))
                    Text("No sessions yet")
                        .font(.fredoka(18))
                        .foregroundStyle(.white)
                    Text("Start one and your transcript and his replies show up here.")
                        .font(.plexSans(13))
                        .foregroundStyle(Color(hex: Palette.inkSoft))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.sessions) { session in
                        NavigationLink(value: session.id) {
                            SessionRow(session: session, live: session.id == store.currentID)
                        }
                        .listRowBackground(Color(hex: Palette.panel))
                    }
                    .onDelete { offsets in
                        offsets.map { store.sessions[$0].id }.forEach(store.delete)
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
        }
    }
}

struct SessionRow: View {
    let session: FrankSession
    let live: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.started.formatted(date: .abbreviated, time: .shortened))
                        .font(.plexSans(15).weight(.semibold))
                        .foregroundStyle(.white)
                    if live {
                        Text("LIVE")
                            .font(.plexMono(10).weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: 0x5BE49B), in: Capsule())
                    }
                }
                Text(session.summary)
                    .font(.plexSans(13))
                    .foregroundStyle(Color(hex: Palette.inkSoft))
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Self.duration(session.duration))
                    .font(.plexMono(12))
                    .foregroundStyle(Color(hex: Palette.inkSoft))
                Text("\(session.questionCount) asked")
                    .font(.plexMono(11))
                    .foregroundStyle(Color(hex: Palette.berry1))
            }
        }
        .padding(.vertical, 4)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
