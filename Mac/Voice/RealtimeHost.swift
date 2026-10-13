import AppKit
import FrankShared

/// The Mac's half of live voice. The phone runs the OpenAI Realtime session (its mic, its speaker);
/// the Mac hands it a short-lived key, runs its tools (look, point, and use the computer) and shows captions.
/// Everything here runs on the main thread, alongside the cursor it drives.
@MainActor
final class RealtimeHost {
    static let model = "gpt-realtime-2.1"

    private let overlay: CursorOverlay
    private let reports = ReportPanel()
    private var snapshot: ScreenSnapshot?
    private var captionClear: DispatchWorkItem?
    private var readingDone: DispatchWorkItem?
    /// Tools run one at a time, in the order he asked for them.
    private var toolChain: Task<Void, Never>?
    /// After the stop hotkey, his actions are refused for a few seconds.
    private var stoppedUntil = 0.0
    /// True while he's awake and talking with you (false = follow mode).
    private(set) var awake = false
    var onChange: (() -> Void)?

    init(overlay: CursorOverlay) {
        self.overlay = overlay
    }

    private var engine: CursorEngine { overlay.view.engine }

    /// Handles a request from the phone. `reply` sends a packet back to that phone.
    func handle(_ packet: Packet, reply: @escaping (Packet) -> Void) {
        switch packet.command {
        case "realtimeToken":
            Task { @MainActor in
                do {
                    let token = try await Self.mintToken()
                    reply(Packet(command: "realtimeToken", callID: packet.callID, text: token))
                } catch {
                    reply(Packet(command: "realtimeToken", callID: packet.callID, text: nil, image: nil))
                    self.showCaption(error.localizedDescription, for: 6)
                }
            }
        case "transcribe":
            // A recorded chunk from the phone: save it, transcribe it with speakers, send the lines back.
            guard let meta = packet.text.flatMap({ try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }),
                  let session = meta["session"] as? String, let index = meta["index"] as? Int,
                  let sessionStarted = meta["sessionStarted"] as? Double,
                  let audio = packet.audio.flatMap({ Data(base64Encoded: $0) }) else {
                reply(Packet(command: "transcribed", callID: packet.callID, text: nil))
                return
            }
            Task {
                do {
                    let result = try await MeetingNotes.transcribe(audio: audio, session: session, index: index,
                                                                   sessionStarted: Date(timeIntervalSince1970: sessionStarted))
                    let lines = result.segments.map { ["speaker": $0.speaker, "start": $0.start, "text": $0.text] as [String: Any] }
                    let body: [String: Any] = ["segments": lines, "notesPath": result.folder.path]
                    let text = (try? JSONSerialization.data(withJSONObject: body)).flatMap { String(data: $0, encoding: .utf8) }
                    reply(Packet(command: "transcribed", callID: packet.callID, text: text))
                } catch {
                    NSLog("Frank: transcription failed: \(error)")
                    reply(Packet(command: "transcribed", callID: packet.callID, text: nil))
                }
            }
        case "notes":
            // The phone's copy of a session: write it out as meeting-notes files.
            guard let json = packet.text.flatMap({ try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }),
                  let folder = MeetingNotes.write(session: json) else {
                reply(Packet(command: "notes", callID: packet.callID, text: nil))
                return
            }
            reply(Packet(command: "notes", callID: packet.callID, text: folder.path))
        case "awake":
            setAwake(true)
        case "asleep":
            setAwake(false)
        case "caption":
            // His reply, streaming in. It shows as a speech bubble by his cursor (or above the phone).
            let text = packet.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            readingDone?.cancel()
            showCaption(text.isEmpty ? nil : text, for: 0)
            if !text.isEmpty { setSpeaking(true) }
        case "captionDone":
            // Keep the bubble (and his pointing) up long enough to read, then tidy away.
            let text = packet.text ?? ""
            if !text.isEmpty { showCaption(text, for: 0) }
            let words = Double(text.split(separator: " ").count)
            let readTime = min(max(2.8, 1.2 + words * 0.32), 12) + 3
            readingDone?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.setSpeaking(false)
                self?.showCaption(nil, for: 0)
            }
            readingDone = work
            DispatchQueue.main.asyncAfter(deadline: .now() + readTime, execute: work)
        case "tool":
            let previous = toolChain
            toolChain = Task { @MainActor in
                await previous?.value
                let result = await self.runTool(packet.tool ?? "", arguments: packet.text ?? "{}")
                reply(Packet(command: "toolResult", callID: packet.callID, text: result.text, image: result.image))
            }
        default:
            break
        }
    }

    /// FRANK_DEMO_RESEARCH="question": runs a real research call and saves pictures of the card.
    func demoResearch(_ question: String, out: String) {
        Task { @MainActor in
            reports.showLoading(question)
            try? await Task.sleep(for: .milliseconds(400))
            reports.snapshot(expanded: false, to: out + "-loading.png")
            do {
                let report = try await WebResearch.research(question, context: nil)
                reports.show(report)
                print(report.plainText, report.sources.map(\.url))
            } catch {
                reports.showError(error.localizedDescription)
                print(error)
            }
            try? await Task.sleep(for: .milliseconds(500))
            reports.snapshot(expanded: false, to: out + "-preview.png")
            reports.snapshot(expanded: true, to: out + "-open.png")
            try? await Task.sleep(for: .milliseconds(800))
            reports.snapshot(expanded: true, to: out + "-open.png")
            exit(0)
        }
    }

    func setAwake(_ on: Bool) {
        awake = on
        engine.awake = on
        engine.brainMood = nil
        engine.gazeOverride = nil  // his eyes follow your mouse while he listens
        if !on {
            queue = []
            stopChoreography()
            overlay.goHome()
            overlay.view.speechTarget = nil
            showCaption(nil, for: 0)
        }
        onChange?()
    }

    /// The stop hotkey: refuse any further actions for a moment and bring the cursor home.
    func stopActions() {
        stoppedUntil = CACurrentMediaTime() + 6
        queue = []
        engine.dragging = false
        goHome()
        overlay.view.bubble("Stopped", life: 1.6)
    }

    // MARK: Tools

    /// Separates his instructions from the report text, so the phone can save the report in the transcript.
    static let reportMarker = "\n---REPORT---\n"

    private static let actionNames: Set<String> = ["click", "type_text", "press_keys", "scroll", "drag", "open_app", "open_url"]

    private func runTool(_ name: String, arguments: String) async -> (text: String, image: String?) {
        let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any]) ?? [:]
        if Self.actionNames.contains(name) {
            if let refusal = actionRefusal() { return (refusal, nil) }
            return await runAction(name, args)
        }
        switch name {
        case "look_at_screen":
            return await look(prefix: nil)
        case "point_at":
            let id = (args["target_id"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard let snapshot else { return ("Call look_at_screen first.", nil) }
            guard let target = snapshot.target(id) else { return ("No target \(id). Use an id from the last look_at_screen.", nil) }
            point(to: CGPoint(x: target.rect.midX, y: target.rect.maxY + 3), showing: target.rect)
            return (queue.count > 1 ? "Queued: your cursor will point at \"\(target.text)\" after the earlier spots." : "Pointing at \"\(target.text)\".", nil)
        case "point_at_spot":
            guard let x = number(args["x"]), let y = number(args["y"]) else { return ("Give x and y.", nil) }
            let spot = gridPoint(x, y)
            point(to: spot, showing: CGRect(x: spot.x - 16, y: spot.y - 16, width: 32, height: 32))
            return ("Pointing there.", nil)
        case "stop_pointing":
            requestHome()
            return ("Your cursor will head home once you finish talking.", nil)
        case "web_research":
            let question = (args["question"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !question.isEmpty else { return ("What should I research?", nil) }
            reports.showLoading(question)
            do {
                let screenText = snapshot?.lines.prefix(40).map { $0.line.text }.joined(separator: " / ")
                let report = try await WebResearch.research(question, context: screenText)
                reports.show(report)
                return ("The full report is now in a card on the user's screen. Reply with ONE short line: the key takeaway in your own words. Don't repeat the report." + Self.reportMarker + report.plainText, nil)
            } catch {
                reports.showError(error.localizedDescription)
                return ("Research failed: \(error.localizedDescription). Tell the user in a few words.", nil)
            }
        case "go_to_sleep":
            // The phone closes the session after this call; the Mac just tidies up.
            return ("Going to sleep. Say a very short goodbye.", nil)
        default:
            return ("Unknown tool \(name).", nil)
        }
    }

    private func look(prefix: String?) async -> (text: String, image: String?) {
        do {
            let shot = try await ScreenReader.snapshot()
            snapshot = shot
            var text = shot.targetList
            let mouse = ComputerControl.mouseLocation
            let mx = Int(min(max(mouse.x / shot.size.width, 0), 1) * 1000), my = Int(min(max(mouse.y / shot.size.height, 0), 1) * 1000)
            text += "\nThe user's mouse pointer is at @\(mx),\(my)"
            if let under = shot.target(near: mouse) { text += ", on \(under.id) \"\(under.text)\"" }
            text += ". When they say \"this\", \"that\" or \"here\", they mean what's at their mouse pointer."
            if let prefix { text = prefix + "\nHere's the screen now (ids have changed):\n" + text }
            if !ComputerControl.isTrusted, Settings.shared.computerControl {
                text += "\n(Clickable controls are hidden until the user allows Frank under Accessibility.)"
            }
            return (text, shot.jpeg.base64EncodedString())
        } catch {
            let problem = "I can't see the screen. Screen Recording permission is off for Frank on the Mac."
            return (prefix.map { $0 + " " + problem } ?? problem, nil)
        }
    }

    private func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private var screenSize: CGSize {
        snapshot?.size ?? NSScreen.screens.first?.frame.size ?? CGSize(width: 1440, height: 900)
    }

    private func gridPoint(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: min(max(x, 0), 1000) / 1000 * screenSize.width, y: min(max(y, 0), 1000) / 1000 * screenSize.height)
    }

    /// Finds the spot an action refers to: a target id (its center) or a grid position.
    private func spot(_ args: [String: Any], id idKey: String, x xKey: String, y yKey: String) -> (point: CGPoint, name: String)? {
        if let id = args[idKey] as? String, !id.isEmpty, let target = snapshot?.target(id) {
            return (CGPoint(x: target.rect.midX, y: target.rect.midY), target.text)
        }
        if let x = number(args[xKey]), let y = number(args[yKey]) {
            return (gridPoint(x, y), "that spot")
        }
        return nil
    }

    // MARK: Using the computer

    private func actionRefusal() -> String? {
        if !Settings.shared.computerControl {
            return "The user has turned off computer control in the menu bar. You can still look and point."
        }
        if CACurrentMediaTime() < stoppedUntil {
            return "The user pressed stop. Don't do anything else until they ask again."
        }
        if !ComputerControl.isTrusted {
            ComputerControl.askForPermission()
            return ComputerControl.ControlError.notTrusted.localizedDescription
        }
        return nil
    }

    /// Shortcuts that log out, lock the screen or force-quit apps are left to the user.
    private static let refusedShortcuts: Set<String> = ["cmd+shift+q", "cmd+option+shift+q", "ctrl+cmd+q", "cmd+option+escape", "cmd+option+esc"]

    private func runAction(_ name: String, _ args: [String: Any]) async -> (text: String, image: String?) {
        takeControl()
        defer { afterAction() }
        let view = overlay.view
        switch name {
        case "click":
            guard let target = spot(args, id: "target_id", x: "x", y: "y") else {
                return ("Tell me what to click: a target id from look_at_screen, or x and y.", nil)
            }
            let right = args["right"] as? Bool ?? false
            let count = (args["double"] as? Bool ?? false) ? 2 : 1
            let saved = ComputerControl.mouseLocation
            await fly(to: target.point)
            view.clickEffect(at: target.point, right: right)
            try? await Task.sleep(for: .milliseconds(90))  // the click lands at the bottom of the squish
            await ComputerControl.click(at: target.point, right: right, count: count)
            try? await Task.sleep(for: .milliseconds(60))
            ComputerControl.warp(to: saved)  // hand your pointer back where you left it
            try? await Task.sleep(for: .milliseconds(380))
            let verb = right ? "Right-clicked" : count == 2 ? "Double-clicked" : "Clicked"
            return await look(prefix: "\(verb) \(target.name == "that spot" ? "there" : "\"\(target.name)\"").")

        case "type_text":
            let text = args["text"] as? String ?? ""
            guard !text.isEmpty else { return ("Nothing to type.", nil) }
            let field = ControlsReader.focusedField()
            if field.secure {
                return ("That's a password field. Ask the user to type it themselves.", nil)
            }
            if let frame = field.frame, CGRect(origin: .zero, size: screenSize).intersects(frame), frame.height < screenSize.height * 0.6 {
                await fly(to: CGPoint(x: frame.minX + min(28, frame.width * 0.2), y: frame.maxY + 2))
            } else if engine.isHome {
                overlay.mode = .docked
            }
            await ComputerControl.type(text) { chunk in view.typedEffect(chunk) }
            if args["press_return"] as? Bool ?? false {
                try? await Task.sleep(for: .milliseconds(120))
                _ = try? ComputerControl.press("return")
                view.bubble("↩")
                try? await Task.sleep(for: .milliseconds(550))
                return await look(prefix: "Typed it and pressed Return.")
            }
            return ("Typed it.", nil)

        case "press_keys":
            let keys = (args["keys"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let normalized = keys.lowercased().replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "command", with: "cmd").replacingOccurrences(of: "alt", with: "option")
            if Self.refusedShortcuts.contains(normalized) {
                return ("I won't press that one (it logs out, locks or force-quits). Ask the user to do it.", nil)
            }
            if engine.isHome { overlay.mode = .docked }
            do {
                let label = try ComputerControl.press(keys)
                view.bubble(label)
            } catch {
                return (error.localizedDescription, nil)
            }
            try? await Task.sleep(for: .milliseconds(380))
            return await look(prefix: "Pressed \(keys).")

        case "scroll":
            let direction = (args["direction"] as? String ?? "down").lowercased()
            let amount = min(max(number(args["amount"]) ?? 3, 1), 10)
            let point = spot(args, id: "target_id", x: "x", y: "y")?.point
                ?? CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
            let pixels = Int(amount * 120)
            let (dx, dy, arrow): (Int, Int, String) = {
                switch direction {
                case "up": return (0, -pixels, "↑")
                case "left": return (-pixels, 0, "←")
                case "right": return (pixels, 0, "→")
                default: return (0, pixels, "↓")
                }
            }()
            let saved = ComputerControl.mouseLocation
            await fly(to: point)
            view.bubble(arrow)
            await ComputerControl.scroll(dx: dx, dy: dy, at: point)
            ComputerControl.warp(to: saved)
            try? await Task.sleep(for: .milliseconds(280))
            return await look(prefix: "Scrolled \(direction).")

        case "drag":
            guard let from = spot(args, id: "from_id", x: "from_x", y: "from_y"),
                  let to = spot(args, id: "to_id", x: "to_x", y: "to_y") else {
                return ("Tell me where to drag from and to (ids or x and y).", nil)
            }
            let saved = ComputerControl.mouseLocation
            await fly(to: from.point)
            engine.press(depth: 0.1)
            ComputerControl.dragBegin(at: from.point)
            try? await Task.sleep(for: .milliseconds(120))
            engine.dragging = true
            overlay.mode = .pinned(to.point)
            try? await Task.sleep(for: .milliseconds(40))
            // The real drag follows the animated cursor, so what you see is what happens.
            while engine.timeToArrive(CACurrentMediaTime()) > 0 {
                ComputerControl.dragMove(to: engine.tip)
                try? await Task.sleep(for: .milliseconds(16))
            }
            ComputerControl.dragMove(to: to.point)
            try? await Task.sleep(for: .milliseconds(80))
            ComputerControl.dragEnd(at: to.point)
            engine.dragging = false
            try? await Task.sleep(for: .milliseconds(60))
            ComputerControl.warp(to: saved)
            try? await Task.sleep(for: .milliseconds(280))
            return await look(prefix: "Dragged it.")

        case "open_app":
            let name = (args["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return ("Which app?", nil) }
            if engine.isHome { overlay.mode = .docked }
            view.bubble("Opening \(name)")
            let result = await ComputerControl.openApp(name)
            try? await Task.sleep(for: .milliseconds(900))
            return await look(prefix: result)

        case "open_url":
            let url = (args["url"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            if engine.isHome { overlay.mode = .docked }
            let result = ComputerControl.openURL(url)
            view.bubble(result.hasPrefix("Opened ") ? String(result.dropFirst(7).dropLast()) : "Hmm")
            try? await Task.sleep(for: .milliseconds(1100))
            return await look(prefix: result)

        default:
            return ("Unknown action \(name).", nil)
        }
    }

    /// Actions take over the cursor: any queued pointing is dropped.
    private func takeControl() {
        queue = []
        holdUntil = 0
        homeRequested = false
        engine.gazeOverride = nil
        overlay.view.speechTarget = nil
    }

    private func afterAction() {
        let now = CACurrentMediaTime()
        holdUntil = now + 1.5
        if !speaking { quietSince = now }
        startChoreography()
    }

    /// Flies the cursor to a spot and waits until it has landed.
    private func fly(to point: CGPoint) async {
        overlay.mode = .pinned(point)
        try? await Task.sleep(for: .milliseconds(40))  // the next frame plans the trip
        let wait = engine.timeToArrive(CACurrentMediaTime())
        if wait > 0 { try? await Task.sleep(for: .seconds(wait + 0.05)) }
    }

    // MARK: Pointing choreography
    //
    // He often asks to point at several things at once. Each spot gets its own flight and a hold long
    // enough to talk about it, and the cursor only goes home once he's finished talking.

    /// Spots to point at, with the thing being shown (so his speech bubble can sit above it, not on it).
    private var queue: [(point: CGPoint, thing: CGRect)] = []
    private var holdUntil = 0.0
    private var homeRequested = false
    private var speaking = false
    private var quietSince = 0.0
    private var timer: Timer?

    /// How long a spot stays pointed at before the next one (after the flight lands).
    private static let minimumHold = 2.2
    /// Out and about with nothing more to say: go home after this much quiet.
    private static let idleHome = 5.0

    private func point(to spot: CGPoint, showing thing: CGRect) {
        queue.append((spot, thing))
        homeRequested = false
        startChoreography()
    }

    private func requestHome() {
        homeRequested = true
        startChoreography()
    }

    private func startChoreography() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.choreograph() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        choreograph()
    }

    private func choreograph() {
        let now = CACurrentMediaTime()
        if now >= holdUntil, !queue.isEmpty {
            let (spot, thing) = queue.removeFirst()
            overlay.view.speechTarget = thing
            if !speaking { quietSince = now }  // give him time to start talking about it
            engine.gazeOverride = nil  // his eyes follow the cursor while pointing
            overlay.mode = .pinned(spot)
            // Flight time plus a comfortable hold; a lone point just holds while he talks.
            holdUntil = now + 1.0 + Self.minimumHold
            return
        }
        guard queue.isEmpty, now >= holdUntil else { return }
        guard overlay.mode != overlay.idleMode else { stopChoreography(); return }
        // Go home once he's done talking: soon after he says so, or after a longer quiet spell.
        let quietFor = speaking ? 0 : now - quietSince
        if (homeRequested && quietFor > 1.2) || quietFor > Self.idleHome {
            goHome()
        }
    }

    private func goHome() {
        overlay.goHome()
        engine.gazeOverride = nil
        overlay.view.speechTarget = nil
        homeRequested = false
        stopChoreography()
    }

    private func stopChoreography() {
        timer?.invalidate()
        timer = nil
    }

    private func setSpeaking(_ on: Bool) {
        if speaking && !on { quietSince = CACurrentMediaTime() }
        speaking = on
    }

    // MARK: Captions

    private func showCaption(_ text: String?, for seconds: Double) {
        captionClear?.cancel()
        overlay.view.caption = text
        if text != nil, seconds > 0 { scheduleCaptionClear(after: seconds) }
    }

    private func scheduleCaptionClear(after seconds: Double) {
        captionClear?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.overlay.view.caption = nil }
        captionClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
