import Foundation
import MCP

/// Maps Carbonara's generation params onto a Higgsfield MCP tool call.
///
/// Tool names and argument keys are best-effort and resolved against the server's advertised
/// tools at call time; verify/tune against the live Higgsfield MCP schema.
enum HiggsfieldRequestBuilder {
    static func toolName(for params: BackendGenerationParams, available: [String]) -> String? {
        let keyword: String
        let preferred: [String]
        switch params {
        case .video:
            keyword = "video"
            preferred = ["generate_video", "text_to_video", "create_video"]
        case .image:
            keyword = "image"
            preferred = ["generate_image", "text_to_image", "create_image"]
        case .audio:
            keyword = "audio"
            preferred = ["generate_audio", "generate_music", "music"]
        case .upscale:
            keyword = "upscale"
            preferred = ["upscale", "upscale_video"]
        }
        if let exact = preferred.first(where: { available.contains($0) }) { return exact }
        return available.first { $0.lowercased().contains(keyword) }
    }

    static func arguments(for params: BackendGenerationParams) -> [String: Value] {
        switch params {
        case .video(let p):
            var args: [String: Value] = ["prompt": .string(p.prompt)]
            if !p.aspectRatio.isEmpty { args["aspect_ratio"] = .string(p.aspectRatio) }
            if p.duration > 0 { args["duration"] = .int(p.duration) }
            if let image = p.startFrameURL { args["image_url"] = .string(image) }
            return args
        case .image(let p):
            var args: [String: Value] = ["prompt": .string(p.prompt), "num_images": .int(p.numImages)]
            if !p.aspectRatio.isEmpty { args["aspect_ratio"] = .string(p.aspectRatio) }
            return args
        case .audio(let p):
            var args: [String: Value] = ["prompt": .string(p.prompt)]
            if let seconds = p.durationSeconds { args["duration"] = .int(seconds) }
            return args
        case .upscale(let p):
            return ["video_url": .string(p.sourceURL)]
        }
    }
}
