import Foundation
import Testing
@testable import Carbonara

@MainActor
@Suite("Backlot photoreal — greybox routing and settings")
struct BacklotPhotorealTests {

    private func seedanceModel() throws -> VideoModelConfig {
        ModelCatalog.shared.configure()
        return try #require(VideoModelConfig.allModels.first { $0.id == EditorViewModel.photorealModelId })
    }

    private func makeEditor() -> EditorViewModel {
        let editor = EditorViewModel()
        var timeline = Timeline()
        timeline.fps = 30
        timeline.width = 1920
        timeline.height = 1080
        timeline.tracks = [Fixtures.videoTrack()]
        editor.timeline = timeline
        return editor
    }

    private func greybox(_ type: ClipType, sceneId: String = "s1") -> MediaAsset {
        let asset = MediaAsset(
            url: URL(fileURLWithPath: "/tmp/\(sceneId).\(type == .image ? "png" : "mp4")"),
            type: type, name: "SH 010", duration: type == .image ? 5 : 4
        )
        asset.backlotSceneId = sceneId
        return asset
    }

    private func scene(_ id: String = "s1", prompt: String = "photoreal shot") -> BacklotScene {
        BacklotScene(id: id, name: "SH 010", shotData: "{}", composedPrompt: prompt,
                     createdAt: nil, updatedAt: nil)
    }

    @Test func stillGreyboxRoutesToImageToVideoFrame() throws {
        let editor = makeEditor()
        let model = try seedanceModel()

        let (input, aspect) = try editor.photorealRouting(
            for: greybox(.image), scene: scene(), model: model
        )

        #expect(input.frames.count == 1)
        #expect(input.videoRefs.isEmpty)
        #expect(input.imageRefs.isEmpty)
        #expect(aspect.isEmpty)  // image-to-video derives aspect from the frame
        #expect(input.validate(for: model) == nil)
    }

    @Test func moveGreyboxRoutesToReferenceToVideo() throws {
        let editor = makeEditor()
        let model = try seedanceModel()

        let (input, aspect) = try editor.photorealRouting(
            for: greybox(.video), scene: scene(), model: model
        )

        #expect(input.videoRefs.count == 1)
        #expect(input.frames.isEmpty)
        #expect(!aspect.isEmpty)  // reference-to-video needs an explicit aspect
        #expect(model.aspectRatios.contains(aspect))
        #expect(input.validate(for: model) == nil)
    }

    @Test func aspectRatioTracksTimelineShape() throws {
        let editor = makeEditor()
        editor.timeline.width = 1080
        editor.timeline.height = 1920
        let model = try seedanceModel()

        let (_, aspect) = try editor.photorealRouting(
            for: greybox(.video), scene: scene(), model: model
        )

        #expect(aspect == "9:16")
    }

    @Test func durationClampsToModelRange() throws {
        let editor = makeEditor()
        let model = try seedanceModel()

        #expect(editor.clampedDuration(2, for: model) == 4)
        #expect(editor.clampedDuration(99, for: model) == 30)
        #expect(editor.clampedDuration(8, for: model) == 8)
    }

    @Test func resolutionPrefers720pForTallEnoughOutput() throws {
        let editor = makeEditor()
        let model = try seedanceModel()

        #expect(editor.photorealResolution(height: 720, for: model) == "720p")
        #expect(editor.photorealResolution(height: 480, for: model) == "480p")
    }

    @Test func failsWithoutScenes() async {
        let editor = makeEditor()

        await #expect(throws: PhotorealBuildError.self) {
            _ = try await editor.generateBacklotPhotoreal()
        }
    }
}
