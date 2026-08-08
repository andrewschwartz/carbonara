import Testing
@testable import Carbonara

@Suite("LocalCatalog")
struct LocalCatalogTests {
    /// The agent's generate_video defaults to the first video entry; Seedance 2.5 must stay first.
    @Test func seedance25IsTheDefaultVideoModel() {
        let firstVideo = LocalCatalog.entries.first { $0.kind == .video }
        #expect(firstVideo?.id == "bytedance/seedance-2.5")
        #expect(firstVideo?.provider == "fal")
    }

    @Test func seedance25CapsMatchFalContract() throws {
        let entry = try #require(LocalCatalog.entries.first { $0.id == "bytedance/seedance-2.5" })
        guard case .video(let caps) = entry.uiCapabilities else {
            Issue.record("expected video capabilities")
            return
        }
        #expect(caps.durations == Array(4...30))
        #expect(caps.resolutions == ["480p", "720p"])
        #expect(caps.supportsFirstFrame)
        #expect(caps.supportsLastFrame)
        #expect(caps.maxReferenceImages == 30)
        #expect(caps.maxReferenceVideos == 10)
        #expect(caps.maxReferenceAudios == 10)
        #expect(caps.maxTotalReferences == 50)
        #expect(caps.framesAndReferencesExclusive)
    }
}
