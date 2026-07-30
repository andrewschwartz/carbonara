import Foundation

/// Resolves the `claude` CLI binary. Dev-only: relies on the binary being installed
/// on the machine (PATH or a known npm/global location). Returns nil when absent.
enum ClaudeCodeLocator {

    /// Common install locations beyond whatever `PATH` the app process inherits.
    private static let candidateDirectories: [String] = [
        "\(NSHomeDirectory())/.genviz/npm-global/bin",
        "\(NSHomeDirectory())/.claude/local",
        "\(NSHomeDirectory())/.npm-global/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
    ]

    /// Resolved once per process; nil means not installed. Must be called off the main actor.
    static func resolve() -> URL? {
        if resolved { return cachedURL }
        cachedURL = search()
        resolved = true
        return cachedURL
    }

    private nonisolated(unsafe) static var resolved = false
    private nonisolated(unsafe) static var cachedURL: URL?

    private static func search() -> URL? {
        let fm = FileManager.default
        for dir in candidateDirectories {
            let path = "\(dir)/claude"
            if fm.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        // Fall back to `which` against the inherited PATH.
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        which.arguments = ["which", "claude"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = FileHandle.nullDevice
        do {
            try which.run()
            which.waitUntilExit()
            guard which.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, fm.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        } catch {
            return nil
        }
        return nil
    }
}
