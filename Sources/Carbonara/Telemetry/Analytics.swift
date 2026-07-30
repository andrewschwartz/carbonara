import Foundation

/// Local-only shim. Carbonara ships no product analytics; nothing leaves the machine.
/// The API is preserved so call sites keep compiling.
enum Analytics {
    typealias Payload = [String: Any]

    struct SessionActivation {
        private(set) var isActivated: Bool

        init(isActivated: Bool = false) {
            self.isActivated = isActivated
        }

        mutating func activate() -> Bool {
            guard !isActivated else { return false }
            isActivated = true
            return true
        }
    }

    enum Event: String {
        case appOpened = "app opened"
        case projectCreated = "project created"
        case projectOpened = "project opened"
        case projectActive = "project active"
        case exportStarted = "export started"
        case exportFinished = "export finished"
        case exportFailed = "export failed"
        case agentSessionStarted = "agent session started"
        case agentToolCalled = "agent tool called"
        case mcpSessionActivated = "mcp session activated"
    }

    static var isEnabled: Bool { false }
    static var enabledForCurrentLaunch: Bool { false }

    static func start() {}
    static func identifyUser(id: String?, properties: Payload = [:]) {}
    static func resetUser() {}

    @discardableResult
    static func capture(_ event: Event, properties: Payload = [:]) -> Bool { false }

    static func captureProjectActive(projectId: String?, properties: Payload = [:]) {}
}
