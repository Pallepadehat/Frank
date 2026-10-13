import SwiftUI

/// Frank's ears: the on-device models that turn speech into text (and optionally clean it up).
/// Pushed from Frank's app screen.
struct EarsView: View {
    @ObservedObject var library: ModelLibrary

    var body: some View {
        Form {
            Section {
                ForEach(ModelLibrary.speechModels) { model in
                    ModelRow(library: library, model: model)
                }
            } header: {
                Text("Speech Recognition")
            } footer: {
                Text("Speech is turned into text on this iPhone. No audio ever leaves it.")
            }

            Section {
                Picker(selection: $library.language) {
                    ForEach(SpeechLanguage.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label("Language", systemImage: "globe")
                }
            } footer: {
                Text("Choosing a language is faster and more accurate than detecting it.")
            }

            Section {
                ModelRow(library: library, model: ModelLibrary.cleanupModel)
                Toggle(isOn: $library.cleanupEnabled) {
                    Label("Clean Up Transcripts", systemImage: "wand.and.stars")
                }
                .disabled(!library.isInstalled(ModelLibrary.cleanupModel))
            } header: {
                Text("Transcript Cleanup")
            } footer: {
                Text("Fixes punctuation and misheard words after each phrase. Your questions never wait for it. Uses more battery.")
            }

            Section {
                LabeledContent("Available", value: ByteCountFormatter.string(fromByteCount: library.freeSpace, countStyle: .file))
                LabeledContent("Used by Models", value: ByteCountFormatter.string(fromByteCount: library.usedSpace, countStyle: .file))
            } header: {
                Text("Storage")
            }
        }
        .navigationTitle("Ears")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { library.refresh() }
    }
}

/// One model: name, what it's for, and an App Store style download button.
/// Tap an installed speech model to use it; swipe to delete.
struct ModelRow: View {
    @ObservedObject var library: ModelLibrary
    let model: LocalModel
    @State private var confirmDelete = false

    private var status: ModelLibrary.Status { library.status(of: model) }
    private var selectable: Bool { model.kind == .speech && library.isInstalled(model) }
    private var selected: Bool { selectable && library.activeSpeechModel == model }

    var body: some View {
        Button {
            if selectable { library.speechModelID = model.id }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.name)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(subtitleIsError ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                trailing
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            if library.isInstalled(model) {
                Button("Delete", role: .destructive) { confirmDelete = true }
            }
        }
        .contextMenu {
            if library.isInstalled(model) {
                Button("Delete Model", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .confirmationDialog("Delete \(model.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { library.delete(model) }
        } message: {
            Text("This frees \(model.sizeText). You can download it again later.")
        }
    }

    private var subtitle: String {
        switch status {
        case .downloading(let fraction):
            let done = ByteCountFormatter.string(fromByteCount: Int64(Double(model.bytes) * fraction), countStyle: .file)
            return "\(done) of \(model.sizeText)"
        case .preparing:
            return "Preparing… this can take a minute"
        case .failed(let message):
            return message
        case .installed:
            return model.detail
        case .notInstalled:
            return ModelLibrary.canRun(model) ? "\(model.detail) \(model.sizeText)." : ModelLibrary.whyNot(model)
        }
    }

    private var subtitleIsError: Bool {
        if case .failed = status { return true }
        return false
    }

    @ViewBuilder private var trailing: some View {
        switch status {
        case .downloading(let fraction):
            Button { library.cancel(model) } label: {
                DownloadProgress(fraction: fraction)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop Download")
        case .preparing:
            ProgressView()
        case .installed:
            if selected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        case .failed:
            Button("Retry") { library.download(model) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
        case .notInstalled:
            if ModelLibrary.canRun(model) {
                Button { library.download(model) } label: {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(!library.hasRoom(for: model))
                .accessibilityLabel("Download \(model.name)")
            }
        }
    }
}

/// The App Store's download ring: progress around a stop square.
struct DownloadProgress: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.02, fraction))
                .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.4), value: fraction)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.tint)
                .frame(width: 8, height: 8)
        }
        .frame(width: 26, height: 26)
    }
}

/// Shown as a sheet the first time you wake Frank without a speech model: one tap gets him his ears.
struct EarsSetupView: View {
    @ObservedObject var library: ModelLibrary
    var onReady: () -> Void
    var onClose: () -> Void

    private var model: LocalModel { ModelLibrary.recommendedSpeechModel }

    var body: some View {
        NavigationStack {
            HStack(spacing: 40) {
                MiniFrank(asleep: !library.isInstalled(model))
                    .frame(width: 170, height: 155)

                VStack(alignment: .leading, spacing: 12) {
                    Text(library.isInstalled(model) ? "Frank Can Hear You" : "Frank Needs Ears")
                        .font(.largeTitle.bold())
                    Text("He turns what you say into text right here on your iPhone, so audio never leaves it. This needs a one-time download of \(model.name) (\(model.sizeText)).")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Group {
                        switch library.status(of: model) {
                        case .downloading(let fraction):
                            VStack(alignment: .leading, spacing: 6) {
                                ProgressView(value: fraction)
                                Text("Downloading… \(Int(fraction * 100))%")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        case .preparing:
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Preparing…").font(.footnote).foregroundStyle(.secondary)
                            }
                        case .installed:
                            Button("Wake Him Up", action: onReady)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                        case .failed(let message):
                            Text(message).font(.footnote).foregroundStyle(.red)
                            Button("Try Again") { library.download(model) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                        case .notInstalled:
                            Button("Download") { library.download(model) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(!library.hasRoom(for: model))
                        }
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: 460, alignment: .leading)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now", action: onClose)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Color(hex: Palette.fur1))
        .onChange(of: library.isInstalled(model)) { _, installed in
            if installed { library.speechModelID = model.id }
        }
    }
}
