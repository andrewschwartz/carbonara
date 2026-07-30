import Foundation

extension ToolExecutor {
    /// Rolling diagnostics trail (recent tools + last error), recorded centrally in execute().
    struct FeedbackState {
        private(set) var recentTools: [String] = []
        private(set) var lastError: String?

        mutating func record(_ result: ToolResult, for tool: ToolName) {
            recentTools.append(tool.rawValue)
            if recentTools.count > 15 { recentTools.removeFirst() }
            if result.isError, case let .text(message)? = result.content.first { lastError = message }
        }

        mutating func recordError(_ message: String) {
            lastError = message
        }
    }

    func resetFeedbackState() { feedbackState = FeedbackState() }
}
