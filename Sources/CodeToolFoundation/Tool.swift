import Foundation

/// Tool category for grouping in the sidebar and landing page.
public enum ToolCategory: String, CaseIterable, Hashable {
    case devTools = "Dev Tools"
    case aiTools = "AI Tools"

    public var displayName: String { rawValue }

    public var systemImage: String {
        switch self {
        case .devTools: return "wrench.and.screwdriver"
        case .aiTools: return "cpu"
        }
    }
}

/// Represents a tool available in the CodeTool application.
public struct Tool: Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let description: String
    public let systemImage: String
    public let category: ToolCategory

    public init(
        id: UUID = UUID(), name: String, description: String, systemImage: String,
        category: ToolCategory = .devTools
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.systemImage = systemImage
        self.category = category
    }
}

/// Provides the default set of developer tools bundled with CodeTool.
/// Additional tools can be registered at launch by appending to `ToolRegistry.defaults`.
public enum ToolRegistry {
    public static var defaults: [Tool] = [
        Tool(
            name: "JSON Tool", description: "Format, validate, minify, and analyze JSON data.",
            systemImage: "curlybraces", category: .devTools),
        Tool(
            name: "Image Converter",
            description: "Convert images between Base64 strings and files.", systemImage: "photo",
            category: .devTools),
        Tool(
            name: "JSON Diff", description: "Compare two JSON objects and find differences.",
            systemImage: "arrow.left.arrow.right", category: .devTools),
        Tool(
            name: "Timestamp Converter",
            description: "Convert between timestamps and human-readable dates.",
            systemImage: "clock", category: .devTools),
        Tool(
            name: "JWT Tool", description: "Encode and decode JWT tokens.", systemImage: "key",
            category: .devTools),
        Tool(
            name: "Word Cloud", description: "Generate word cloud visualizations from text.",
            systemImage: "cloud", category: .devTools),
        Tool(
            name: "AI Chat", description: "Chat with Claude — full agentic capabilities via CLI.",
            systemImage: "bubble.left.and.bubble.right", category: .aiTools),
        Tool(
            name: "AI Speech", description: "Convert text to speech with MiniMax Speech 2.8.",
            systemImage: "waveform", category: .aiTools),
        Tool(
            name: "AI Image", description: "Generate images with MiniMax image-01 model.",
            systemImage: "photo.artframe", category: .aiTools),
        Tool(
            name: "AI Music", description: "Generate music with MiniMax Music-2.5 model.",
            systemImage: "music.note", category: .aiTools),
    ]
}
