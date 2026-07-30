import Foundation

/// Resolves which generation backend handles a given model.
///
/// Routing is intentionally centralized so `GenerationService` never hard-codes a backend.
/// Later phases route by the model's catalog entry (fal.ai / ComfyUI / Higgsfield); for now
/// every model still resolves to the Carbonara cloud backend.
@MainActor
enum ProviderRouter {
    static func provider(for modelId: String) -> any GenerationProvider {
        switch ModelCatalog.shared.providerId(for: modelId) {
        case "higgsfield": return HiggsfieldProvider()
        default: return FalProvider()
        }
    }
}
