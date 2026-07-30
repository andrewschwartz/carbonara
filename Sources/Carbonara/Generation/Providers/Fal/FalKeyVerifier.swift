import Foundation

/// Validates a fal.ai API key by hitting a queue status endpoint (a GET that runs no inference,
/// so it costs nothing). Auth is checked before the request is resolved: a 401/403 means the key
/// is bad; any other status means auth passed.
enum FalKeyVerifier {
    enum Outcome: Sendable {
        case ok
        case rejected
        case network(String)
    }

    static func verify(_ key: String) async -> Outcome {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: "https://queue.fal.run/fal-ai/flux/schnell/requests/auth-check/status")
        else { return .rejected }

        var request = URLRequest(url: url)
        request.setValue("Key \(trimmed)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .network("No HTTP response") }
            switch http.statusCode {
            case 401, 403: return .rejected
            default: return .ok
            }
        } catch {
            return .network(error.localizedDescription)
        }
    }
}
