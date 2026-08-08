import Foundation

/// Result of upgrading Backlot greybox previs into photoreal Seedance generations.
struct PhotorealBuildReceipt: Sendable {
    /// Scene id → placeholder asset id for the in-flight generation, in scene order.
    let submissions: [(sceneId: String, placeholderId: String)]
    /// Scenes that had no greybox and couldn't be baked.
    let skippedSceneIds: [String]
    let modelId: String
    let durationSeconds: Int
}

enum PhotorealBuildError: LocalizedError {
    case noScenes
    case modelUnavailable
    case notPaid
    case noProvider
    case outOfCredits
    case invalidSettings(String)

    var errorDescription: String? {
        switch self {
        case .noScenes: "This project has no Backlot scenes to upgrade."
        case .modelUnavailable: "Seedance 2.5 isn't available. The model catalog may not be loaded yet."
        case .notPaid: "Photoreal generation requires a paid plan."
        case .noProvider: "No generation provider configured. Add a fal.ai API key in Settings."
        case .outOfCredits: "Out of credits. Add credits or subscribe to keep generating."
        case .invalidSettings(let why): why
        }
    }
}

extension EditorViewModel {
    static let photorealModelId = "bytedance/seedance-2.5"

    /// Default clip length for a photoreal take, in seconds. A greybox move loops
    /// ~4.2s; stills have no inherent length, so both default here and clamp to
    /// the model's supported range.
    static let photorealDefaultSeconds = 5

    /// Upgrades every Backlot scene into a photoreal Seedance 2.5 generation,
    /// conditioning each take on that scene's greybox and its `composedPrompt`.
    ///
    /// Coverage angles derive from one master setup, so the greyboxes already
    /// agree on blocking; each take conditions on its own greybox independently
    /// and all submissions fire concurrently. A still greybox routes to
    /// image-to-video (greybox as the first frame); a move greybox routes to
    /// reference-to-video (greybox as a video reference) — Seedance forbids
    /// mixing frames and references in one call. Results are tagged with
    /// `backlotSceneId` and land in the media library; placement stays a
    /// separate, explicit step because each generation is async and billable.
    ///
    /// Reuses any existing greybox already baked for a scene (e.g. from a prior
    /// animatic build) and bakes only the scenes still missing one.
    @discardableResult
    func generateBacklotPhotoreal(
        durationSeconds requestedDuration: Int = EditorViewModel.photorealDefaultSeconds,
        height: Int = 720
    ) async throws -> PhotorealBuildReceipt {
        guard AccountService.shared.aiAllowed else { throw PhotorealBuildError.noProvider }
        guard AccountService.shared.hasCredits else { throw PhotorealBuildError.outOfCredits }

        let scenes = backlotScenes
        guard !scenes.isEmpty else { throw PhotorealBuildError.noScenes }

        guard let model = VideoModelConfig.allModels.first(where: { $0.id == Self.photorealModelId }) else {
            throw PhotorealBuildError.modelUnavailable
        }
        if model.paidOnly && !AccountService.shared.isPaid { throw PhotorealBuildError.notPaid }

        let greyboxes = try await resolveGreyboxes(for: scenes, height: height)
        guard !greyboxes.isEmpty else { throw PhotorealBuildError.noScenes }

        let duration = clampedDuration(requestedDuration, for: model)
        let resolution = photorealResolution(height: height, for: model)

        var submissions: [(sceneId: String, placeholderId: String)] = []
        for (scene, greybox) in greyboxes {
            let placeholderId = try submitPhotorealTake(
                scene: scene, greybox: greybox, model: model,
                duration: duration, resolution: resolution
            )
            submissions.append((scene.id, placeholderId))
        }

        let covered = Set(greyboxes.map { $0.scene.id })
        return PhotorealBuildReceipt(
            submissions: submissions,
            skippedSceneIds: scenes.map(\.id).filter { !covered.contains($0) },
            modelId: model.id,
            durationSeconds: duration
        )
    }

