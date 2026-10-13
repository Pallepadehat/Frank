import Foundation
@preconcurrency import HuggingFace
@preconcurrency import WhisperKit

/// One on-device model Frank can download.
struct LocalModel: Identifiable, Equatable, Sendable {
    enum Kind { case speech, cleanup }

    let id: String
    let kind: Kind
    let name: String
    let detail: String
    let badge: String?
    let symbol: String
    let bytes: Int64
    /// Where it comes from: a WhisperKit variant, or a Hugging Face repo for the language model.
    let source: String

    var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

/// The models Frank can use, whether they're on this iPhone, and downloading, preparing and deleting them.
/// Everything lives in Application Support/Models, kept out of iCloud backups.
@MainActor
final class ModelLibrary: ObservableObject {
    enum Status: Equatable {
        case notInstalled
        case downloading(Double)
        case preparing
        case installed(bytes: Int64)
        case failed(String)
    }

    static let whisperSmall = LocalModel(
        id: "whisper-small", kind: .speech, name: "Whisper Small",
        detail: "Quick and light. Good everyday accuracy in Danish and English.",
        badge: "RECOMMENDED", symbol: "ear", bytes: 490_000_000, source: "openai_whisper-small")
    static let whisperTurbo = LocalModel(
        id: "whisper-large-v3-turbo", kind: .speech, name: "Whisper Large v3 Turbo",
        detail: "The most accurate, especially for Danish. A little slower to answer.",
        badge: nil, symbol: "ear.badge.waveform", bytes: 650_000_000, source: "openai_whisper-large-v3-v20240930_turbo_632MB")
    static let qwen = LocalModel(
        id: "qwen2.5-1.5b-instruct-4bit", kind: .cleanup, name: "Qwen2.5 1.5B Instruct",
        detail: "Fixes punctuation, capitals and misheard words in what he heard. Runs between phrases.",
        badge: nil, symbol: "wand.and.stars", bytes: 880_000_000, source: "mlx-community/Qwen2.5-1.5B-Instruct-4bit")

    static let speechModels = [whisperSmall, whisperTurbo]
    static let cleanupModel = qwen
    static let recommendedSpeechModel = whisperSmall

