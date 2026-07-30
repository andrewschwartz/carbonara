import Foundation

extension Notification.Name {
    static let higgsfieldTokenChanged = Notification.Name("higgsfieldTokenChanged")
}

/// Keychain-backed storage for the Higgsfield MCP access token.
///
/// Higgsfield's hosted MCP server authenticates via the user's Higgsfield account. This stores a
/// bearer token; full browser-based OAuth (the SDK's `HTTPClientAuthorizer`) is a later enhancement.
enum HiggsfieldKeyStore {
    private static let account = "higgsfield-mcp-token"

    static func save(_ token: String) {
        KeychainStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines), account: account)
        NotificationCenter.default.post(name: .higgsfieldTokenChanged, object: nil)
    }

    static func load() -> String? {
        #if DEBUG
        if let env = ProcessInfo.processInfo.environment["HIGGSFIELD_MCP_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }
        #endif
        return KeychainStore.load(account: account)
    }

    static func delete() {
        KeychainStore.delete(account: account)
        NotificationCenter.default.post(name: .higgsfieldTokenChanged, object: nil)
    }

    static var isConfigured: Bool { load() != nil }
}
