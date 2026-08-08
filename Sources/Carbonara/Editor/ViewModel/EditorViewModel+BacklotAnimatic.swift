import CoreGraphics
import Foundation
import ImageIO

/// Result of baking Backlot scenes into a previs animatic.
struct AnimaticBuildReceipt: Sendable {
    let timelineId: String
    let timelineName: String
    /// Scene id → placed clip id, in timeline order.
    let placements: [(sceneId: String, clipId: String)]
    let skippedSceneIds: [String]
}

enum AnimaticBuildError: LocalizedError {
    case noScenes
    case encodeFailed(sceneId: String)
    case projectChanged

    var errorDescription: String? {
        switch self {
        case .noScenes: "This project has no Backlot scenes to build."
        case .encodeFailed(let id): "Couldn't encode baked media for scene \(id)."
        case .projectChanged: "The project changed while building the animatic."
        }
    }
}

extension EditorViewModel {
    static let animaticTimelineName = "Animatic"

    /// Bakes every Backlot scene into greybox previs media and lays it out on a
    /// dedicated "Animatic" timeline in scene order, as one undoable action.
    ///
    /// Stills bake to a single PNG; camera moves bake to an mp4. All media is
    /// committed into the package before the undo group opens, mirroring
    /// `importFinderItemsToTimeline`, so the timeline build and asset import
    /// collapse into a single `EditorUndo` entry. Reuses an existing "Animatic"
    /// timeline by rebuilding it rather than accumulating stale cuts.
    @discardableResult
    func buildBacklotAnimatic(height: Int = 720) async throws -> AnimaticBuildReceipt {
        let scenes = backlotScenes
        guard !scenes.isEmpty else { throw AnimaticBuildError.noScenes }

        let bakeFps = timeline.fps
        let shots = try await BacklotWindowController.shared.bakeScenes(
            scenes.map(\.id), height: height, fps: bakeFps, for: self
        )
        guard !shots.isEmpty else { throw AnimaticBuildError.noScenes }
        return try await assembleAnimatic(from: shots)
    }

    /// Encodes baked shots, imports them, and lays them out as one undoable build.
    /// Separated from the WKWebView bake step so it can be exercised in isolation.
    @discardableResult
    func assembleAnimatic(from shots: [BacklotBakedShot]) async throws -> AnimaticBuildReceipt {
        guard !shots.isEmpty else { throw AnimaticBuildError.noScenes }

        // Commit all baked media into the package before mutating project state.
        let committed = try await commitBakedShots(shots)

        // Snapshot before adding assets so a single restore reverts import + build.
        let before = mediaLibraryUndoSnapshot()
        let imported = try await importCommittedGreyboxes(committed)

        var placements: [(sceneId: String, clipId: String)] = []
        undo.perform("Build Animatic") {
            undo.register("Build Animatic", withTarget: self) { vm in
                vm.restoreMediaLibraryUndoSnapshot(before, actionName: "Build Animatic")
            }
            undo.withoutRegistration {
                updateManifestMetadata(for: imported.map(\.asset))
                let trackIndex = resetAnimaticTimeline()
                var cursor = 0
                for entry in imported {
                    let duration = clipDurationFrames(for: entry.asset, segment: nil)
                    let ids = placeClip(
                        asset: entry.asset,
                        trackIndex: trackIndex,
                        startFrame: cursor,
                        durationFrames: duration,
                        addLinkedAudio: false
                    )
                    if let clipId = ids.first {
                        placements.append((entry.sceneId, clipId))
                    }
                    cursor += duration
                }
            }
        }

        let placedScenes = Set(placements.map(\.sceneId))
        return AnimaticBuildReceipt(
            timelineId: activeTimelineId,
            timelineName: timeline.name,
            placements: placements,
            skippedSceneIds: shots.map(\.sceneId).filter { !placedScenes.contains($0) }
        )
    }

