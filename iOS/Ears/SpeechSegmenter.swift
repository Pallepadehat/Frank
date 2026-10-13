import Foundation

/// Cuts the live microphone stream (16 kHz mono) into phrases worth transcribing.
///
/// Background talk is split on pauses by a small voice-activity detector that adapts to the room's noise.
/// While you hold Frank's face everything is kept, pauses and all, and letting go hands it over as one question.
/// Not thread-safe: Ears only ever uses it from one serial queue.
final class SpeechSegmenter: @unchecked Sendable {
    struct Segment {
        let id: String
        let samples: [Float]
        let asked: Bool
    }

    static let sampleRate = 16_000

    /// A phrase began (so the transcript keeps things in the order they were said).
    var onStart: ((_ id: String, _ asked: Bool) -> Void)?
    /// A phrase is complete and ready to transcribe.
    var onSegment: ((Segment) -> Void)?

    private let frameLength = 480                 // 30 ms
    private let preRollFrames = 10                // keep 300 ms before speech starts
    private let startFrames = 3                   // 90 ms of voice starts a phrase
    private let endSilenceFrames = 24             // 720 ms of quiet ends one
    private let maxFrames = 600                   // 18 s at most, then cut anyway
    private let minVoicedFrames = 8               // shorter blips (a cough, a knock) are dropped

    private var pending: [Float] = []
    private var preRoll: [[Float]] = []
    private var current: [Float] = []
    private var currentID: String?
    private var voicedFrames = 0
    private var frameCount = 0
    private var silentRun = 0
    private var speechRun = 0
    private var noiseFloor: Float = 0.003
    private var asking = false

    /// Starts a question: whatever you were saying is closed off first, then everything until `endQuestion` is kept.
    func beginQuestion() {
        finishCurrent()
        asking = true
        startPhrase(asked: true)
    }

    /// You let go: the question is handed over right away.
    func endQuestion() {
        guard asking else { return }
        asking = false
        if let id = currentID {
            let samples = current
            reset()
            onSegment?(Segment(id: id, samples: samples, asked: true))
        }
    }

    /// Drops everything, for when the session ends.
    func clear() {
        pending = []
        preRoll = []
        asking = false
        reset()
    }

    /// Adds samples (16 kHz mono) as they arrive from the microphone.
    func append(_ samples: [Float]) {
        pending += samples
        while pending.count >= frameLength {
            let frame = Array(pending[0..<frameLength])
            pending.removeFirst(frameLength)
            process(frame)
        }
    }

    private func process(_ frame: [Float]) {
        var sum: Float = 0
        for s in frame { sum += s * s }
        let rms = (sum / Float(frame.count)).squareRoot()
        // Voice is clearly louder than the room: about 9 dB over the noise floor, and not too faint overall.
        let voiced = rms > max(noiseFloor * 2.8, 0.006)
        if !voiced {
            // The floor follows quiet frames slowly, so a fan or a café hum isn't taken for speech.
            noiseFloor = noiseFloor * 0.97 + rms * 0.03
        }

        if asking {
            current += frame
            frameCount += 1
            if voiced { voicedFrames += 1 }
            return
        }

        if currentID == nil {
            preRoll.append(frame)
            if preRoll.count > preRollFrames { preRoll.removeFirst() }
            speechRun = voiced ? speechRun + 1 : 0
            if speechRun >= startFrames {
                startPhrase(asked: false)
                for f in preRoll { current += f }
                frameCount = preRoll.count
                voicedFrames = speechRun
                preRoll = []
            }
            return
        }

        current += frame
        frameCount += 1
        if voiced {
            voicedFrames += 1
            silentRun = 0
        } else {
            silentRun += 1
        }
        if silentRun >= endSilenceFrames || frameCount >= maxFrames {
            finishCurrent()
        }
    }

    private func startPhrase(asked: Bool) {
        let id = UUID().uuidString
        currentID = id
        current = []
        frameCount = 0
        voicedFrames = 0
        silentRun = 0
        onStart?(id, asked)
    }

    private func finishCurrent() {
        guard let id = currentID else { return }
        let samples = current, voiced = voicedFrames
        reset()
        if voiced >= minVoicedFrames {
            onSegment?(Segment(id: id, samples: samples, asked: false))
        } else {
            onSegment?(Segment(id: id, samples: [], asked: false))  // too short: the placeholder is dropped
        }
    }

    private func reset() {
        currentID = nil
        current = []
        frameCount = 0
        voicedFrames = 0
        silentRun = 0
        speechRun = 0
    }
}
