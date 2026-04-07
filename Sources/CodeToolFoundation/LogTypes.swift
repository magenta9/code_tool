import Foundation

/// Log severity levels used across the application.
public enum AppLogLevel: String, Codable, Sendable {
    case fault
    case error
    case info
    case debug
    case trace
}

/// Log categories corresponding to each feature area.
public enum AppLogCategory: String, Codable, Sendable {
    case aimusic
    case aispeech
    case aiimage
    case aichat
    case claudechat
    case hermesagent
    case observability
}
