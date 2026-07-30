import Foundation

extension Notification.Name {
    static let falAPIKeyChanged = Notification.Name("falAPIKeyChanged")
}

/// Keychain-backed storage for the user's fal.ai API key.
enum FalKeyStore {
    private static let account = "fal-api-key"

    static func save(_ key: String) {
        KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: account)
        NotificationCenter.default.post(name: .falAPIKeyChanged, object: nil)
    }

    static func load() -> String? {
        #if DEBUG
        if let env = ProcessInfo.processInfo.environment["FAL_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }
        #endif
        return KeychainStore.load(account: account)
    }

    static func delete() {
        KeychainStore.delete(account: account)
        NotificationCenter.default.post(name: .falAPIKeyChanged, object: nil)
    }

    static var isConfigured: Bool { load() != nil }
}
