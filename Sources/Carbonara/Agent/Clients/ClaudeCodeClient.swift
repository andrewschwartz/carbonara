import Foundation

/// Drives the chat through the local `claude` CLI (the user's Claude Code subscription)
/// instead of the Anthropic API. Claude Code runs its own agentic loop and calls
/// Carbonara's editing tools over the local MCP server, so this client streams text
/// only — it never emits `toolUseComplete`, and every turn ends with `.endTurn`.
final class ClaudeCodeClient: AgentClient {

    /// Fixed chat model. Chosen by the app, not the user's Claude Code default.
    static let model = "claude-fable-5"

    /// Tools the embedded agent may call without a permission prompt. Carbonara's editor
    /// tools plus Skill + Bash, so the default `nara-agent0-betav1` skill can run its CCS
    /// workflow (create Nara projects, generate paid media via the bundled node script).
    static let allowedTools = ["mcp__carbonara__*", "Skill", "Bash"]

    private let binary: URL
    private let mcpEndpoint: String
    private let workingDirectory: URL
    private let resumeSessionID: String?
    private let onSessionID: @Sendable (String) -> Void

    init(
        binary: URL,
        mcpEndpoint: String,
        workingDirectory: URL,
        resumeSessionID: String?,
        onSessionID: @escaping @Sendable (String) -> Void
    ) {
        self.binary = binary
        self.mcpEndpoint = mcpEndpoint
        self.workingDirectory = workingDirectory
        self.resumeSessionID = resumeSessionID
        self.onSessionID = onSessionID
    }

    func stream(
        system: String,
        tools: [AnthropicToolSchema],
        messages: [AnthropicMessage]
    ) -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        // Only the latest user turn is sent; prior context lives in the resumed session.
        let userContent = messages.last(where: { $0.role == .user }).map(\.content) ?? []
        let stdinLine = Self.userMessageLine(content: userContent)
        let binary = self.binary
        let args = arguments(system: system)
        let cwd = workingDirectory
        let onSessionID = self.onSessionID

        return AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try await Self.run(
                        binary: binary,
                        arguments: args,
                        workingDirectory: cwd,
                        stdinLine: stdinLine,
                        onSessionID: onSessionID,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func arguments(system: String) -> [String] {
        var args = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--model", Self.model,
            "--mcp-config", mcpConfigJSON,
            "--strict-mcp-config",
            "--allowedTools",
        ]
        args.append(contentsOf: Self.allowedTools)
        args.append(contentsOf: ["--append-system-prompt", system])
        if let resumeSessionID {
            args.append(contentsOf: ["--resume", resumeSessionID])
        }
        return args
    }

    private var mcpConfigJSON: String {
        let config: [String: Any] = [
            "mcpServers": ["carbonara": ["type": "http", "url": mcpEndpoint]]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: config),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"mcpServers\":{\"carbonara\":{\"type\":\"http\",\"url\":\"\(mcpEndpoint)\"}}}"
        }
        return json
    }

    // MARK: - Process

    private static func run(
        binary: URL,
        arguments: [String],
        workingDirectory: URL,
        stdinLine: String,
        onSessionID: @Sendable (String) -> Void,
        continuation: AsyncThrowingStream<AnthropicStreamEvent, Error>.Continuation
    ) async throws {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Send the single user turn, then close stdin to signal end of input.
        try? stdinPipe.fileHandleForWriting.write(contentsOf: Data(stdinLine.utf8))
        try? stdinPipe.fileHandleForWriting.close()

        var sawSessionID = false
        var sawText = false
        do {
            for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                try Task.checkCancellation()
                guard let event = parseLine(line) else { continue }
                switch event {
                case .sessionID(let id):
                    if !sawSessionID { sawSessionID = true; onSessionID(id) }
                case .text(let chunk):
                    sawText = true
                    continuation.yield(.textDelta(chunk))
                case .done:
                    continuation.yield(.messageStop(stopReason: .endTurn))
                }
            }
        } catch is CancellationError {
            process.terminate()
            throw CancellationError()
        }

        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sawText {
                throw AgentStreamError.upstream(detail.isEmpty ? "Claude Code exited with status \(process.terminationStatus)." : detail)
            }
        }
    }

    private static func userMessageLine(content: [[String: Any]]) -> String {
        let message: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": content],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"\"}}\n"
        }
        return json + "\n"
    }

    // MARK: - Event parsing

    private enum ParsedEvent {
        case sessionID(String)
        case text(String)
        case done
    }

    private static func parseLine(_ line: String) -> ParsedEvent? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return nil }

        switch type {
        case "system":
            if obj["subtype"] as? String == "init", let id = obj["session_id"] as? String {
                return .sessionID(id)
            }
            return nil

        case "stream_event":
            guard let event = obj["event"] as? [String: Any],
                  let eventType = event["type"] as? String else { return nil }
            if eventType == "content_block_delta",
               let delta = event["delta"] as? [String: Any],
               delta["type"] as? String == "text_delta",
               let text = delta["text"] as? String, !text.isEmpty {
                return .text(text)
            }
            return nil

        case "result":
            return .done

        default:
            return nil
        }
    }
}
