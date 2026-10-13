import AVFoundation
import Foundation

/// A session with Frank, from the phone's side. Once he's awake the mic is on the whole time and his ears
/// (on-device speech recognition) turn everything you say into text, which goes to his brain on the Mac as
/// context; he stays quiet until you hold the screen and ask. No audio is ever sent anywhere.
/// He never talks out loud: replies are speech bubbles on the Mac, with a little cartoon chirp here.
@MainActor
final class LiveVoice: NSObject, ObservableObject {
    enum State: Equatable { case asleep, waking, listening, asking, thinking, speaking }

    @Published private(set) var state: State = .asleep

    /// Sends a packet to the Mac, where his brain lives.
    var send: ((Packet) -> Void)?
    /// Whether the Mac is there to think for him.
    var isConnected: (() -> Bool)?
    var onStateChange: ((State) -> Void)?
    /// For the saved transcript: a session started or ended, something you said (in order, then its words), his replies.
    var onSessionStart: (() -> Void)?
    var onSessionEnd: (() -> Void)?
    var onUserTurn: ((_ itemID: String, _ asked: Bool) -> Void)?
    var onUserWords: ((_ itemID: String, _ text: String, _ asked: Bool) -> Void)?
    var onReply: ((String) -> Void)?
    var onReport: ((String) -> Void)?
    /// He was woken but has no speech model yet: time to get him his ears.
    var onNeedsEars: (() -> Void)?

    let ears: Ears

    /// Loudness of his chirp right now, 0…1.
    private(set) var level: Double = 0

