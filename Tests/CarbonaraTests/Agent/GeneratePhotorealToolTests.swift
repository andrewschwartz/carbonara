import Foundation
import Testing
@testable import Carbonara

@MainActor
@Suite("generate_photoreal tool — discovery and validation")
struct GeneratePhotorealToolTests {

    @Test func toolIsExposedToBothSurfaces() {
        #expect(ToolDefinitions.mcpServer.contains { $0.name == .generatePhotoreal })
        #expect(ToolDefinitions.inAppAgent.contains { $0.name == .generatePhotoreal })
    }

    @Test func schemaTakesOptionalDurationOnly() throws {
        let tool = try #require(ToolDefinitions.all.first { $0.name == .generatePhotoreal })
        #expect(tool.inputSchema["type"] as? String == "object")
        let props = try #require(tool.inputSchema["properties"] as? [String: Any])
        #expect(props.keys.sorted() == ["durationSeconds"])
        #expect(tool.inputSchema["required"] == nil)
    }

    @Test func failsWithoutBacklotScenes() async {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack()])
        let executor = ToolExecutor(editor: editor, exportQueue: ExportQueue())

        let result = await executor.execute(name: "generate_photoreal", args: [:])

        #expect(result.isError)
    }

    @Test func rejectsUnknownArguments() async {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack()])
        editor.backlotScenes = [
            BacklotScene(id: "s1", name: "SH 010", shotData: "{}", composedPrompt: "",
                         createdAt: nil, updatedAt: nil)
        ]
        let executor = ToolExecutor(editor: editor, exportQueue: ExportQueue())

        let result = await executor.execute(name: "generate_photoreal", args: ["height": 720])

        #expect(result.isError)
    }
}
