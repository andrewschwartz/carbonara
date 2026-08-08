import Testing
@testable import Carbonara

@Suite("FalRequestBuilder")
struct FalRequestBuilderTests {
    private static let seedance = "bytedance/seedance-2.5"

    private func videoParams(
        duration: Int = 8,
        aspectRatio: String = "16:9",
        resolution: String? = "720p",
        startFrameURL: String? = nil,
        endFrameURL: String? = nil,
        referenceImageURLs: [String] = [],
        referenceVideoURLs: [String] = [],
        referenceAudioURLs: [String] = [],
        generateAudio: Bool = true
    ) -> BackendGenerationParams {
        .video(VideoGenerationParams(
            prompt: "dolly in on the actor",
            duration: duration,
            aspectRatio: aspectRatio,
            resolution: resolution,
            startFrameURL: startFrameURL,
            endFrameURL: endFrameURL,
            referenceImageURLs: referenceImageURLs,
            referenceVideoURLs: referenceVideoURLs,
            referenceAudioURLs: referenceAudioURLs,
            generateAudio: generateAudio
        ))
    }

    // MARK: - Endpoint resolution

    @Test func seedanceWithoutInputsResolvesToTextToVideo() {
        let endpoint = FalRequestBuilder.endpoint(model: Self.seedance, params: videoParams())
        #expect(endpoint == "bytedance/seedance-2.5/text-to-video")
    }

    @Test func seedanceWithStartFrameResolvesToImageToVideo() {
        let endpoint = FalRequestBuilder.endpoint(
            model: Self.seedance,
            params: videoParams(startFrameURL: "data:image/jpeg;base64,x")
        )
        #expect(endpoint == "bytedance/seedance-2.5/image-to-video")
    }

    @Test(arguments: [
        (["data:image/jpeg;base64,x"], [String](), [String]()),
        ([String](), ["data:video/mp4;base64,x"], [String]()),
        ([String](), [String](), ["data:audio/mpeg;base64,x"]),
    ])
    func seedanceWithReferencesResolvesToReferenceToVideo(
        images: [String], videos: [String], audios: [String]
    ) {
        let endpoint = FalRequestBuilder.endpoint(
            model: Self.seedance,
            params: videoParams(
                referenceImageURLs: images,
                referenceVideoURLs: videos,
                referenceAudioURLs: audios
            )
        )
        #expect(endpoint == "bytedance/seedance-2.5/reference-to-video")
    }

    @Test func nonSeedanceModelKeepsItsSlug() {
        let endpoint = FalRequestBuilder.endpoint(
            model: "fal-ai/ltx-video-13b-distilled",
            params: videoParams(startFrameURL: "data:image/jpeg;base64,x")
        )
        #expect(endpoint == "fal-ai/ltx-video-13b-distilled")
    }

    // MARK: - Seedance input body

    @Test func seedanceEncodesDurationAsStringEnum() {
        let d = FalRequestBuilder.inputDict(
            model: "bytedance/seedance-2.5/text-to-video",
            params: videoParams(duration: 12)
        )
        #expect(d["duration"] as? String == "12")
        #expect(d["generate_audio"] as? Bool == true)
        #expect(d["aspect_ratio"] as? String == "16:9")
        #expect(d["resolution"] as? String == "720p")
    }

    @Test func seedanceImageToVideoOmitsAspectRatioAndSendsFrames() {
        let d = FalRequestBuilder.inputDict(
            model: "bytedance/seedance-2.5/image-to-video",
            params: videoParams(startFrameURL: "start-url", endFrameURL: "end-url")
        )
        #expect(d["image_url"] as? String == "start-url")
        #expect(d["end_image_url"] as? String == "end-url")
        #expect(d["aspect_ratio"] == nil)
        #expect(d["image_urls"] == nil)
    }

    @Test func seedanceReferenceToVideoSendsReferenceArrays() {
        let d = FalRequestBuilder.inputDict(
            model: "bytedance/seedance-2.5/reference-to-video",
            params: videoParams(
                referenceImageURLs: ["img1"],
                referenceVideoURLs: ["vid1"],
                referenceAudioURLs: ["aud1"]
            )
        )
        #expect(d["image_urls"] as? [String] == ["img1"])
        #expect(d["video_urls"] as? [String] == ["vid1"])
        #expect(d["audio_urls"] as? [String] == ["aud1"])
        #expect(d["image_url"] == nil)
    }

    @Test func seedanceHonorsGenerateAudioOff() {
        let d = FalRequestBuilder.inputDict(
            model: "bytedance/seedance-2.5/text-to-video",
            params: videoParams(generateAudio: false)
        )
        #expect(d["generate_audio"] as? Bool == false)
    }

    @Test func genericVideoModelKeepsIntegerDuration() {
        let d = FalRequestBuilder.inputDict(
            model: "fal-ai/ltx-video-13b-distilled",
            params: videoParams(duration: 5)
        )
        #expect(d["duration"] as? Int == 5)
        #expect(d["generate_audio"] == nil)
    }
}
