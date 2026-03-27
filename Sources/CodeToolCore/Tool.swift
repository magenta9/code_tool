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
/// Additional tools can be registered at launch by appending to `ToolRegistry.defaults`.
public enum ToolRegistry {
    public static var defaults: [Tool] = [
        Tool(name: "JSON Tool", description: "Format, validate, minify, and analyze JSON data.", systemImage: "curlybraces"),
        Tool(name: "Image Converter", description: "Convert images between Base64 strings and files.", systemImage: "photo"),
        Tool(name: "JSON Diff", description: "Compare two JSON objects and find differences.", systemImage: "arrow.left.arrow.right"),
        Tool(name: "Timestamp Converter", description: "Convert between timestamps and human-readable dates.", systemImage: "clock"),
        Tool(name: "JWT Tool", description: "Encode and decode JWT tokens.", systemImage: "key"),
        Tool(name: "Word Cloud", description: "Generate word cloud visualizations from text.", systemImage: "cloud"),
        Tool(name: "AI Chat", description: "Chat with MiniMax M2.7-highspeed AI model.", systemImage: "bubble.left.and.bubble.right"),
        Tool(name: "AI Speech", description: "Convert text to speech with MiniMax Speech 2.8.", systemImage: "waveform"),
        Tool(name: "AI Image", description: "Generate images with MiniMax image-01 model.", systemImage: "photo.artframe"),
        Tool(name: "AI Music", description: "Generate music with MiniMax Music-2.5 model.", systemImage: "music.note"),
        Tool(name: "MiniMax Settings", description: "Configure MiniMax API provider settings.", systemImage: "gearshape.2")
    ]
}
