import Foundation

// get_backlot, set_backlot_scenes. Backlot state lives in the Backlot web page;
// these tools drive it through `BacklotWindowController.runAgentScript`.
extension ToolExecutor {
    private static let sceneOpKeys: Set<String> = [
        "action", "sceneId", "toIndex", "name", "set", "blocking",
        "actors", "pieces", "camera", "look", "move",
    ]
    private static let sceneActorKeys: Set<String> = ["x", "z", "face", "anim"]
    private static let scenePieceKeys: Set<String> = ["type", "x", "z", "rotation", "scale"]
    private static let sceneCameraKeys: Set<String> = [
        "angle", "distance", "height", "focal", "dutch", "aimHeight", "lookAt", "lookAtFace",
    ]
    private static let sceneLookKeys: Set<String> = ["kit", "stock", "light", "style", "aperture", "notes"]

    func getBacklot(_ args: [String: Any]) async throws -> ToolResult {
        try validateUnknownKeys(args, allowed: [], path: "get_backlot")
        return .ok(try await runBacklotScript("window.backlotAgent.getState()"))
    }

    func setBacklotScenes(_ args: [String: Any]) async throws -> ToolResult {
        try validateUnknownKeys(args, allowed: ["scenes"], path: "set_backlot_scenes")
        guard let scenes = args["scenes"] as? [[String: Any]], !scenes.isEmpty else {
            throw ToolError("set_backlot_scenes requires a non-empty 'scenes' array.")
        }
        if let badPath = firstNonFiniteNumberPath(in: args, path: "set_backlot_scenes") {
            throw ToolError("\(badPath): value must be finite")
        }
        for (index, op) in scenes.enumerated() {
            try Self.validateSceneOpShape(op, path: "scenes[\(index)]")
        }
        guard let payload = Self.jsonString(["scenes": scenes]) else {
            throw ToolError("Couldn't encode the scene operations.")
        }
        let raw = try await runBacklotScript("window.backlotAgent.setScenes(\(payload))")
        guard let data = raw.data(using: .utf8),
              let receipt = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolError("Backlot returned an unreadable receipt.")
        }
        if receipt["ok"] as? Bool != true {
            throw ToolError(receipt["error"] as? String ?? "Backlot rejected the request.")
        }
        var payloadOut = receipt
        payloadOut.removeValue(forKey: "ok")
        payloadOut["note"] = "Backlot scenes persist with the project but are not undoable with the undo tool."
        return .ok(Self.jsonString(payloadOut) ?? raw)
    }

    func buildAnimatic(_ editor: EditorViewModel, _ args: [String: Any]) async throws -> ToolResult {
        try validateUnknownKeys(args, allowed: [], path: "build_animatic")
        guard !editor.backlotScenes.isEmpty else {
            throw ToolError("This project has no Backlot scenes. Call set_backlot_scenes to build a previs bin first.")
        }
        let receipt: AnimaticBuildReceipt
        do {
            receipt = try await editor.buildBacklotAnimatic()
        } catch let error as AnimaticBuildError {
            throw ToolError(error.localizedDescription)
        } catch let error as BacklotBakeError {
            throw ToolError(error.localizedDescription)
        } catch let error as BacklotControlError {
            throw ToolError(error.localizedDescription)
        }
        var payload: [String: Any] = [
            "timelineId": receipt.timelineId,
            "timelineName": receipt.timelineName,
            "shotCount": receipt.placements.count,
            "clips": receipt.placements.map { ["sceneId": $0.sceneId, "clipId": $0.clipId] },
        ]
        if !receipt.skippedSceneIds.isEmpty {
            payload["skippedSceneIds"] = receipt.skippedSceneIds
        }
        payload["note"] = "Baked greybox previs. Activate this timeline to edit; regenerate photoreal footage per shot to replace the greybox."
        return .ok(Self.jsonString(payload) ?? "{\"timelineId\":\"\(receipt.timelineId)\"}")
    }

    func generatePhotoreal(_ editor: EditorViewModel, _ args: [String: Any]) async throws -> ToolResult {
        try validateUnknownKeys(args, allowed: ["durationSeconds"], path: "generate_photoreal")
        guard !editor.backlotScenes.isEmpty else {
            throw ToolError("This project has no Backlot scenes. Call set_backlot_scenes to build a previs bin first.")
        }
        let receipt: PhotorealBuildReceipt
        do {
            if let duration = args.int("durationSeconds") {
                receipt = try await editor.generateBacklotPhotoreal(durationSeconds: duration)
            } else {
                receipt = try await editor.generateBacklotPhotoreal()
            }
        } catch let error as PhotorealBuildError {
            throw ToolError(error.localizedDescription)
        } catch let error as BacklotBakeError {
            throw ToolError(error.localizedDescription)
        } catch let error as BacklotControlError {
            throw ToolError(error.localizedDescription)
        }
        var payload: [String: Any] = [
            "model": receipt.modelId,
            "durationSeconds": receipt.durationSeconds,
            "shotCount": receipt.submissions.count,
            "shots": receipt.submissions.map { ["sceneId": $0.sceneId, "placeholderId": $0.placeholderId] },
        ]
        if !receipt.skippedSceneIds.isEmpty {
            payload["skippedSceneIds"] = receipt.skippedSceneIds
        }
        payload["note"] = "Generations started in the background. Poll get_media with pending=true; assets are tagged with their sceneId. They are not on a timeline — use add_clips once ready."
        return .ok(Self.jsonString(payload) ?? "{\"shotCount\":\(receipt.submissions.count)}")
    }

    private static func validateSceneOpShape(_ op: [String: Any], path: String) throws {
        try validateUnknownKeys(op, allowed: sceneOpKeys, path: path)
        if let actors = op["actors"] as? [[String: Any]] {
            for (i, actor) in actors.enumerated() {
                try validateUnknownKeys(actor, allowed: sceneActorKeys, path: "\(path).actors[\(i)]")
            }
        }
        if let pieces = op["pieces"] as? [[String: Any]] {
            for (i, piece) in pieces.enumerated() {
                try validateUnknownKeys(piece, allowed: scenePieceKeys, path: "\(path).pieces[\(i)]")
            }
        }
        if let camera = op["camera"] as? [String: Any] {
            try validateUnknownKeys(camera, allowed: sceneCameraKeys, path: "\(path).camera")
        }
        if let look = op["look"] as? [String: Any] {
            try validateUnknownKeys(look, allowed: sceneLookKeys, path: "\(path).look")
        }
    }

    private func runBacklotScript(_ script: String) async throws -> String {
        do {
            return try await BacklotWindowController.shared.runAgentScript(script)
        } catch let error as BacklotControlError {
            throw ToolError(error.localizedDescription)
        }
    }
}
