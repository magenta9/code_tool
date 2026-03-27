import Foundation

/// Represents a tool available in the CodeTool application.
public struct Tool: Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let description: String
    public let systemImage: String

    public init(id: UUID = UUID(), name: String, description: String, systemImage: String) {
        self.id = id
        self.name = name
        self.description = description
        self.systemImage = systemImage
    }
}

/// Provides the default set of developer tools bundled with CodeTool.
public enum ToolRegistry {
    public static let defaults: [Tool] = [
        Tool(name: "JSON Formatter", description: "Format and validate JSON documents.", systemImage: "curlybraces"),
        Tool(name: "Base64 Encoder", description: "Encode and decode Base64 strings.", systemImage: "lock.doc"),
        Tool(name: "UUID Generator", description: "Generate random UUIDs.", systemImage: "number"),
        Tool(name: "Hash Calculator", description: "Compute MD5, SHA-1, and SHA-256 hashes.", systemImage: "number.square")
    ]
}
