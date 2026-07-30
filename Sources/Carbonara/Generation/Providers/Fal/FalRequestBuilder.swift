import Foundation

/// Translates Carbonara's provider-neutral generation params into a fal.ai model input body.
///
/// fal input schemas vary per model; this covers the common text/image/audio/video fields.
/// When a specific fal model needs different keys, branch on `model` here.
enum FalRequestBuilder {
    static func inputJSON(model: String, params: BackendGenerationParams) throws -> Data {
        try JSONSerialization.data(withJSONObject: inputDict(model: model, params: params), options: [.sortedKeys])
    }

    static func inputDict(model: String, params: BackendGenerationParams) -> [String: Any] {
        switch params {
        case .video(let p): return videoInput(p)
        case .image(let p): return imageInput(p)
        case .audio(let p): return audioInput(p)
        case .upscale(let p): return upscaleInput(p)
        }
    }

    private static func videoInput(_ p: VideoGenerationParams) -> [String: Any] {
        var d: [String: Any] = ["prompt": p.prompt]
        if !p.aspectRatio.isEmpty { d["aspect_ratio"] = p.aspectRatio }
        if let r = p.resolution, !r.isEmpty { d["resolution"] = r }
        if p.duration > 0 { d["duration"] = p.duration }
        if let start = p.startFrameURL { d["image_url"] = start }
        if let end = p.endFrameURL { d["end_image_url"] = end }
        if let src = p.sourceVideoURL { d["video_url"] = src }
        if !p.referenceImageURLs.isEmpty { d["image_urls"] = p.referenceImageURLs }
        return d
    }

    private static func imageInput(_ p: ImageGenerationParams) -> [String: Any] {
        var d: [String: Any] = ["prompt": p.prompt, "num_images": p.numImages]
        if !p.aspectRatio.isEmpty { d["aspect_ratio"] = p.aspectRatio }
        if let r = p.resolution, !r.isEmpty { d["resolution"] = r }
        if !p.imageURLs.isEmpty { d["image_urls"] = p.imageURLs }
        return d
    }

    private static func audioInput(_ p: AudioGenerationParams) -> [String: Any] {
        var d: [String: Any] = ["prompt": p.prompt]
        if let secs = p.durationSeconds { d["seconds_total"] = secs }
        if let lyrics = p.lyrics, !lyrics.isEmpty { d["lyrics"] = lyrics }
        if let style = p.styleInstructions, !style.isEmpty { d["style"] = style }
        if let voice = p.voice, !voice.isEmpty { d["voice"] = voice }
        if let src = p.sourceURL { d["audio_url"] = src }
        if let video = p.videoURL { d["video_url"] = video }
        return d
    }

    private static func upscaleInput(_ p: UpscaleGenerationParams) -> [String: Any] {
        ["video_url": p.sourceURL]
    }
}
