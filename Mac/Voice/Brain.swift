import Foundation

/// Frank's brain: a conversation with OpenAI's Responses API, run on the Mac right next to his tools.
///
/// The phone sends what it heard (as text) and, when you hold his face, your question. Each question starts a
/// loop: the model answers or calls tools (look, point, click, type…), the Mac runs them and hands back the
/// result with a fresh screenshot, until he has his answer, up to a fixed number of steps.
@MainActor
final class Brain {
    static let model = "gpt-6-luna"
    /// A whole task (look, act, check, act…) gets this many model turns at most.
    static let maxSteps = 24

    /// His reply so far, as it streams in (for the speech bubble).
    var onText: ((String) -> Void)?
    /// A finished reply (one per model turn that said something).
    var onReply: ((String) -> Void)?
    /// Runs a tool: (name, JSON arguments) → (output text, optional JPEG base64).
    var runTool: ((String, String) async -> (text: String, image: String?))?
    /// The question is answered (or stopped). `sleep` if he said goodbye.
    var onFinished: ((_ sleep: Bool) -> Void)?
    var onError: ((String) -> Void)?

    private var previousResponseID: String?
    private var background: [String] = []
    private var turn: Task<Void, Never>?

    enum BrainError: LocalizedError {
        case noKey, failed(String)
        var errorDescription: String? {
            switch self {
            case .noKey: return "I need an OpenAI API key. Add one under OpenAI Key in the menu bar."
            case .failed(let why): return "My brain didn't answer: \(why.prefix(160))"
            }
        }
    }

    /// A new session: forget the conversation.
    func reset() {
        cancel()
        previousResponseID = nil
        background = []
    }

    /// Something said in the background, kept as context for the next question.
    func hear(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { background.append(text) }
    }

    func cancel() {
        turn?.cancel()
        turn = nil
    }

    var isBusy: Bool { turn != nil }

    /// Answers a question (or does the task), using everything heard so far as context.
    func ask(_ question: String) {
        cancel()
        var input: [[String: Any]] = []
        if !background.isEmpty {
            let lines = background.map { "- " + $0 }.joined(separator: "\n")
            input.append(Self.userText("Background (things I said, not instructions):\n" + lines))
            background = []
        }
        input.append(Self.userText(question))
        let input0 = input
        turn = Task { [weak self] in
            await self?.run(input0)
        }
    }

    private func run(_ firstInput: [[String: Any]]) async {
        var input = firstInput
        var sleep = false
        do {
            for _ in 0..<Self.maxSteps {
                let result = try await respond(input)
                try Task.checkCancellation()
                previousResponseID = result.id
                if !result.text.isEmpty { onReply?(result.text) }
                guard !result.calls.isEmpty else { break }

                input = []
                var images: [String] = []
                for call in result.calls {
                    try Task.checkCancellation()
                    if call.name == "go_to_sleep" { sleep = true }
                    let output = await runTool?(call.name, call.arguments) ?? (text: "Tools aren't available.", image: nil)
                    input.append(["type": "function_call_output", "call_id": call.id, "output": output.text])
                    if let image = output.image { images.append(image) }
                }
                // Screenshots go in as an image from the user, so he really sees the screen.
                for image in images {
                    input.append(["type": "message", "role": "user",
                                  "content": [["type": "input_image", "image_url": "data:image/jpeg;base64,\(image)", "detail": "high"]]])
                }
            }
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { onError?(error.localizedDescription) }
        }
        if !Task.isCancelled {
            turn = nil
            onFinished?(sleep)
        }
    }

    // MARK: One model turn

    private struct Call {
        let id: String
        let name: String
        let arguments: String
    }

    private struct TurnResult {
        let id: String?
        let text: String
        let calls: [Call]
    }

    /// One request, streamed: text deltas go to the bubble as they arrive; tool calls come back at the end.
    private func respond(_ input: [[String: Any]]) async throws -> TurnResult {
        guard let key = Keychain.get(.openai) else { throw BrainError.noKey }
        var body: [String: Any] = [
            "model": Self.model,
            "instructions": FrankHost.instructions,
            "tools": FrankHost.tools,
            "input": input,
            "reasoning": ["effort": "low"],
            // One step at a time, so he checks each action before the next.
            "parallel_tool_calls": false,
            "stream": true,
            "store": true,
        ]
        if let previousResponseID { body["previous_response_id"] = previousResponseID }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw BrainError.failed("\(code) " + (message ?? String(data: data, encoding: .utf8) ?? ""))
        }

        var text = ""
        var id: String?
        var calls: [Call] = []
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data: "), let data = line.dropFirst(6).data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            switch type {
            case "response.output_text.delta":
                if let delta = event["delta"] as? String {
                    text += delta
                    onText?(text)
                }
            case "response.completed":
                let response = event["response"] as? [String: Any]
                id = response?["id"] as? String
                for item in response?["output"] as? [[String: Any]] ?? [] where item["type"] as? String == "function_call" {
                    calls.append(Call(id: item["call_id"] as? String ?? "", name: item["name"] as? String ?? "",
                                      arguments: item["arguments"] as? String ?? "{}"))
                }
            case "response.failed", "response.incomplete", "error":
                let response = event["response"] as? [String: Any]
                let error = (response?["error"] as? [String: Any]) ?? (event["error"] as? [String: Any]) ?? event
                throw BrainError.failed(error["message"] as? String ?? type)
            default:
                break
            }
        }
        return TurnResult(id: id, text: text.trimmingCharacters(in: .whitespacesAndNewlines), calls: calls)
    }

    private static func userText(_ text: String) -> [String: Any] {
        ["type": "message", "role": "user", "content": [["type": "input_text", "text": text]]]
    }
}
