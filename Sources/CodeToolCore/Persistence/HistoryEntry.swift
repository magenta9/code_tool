import Foundation

// MARK: - History Tool Identity

/// Identifies which tool produced a history entry. Raw values match the on-disk directory names.
public enum HistoryToolID: String, CaseIterable, Codable, Sendable {
    case chat
    case claudeChat = "claude-chat"
    case hermesAgent = "hermes-agent"
    case speech
    case image
    case music
    case jsonTool
    case imageConverter
    case jsonDiff
    case timestampConverter
    case jwtTool
    case wordCloud

    /// Convert from the legacy `HistoryCategory` enum.
    public init(_ category: HistoryCategory) {
        switch category {
        case .chat: self = .chat
        case .claudeChat: self = .claudeChat
        case .hermesAgent: self = .hermesAgent
        case .speech: self = .speech
        case .image: self = .image
        case .music: self = .music
        case .jsonTool: self = .jsonTool
        case .imageConverter: self = .imageConverter
        case .jsonDiff: self = .jsonDiff
        case .timestampConverter: self = .timestampConverter
        case .jwtTool: self = .jwtTool
        case .wordCloud: self = .wordCloud
        }
    }

    /// Convert back to the legacy `HistoryCategory`.
    public var category: HistoryCategory {
        switch self {
        case .chat: return .chat
        case .claudeChat: return .claudeChat
        case .hermesAgent: return .hermesAgent
        case .speech: return .speech
        case .image: return .image
        case .music: return .music
        case .jsonTool: return .jsonTool
        case .imageConverter: return .imageConverter
        case .jsonDiff: return .jsonDiff
        case .timestampConverter: return .timestampConverter
        case .jwtTool: return .jwtTool
        case .wordCloud: return .wordCloud
        }
    }
}

// MARK: - History Entry Summary

/// Pre-computed display metadata for a history entry, used by the drawer and list UI.
public struct HistoryEntrySummary: Sendable {
    public let title: String
    public let subtitle: String
    public let icon: String

    public init(title: String, subtitle: String, icon: String) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }
}

// MARK: - History Diagnostics Info

/// Diagnostics-specific metadata extracted from a history entry payload.
public struct HistoryDiagnosticsInfo: Sendable {
    public let title: String
    public let detail: String
    public let sessionID: String?

    public init(title: String, detail: String, sessionID: String? = nil) {
        self.title = title
        self.detail = detail
        self.sessionID = sessionID
    }
}

// MARK: - History Entry

/// Unified runtime envelope for any history record. Not stored on disk directly;
/// assembled at load time by decoding the per-tool record and extracting metadata.
///
/// `HistoryEntry` is a **runtime-only** type — it is not `Codable` and is never serialized.
/// The on-disk format remains the original per-tool record JSON.  The `payloadData` field
/// holds the raw bytes read from (or to be written to) disk, not a base64-encoded blob.
public struct HistoryEntry: Identifiable, Sendable {
    public let id: UUID
    public let toolID: HistoryToolID
    public let createdAt: Date
    public let summary: HistoryEntrySummary
    public let referenceID: String?
    /// Claude chat session ID, surfaced for diagnostics trace correlation.
    public let sessionID: String?
    public let assetFileNames: [String]
    public let diagnosticsInfo: HistoryDiagnosticsInfo?
    /// The raw JSON bytes of the original record, for on-demand payload decoding.
    /// This is the exact content of the `{id}.json` file — not base64-wrapped.
    public let payloadData: Data

    public init(
        id: UUID,
        toolID: HistoryToolID,
        createdAt: Date,
        summary: HistoryEntrySummary,
        referenceID: String? = nil,
        sessionID: String? = nil,
        assetFileNames: [String] = [],
        diagnosticsInfo: HistoryDiagnosticsInfo? = nil,
        payloadData: Data
    ) {
        self.id = id
        self.toolID = toolID
        self.createdAt = createdAt
        self.summary = summary
        self.referenceID = referenceID
        self.sessionID = sessionID
        self.assetFileNames = assetFileNames
        self.diagnosticsInfo = diagnosticsInfo
        self.payloadData = payloadData
    }
}

