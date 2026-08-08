import Foundation

/// One baked Backlot shot: a still is a single PNG frame; a camera move is an
/// ordered PNG sequence at `fps`. Frames are raw PNG bytes so the caller can
/// stage stills verbatim and encode moves to mp4 without a re-decode round-trip.
struct BacklotBakedShot: Sendable {
    let sceneId: String
    let sceneName: String
    let isStill: Bool
    let width: Int
    let height: Int
    let fps: Int
    let frames: [Data]
}

enum BacklotBakeError: LocalizedError {
    case bakeRejected(String)
    case unreadableReceipt
    case frameDecodeFailed(sceneId: String, index: Int)

    var errorDescription: String? {
        switch self {
        case .bakeRejected(let reason): "Backlot couldn't bake the shot: \(reason)"
        case .unreadableReceipt: "Backlot returned an unreadable bake receipt."
        case .frameDecodeFailed(_, let index): "Couldn't decode baked frame \(index)."
        }
    }
}

extension BacklotWindowController {
    /// Bakes each scene's greybox frames deterministically through the web page's
    /// begin/prepare/frame/end protocol, one frame per `evaluateJavaScript` so a
    /// large sequence never has to cross the bridge at once. Hydrates the bin from
    /// `editor` first so `bakePrepare` resolves scene ids, and always ends the
    /// session even on failure. PNG data-URL decode runs off the main actor.
    func bakeScenes(
        _ sceneIds: [String],
        height: Int,
        fps: Int,
        for editor: EditorViewModel
    ) async throws -> [BacklotBakedShot] {
        guard !sceneIds.isEmpty else { return [] }
        try await prepareForBake(editor: editor)

        _ = try await runBakeStep("window.backlotAgent.bakeBegin()")
        var ended = false
        defer {
            if !ended { Task { _ = try? await self.evaluateQuiet("window.backlotAgent.bakeEnd()") } }
        }

        var shots: [BacklotBakedShot] = []
        for sceneId in sceneIds {
            let prep = try await runBakeStep(
                "window.backlotAgent.bakePrepare(\(Self.jsStringLiteral(sceneId)), {height:\(height), fps:\(fps)})"
            )
            let frameCount = max(1, prep["frameCount"] as? Int ?? 1)
            let isStill = prep["isStill"] as? Bool ?? (frameCount <= 1)
            let width = prep["width"] as? Int ?? height
            let bakedHeight = prep["height"] as? Int ?? height
            let bakedFps = max(1, prep["fps"] as? Int ?? fps)
            let name = prep["name"] as? String ?? sceneId

            var frames: [Data] = []
            frames.reserveCapacity(frameCount)
            for index in 0..<frameCount {
                let frame = try await runBakeStep("window.backlotAgent.bakeFrame(\(index))")
                guard let dataURL = frame["dataURL"] as? String,
                      let data = await Self.decodePNGDataURL(dataURL) else {
                    throw BacklotBakeError.frameDecodeFailed(sceneId: sceneId, index: index)
                }
                frames.append(data)
            }
            shots.append(BacklotBakedShot(
                sceneId: sceneId, sceneName: name, isStill: isStill,
                width: width, height: bakedHeight, fps: bakedFps, frames: frames
            ))
        }

        _ = try await runBakeStep("window.backlotAgent.bakeEnd()")
        ended = true
        return shots
    }

    private func runBakeStep(_ script: String) async throws -> [String: Any] {
        let raw: String
        do {
            raw = try await evaluateQuiet(script)
        } catch let error as BacklotControlError {
            throw BacklotBakeError.bakeRejected(error.localizedDescription)
        }
        guard let data = raw.data(using: .utf8),
              let receipt = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BacklotBakeError.unreadableReceipt
        }
        if receipt["ok"] as? Bool != true {
            throw BacklotBakeError.bakeRejected(receipt["error"] as? String ?? "unknown error")
        }
        return receipt
    }

    private static func jsStringLiteral(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value])
        guard let data, let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        // JSONSerialization wraps in [ ... ]; strip the array brackets to get the literal.
        return String(json.dropFirst().dropLast())
    }

    private nonisolated static func decodePNGDataURL(_ string: String) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            guard string.hasPrefix("data:"), let comma = string.firstIndex(of: ",") else { return nil }
            let payload = String(string[string.index(after: comma)...])
            return Data(base64Encoded: payload)
        }.value
    }
}
