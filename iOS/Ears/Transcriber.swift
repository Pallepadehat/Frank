import Foundation
@preconcurrency import WhisperKit

/// Turns phrases of speech into text with Whisper, on the device. One phrase at a time; WhisperKit isn't
/// safe to call concurrently.
actor Transcriber {
    private var whisper: WhisperKit?
    private var loadedFolder: URL?

    /// Loads (or switches to) a downloaded model. The first load of a model compiles it for the Neural Engine,
    /// which can take a while; after that it's quick.
    func load(model folder: URL, base: URL) async throws {
        if loadedFolder == folder, whisper != nil { return }
        await unload()
        let config = WhisperKitConfig(downloadBase: base, modelFolder: folder.path, tokenizerFolder: base,
                                      verbose: false, logLevel: .error, prewarm: true, load: true, download: false)
        whisper = try await WhisperKit(config)
        loadedFolder = folder
    }

    func unload() async {
        await whisper?.unloadModels()
        whisper = nil
        loadedFolder = nil
    }

    var isLoaded: Bool { whisper != nil }

    /// Transcribes 16 kHz mono samples. Returns nil when there was nothing worth keeping.
    func transcribe(_ samples: [Float], language: SpeechLanguage) async throws -> String? {
        guard let whisper, samples.count > SpeechSegmenter.sampleRate / 4 else { return nil }
        let options = DecodingOptions(task: .transcribe, language: language.code, temperatureFallbackCount: 2,
                                      usePrefillPrompt: true, detectLanguage: language.code == nil,
                                      skipSpecialTokens: true, withoutTimestamps: true,
                                      noSpeechThreshold: 0.6, chunkingStrategy: ChunkingStrategy.none)
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.isPhantom(text) ? nil : text
    }

    /// Whisper sometimes "hears" stock phrases in silence or noise, mostly from the subtitles it was trained on.
    static func isPhantom(_ text: String) -> Bool {
        let plain = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        guard !plain.isEmpty, plain.rangeOfCharacter(from: .letters) != nil else { return true }
        if plain.hasPrefix("[") || plain.hasPrefix("(") || plain.hasPrefix("♪") { return true }
        let phantoms = ["thank you", "thanks for watching", "thank you for watching", "you", "bye", "subtitles by",
                        "tak for at se med", "tak fordi du så med", "tekstning af", "undertekster af", "undertekster",
                        "tak", "danske tekster", "tekster af"]
        return phantoms.contains { plain == $0 || (plain.hasPrefix($0) && plain.count < $0.count + 24 && $0.count > 8) }
    }
}

/// The language Frank listens for. Telling Whisper is faster and more accurate than letting it guess.
enum SpeechLanguage: String, CaseIterable, Identifiable {
    case automatic, danish, english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Detect"
        case .danish: return "Dansk"
        case .english: return "English"
        }
    }

    /// Whisper's language code, or nil to detect it.
    var code: String? {
        switch self {
        case .automatic: return nil
        case .danish: return "da"
        case .english: return "en"
        }
    }

    /// What the tidy-up model is told the text is in.
    var name: String {
        switch self {
        case .automatic: return "the same language as the input"
        case .danish: return "Danish"
        case .english: return "English"
        }
    }

    /// A good default from the phone's own languages.
    static var preferred: SpeechLanguage {
        let codes = Locale.preferredLanguages.map { String($0.prefix(2)) }
        if codes.first == "da" { return .danish }
        if codes.first == "en" { return codes.contains("da") ? .automatic : .english }
        return .automatic
    }
}
