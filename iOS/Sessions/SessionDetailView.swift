import SwiftUI

/// One session as a chat: what you said in grey, your questions in blue, his replies in white bubbles.
struct SessionDetailView: View {
    @ObservedObject var store: SessionStore
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    /// A prompt for an agent (like Claude Code on the Mac) that points it at this session's notes files.
    private func copyPrompt(_ session: FrankSession) {
        let root = "~/Documents/Frank Notes"
        let path = session.notesPath.map { p -> String in
            // Show the Mac path with ~ for the home folder.
            if let range = p.range(of: "/Documents/Frank Notes") { return "~" + p[range.lowerBound...] }
            return p
        } ?? "\(root)/ (the folder starting \(session.started.formatted(.iso8601.year().month().day())))"
        let prompt = """
        I recorded a meeting with my Frank app on \(session.started.formatted(date: .complete, time: .shortened)). \
        The notes are on my Mac in \(path)

        - notes.md: the full transcript with timestamps and speaker labels (A, B, … per five-minute chunk), plus \
        my questions to Frank, its replies and research reports. Start here.
        - session.json: the same data, structured.
        - audio/: the original recording in five-minute chunks.

        All my sessions are in \(root)/, one folder per session (see README.md there). Read the notes, then help me \
        with: 
        """
        #if canImport(UIKit)
        UIPasteboard.general.string = prompt
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }

    private var session: FrankSession? { store.sessions.first { $0.id == id } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session?.started.formatted(date: .abbreviated, time: .shortened) ?? "Session")
                        .font(.fredoka(20))
                        .foregroundStyle(.white)
                    if let session {
                        Text("\(SessionRow.duration(session.duration)) · \(session.questionCount) asked"
                             + (session.transcribing > 0 ? " · transcribing \(session.transcribing) chunk\(session.transcribing == 1 ? "" : "s")…" : ""))
                            .font(.plexMono(11))
                            .foregroundStyle(Color(hex: Palette.inkSoft))
                    }
                }
                Spacer()
                if let session {
                    Button { copyPrompt(session) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Copied" : "Copy prompt for agent")
                        }
                        .font(.plexSans(13).weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Color(hex: Palette.berry3), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    ShareLink(item: session.exportText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(session?.displayEntries ?? []) { entry in
                            EntryView(entry: entry).id(entry.id)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                }
                .onAppear { if let last = session?.entries.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                .onChange(of: session?.entries.count) { _, _ in
                    if let last = session?.entries.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct EntryView: View {
    static func speakerColor(_ speaker: String?) -> Color {
        let colors: [UInt32] = [0x8FB3FF, 0x5BE49B, 0xFFB86B, 0xFF9AD0, 0xC79BFF, 0x6BE3E0]
        guard let first = speaker?.unicodeScalars.first?.value, speaker != "?" else { return Color(hex: Palette.inkSoft) }
        return Color(hex: colors[Int(first) % colors.count])
    }

    let entry: TranscriptEntry
    @State private var open = false

    var body: some View {
        switch entry.kind {
        case .transcript:
            HStack(alignment: .top, spacing: 10) {
                Text(entry.speaker.map { "Speaker \($0)" } ?? "Speaker")
                    .font(.plexMono(11).weight(.medium))
                    .foregroundStyle(Self.speakerColor(entry.speaker))
                    .frame(width: 78, alignment: .leading)
                    .padding(.top, 2)
                Text(entry.text)
                    .font(.plexSans(15))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.time.formatted(date: .omitted, time: .shortened))
                    .font(.plexMono(10))
                    .foregroundStyle(Color(hex: Palette.inkSoft).opacity(0.7))
                    .padding(.top, 3)
            }
        case .heard:
            Text(entry.text)
                .font(.plexSans(14))
                .foregroundStyle(Color(hex: Palette.inkSoft))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
        case .asked:
            HStack {
                Spacer(minLength: 120)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("You asked")
                        .font(.plexMono(10))
                        .foregroundStyle(Color(hex: Palette.berry1))
                    Text(entry.text)
                        .font(.plexSans(15).weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(BlobShape.linear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        case .reply:
            HStack(alignment: .bottom, spacing: 8) {
                MiniFrank().frame(width: 28, height: 25)
                Text(entry.text)
                    .font(.fredoka(16))
                    .foregroundStyle(Color(hex: Palette.ink))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Spacer(minLength: 120)
            }
        case .report:
            let lines = entry.text.components(separatedBy: "\n\n")
            VStack(alignment: .leading, spacing: 8) {
                Button { withAnimation(.spring(duration: 0.3)) { open.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass").foregroundStyle(Color(hex: Palette.berry2))
                        Text(lines.first ?? "Research")
                            .font(.fredoka(16))
                            .foregroundStyle(Color(hex: Palette.ink))
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: open ? "minus" : "plus")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color(hex: Palette.berry2)))
                    }
                }
                .buttonStyle(.plain)
                Text(lines.dropFirst().joined(separator: "\n\n"))
                    .font(.plexSans(14))
                    .foregroundStyle(Color(hex: Palette.ink))
                    .lineLimit(open ? nil : 3)
            }
            .padding(14)
            .background(Color(hex: 0xEEF0FF), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(hex: Palette.berry2), lineWidth: 2))
            .padding(.leading, 36)
            .padding(.trailing, 80)
        }
    }
}