// MARK: - History Query

/// Parameters for querying history entries.
public struct HistoryQuery: Sendable {
    public let toolID: HistoryToolID?
    public let referenceID: String?
    public let limit: Int?

    public init(toolID: HistoryToolID? = nil, referenceID: String? = nil, limit: Int? = nil) {
        self.toolID = toolID
        self.referenceID = referenceID
        self.limit = limit
    }
}

// MARK: - History Repository Protocol

/// Unified storage API for history entries.
///
/// ## Storage Contract
///
/// - **Upsert semantics**: `upsert` writes to `{entry.id}.json`. Saving an entry whose ID
///   already exists overwrites the previous record.  This matches the legacy behavior
///   that `ClaudeChatView` relies on for conversation-record reuse.
///
/// - **Asset directories**: Most tool assets live alongside the record JSON in the
///   tool's directory.  Claude chat attachments are the exception — they are stored
///   in a separate `claude-chat-attachments/` directory.  `delete` and `clear` handle
///   both locations for `.claudeChat` entries.
///
/// - **Image two-phase commit**: The typed `save(_:ImageHistoryRecord,…)` method on
///   `HistoryStore` writes image data to temp files, commits the JSON, then renames
///   temps to final paths.  The generic `upsert(_:assets:)` method writes
///   assets directly — callers that need atomic semantics should use the typed method.
///
/// - **Error strategy**: `save` and `list` throw on I/O errors.  `delete` is silently
///   idempotent — missing files are ignored (views depend on this).  `clear` removes
///   everything it can, swallowing per-file errors.
///
/// - **Diagnostics**: `diagnosticsMatches` scans all tool categories at query time
///   using codec-defined `diagnosticsInfo`.  Only AI tools (chat, claude-chat, speech,
///   image, music) produce non-nil diagnostics info; dev tools return nil and are
///   skipped.
///
/// - **Sync attachment helpers**: `HistoryStore` exposes `static` (non-actor) helpers
///   `syncSaveClaudeChatAttachment` / `syncClaudeChatAttachmentURL` for main-thread
///   callers that cannot await.  These are outside the `HistoryRepository` protocol.
public protocol HistoryRepository: Sendable {
    /// Upsert an entry with optional binary assets.
    /// Writing an entry whose `id` already exists overwrites the previous file.
    func upsert(_ entry: HistoryEntry, assets: [HistoryAsset]) async throws

    /// List entries matching a query, newest first.
    /// Corrupted JSON files are silently skipped.
    func list(_ query: HistoryQuery) async throws -> [HistoryEntry]

    /// Delete a single entry and its associated assets.
    /// Silently succeeds if the entry does not exist (idempotent).
    func delete(toolID: HistoryToolID, id: UUID) async throws

    /// Load binary data for an asset file in a tool's storage directory.
    func loadAsset(toolID: HistoryToolID, fileName: String) async throws -> Data

    /// Clear all entries for a specific tool.
    /// For `.claudeChat`, also clears the separate attachment directory.
    func clear(toolID: HistoryToolID) async throws

    /// Clear all entries across all tools, including Claude attachments.
    func clearAll() async throws

    /// Count entries for a specific tool.
    func count(toolID: HistoryToolID) async throws -> Int

    /// Find entries matching a reference ID for diagnostics.
    /// Scans all tool categories, computed at query time via codec definitions.
    func diagnosticsMatches(referenceID: String) async throws -> [DiagnosticsHistoryMatch]
}

// MARK: - History Asset

/// A binary asset (audio file, image file) associated with a history entry.
public struct HistoryAsset: Sendable {
    public let fileName: String
    public let data: Data

    public init(fileName: String, data: Data) {
        self.fileName = fileName
        self.data = data
    }
}
