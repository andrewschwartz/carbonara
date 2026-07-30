import Foundation

/// Local provider access state. Carbonara has no accounts, sign-in, credits, or plans —
/// generation is gated only on whether a backend (fal.ai key or Higgsfield token) is configured.
/// The legacy property names are kept so gating call sites read naturally.
@Observable
@MainActor
final class AccountService {
    static let shared = AccountService()

    /// A generation backend is configured. Cached so hot gating paths never touch the Keychain.
    private(set) var hasLocalProvider: Bool = false

    var aiAllowed: Bool { hasLocalProvider }
    var isSignedIn: Bool { hasLocalProvider }
    var isPaid: Bool { hasLocalProvider }
    var hasCredits: Bool { hasLocalProvider }
    var isMisconfigured: Bool { false }

    // Legacy credit surface: local providers bill directly, so no in-app credits exist.
    var spentCredits: Int { 0 }
    var remainingCredits: Int { 0 }
    var budgetCredits: Int? { nil }

    @ObservationIgnored private var didConfigure = false

    private init() {}

    func configure() {
        guard !didConfigure else { return }
        didConfigure = true
        refreshLocalProviderState()
        for name in [Notification.Name.falAPIKeyChanged, .higgsfieldTokenChanged] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshLocalProviderState() }
            }
        }
    }

    func refreshLocalProviderState() {
        hasLocalProvider = FalKeyStore.isConfigured || HiggsfieldKeyStore.isConfigured
    }
}
