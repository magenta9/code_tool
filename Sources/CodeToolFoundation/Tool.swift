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

/// Stable identity for bundled tools, independent of display text.
public enum ToolID: String, CaseIterable, Codable, Hashable, Sendable {
    case jsonTool
    case imageConverter
    case jsonDiff
    case timestampConverter
    case jwtTool
    case wordCloud
    case aiChat
    case aiSpeech
    case aiImage
    case aiMusic

    /// Presentation-facing route label shown in the sidebar and landing cards.
    public var routeSlug: String {
        switch self {
        case .jsonTool: return "Format"
        case .imageConverter: return "Convert"
        case .jsonDiff: return "Compare"
        case .timestampConverter: return "Time"
        case .jwtTool: return "Inspect"
        case .wordCloud: return "Visualize"
        case .aiChat: return "Chat"
        case .aiSpeech: return "Speech"
        case .aiImage: return "Image"
        case .aiMusic: return "Music"
        }
    }
}

/// Canonical bundled-tool metadata keyed by stable `ToolID`.
public struct ToolCatalogEntry: Identifiable, Hashable {
    public let id: ToolID
    public let title: String
    public let description: String
    public let systemImage: String
    public let category: ToolCategory
    public let routeSlug: String

    public init(
        id: ToolID,
        title: String,
        description: String,
        systemImage: String,
        category: ToolCategory,
        routeSlug: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.systemImage = systemImage
        self.category = category
        self.routeSlug = routeSlug ?? id.routeSlug
    }

    public var tool: Tool {
        Tool(
            toolID: id,
            name: title,
            description: description,
            systemImage: systemImage,
            category: category
        )
    }
}

/// Single source of truth for bundled catalog entries.
public enum ToolCatalog {
    public static let bundled: [ToolCatalogEntry] = [
        ToolCatalogEntry(
            id: .jsonTool,
            title: "JSON Tool",
            description: "Format, validate, minify, and analyze JSON data.",
            systemImage: "curlybraces",
            category: .devTools
        ),
        ToolCatalogEntry(
            id: .imageConverter,
            title: "Image Converter",
            description: "Convert images between Base64 strings and files.",
            systemImage: "photo",
            category: .devTools
        ),
        ToolCatalogEntry(
            id: .jsonDiff,
            title: "JSON Diff",
            description: "Compare two JSON objects and find differences.",
            systemImage: "arrow.left.arrow.right",
            category: .devTools
        ),
        ToolCatalogEntry(
            id: .timestampConverter,
            title: "Timestamp Converter",
            description: "Convert between timestamps and human-readable dates.",
            systemImage: "clock",
            category: .devTools
        ),
        ToolCatalogEntry(
            id: .jwtTool,
            title: "JWT Tool",
            description: "Encode and decode JWT tokens.",
            systemImage: "key",
            category: .devTools
        ),
        ToolCatalogEntry(
            id: .wordCloud,
            title: "Word Cloud",
            description: "Generate word cloud visualizations from text.",
            systemImage: "cloud",
            category: .devTools
        ),
        ToolCatalogEntry(
            id: .aiChat,
            title: "AI Chat",
            description: "Chat with MiniMax using a minimal streaming text workspace.",
            systemImage: "bubble.left.and.bubble.right",
            category: .aiTools
        ),
        ToolCatalogEntry(
            id: .aiSpeech,
            title: "AI Speech",
            description: "Convert text to speech with MiniMax Speech 2.8.",
            systemImage: "waveform",
            category: .aiTools
        ),
        ToolCatalogEntry(
            id: .aiImage,
            title: "AI Image",
            description: "Generate images with MiniMax image-01 model.",
            systemImage: "photo.artframe",
            category: .aiTools
        ),
        ToolCatalogEntry(
            id: .aiMusic,
            title: "AI Music",
            description: "Generate music with MiniMax Music-2.5 model.",
            systemImage: "music.note",
            category: .aiTools
        ),
    ]

    public static var bundledToolIDs: Set<ToolID> {
        Set(bundled.map(\.id))
    }

    public static func entry(for toolID: ToolID) -> ToolCatalogEntry? {
        bundled.first { $0.id == toolID }
    }
}

/// Represents a tool available in the CodeTool application.
public struct Tool: Identifiable, Hashable {
    public let id: UUID
    public let toolID: ToolID?
    public let name: String
    public let description: String
    public let systemImage: String
    public let category: ToolCategory

    public init(
        id: UUID = UUID(), toolID: ToolID? = nil, name: String, description: String,
        systemImage: String, category: ToolCategory = .devTools
    ) {
        self.id = id
        self.toolID = toolID
        self.name = name
        self.description = description
        self.systemImage = systemImage
        self.category = category
    }

    /// Presentation-facing route label; derived from `toolID` when available.
    public var routeSlug: String {
        guard let toolID else {
            return "Tool"
        }

        return ToolCatalog.entry(for: toolID)?.routeSlug ?? toolID.routeSlug
    }
}

/// Provides the default set of developer tools bundled with CodeTool.
/// Additional tools can be registered at launch by appending to `ToolRegistry.defaults`.
public enum ToolRegistry {
    public static var defaults: [Tool] = ToolCatalog.bundled.map(\.tool)

    /// The set of `ToolID`s that have catalog entries in `defaults`.
    public static var bundledToolIDs: Set<ToolID> {
        ToolCatalog.bundledToolIDs
    }
}
