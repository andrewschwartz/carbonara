import Foundation
import MCP

/// Owns the long-lived MCP client connection to Higgsfield's hosted server.
///
/// The app acts as an MCP *client* here (distinct from its own MCP server). The connection is
/// established lazily and reused across tool calls.
///
/// NOTE: the endpoint path and tool schema are best-effort — verify against Higgsfield's MCP docs
/// (base https://mcp.higgsfield.ai) with a real account.
actor HiggsfieldConnection {
    static let shared = HiggsfieldConnection()

    private let endpoint = URL(string: "https://mcp.higgsfield.ai/mcp")!
    private var client: Client?

    func toolNames() async throws -> [String] {
        try await connected().listTools().tools.map(\.name)
    }

    func callTool(name: String, arguments: [String: Value]) async throws -> [Tool.Content] {
        let (content, isError) = try await connected().callTool(name: name, arguments: arguments)
        if isError == true {
            throw HiggsfieldError.toolFailed(Self.text(from: content))
        }
        return content
    }

    /// Drop the connection so the next call reconnects (e.g. after a token change).
    func reset() {
        client = nil
    }

    private func connected() async throws -> Client {
        if let client { return client }
        guard HiggsfieldKeyStore.isConfigured else { throw HiggsfieldError.notAuthorized }
        let transport = HTTPClientTransport(
            endpoint: endpoint,
            streaming: true,
            requestModifier: { request in
                var request = request
                if let token = HiggsfieldKeyStore.load() {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                return request
            }
        )
        let client = Client(name: "carbonara", version: "1.0.0")
        try await client.connect(transport: transport)
        self.client = client
        return client
    }

    private static func text(from content: [Tool.Content]) -> String {
        content.compactMap { item in
            if case .text(let text, _, _) = item { return text }
            return nil
        }
        .joined(separator: " ")
    }
}

enum HiggsfieldError: LocalizedError {
    case notAuthorized
    case noMatchingTool
    case toolFailed(String)
    case noOutput

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Connect your Higgsfield account in Settings to generate."
        case .noMatchingTool:
            return "Higgsfield MCP exposed no matching generation tool."
        case .toolFailed(let message):
            return message.isEmpty ? "Higgsfield generation failed." : message
        case .noOutput:
            return "Higgsfield returned no output URL."
        }
    }
}