    /// Reuses an existing greybox asset per scene or bakes the missing ones. A
    /// greybox is a `backlotSceneId`-tagged, non-generated image or video asset.
    private func resolveGreyboxes(
        for scenes: [BacklotScene], height: Int
    ) async throws -> [(scene: BacklotScene, asset: MediaAsset)] {
        var existing: [String: MediaAsset] = [:]
        for asset in mediaAssets where !asset.isGenerated {
            guard let sceneId = asset.backlotSceneId, existing[sceneId] == nil else { continue }
            if asset.type == .image || asset.type == .video { existing[sceneId] = asset }
        }

        let missing = scenes.filter { existing[$0.id] == nil }
        if !missing.isEmpty {
            let shots = try await BacklotWindowController.shared.bakeScenes(
                missing.map(\.id), height: height, fps: timeline.fps, for: self
            )
            let committed = try await commitBakedShots(shots)
            let before = mediaLibraryUndoSnapshot()
            let imported = try await importCommittedGreyboxes(committed)
            undo.perform("Bake Greybox") {
                undo.register("Bake Greybox", withTarget: self) { vm in
                    vm.restoreMediaLibraryUndoSnapshot(before, actionName: "Bake Greybox")
                }
                undo.withoutRegistration {
                    updateManifestMetadata(for: imported.map(\.asset))
                }
            }
            for entry in imported { existing[entry.sceneId] = entry.asset }
        }

        return scenes.compactMap { scene in
            existing[scene.id].map { (scene, $0) }
        }
    }

    /// Submits one Seedance take and returns the placeholder asset id. Stamps
    /// `backlotSceneId` on the placeholder; the generation service mutates that
    /// same asset through download and finalize, so the tag persists into the
    /// manifest without a completion callback.
    private func submitPhotorealTake(
        scene: BacklotScene, greybox: MediaAsset, model: VideoModelConfig,
        duration: Int, resolution: String?
    ) throws -> String {
        let prompt = scene.composedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw PhotorealBuildError.invalidSettings("Scene \"\(scene.name)\" has no prompt to generate from.")
        }

        let (inputAssets, aspectRatio) = try photorealRouting(for: greybox, scene: scene, model: model)
        if let err = inputAssets.validate(for: model) {
            throw PhotorealBuildError.invalidSettings(err)
        }

        let genInput = GenerationInput(
            prompt: prompt, model: model.id, duration: duration,
            aspectRatio: aspectRatio, resolution: resolution
        )
        let placeholderId = VideoGenerationSubmission.make(
            genInput: genInput,
            model: model,
            inputAssets: inputAssets,
            placeholderDuration: Double(max(1, duration)),
            name: scene.name,
            folderId: nil,
            generateAudio: true
        ).submit(
            service: generationService,
            projectURL: projectURL,
            editor: self
        )
        if let placeholder = mediaAssetsById[placeholderId] {
            placeholder.backlotSceneId = scene.id
        }
        return placeholderId
    }

    /// Routes a greybox to Seedance conditioning by type: a still becomes the
    /// first frame (image-to-video, aspect derived from the frame); a move becomes
    /// a video reference (reference-to-video). Frames and references are mutually
    /// exclusive on Seedance, so exactly one slot is populated. Internal seam so
    /// the routing decision is testable without the account gate or network.
    func photorealRouting(
        for greybox: MediaAsset, scene: BacklotScene, model: VideoModelConfig
    ) throws -> (inputAssets: VideoGenerationSubmission.InputAssets, aspectRatio: String) {
        switch greybox.type {
        case .image:
            return (.init(frames: [greybox]), "")
        case .video:
            return (.init(videoRefs: [greybox]), photorealAspectRatio(for: model))
        default:
            throw PhotorealBuildError.invalidSettings("Scene \"\(scene.name)\" greybox is not image or video.")
        }
    }

    func clampedDuration(_ requested: Int, for model: VideoModelConfig) -> Int {
        guard let lo = model.durations.min(), let hi = model.durations.max() else { return requested }
        return min(max(requested, lo), hi)
    }

    func photorealResolution(height: Int, for model: VideoModelConfig) -> String? {
        guard let resolutions = model.resolutions, !resolutions.isEmpty else { return nil }
        let preferred = height >= 720 ? "720p" : "480p"
        return resolutions.contains(preferred) ? preferred : resolutions.first
    }

    private func photorealAspectRatio(for model: VideoModelConfig) -> String {
        let target = timeline.height > 0 ? Double(timeline.width) / Double(timeline.height) : 16.0 / 9.0
        let best = model.aspectRatios.min { lhs, rhs in
            abs(aspectValue(lhs) - target) < abs(aspectValue(rhs) - target)
        }
        return best ?? model.aspectRatios.first ?? "16:9"
    }

    private func aspectValue(_ ratio: String) -> Double {
        let parts = ratio.split(separator: ":")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), h > 0 else {
            return 16.0 / 9.0
        }
        return w / h
    }
}
