import Foundation

/// Local-only shim. Carbonara ships no crash reporting; diagnostics stay in os_log (`Log`).
/// The API is preserved so log call sites keep their telemetry annotations.
enum Telemetry {
    typealias Payload = [String: Any]

    enum Level {
        case info
        case warning
        case error
        case fatal
    }

    static var isEnabled: Bool { false }
    static var enabledForCurrentLaunch: Bool { false }

    static func start() {}

    static func breadcrumb(
        _ message: String,
        category: String = "app",
        level: Level = .info,
        data: Payload? = nil
    ) {}

    static func shortId(_ id: String) -> String {
        String(id.prefix(8))
    }

    static func setUser(id: String?) {}
    static func setExtra(value: Any?, key: String) {}
    static func logWarning(_ message: String, category: String, data: Payload? = nil) {}
    static func logError(_ message: String, category: String, data: Payload? = nil) {}
    static func logFault(_ message: String, category: String, data: Payload? = nil) {}
}
