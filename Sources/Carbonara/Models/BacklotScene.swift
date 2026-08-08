import Foundation

/// A previs shot definition owned by the project, not the Backlot web session.
///
/// `shotData` is the Backlot web app's own serialized scene JSON, stored opaquely
/// as a string: Swift never parses it, so it survives any Backlot schema change.
/// The web bin is a live projection of these; assets baked from a scene carry its
/// `id` so a timeline clip resolves back through mediaRef -> asset -> scene.
struct BacklotScene: Codable, Sendable, Equatable, Identifiable {
    let id: String
    var name: String
    /// Backlot's `shotData()` JSON, verbatim.
    var shotData: String
    /// The composed generation prompt for this scene, verbatim from the web app.
    var composedPrompt: String
    var createdAt: Date?
    var updatedAt: Date?
}