    @Published private(set) var statuses: [String: Status] = [:]
    @Published private(set) var freeSpace: Int64 = 0
    @Published var speechModelID: String {
        didSet { UserDefaults.standard.set(speechModelID, forKey: "speechModel") }
    }
    @Published var language: SpeechLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "speechLanguage") }
    }
    @Published var cleanupEnabled: Bool {
        didSet { UserDefaults.standard.set(cleanupEnabled, forKey: "cleanupEnabled") }
    }

    private var tasks: [String: Task<Void, Never>] = [:]
    private var progressTimers: [String: Timer] = [:]

    /// Prepares a freshly downloaded speech model (compiles it and fetches its tokenizer). Set by Ears.
    var prepareSpeech: ((LocalModel) async throws -> Void)?
    /// Called before a model's files are deleted, so it can be unloaded first. Set by Ears.
    var willDelete: ((LocalModel) async -> Void)?

    init() {
        let defaults = UserDefaults.standard
        speechModelID = defaults.string(forKey: "speechModel") ?? Self.recommendedSpeechModel.id
        language = defaults.string(forKey: "speechLanguage").flatMap(SpeechLanguage.init(rawValue:)) ?? .preferred
        cleanupEnabled = defaults.object(forKey: "cleanupEnabled") as? Bool ?? true
        try? FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
        var root = Self.root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
        refresh()
    }

    // MARK: Where things are

    nonisolated static let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Models", isDirectory: true)
    nonisolated static let whisperBase = root.appendingPathComponent("whisper", isDirectory: true)
    nonisolated static let whisperRepo = whisperBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
    nonisolated static let languageBase = root.appendingPathComponent("language", isDirectory: true)

    nonisolated static func folder(for model: LocalModel) -> URL {
        switch model.kind {
        case .speech: return whisperRepo.appendingPathComponent(model.source, isDirectory: true)
        case .cleanup: return languageBase.appendingPathComponent(model.source.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
        }
    }

    /// Written once a model is fully downloaded and ready, so a half-finished download never counts.
    nonisolated private static func readyMarker(for model: LocalModel) -> URL {
        folder(for: model).appendingPathComponent(".frank-ready")
    }

    // MARK: State

    func status(of model: LocalModel) -> Status { statuses[model.id] ?? .notInstalled }

    func isInstalled(_ model: LocalModel) -> Bool {
        if case .installed = status(of: model) { return true }
        return false
    }

    /// The speech model to listen with: the chosen one if it's here, otherwise any that is.
    var activeSpeechModel: LocalModel? {
        let installed = Self.speechModels.filter(isInstalled)
        return installed.first { $0.id == speechModelID } ?? installed.first
    }

    var activeCleanupModel: LocalModel? {
        cleanupEnabled && isInstalled(Self.cleanupModel) && Self.canRun(Self.cleanupModel) ? Self.cleanupModel : nil
    }

    /// Space taken by downloaded models.
    var usedSpace: Int64 {
        statuses.values.reduce(0) { total, status in
            if case .installed(let bytes) = status { return total + bytes }
            return total
        }
    }

    func hasRoom(for model: LocalModel) -> Bool {
        freeSpace == 0 || freeSpace > model.bytes + 300_000_000
    }

    /// Whether this iPhone can run a model at all.
    static func canRun(_ model: LocalModel) -> Bool {
        switch model.kind {
        case .speech:
            guard model == whisperTurbo else { return true }
            #if targetEnvironment(simulator)
            return true
            #else
            let support = WhisperKit.recommendedModels()
            return support.supported.contains(model.source)
            #endif
        case .cleanup:
            #if targetEnvironment(simulator)
            return false  // MLX needs a real GPU
            #else
            return ProcessInfo.processInfo.physicalMemory >= 5_500_000_000
            #endif
        }
    }

    static func whyNot(_ model: LocalModel) -> String {
        #if targetEnvironment(simulator)
        if model.kind == .cleanup { return "Needs a real iPhone." }
        #endif
        return model.kind == .cleanup ? "Needs an iPhone with at least 6 GB of memory." : "Needs a newer iPhone (A15 chip or later)."
    }

    /// Re-reads what's on disk and how much space is free.
    func refresh() {
        for model in Self.speechModels + [Self.cleanupModel] where tasks[model.id] == nil {
            if FileManager.default.fileExists(atPath: Self.readyMarker(for: model).path) {
                statuses[model.id] = .installed(bytes: Self.size(of: Self.folder(for: model)))
            } else if case .failed = status(of: model) {
                continue
            } else {
                statuses[model.id] = .notInstalled
            }
        }
        let values = try? Self.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        freeSpace = values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // MARK: Download, cancel, delete

    func download(_ model: LocalModel) {
        guard tasks[model.id] == nil else { return }
        statuses[model.id] = .downloading(0)
        startProgressPolling(model)
        tasks[model.id] = Task { [weak self] in
            guard let self else { return }
            do {
                switch model.kind {
                case .speech: try await self.downloadSpeech(model)
                case .cleanup: try await self.downloadLanguageModel(model)
                }
                try Task.checkCancellation()
                FileManager.default.createFile(atPath: Self.readyMarker(for: model).path, contents: Data())
                self.finish(model, .installed(bytes: Self.size(of: Self.folder(for: model))))
                if model.kind == .speech, self.activeSpeechModel == nil || !self.isInstalled(self.speechModel) {
                    self.speechModelID = model.id
                }
            } catch is CancellationError {
                self.finish(model, .notInstalled)
            } catch {
                if Task.isCancelled {
                    self.finish(model, .notInstalled)
                } else {
                    self.finish(model, .failed(Self.describe(error)))
                }
            }
        }
    }

    func cancel(_ model: LocalModel) {
        tasks[model.id]?.cancel()
        tasks[model.id] = nil
        stopProgressPolling(model)
        statuses[model.id] = .notInstalled
        // Partly downloaded files go too, so cancelling gives the space back.
        Task.detached { Self.removeFiles(of: model) }
    }

    func delete(_ model: LocalModel) {
        Task {
            await willDelete?(model)
            Self.removeFiles(of: model)
            refresh()
        }
    }

    private var speechModel: LocalModel {
        Self.speechModels.first { $0.id == speechModelID } ?? Self.recommendedSpeechModel
    }

    private func finish(_ model: LocalModel, _ status: Status) {
        tasks[model.id] = nil
        stopProgressPolling(model)
        statuses[model.id] = status
        refresh()
    }

    private func downloadSpeech(_ model: LocalModel) async throws {
        try FileManager.default.createDirectory(at: Self.whisperBase, withIntermediateDirectories: true)
        _ = try await WhisperKit.download(variant: model.source, downloadBase: Self.whisperBase) { [weak self] progress in
            let fraction = progress.fractionCompleted
            Task { @MainActor in self?.report(model, fileFraction: fraction) }
        }
        try Task.checkCancellation()
        // Compile it for this iPhone's Neural Engine and fetch its tokenizer now, so waking him later is quick.
        statuses[model.id] = .preparing
        stopProgressPolling(model)
        try await prepareSpeech?(model)
    }

    private func downloadLanguageModel(_ model: LocalModel) async throws {
        let cache = Self.languageBase.appendingPathComponent(".hub", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let hub = HubClient(cache: HubCache(cacheDirectory: cache))
        let snapshot = try await hub.downloadSnapshot(
            of: Repo.ID(rawValue: model.source)!, matching: ["*.safetensors", "*.json", "*.jinja", "*.txt"],
            progressHandler: { @MainActor [weak self] progress in
                self?.report(model, fileFraction: progress.fractionCompleted)
            })
        try Task.checkCancellation()
        // Keep a plain copy of the files in our own folder and drop the hub's cache.
        let destination = Self.folder(for: model)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in try FileManager.default.contentsOfDirectory(at: snapshot, includingPropertiesForKeys: nil) {
            let resolved = file.resolvingSymlinksInPath()
            try FileManager.default.moveItem(at: resolved, to: destination.appendingPathComponent(file.lastPathComponent))
        }
        try? FileManager.default.removeItem(at: cache)
    }

    // MARK: Progress

    /// Both downloaders report progress in whole files, which stalls on the big weight file, so the bytes
    /// already on disk are polled too and whichever is further along wins.
    private func startProgressPolling(_ model: LocalModel) {
        progressTimers[model.id]?.invalidate()
        let folders = Self.downloadFolders(for: model)
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task.detached(priority: .utility) { [weak self] in
                let bytes = folders.reduce(Int64(0)) { $0 + Self.size(of: $1) }
                await self?.report(model, byteFraction: Double(bytes) / Double(model.bytes))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimers[model.id] = timer
    }

    private func stopProgressPolling(_ model: LocalModel) {
        progressTimers[model.id]?.invalidate()
        progressTimers[model.id] = nil
    }

    private func report(_ model: LocalModel, fileFraction: Double = 0, byteFraction: Double = 0) {
        guard case .downloading(let current) = status(of: model) else { return }
        let next = min(0.99, max(current, fileFraction, byteFraction))
        if next - current >= 0.002 { statuses[model.id] = .downloading(next) }
    }

    nonisolated private static func downloadFolders(for model: LocalModel) -> [URL] {
        switch model.kind {
        case .speech: return [folder(for: model), whisperRepo.appendingPathComponent(".cache", isDirectory: true)]
        case .cleanup: return [languageBase.appendingPathComponent(".hub", isDirectory: true)]
        }
    }

    nonisolated private static func removeFiles(of model: LocalModel) {
        for folder in downloadFolders(for: model) + [folder(for: model)] {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    nonisolated static func size(of folder: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "The download stopped because the internet connection dropped. Try again on Wi-Fi."
            case NSURLErrorTimedOut:
                return "The download timed out. Try again on a faster connection."
            default: break
            }
        }
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError {
            return "Your iPhone ran out of space. Free some up and try again."
        }
        return "The download didn't finish: \(error.localizedDescription)"
    }
}
