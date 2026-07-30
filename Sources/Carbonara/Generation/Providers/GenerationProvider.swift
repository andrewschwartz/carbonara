import Foundation

/// Provider-neutral generation job status update.
///
/// Every backend (fal.ai, ComfyUI, Higgsfield, …) reports progress as a stream of
/// these, terminating in `.succeeded` (carrying result URLs) or `.failed`.
struct GenerationJobUpdate: Sendable {
    enum State: String, Sendable {
        case queued
        case running
        case succeeded
        case failed
    }

    let state: State
    let resultURLs: [String]?
    let errorMessage: String?

    init(state: State, resultURLs: [String]? = nil, errorMessage: String? = nil) {
        self.state = state
        self.resultURLs = resultURLs
        self.errorMessage = errorMessage
    }
}

/// A generation backend.
///
/// Implementations own transport, authentication, and job tracking. `GenerationService`
/// owns everything above the provider line: placeholder lifecycle, reference preparation,
/// result download, and the atomic install into the project package. Adding a backend means
/// conforming to this protocol and registering it in `ProviderRouter` — the placeholder and
/// download machinery is untouched.
@MainActor
protocol GenerationProvider: Sendable {
    /// Stable identifier used for routing and diagnostics (e.g. "fal", "comfyui").
    var id: String { get }

    /// Upload a local reference file and return a URL the provider's models can consume.
    func uploadReference(fileURL: URL, contentType: String) async throws -> String

    /// Submit a generation and return a provider-scoped job id.
    func submit(model: String, params: BackendGenerationParams, projectId: String?) async throws -> String

    /// Stream status updates until a terminal state. The stream finishes when the job
    /// settles or the provider becomes unavailable; a stream that finishes without a
    /// terminal update is treated as inconclusive (resume on reopen).
    func updates(forJob jobId: String) -> AsyncStream<GenerationJobUpdate>
}
