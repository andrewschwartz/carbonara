import Foundation
import MCP

/// Higgsfield generation backend via its hosted MCP server.
///
/// Because MCP tool calls are request/response, `submit` performs the call and encodes the
/// resulting media URLs into the job id; `updates` decodes and reports them. Errors surface
/// through `submit` throwing, which the generation service renders as a failed placeholder.
@MainActor
struct HiggsfieldProvider: GenerationProvider {
    let id = "higgsfield"

    private nonisolated static let jobPrefix = "higgsfield#"

    func uploadReference(fileURL: URL, contentType: String) async throws -> String {
        let data = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: fileURL)
        }.value
        return "data:\(contentType);base64,\(data.base64EncodedString())"
    }

    func submit(model: String, params: BackendGenerationParams, projectId: String?) async throws -> String {
        let available = try await HiggsfieldConnection.shared.toolNames()
        guard let tool = HiggsfieldRequestBuilder.toolName(for: params, available: available) else {
            throw HiggsfieldError.noMatchingTool
        }
        let content = try await HiggsfieldConnection.shared.callTool(
            name: tool,
            arguments: HiggsfieldRequestBuilder.arguments(for: params)
        )
        let urls = Self.extractURLs(content)
        guard !urls.isEmpty else { throw HiggsfieldError.noOutput }
        let payload = try JSONSerialization.data(withJSONObject: urls)
        return Self.jobPrefix + payload.base64EncodedString()
    }

    func updates(forJob jobId: String) -> AsyncStream<GenerationJobUpdate> {
        AsyncStream { continuation in
            guard jobId.hasPrefix(Self.jobPrefix),
                  let data = Data(base64Encoded: String(jobId.dropFirst(Self.jobPrefix.count))),
                  let urls = (try? JSONSerialization.jsonObject(with: data)) as? [String] else {
                continuation.yield(GenerationJobUpdate(state: .failed, errorMessage: "Malformed Higgsfield job"))
                continuation.finish()
                return
            }
            continuation.yield(GenerationJobUpdate(state: .succeeded, resultURLs: urls))
            continuation.finish()
        }
    }

    /// Pulls http(s) URLs out of the tool's text content (Higgsfield returns result links as text).
    private nonisolated static func extractURLs(_ content: [Tool.Content]) -> [String] {
        var out: [String] = []
        for item in content {
            if case .text(let text, _, _) = item {
                out += urls(in: text)
            }
        }
        return out
    }

    private nonisolated static func urls(in text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range)
            .compactMap { $0.url?.absoluteString }
            .filter { $0.hasPrefix("http") }
    }
}
