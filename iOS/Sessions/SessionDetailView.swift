import SwiftUI

/// One session as a conversation: what you said in grey, your questions in bubbles on the right,
/// his replies on the left, and research reports as cards you can expand.
struct SessionDetailView: View {
    @ObservedObject var store: SessionStore
    let id: UUID
    private var session: FrankSession? { store.sessions.first { $0.id == id } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let session {
                        Text("\(session.started.formatted(date: .complete, time: .shortened)) · \(SessionRow.duration(session.duration)) · \(session.questionCount) asked")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 6)
                    }
                    ForEach(session?.displayEntries ?? []) { entry in
                        EntryView(entry: entry).id(entry.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .onAppear { if let last = session?.entries.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            .onChange(of: session?.entries.count) { _, _ in
                if let last = session?.entries.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .navigationTitle(session?.started.formatted(date: .abbreviated, time: .shortened) ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let session {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: session.exportText)
                }
            }
        }
    }
}

private struct EntryView: View {
    let entry: TranscriptEntry
    @State private var open = false

    var body: some View {
        switch entry.kind {
        case .heard:
            Text(entry.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .asked:
            HStack {
                Spacer(minLength: 120)
                Text(entry.text)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color(hex: Palette.fur3), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        case .reply:
            HStack(alignment: .bottom, spacing: 8) {
                MiniFrank().frame(width: 28, height: 25)
                Text(entry.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Spacer(minLength: 120)
            }
        case .report:
            let lines = entry.text.components(separatedBy: "\n\n")
            DisclosureGroup(isExpanded: $open) {
                Text(lines.dropFirst().joined(separator: "\n\n"))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            } label: {
                Label(lines.first ?? "Research", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.leading, 36)
            .padding(.trailing, 80)
        }
    }
}