    var volume: Double {
        get { UserDefaults.standard.object(forKey: "volume") as? Double ?? 1 }
        set {
            UserDefaults.standard.set(newValue, forKey: "volume")
            player.volume = Float(newValue)
        }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let playFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    private var audioReady = false

    private var pendingBuffers = 0
    /// His brain is working on a question.
    private var answering = false
    private var sleepAfterReply = false
    /// Holding the screen to ask.
    private var holding = false

    init(ears: Ears) {
        self.ears = ears
        super.init()
        ears.onStart = { [weak self] id, asked in self?.onUserTurn?(id, asked) }
        ears.onHeard = { [weak self] id, text, asked in self?.onUserWords?(id, text, asked) }
        ears.onContext = { [weak self] text in self?.send?(Packet(command: "heard", text: text)) }
        ears.onQuestion = { [weak self] text in self?.heardQuestion(text) }
    }

    private func setState(_ new: State) {
        guard new != state else { return }
        state = new
        onStateChange?(new)
    }

    // MARK: Wake and sleep

    func toggle() {
        state == .asleep ? wake() : sleep()
    }

    func wake() {
        guard state == .asleep, isConnected?() ?? false else { holding = false; return }
        guard ears.canHear else {
            holding = false
            onNeedsEars?()
            return
        }
        setState(.waking)
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard self.state == .waking else { return }
                guard granted else {
                    self.send?(Packet(command: "missed"))
                    self.setState(.asleep)
                    return
                }
                do {
                    try self.startAudio()
                } catch {
                    NSLog("Frank: couldn't start the microphone: \(error)")
                    self.setState(.asleep)
                    return
                }
                self.ears.start()
                self.onSessionStart?()
                self.chirp(syllables: 2)
                if self.holding { self.ears.beginQuestion() }
                self.setState(self.holding ? .asking : .listening)
            }
        }
    }

    func sleep() {
        guard state != .asleep else { return }
        onSessionEnd?()
        ears.stop()
        stopAudio()
        pendingBuffers = 0
        answering = false
        sleepAfterReply = false
        holding = false
        level = 0
        setState(.asleep)
    }

    /// Says a quick hi (for checking the chirp volume).
    func sayHi() {
        guard state != .asleep else { wake(); return }
        answering = true
        send?(Packet(command: "hi"))
    }

    // MARK: Hold to ask

    /// You pressed and held the screen: what you say now is the question.
    func beginAsk() {
        holding = true
        if state == .asleep { wake(); return }
        ears.beginQuestion()
        if state == .listening || state == .speaking { setState(.asking) }
    }

    /// You let go: his ears hand over the question in a moment; he's thinking meanwhile.
    func endAsk() {
        guard holding else { return }
        holding = false
        guard state != .asleep else { return }
        ears.endQuestion()
        if state != .waking { setState(.thinking) }
    }

    /// The question you asked, as text. Nothing caught: back to listening.
    private func heardQuestion(_ text: String?) {
        guard let text, !text.isEmpty else {
            send?(Packet(command: "missed"))
            if state == .thinking || state == .asking { setState(holding ? .asking : .listening) }
            return
        }
        answering = true
        setState(.thinking)
        send?(Packet(command: "ask", text: text))
    }

    // MARK: From his brain on the Mac

    func handle(_ packet: Packet) {
        guard state != .asleep else { return }
        switch packet.command {
        case "speaking":
            // He started replying: a little chirp, sized to how much he says.
            setState(.speaking)
            let words = packet.text?.split(separator: " ").count ?? 3
            chirp(syllables: min(max(words, 3), 5))
        case "reply":
            if let text = packet.text { onReply?(text) }
        case "report":
            if let text = packet.text { onReport?(text) }
        case "turnDone":
            answering = false
            if packet.text == "sleep" { sleepAfterReply = true }
            finishIfQuiet()
        default:
            break
        }
    }

    /// Back to listening once he's replied and chirped (or asleep, if he said goodbye).
    private func finishIfQuiet() {
        guard pendingBuffers == 0, !answering else { return }
        if sleepAfterReply { sleep(); return }
        if state == .speaking || state == .thinking { setState(holding ? .asking : .listening) }
    }

    // MARK: Audio

    private func startAudio() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        #endif

        if !audioReady {
            let input = engine.inputNode
            try input.setVoiceProcessingEnabled(true)  // echo cancellation, so he doesn't hear himself
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: playFormat)
            player.installTap(onBus: 0, bufferSize: 1024, format: playFormat) { [weak self] buffer, _ in
                guard let self, let samples = buffer.floatChannelData?[0] else { return }
                var sum: Float = 0
                for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
                let rms = sqrt(sum / Float(max(buffer.frameLength, 1)))
                self.level = min(1, Double(rms) * 5)
            }
            audioReady = true
        }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        let ears = self.ears
        input.installTap(onBus: 0, bufferSize: 2400, format: inputFormat) { buffer, _ in
            ears.hear(buffer)  // turned into text on the phone; the audio itself goes nowhere
        }
        player.volume = Float(volume)
        engine.prepare()
        try engine.start()
        player.play()
    }

    private func stopAudio() {
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// A tiny cartoon chirp: a few soft, round, bell-like notes from a happy pentatonic scale,
    /// each with a little upward "boop" at the start, like a small creature humming.
    private func chirp(syllables: Int) {
        guard audioReady else { return }
        let rate = playFormat.sampleRate
        // C major pentatonic, two octaves up high (C6…E7), so it always sounds sweet together.
        let scale = [1046.5, 1174.7, 1318.5, 1568.0, 1760.0, 2093.0, 2349.3, 2637.0]
        var index = Int.random(in: 1...3)
        var samples: [Float] = []
        for i in 0..<syllables {
            if i > 0 { index = min(max(index + [-1, 1, 1, 2].randomElement()!, 0), scale.count - 1) }
            let note = scale[index] * 0.5  // drop an octave: rounder, less piercing
            let duration = i == syllables - 1 ? 0.13 : Double.random(in: 0.07...0.09)
            let count = Int(duration * rate)
            var phase = 0.0
            for n in 0..<count {
                let time = Double(n) / rate
                let t = Double(n) / Double(count)
                // Scoops up into the note over the first 25 ms, with a gentle wobble on the last one.
                let scoop = 1 - 0.18 * exp(-time / 0.012)
                let wobble = i == syllables - 1 ? 1 + 0.012 * sin(time * 2 * .pi * 18) : 1
                phase += 2 * .pi * note * scoop * wobble / rate
                let attack = min(1, time / 0.006)
                let envelope = attack * exp(-t * 3.2) * (1 - pow(t, 6))
                let wave = sin(phase) + 0.12 * sin(2 * phase)
                samples.append(Float(wave * envelope * 0.26))
            }
            samples += [Float](repeating: 0, count: Int(rate * 0.028))
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let out = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { out.update(from: $0.baseAddress!, count: samples.count) }
        pendingBuffers += 1
        player.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingBuffers = max(0, self.pendingBuffers - 1)
                if self.pendingBuffers == 0 { self.level = 0 }
                self.finishIfQuiet()
            }
        }
    }
}
