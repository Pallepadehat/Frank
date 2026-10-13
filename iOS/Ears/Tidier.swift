import Foundation
@preconcurrency import MLX
@preconcurrency import MLXLLM
@preconcurrency import MLXLMCommon
@preconcurrency import Tokenizers

/// Tidies up what Whisper heard with a small language model on the device: punctuation, capitals and
/// clearly misheard words. It only ever polishes; if the result looks like anything more than that, the
/// original is kept.
actor Tidier {
    private var container: ModelContainer?
    private var loadedFolder: URL?

    func load(model folder: URL) async throws {
        if loadedFolder == folder, container != nil { return }
        unload()
        Memory.cacheLimit = 32 * 1024 * 1024
        let configuration = ModelConfiguration(directory: folder, extraEOSTokens: ["<|im_end|>"])
        container = try await LLMModelFactory.shared.loadContainer(
            from: NoDownloads(), using: TokenizerFiles(), configuration: configuration)
        loadedFolder = folder
    }

    func unload() {
        container = nil
        loadedFolder = nil
        Memory.clearCache()
    }

    var isLoaded: Bool { container != nil }

    /// Returns the tidied text, or the original if the model wandered off.
    func tidy(_ text: String, language: SpeechLanguage) async -> String {
        guard let container, text.split(separator: " ").count >= 3 else { return text }
        let instructions = """
        You correct transcripts made by speech recognition. The text is in \(language.name). Fix punctuation, \
        capital letters, spelling and words that were clearly misheard, so it reads as what the speaker most likely \
        said. Keep the speaker's own words, meaning, language and style. Never translate, summarise, answer, explain \
        or add anything. Reply with the corrected text only.
        """
        let words = text.split(separator: " ").count
        let parameters = GenerateParameters(maxTokens: min(400, words * 4 + 24), temperature: 0)
        do {
            let session = ChatSession(container, instructions: instructions, generateParameters: parameters)
            let reply = try await session.respond(to: text)
            return Self.accept(reply, for: text)
        } catch {
            return text
        }
    }

    /// Only takes the model's version if it's plainly the same sentence, tidied.
    static func accept(_ reply: String, for original: String) -> String {
        var cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        for quote in ["\"", "“", "”", "«", "»"] where cleaned.hasPrefix(quote) || cleaned.hasSuffix(quote) {
            cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: quote))
        }
        guard !cleaned.isEmpty, !cleaned.contains("\n") else { return original }
        let ratio = Double(cleaned.count) / Double(max(original.count, 1))
        guard (0.7...1.4).contains(ratio) else { return original }
        // Most of the words should still be the speaker's own.
        let before = Set(original.lowercased().split { !$0.isLetter && !$0.isNumber })
        let after = cleaned.lowercased().split { !$0.isLetter && !$0.isNumber }
        let kept = after.filter { before.contains($0) }.count
        guard Double(kept) >= Double(after.count) * 0.6 else { return original }
        return cleaned
    }
}

/// The model is always loaded from its folder on the phone; nothing is fetched at load time.
private struct NoDownloads: Downloader {
    func download(id: String, revision: String?, matching patterns: [String], useLatest: Bool,
                  progressHandler: @Sendable @escaping (Progress) -> Void) async throws -> URL {
        throw CocoaError(.fileNoSuchFile)
    }
}

/// Loads the tokenizer from the model's folder with swift-transformers.
private struct TokenizerFiles: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(try await AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
