import Foundation
import Testing
@testable import Carbonara

@MainActor
@Suite("build_animatic tool — discovery and validation")
struct BuildAnimaticToolTests {

    @Test func toolIsExposedToBothSurfaces() {
        #expect(ToolDefinitions.mcpServer.contains { $0.name == .buildAnimatic })
        #expect(ToolDefinitions.inAppAgent.contains { $0.name == .buildAnimatic })
    }

    @Test func schemaTakesNoArguments() throws {
        let tool = try #require(ToolDefinitions.all.first { $0.name == .buildAnimatic })
        #expect(tool.inputSchema["type"] as? String == "object")
        #expect(tool.inputSchema["properties"] == nil)
    }

    @Test func failsWithoutBacklotScenes() async {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack()])
        let executor = ToolExecutor(editor: editor, exportQueue: ExportQueue())

        let result = await executor.execute(name: "build_animatic", args: [:])

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

        let result = await executor.execute(name: "build_animatic", args: ["height": 720])

        #expect(result.isError)
    }
}
