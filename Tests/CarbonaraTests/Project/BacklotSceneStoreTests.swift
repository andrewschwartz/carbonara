import Foundation
import Testing
@testable import Carbonara

@MainActor
@Suite("Backlot scene store — project persistence round-trip")
struct BacklotSceneStoreTests {

    private func scene(_ id: String, name: String = "SH 010") -> BacklotScene {
        BacklotScene(
            id: id, name: name,
            shotData: "{\"actors\":[],\"camera\":{\"angle\":45}}",
            composedPrompt: "wide establishing shot",
            createdAt: nil, updatedAt: nil
        )
    }

    @Test func snapshotOmitsEmptySceneStore() {
        let e = EditorViewModel()
        e.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack()])
        #expect(e.projectFileSnapshot().backlotScenes == nil)
    }

    @Test func scenesSurviveSnapshotAndApply() {
        let e = EditorViewModel()
        e.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack()])
        e.backlotScenes = [scene("sc1"), scene("sc2", name: "SH 020")]

        let file = e.projectFileSnapshot()
        let restored = EditorViewModel()
        restored.applyProjectFile(file)

        #expect(restored.backlotScenes == e.backlotScenes)
    }

    @Test func applyWithoutScenesResetsToEmpty() {
        let e = EditorViewModel()
        e.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack()])
        e.backlotScenes = [scene("sc1")]

        var file = e.projectFileSnapshot()
        file.backlotScenes = nil
        e.applyProjectFile(file)

        #expect(e.backlotScenes.isEmpty)
    }

    @Test func shotDataStoredVerbatim() throws {
        let e = EditorViewModel()
        e.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack()])
        let raw = "{\"pieces\":[{\"type\":\"wall\",\"x\":1.5}],\"move\":\"push-in\"}"
        e.backlotScenes = [BacklotScene(id: "sc1", name: "A", shotData: raw, composedPrompt: "", createdAt: nil, updatedAt: nil)]

        let data = try JSONEncoder().encode(e.projectFileSnapshot())
        let decoded = try JSONDecoder().decode(ProjectFile.self, from: data)

        #expect(decoded.backlotScenes?.first?.shotData == raw)
    }
}
