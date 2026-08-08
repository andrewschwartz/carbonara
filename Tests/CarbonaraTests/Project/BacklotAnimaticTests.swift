import AppKit
import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Carbonara

@MainActor
@Suite("Backlot animatic — bake assembly into a timeline")
struct BacklotAnimaticTests {

    private func makeEditor() -> (EditorViewModel, URL, UndoManager) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("animatic-\(UUID().uuidString)", isDirectory: true)
        let editor = EditorViewModel()
        editor.projectURL = root.appendingPathComponent("Animatic.nar", isDirectory: true)
        var timeline = Timeline()
        timeline.fps = 30
        timeline.width = 1280
        timeline.height = 720
        timeline.tracks = [Fixtures.videoTrack()]
        editor.timeline = timeline
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undo.attach(undoManager)
        return (editor, root, undoManager)
    }

    private func cleanup(_ root: URL) {
        Task.detached { try? FileManager.default.removeItem(at: root) }
    }

    private func pngFrame(rgb: (UInt8, UInt8, UInt8), width: Int, height: Int) throws -> Data {
        let ctx = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        ctx.setFillColor(red: CGFloat(rgb.0)/255, green: CGFloat(rgb.1)/255, blue: CGFloat(rgb.2)/255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(ctx.makeImage())
        return try #require(ImageEncoder.encodePNG(image))
    }

    private func stillShot(_ sceneId: String, name: String = "SH 010") throws -> BacklotBakedShot {
        BacklotBakedShot(
            sceneId: sceneId, sceneName: name, isStill: true,
            width: 1280, height: 720, fps: 30,
            frames: [try pngFrame(rgb: (40, 90, 160), width: 1280, height: 720)]
        )
    }

    private func motionShot(_ sceneId: String, name: String = "SH 020", frameCount: Int = 6) throws -> BacklotBakedShot {
        let frames = try (0..<frameCount).map { i in
            try pngFrame(rgb: (UInt8(20 + i * 10), 60, 120), width: 1280, height: 720)
        }
        return BacklotBakedShot(
            sceneId: sceneId, sceneName: name, isStill: false,
            width: 1280, height: 720, fps: 30, frames: frames
        )
    }

    @Test func stillBakesToImageAndMoveBakesToVideoInOrder() async throws {
        let (editor, root, _) = makeEditor()
        defer { cleanup(root) }

        let receipt = try await editor.assembleAnimatic(from: [
            try stillShot("sc-still"),
            try motionShot("sc-move"),
        ])

        #expect(receipt.placements.map(\.sceneId) == ["sc-still", "sc-move"])
        #expect(receipt.skippedSceneIds.isEmpty)

        let stillAsset = try #require(editor.mediaAssets.first { $0.backlotSceneId == "sc-still" })
        let moveAsset = try #require(editor.mediaAssets.first { $0.backlotSceneId == "sc-move" })
        #expect(stillAsset.type == .image)
        #expect(moveAsset.type == .video)
    }

    @Test func buildsDedicatedAnimaticTimelineWithClipsBackToBack() async throws {
        let (editor, root, _) = makeEditor()
        defer { cleanup(root) }

        let receipt = try await editor.assembleAnimatic(from: [
            try stillShot("a"),
            try stillShot("b", name: "SH 020"),
        ])

        #expect(receipt.timelineName == EditorViewModel.animaticTimelineName)
        let animatic = try #require(editor.timelines.first { $0.id == receipt.timelineId })
        #expect(animatic.name == EditorViewModel.animaticTimelineName)
        let videoTrack = try #require(animatic.tracks.first { $0.type == .video })
        #expect(videoTrack.clips.count == 2)
        let sorted = videoTrack.clips.sorted { $0.startFrame < $1.startFrame }
        #expect(sorted[0].startFrame == 0)
        #expect(sorted[1].startFrame == sorted[0].durationFrames)
    }

    @Test func assetsCarryBacklotSceneProvenanceIntoManifest() async throws {
        let (editor, root, _) = makeEditor()
        defer { cleanup(root) }

        _ = try await editor.assembleAnimatic(from: [try stillShot("scene-42")])

        let asset = try #require(editor.mediaAssets.first { $0.backlotSceneId == "scene-42" })
        let entry = try #require(editor.mediaManifest.entries.first { $0.id == asset.id })
        #expect(entry.backlotSceneId == "scene-42")
    }

    @Test func wholeBuildIsOneUndoStep() async throws {
        let (editor, root, undoManager) = makeEditor()
        defer { cleanup(root) }
        let timelineCountBefore = editor.timelines.count

        _ = try await editor.assembleAnimatic(from: [
            try stillShot("a"),
            try motionShot("b"),
        ])
        #expect(editor.timelines.count == timelineCountBefore + 1)
        #expect(editor.mediaAssets.count == 2)

        undoManager.undo()

        #expect(editor.timelines.count == timelineCountBefore)
        #expect(editor.mediaAssets.isEmpty)
    }

    @Test func rebuildReplacesAnimaticRatherThanAppending() async throws {
        let (editor, root, _) = makeEditor()
        defer { cleanup(root) }

        _ = try await editor.assembleAnimatic(from: [try stillShot("a"), try stillShot("b")])
        let firstReceipt = try await editor.assembleAnimatic(from: [try stillShot("c")])

        let animaticTimelines = editor.timelines.filter { $0.name == EditorViewModel.animaticTimelineName }
        #expect(animaticTimelines.count == 1)
        let animatic = try #require(editor.timelines.first { $0.id == firstReceipt.timelineId })
        let videoClips = animatic.tracks.filter { $0.type == .video }.flatMap(\.clips)
        #expect(videoClips.count == 1)
    }
}
