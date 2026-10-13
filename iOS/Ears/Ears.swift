import AVFoundation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Frank's ears: turns the microphone into text on the iPhone. No audio ever leaves the phone.
///
/// Phrases are transcribed one at a time, questions first. Background talk can be tidied up by a small
/// language model before it's handed on, always in the order it was said; a question never waits for that.
@MainActor
final class Ears {
    let library: ModelLibrary

    /// A phrase began. Its words follow in `onHeard`.
    var onStart: ((_ id: String, _ asked: Bool) -> Void)?
    /// What was heard (empty if it turned out to be nothing), and later its tidied version.
    var onHeard: ((_ id: String, _ text: String, _ asked: Bool) -> Void)?
    /// Background talk for Frank, in order.
    var onContext: ((_ text: String) -> Void)?
    /// The question you asked while holding his face (nil if nothing was caught).
    var onQuestion: ((_ text: String?) -> Void)?

    private let transcriber = Transcriber()
    private let tidier = Tidier()
    // The segmenter is only ever used on `queue`, fed straight from the audio thread.
    nonisolated private let segmenter = SpeechSegmenter()
    nonisolated private let queue = DispatchQueue(label: "frank.ears")
    nonisolated private let resampler = Resampler()

    private var questions: [SpeechSegmenter.Segment] = []
    private var phrases: [SpeechSegmenter.Segment] = []
    private var tidyJobs: [(id: String, text: String)] = []
    private var working = false
    /// Background lines waiting to go to Frank, in order. `ready` once tidied (or straight away if tidying is off).
    private var outbox: [(id: String, text: String, ready: Bool)] = []
    private var listening = false

    init(library: ModelLibrary) {
        self.library = library
        segmenter.onStart = { [weak self] id, asked in
            Task { @MainActor in self?.onStart?(id, asked) }
        }
        segmenter.onSegment = { [weak self] segment in
            Task { @MainActor in self?.received(segment) }
        }
        library.prepareSpeech = { [weak self] model in
            try await self?.transcriber.load(model: ModelLibrary.folder(for: model), base: ModelLibrary.whisperBase)
        }
        library.willDelete = { [weak self] model in
            guard let self else { return }
            switch model.kind {
            case .speech: await self.transcriber.unload()
            case .cleanup: await self.tidier.unload()
            }
        }
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                // The tidy-up model is the nice-to-have: let it go first.
                await self?.tidier.unload()
            }
        }
        #endif
    }

    /// Whether he can hear at all: a speech model is downloaded.
    var canHear: Bool { library.activeSpeechModel != nil }

    // MARK: Session

    /// Starts listening. Models load in the background; anything said meanwhile is transcribed once they're ready.
    func start() {
        listening = true
        Task { await loadModels() }
    }

    func stop() {
        listening = false
        queue.async { [segmenter] in segmenter.clear() }
        questions = []
        phrases = []
        tidyJobs = []
        outbox = []
        Task { await tidier.unload() }
    }

    func beginQuestion() {
        queue.async { [segmenter] in segmenter.beginQuestion() }
    }

    func endQuestion() {
        queue.async { [segmenter] in segmenter.endQuestion() }
    }

    /// Feeds microphone audio, straight from the audio tap (any thread).
    nonisolated func hear(_ buffer: AVAudioPCMBuffer) {
        guard let samples = resampler.convert(buffer) else { return }
        queue.async { [segmenter] in segmenter.append(samples) }
    }

    // MARK: Work, one thing at a time

    private func received(_ segment: SpeechSegmenter.Segment) {
        guard listening else { return }
        if segment.samples.isEmpty {
            onHeard?(segment.id, "", false)
            return
        }
        if segment.asked { questions.append(segment) } else { phrases.append(segment) }
        pump()
    }

    private func pump() {
        guard !working else { return }
        if !questions.isEmpty {
            let segment = questions.removeFirst()
            run { await self.transcribe(segment) }
        } else if !phrases.isEmpty {
            let segment = phrases.removeFirst()
            run { await self.transcribe(segment) }
        } else if !tidyJobs.isEmpty {
            let job = tidyJobs.removeFirst()
            run { await self.tidy(job.id, job.text) }
        }
    }

    private func run(_ work: @escaping @MainActor () async -> Void) {
        working = true
        Task { @MainActor in
            await work()
            self.working = false
            self.pump()
        }
    }

    private func transcribe(_ segment: SpeechSegmenter.Segment) async {
        await loadModels()
        var text: String?
        do {
            text = try await transcriber.transcribe(segment.samples, language: library.language)
        } catch {
            NSLog("Frank: transcription failed: \(error)")
        }
        guard listening else { return }
        onHeard?(segment.id, text ?? "", segment.asked)

        if segment.asked {
            // Everything said before the question goes to Frank first, tidied or not.
            flushOutbox(all: true)
            onQuestion?(text)
            return
        }
        guard let text else { return }
        let tidying = library.activeCleanupModel != nil
        outbox.append((segment.id, text, !tidying))
        if tidying { tidyJobs.append((segment.id, text)) }
        flushOutbox(all: false)
    }

    private func tidy(_ id: String, _ text: String) async {
        guard let model = library.activeCleanupModel else { markReady(id, text); return }
        do {
            try await tidier.load(model: ModelLibrary.folder(for: model))
        } catch {
            NSLog("Frank: couldn't load the tidy-up model: \(error)")
            markReady(id, text)
            return
        }
        let tidied = await tidier.tidy(text, language: library.language)
        guard listening else { return }
        if tidied != text { onHeard?(id, tidied, false) }
        markReady(id, tidied)
    }

    private func markReady(_ id: String, _ text: String) {
        if let i = outbox.firstIndex(where: { $0.id == id }) {
            outbox[i].text = text
            outbox[i].ready = true
        }
        flushOutbox(all: false)
    }

    /// Hands background lines to Frank in order, stopping at the first one still being tidied (unless `all`).
    private func flushOutbox(all: Bool) {
        while let first = outbox.first, all || first.ready {
            outbox.removeFirst()
            onContext?(first.text)
        }
    }

    private func loadModels() async {
        guard let speech = library.activeSpeechModel else { return }
        do {
            try await transcriber.load(model: ModelLibrary.folder(for: speech), base: ModelLibrary.whisperBase)
        } catch {
            NSLog("Frank: couldn't load the speech model: \(error)")
        }
    }
}

/// Converts microphone buffers to 16 kHz mono floats for Whisper. Used from the audio thread only.
private final class Resampler: @unchecked Sendable {
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(SpeechSegmenter.sampleRate),
                                       channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private let lock = NSLock()

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        if sourceFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            sourceFormat = buffer.format
        }
        guard let converter else { return nil }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let samples = out.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: samples, count: Int(out.frameLength)))
    }
}
