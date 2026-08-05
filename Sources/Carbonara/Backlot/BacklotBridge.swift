import AppKit
import WebKit

/// Routes messages from the Backlot page into Carbonara.
///
/// Reference frames (PNG data URLs) are committed into the active project's
/// media library through the shared staged-import path; generated fal media is
/// downloaded and imported the same way. Non-media exports (OBJ, shot JSON)
/// go to a save panel.
@MainActor
final class BacklotBridge: NSObject, WKScriptMessageHandler {
    static let messageName = "carbonara"

    weak var window: NSWindow?

    private var importSequence = 0

    private static let frameExtensions: Set<String> = ["png", "jpg", "jpeg"]
    private nonisolated static let remoteMaxBytes: Int64 = 5 * 1024 * 1024 * 1024

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageName,
              let body = message.body as? [String: Any],
              let kind = body["kind"] as? String else { return }
        switch kind {
        case "download":
            guard let filename = body["filename"] as? String,
                  let dataURL = body["dataURL"] as? String else { return }
            Task { await self.handleDownload(filename: filename, dataURL: dataURL) }
        case "importRemote":
            guard let urlString = body["url"] as? String else { return }
            Task { await self.handleRemoteImport(urlString: urlString) }
        default:
            Log.project.warning("backlot bridge received unknown message kind=\(kind)")
        }
    }

    // MARK: - Exported files (frames, OBJ, shot JSON)

    private func handleDownload(filename: String, dataURL: String) async {
        let name = Self.sanitizedFilename(filename)
        guard let data = await Task.detached(priority: .userInitiated, operation: {
            Self.decodeDataURL(dataURL)
        }).value else {
            presentError("Couldn't read the exported file from Backlot.")
            return
        }
        let ext = (name as NSString).pathExtension.lowercased()
        if Self.frameExtensions.contains(ext), AppState.shared.activeProject != nil {
            await importIntoProject(data: data, preferredName: name)
        } else {
            await saveWithPanel(data: data, suggestedName: name)
        }
    }

    private func saveWithPanel(data: Data, suggestedName: String) async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        let response: NSApplication.ModalResponse
        if let window {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }
        guard response == .OK, let destination = panel.url else { return }
        do {
            try await Task.detached(priority: .userInitiated) {
                try data.write(to: destination)
            }.value
        } catch {
            Log.project.error("backlot save failed: \(Log.detail(error))")
            presentError("Couldn't save \"\(suggestedName)\": \(error.localizedDescription)")
        }
    }

    // MARK: - Generated media from fal

    private func handleRemoteImport(urlString: String) async {
        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              url.host() != nil else {
            presentError("Generated media has an unsupported URL.")
            return
        }
        guard AppState.shared.activeProject != nil else {
            presentError("Open a project to add generated media to it.")
            return
        }
        do {
            let (downloaded, response) = try await URLSession.shared.download(from: url)
            guard let ext = Self.mediaExtension(for: url, response: response) else {
                try? await Self.removeFile(downloaded)
                presentError("Generated media has an unsupported format.")
                return
            }
            let filename = nextImportFilename(stem: "backlot-gen", ext: ext)
            let staged = try await Task.detached(priority: .userInitiated) {
                let size = (try? downloaded.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                guard size <= Self.remoteMaxBytes else {
                    try? FileManager.default.removeItem(at: downloaded)
                    throw CocoaError(.fileReadTooLarge)
                }
                let staged = FileManager.default.temporaryDirectory
                    .appendingPathComponent("backlot-stage-\(UUID().uuidString).\(ext)")
                try FileManager.default.moveItem(at: downloaded, to: staged)
                return staged
            }.value
            await commitAndRegister(staged: staged, filename: filename)
        } catch {
            Log.project.error("backlot remote import failed: \(Log.detail(error))")
            presentError("Couldn't download the generated media: \(error.localizedDescription)")
        }
    }

    // MARK: - Shared project import

    private func importIntoProject(data: Data, preferredName: String) async {
        let ext = (preferredName as NSString).pathExtension.lowercased()
        let stem = (preferredName as NSString).deletingPathExtension
        let filename = nextImportFilename(stem: stem, ext: ext)
        do {
            let staged = try await Task.detached(priority: .userInitiated) {
                let staged = FileManager.default.temporaryDirectory
                    .appendingPathComponent("backlot-stage-\(UUID().uuidString).\(ext)")
                try data.write(to: staged)
                return staged
            }.value
            await commitAndRegister(staged: staged, filename: filename)
        } catch {
            Log.project.error("backlot import failed: \(Log.detail(error))")
            presentError("Couldn't add \"\(preferredName)\" to the project: \(error.localizedDescription)")
        }
    }

    private func commitAndRegister(staged: URL, filename: String) async {
        guard let editor = AppState.shared.activeProject?.editorViewModel else {
            try? await Self.removeFile(staged)
            presentError("Open a project to add media to it.")
            return
        }
        let ext = (filename as NSString).pathExtension.lowercased()
        guard let type = ClipType(fileExtension: ext) else {
            try? await Self.removeFile(staged)
            presentError("Unsupported media type \".\(ext)\".")
            return
        }
        do {
            let committed = try await editor.commitStagedProjectMedia(staged, filename: filename)
            guard AppState.shared.openProjects.contains(where: { $0.editorViewModel === editor }) else {
                Log.project.warning("backlot import dropped: project closed during commit file=\(filename)")
                return
            }
            let asset = editor.undo.perform("Import Media (Backlot)") {
                editor.addMediaAsset(from: committed, type: type)
            }
            editor.mediaPanelToast = "Added \"\(asset.name)\" from Backlot."
            Log.project.notice(
                "backlot media imported asset=\(asset.id.prefix(8)) type=\(type.rawValue)",
                telemetry: "Backlot media imported",
                data: ["assetId": Telemetry.shortId(asset.id), "type": type.rawValue]
            )
        } catch {
            Log.project.error("backlot commit failed: \(Log.detail(error))")
            presentError("Couldn't add the media to the project: \(error.localizedDescription)")
        }
    }

    private func nextImportFilename(stem: String, ext: String) -> String {
        importSequence += 1
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(stem)-\(formatter.string(from: Date()))-\(importSequence).\(ext)"
    }

    private func presentError(_ message: String) {
        Log.project.warning("backlot bridge error shown: \(message)")
        let alert = NSAlert()
        alert.messageText = "Backlot"
        alert.informativeText = message
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Helpers

    private nonisolated static func removeFile(_ url: URL) async throws {
        try await Task.detached(priority: .utility) {
            try FileManager.default.removeItem(at: url)
        }.value
    }

    private nonisolated static func sanitizedFilename(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let last = (cleaned as NSString).lastPathComponent
        return last.isEmpty ? "backlot-file" : last
    }

    private nonisolated static func decodeDataURL(_ string: String) -> Data? {
        guard string.hasPrefix("data:"), let comma = string.firstIndex(of: ",") else { return nil }
        let meta = string[string.index(string.startIndex, offsetBy: 5)..<comma]
        let payload = String(string[string.index(after: comma)...])
        if meta.hasSuffix(";base64") {
            return Data(base64Encoded: payload)
        }
        return payload.removingPercentEncoding.flatMap { $0.data(using: .utf8) }
    }

    private nonisolated static func mediaExtension(for url: URL, response: URLResponse) -> String? {
        let fromPath = url.pathExtension.lowercased()
        if !fromPath.isEmpty, ClipType(fileExtension: fromPath) != nil { return fromPath }
        switch response.mimeType?.lowercased() {
        case "image/png": return "png"
        case "image/jpeg": return "jpg"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        default: return nil
        }
    }
}
