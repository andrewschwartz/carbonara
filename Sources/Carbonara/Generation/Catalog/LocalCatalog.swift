import Foundation

/// Built-in, client-side model catalog for the local/third-party providers.
///
/// Replaces the former Convex-streamed catalog. Each entry's `provider` drives routing in
/// `ProviderRouter`; for fal, the entry `id` is the fal endpoint slug used at
/// `https://queue.fal.run/{id}`, except where `FalRequestBuilder.endpoint` maps one model
/// to per-mode endpoints (Seedance 2.5).
///
/// NOTE: fal endpoint slugs and per-model input schemas evolve — verify against fal's live
/// model list (https://fal.ai/models) and adjust `FalRequestBuilder` when a model's inputs differ.
enum LocalCatalog {
    static let entries: [CatalogEntry] = fal + higgsfield

    // MARK: - Higgsfield (via MCP)

    /// Model ids are Carbonara-facing labels; the actual MCP tool is resolved at call time.
    private static let higgsfield: [CatalogEntry] = [
        CatalogEntry(
            id: "higgsfield/video",
            kind: .video,
            displayName: "Higgsfield Video",
            provider: "higgsfield",
            uiCapabilities: .video(videoCaps(
                durations: [5],
                aspectRatios: ["16:9", "9:16", "1:1"],
                firstFrame: true
            )),
            responseShape: .video
        ),
        CatalogEntry(
            id: "higgsfield/image",
            kind: .image,
            displayName: "Higgsfield Image",
            provider: "higgsfield",
            uiCapabilities: .image(imageCaps(
                aspectRatios: ["1:1", "16:9", "9:16"],
                maxImages: 4
            )),
            responseShape: .images
        ),
    ]

    // MARK: - fal.ai

    private static let fal: [CatalogEntry] = [
        // Video
        // One catalog model, three fal endpoints (text/image/reference-to-video);
        // FalRequestBuilder resolves the endpoint from the submitted inputs.
        CatalogEntry(
            id: "bytedance/seedance-2.5",
            kind: .video,
            displayName: "Seedance 2.5",
            provider: "fal",
            uiCapabilities: .video(videoCaps(
                durations: Array(4...30),
                aspectRatios: ["16:9", "9:16", "1:1", "21:9", "4:3", "3:4"],
                resolutions: ["480p", "720p"],
                firstFrame: true, lastFrame: true,
                maxRefImages: 30, maxRefVideos: 10, maxRefAudios: 10,
                maxTotalRefs: 50,
                maxCombinedVideoRefSeconds: 30.2, maxCombinedAudioRefSeconds: 30.2,
                framesAndReferencesExclusive: true,
                referenceTagNoun: "Image"
            )),
            responseShape: .video
        ),
        CatalogEntry(
            id: "fal-ai/ltx-video-13b-distilled",
            kind: .video,
            displayName: "LTX Video 13B",
            provider: "fal",
            uiCapabilities: .video(videoCaps(
                durations: [5, 8, 10],
                aspectRatios: ["16:9", "9:16", "1:1"],
                resolutions: ["1280x720", "720x1280", "960x960"],
                firstFrame: true, lastFrame: true, maxRefImages: 0
            )),
            responseShape: .video
        ),
        CatalogEntry(
            id: "fal-ai/minimax/video-01",
            kind: .video,
            displayName: "MiniMax Video 01",
            provider: "fal",
            uiCapabilities: .video(videoCaps(
                durations: [6],
                aspectRatios: ["16:9", "9:16", "1:1"],
                firstFrame: true
            )),
            responseShape: .video
        ),

        // Image
        CatalogEntry(
            id: "fal-ai/flux/dev",
            kind: .image,
            displayName: "FLUX.1 [dev]",
            provider: "fal",
            uiCapabilities: .image(imageCaps(
                aspectRatios: ["1:1", "16:9", "9:16", "4:3", "3:4"],
                supportsImageReference: false, maxImages: 4
            )),
            responseShape: .images
        ),
        CatalogEntry(
            id: "fal-ai/flux/schnell",
            kind: .image,
            displayName: "FLUX.1 [schnell]",
            provider: "fal",
            uiCapabilities: .image(imageCaps(
                aspectRatios: ["1:1", "16:9", "9:16", "4:3", "3:4"],
                supportsImageReference: false, maxImages: 4
            )),
            responseShape: .images
        ),

        // Audio — the audio bed toolset targets these
        CatalogEntry(
            id: "fal-ai/stable-audio-25/text-to-audio",
            kind: .audio,
            displayName: "Stable Audio 2.5",
            provider: "fal",
            uiCapabilities: .audio(audioCaps(
                category: "music",
                supportsInstrumental: true,
                supportsStyleInstructions: true,
                minSeconds: 1, maxSeconds: 300,
                promptLabel: "Describe the music bed"
            )),
            responseShape: .audio
        ),
        CatalogEntry(
            id: "fal-ai/minimax-music",
            kind: .audio,
            displayName: "MiniMax Music",
            provider: "fal",
            uiCapabilities: .audio(audioCaps(
                category: "music",
                supportsLyrics: true,
                minSeconds: 1, maxSeconds: 90,
                promptLabel: "Describe the track"
            )),
            responseShape: .audio
        ),
    ]