    /// Encodes and commits every baked shot into the package, preserving order.
    /// Kept separate so the photoreal path shares the exact greybox media staging.
    func commitBakedShots(
        _ shots: [BacklotBakedShot]
    ) async throws -> [(shot: BacklotBakedShot, url: URL, type: ClipType)] {
        var committed: [(shot: BacklotBakedShot, url: URL, type: ClipType)] = []
        for shot in shots {
            let (url, type) = try await encodeAndCommitBakedShot(shot)
            committed.append((shot, url, type))
        }
        return committed
    }

    /// Imports committed greybox media un-appended, tags each with its scene id,
    /// finalizes metadata, and revalidates identity across the awaits. The caller
    /// owns the surrounding undo snapshot. Throws `projectChanged` if the library
    /// was replaced underneath the import.
    func importCommittedGreyboxes(
        _ committed: [(shot: BacklotBakedShot, url: URL, type: ClipType)]
    ) async throws -> [(sceneId: String, asset: MediaAsset)] {
        var imported: [(sceneId: String, asset: MediaAsset)] = []
        for entry in committed {
            let asset = addMediaAsset(from: entry.url, type: entry.type, finalize: false)
            asset.backlotSceneId = entry.shot.sceneId
            imported.append((entry.shot.sceneId, asset))
        }
        for entry in imported {
            _ = await finalizeImportedAsset(entry.asset, batchManifestUpdate: true)
        }
        guard imported.allSatisfy({ mediaAssetsById[$0.asset.id] === $0.asset }) else {
            throw AnimaticBuildError.projectChanged
        }
        return imported
    }

    /// Reuses the "Animatic" timeline (cleared) or creates it, and returns the
    /// index of an empty video track ready for placement. Runs without undo
    /// registration; the caller owns the single undo entry.
    private func resetAnimaticTimeline() -> Int {
        if let existing = timelines.first(where: { $0.name == Self.animaticTimelineName }) {
            activateTimeline(existing.id)
            timeline.tracks = []
        } else {
            _ = createTimeline(name: Self.animaticTimelineName, activate: true)
        }
        return insertTrack(at: 0, type: .video)
    }

    /// Stages a still to PNG or a move to mp4, then commits it into the package.
    private func encodeAndCommitBakedShot(_ shot: BacklotBakedShot) async throws -> (URL, ClipType) {
        let base = "backlot-\(sanitizedFilenameComponent(shot.sceneId))-\(UUID().uuidString.prefix(8))"
        if shot.isStill, let png = shot.frames.first {
            let staged = try await Task.detached(priority: .userInitiated) {
                try FileIO.stageData(png, pathExtension: "png")
            }.value
            let url = try await commitStagedProjectMedia(staged, filename: "\(base).png")
            return (url, .image)
        }

        let size = CGSize(width: shot.width, height: shot.height)
        let images = await Self.decodeFrames(shot.frames)
        guard images.count == shot.frames.count, !images.isEmpty else {
            throw AnimaticBuildError.encodeFailed(sceneId: shot.sceneId)
        }
        let staged = FileIO.temporaryFileURL(pathExtension: "mp4")
        do {
            try await FrameSequenceVideoWriter.write(frames: images, size: size, fps: shot.fps, to: staged)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw AnimaticBuildError.encodeFailed(sceneId: shot.sceneId)
        }
        let url = try await commitStagedProjectMedia(staged, filename: "\(base).mp4")
        return (url, .video)
    }

    private func sanitizedFilenameComponent(_ value: String) -> String {
        let allowed = value.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let joined = String(allowed).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return joined.isEmpty ? "scene" : String(joined.prefix(40))
    }

    private nonisolated static func decodeFrames(_ pngFrames: [Data]) async -> [CGImage] {
        await Task.detached(priority: .userInitiated) {
            pngFrames.compactMap { data -> CGImage? in
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
                return CGImageSourceCreateImageAtIndex(source, 0, nil)
            }
        }.value
    }
}
