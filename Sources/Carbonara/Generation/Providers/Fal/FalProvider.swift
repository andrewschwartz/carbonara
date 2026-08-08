import Foundation

/// fal.ai generation backend over the queue API (https://queue.fal.run).
///
/// Submit → poll status → fetch result. Reference files are inlined as `data:` URIs, which
/// fal accepts as input URLs. The provider is stateless; the model slug is encoded into the
/// job id so `updates(forJob:)` can address the correct queue endpoint.
@MainActor
struct FalProvider: GenerationProvider {
    let id = "fal"

    private nonisolated static let queueBase = "https://queue.fal.run"
    private nonisolated static let jobSeparator: Character = "|"

    func uploadReference(fileURL: URL, contentType: String) async throws -> String {
        let data = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: fileURL)
        }.value
        return "data:\(contentType);base64,\(data.base64EncodedString())"
    }

    func submit(model: String, params: BackendGenerationParams, projectId: String?) async throws -> String {
        guard let key = FalKeyStore.load() else { throw FalError.missingKey }
        let endpoint = FalRequestBuilder.endpoint(model: model, params: params)
        guard let url = URL(string: "\(Self.queueBase)/\(endpoint)") else { throw FalError.badModel(endpoint) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try FalRequestBuilder.inputJSON(model: endpoint, params: params)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.assertOK(response, data)
        let submitted = try JSONDecoder().decode(FalSubmitResponse.self, from: data)
        return "\(endpoint)\(Self.jobSeparator)\(submitted.requestId)"
    }

    func updates(forJob jobId: String) -> AsyncStream<GenerationJobUpdate> {
        let key = FalKeyStore.load()
        return AsyncStream { continuation in
            let task = Task {
                await Self.poll(jobId: jobId, key: key, into: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Polling (off-main)

    private nonisolated static func poll(
        jobId: String,
        key: String?,
        into continuation: AsyncStream<GenerationJobUpdate>.Continuation
    ) async {
        guard let key else {
            continuation.yield(GenerationJobUpdate(state: .failed, errorMessage: "fal API key not set"))
            continuation.finish()
            return
        }
        let parts = jobId.split(separator: jobSeparator, maxSplits: 1).map(String.init)
        guard parts.count == 2, let statusURL = URL(string: "\(queueBase)/\(parts[0])/requests/\(parts[1])/status"),
              let resultURL = URL(string: "\(queueBase)/\(parts[0])/requests/\(parts[1])") else {
            continuation.yield(GenerationJobUpdate(state: .failed, errorMessage: "Malformed fal job id"))
            continuation.finish()
            return
        }

        var emittedRunning = false
        while !Task.isCancelled {
            do {
                var request = URLRequest(url: statusURL)
                request.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: request)
                try assertOK(response, data)
                let status = try JSONDecoder().decode(FalStatusResponse.self, from: data)

                switch status.status {
                case "IN_QUEUE":
                    continuation.yield(GenerationJobUpdate(state: .queued))
                case "IN_PROGRESS":
                    if !emittedRunning {
                        continuation.yield(GenerationJobUpdate(state: .running))
                        emittedRunning = true
                    }
                case "COMPLETED":
                    let urls = try await fetchResultURLs(resultURL: resultURL, key: key)
                    continuation.yield(GenerationJobUpdate(state: .succeeded, resultURLs: urls))
                    continuation.finish()
                    return
                default:
                    continuation.yield(GenerationJobUpdate(state: .failed, errorMessage: "fal returned status \(status.status)"))
                    continuation.finish()
                    return
                }
            } catch {
                continuation.yield(GenerationJobUpdate(state: .failed, errorMessage: error.localizedDescription))
                continuation.finish()
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }
        continuation.finish()
    }

    private nonisolated static func fetchResultURLs(resultURL: URL, key: String) async throws -> [String] {
        var request = URLRequest(url: resultURL)
        request.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try assertOK(response, data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return extractURLs(obj)
    }

    /// Pulls output media URLs from a fal result payload (shapes vary per model).
    private nonisolated static func extractURLs(_ obj: [String: Any]) -> [String] {
        var out: [String] = []
        if let images = obj["images"] as? [[String: Any]] {
            out += images.compactMap { $0["url"] as? String }
        }
        for key in ["video", "audio", "audio_file", "image", "file"] {
            if let file = obj[key] as? [String: Any], let url = file["url"] as? String {
                out.append(url)
            }
        }
        if out.isEmpty {
            for (_, value) in obj {
                if let s = value as? String, s.hasPrefix("http") {
                    out.append(s)
                } else if let file = value as? [String: Any], let url = file["url"] as? String {
                    out.append(url)
                }
            }
        }
        return out
    }

    private nonisolated static func assertOK(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw FalError.transport("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw FalError.api(status: http.statusCode, message: String(body.prefix(300)))
        }
    }
}

// MARK: - Wire types

private struct FalSubmitResponse: Decodable {
    let requestId: String
    enum CodingKeys: String, CodingKey { case requestId = "request_id" }
}

private struct FalStatusResponse: Decodable {
    let status: String
}

enum FalError: LocalizedError {
    case missingKey
    case badModel(String)
    case transport(String)
    case api(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Add your fal.ai API key in Settings to generate."
        case .badModel(let model):
            return "Invalid fal model endpoint '\(model)'."
        case .transport(let message):
            return message
        case .api(let status, let message):
            return "fal error \(status): \(message)"
        }
    }
}