    // MARK: - Caps builders

    private static func videoCaps(
        durations: [Int],
        aspectRatios: [String],
        resolutions: [String]? = nil,
        firstFrame: Bool = false,
        lastFrame: Bool = false,
        maxRefImages: Int = 0,
        maxRefVideos: Int = 0,
        maxRefAudios: Int = 0,
        maxTotalRefs: Int? = nil,
        maxCombinedVideoRefSeconds: Double? = nil,
        maxCombinedAudioRefSeconds: Double? = nil,
        framesAndReferencesExclusive: Bool = false,
        referenceTagNoun: String = "reference"
    ) -> VideoCaps {
        VideoCaps(
            durations: durations,
            resolutions: resolutions,
            aspectRatios: aspectRatios,
            supportsFirstFrame: firstFrame,
            supportsLastFrame: lastFrame,
            maxReferenceImages: maxRefImages,
            maxReferenceVideos: maxRefVideos,
            maxReferenceAudios: maxRefAudios,
            maxTotalReferences: maxTotalRefs,
            maxCombinedVideoRefSeconds: maxCombinedVideoRefSeconds,
            maxCombinedAudioRefSeconds: maxCombinedAudioRefSeconds,
            framesAndReferencesExclusive: framesAndReferencesExclusive,
            referenceTagNoun: referenceTagNoun,
            requiresSourceVideo: false,
            requiresReferenceImage: false
        )
    }

    private static func imageCaps(
        aspectRatios: [String],
        resolutions: [String]? = nil,
        qualities: [String]? = nil,
        supportsImageReference: Bool = false,
        maxImages: Int = 1
    ) -> ImageCaps {
        ImageCaps(
            resolutions: resolutions,
            aspectRatios: aspectRatios,
            qualities: qualities,
            supportsImageReference: supportsImageReference,
            maxImages: maxImages
        )
    }

    private static func audioCaps(
        category: String,
        voices: [String]? = nil,
        defaultVoice: String? = nil,
        supportsLyrics: Bool = false,
        supportsInstrumental: Bool = false,
        supportsStyleInstructions: Bool = false,
        minSeconds: Int = 1,
        maxSeconds: Int = 300,
        minPromptLength: Int = 1,
        promptLabel: String = "Describe the sound"
    ) -> AudioCaps {
        AudioCaps(
            category: category,
            voices: voices,
            defaultVoice: defaultVoice,
            supportsLyrics: supportsLyrics,
            supportsInstrumental: supportsInstrumental,
            supportsStyleInstructions: supportsStyleInstructions,
            durations: nil,
            durationRange: nil,
            minPromptLength: minPromptLength,
            inputs: ["text"],
            promptLabel: promptLabel,
            minSeconds: minSeconds,
            maxSeconds: maxSeconds,
            targetLanguages: nil,
            defaultTargetLanguage: nil
        )
    }
}
