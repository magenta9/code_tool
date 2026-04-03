import CodeToolFoundation
import Foundation
import Observation

/// Immutable snapshot of MiniMax provider configuration.
public struct MiniMaxConfig: Sendable, Equatable {
    public var apiKey: String
    public var baseURL: String
    public var chatModel: String
    public var speechModel: String
    public var imageModel: String
    public var musicModel: String

    public var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static let defaults = MiniMaxConfig(
        apiKey: "",
        baseURL: "https://api.minimaxi.com/v1",
        chatModel: "MiniMax-M2.7",
        speechModel: "speech-2.8-hd",
        imageModel: "image-01",
        musicModel: "music-2.5+"
    )

    public init(
        apiKey: String = "",
        baseURL: String = "https://api.minimaxi.com/v1",
        chatModel: String = "MiniMax-M2.7",
        speechModel: String = "speech-2.8-hd",
        imageModel: String = "image-01",
        musicModel: String = "music-2.5+"
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.chatModel = chatModel
        self.speechModel = speechModel
        self.imageModel = imageModel
        self.musicModel = musicModel
    }
}

/// Manages MiniMax API provider configuration with optional UserDefaults persistence.
@Observable
public final class MiniMaxSettingsStore: UserDefaultsStorage {
    public static let shared = MiniMaxSettingsStore()

    public enum Keys: UserDefaultsStorageKeys {
        static let apiKey = "minimax_api_key"
        static let baseURL = "minimax_base_url"
        static let chatModel = "minimax_chat_model"
        static let speechModel = "minimax_speech_model"
        static let imageModel = "minimax_image_model"
        static let musicModel = "minimax_music_model"
    }

    public let persisting: Bool

    public var apiKey: String {
        didSet { setValue(apiKey, forKey: Keys.apiKey) }
    }

    public var baseURL: String {
        didSet { setValue(baseURL, forKey: Keys.baseURL) }
    }

    public var chatModel: String {
        didSet { setValue(chatModel, forKey: Keys.chatModel) }
    }

    public var speechModel: String {
        didSet { setValue(speechModel, forKey: Keys.speechModel) }
    }

    public var imageModel: String {
        didSet { setValue(imageModel, forKey: Keys.imageModel) }
    }

    public var musicModel: String {
        didSet { setValue(musicModel, forKey: Keys.musicModel) }
    }

    public var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Returns an immutable snapshot of the current configuration.
    public var currentConfig: MiniMaxConfig {
        MiniMaxConfig(
            apiKey: apiKey,
            baseURL: baseURL,
            chatModel: chatModel,
            speechModel: speechModel,
            imageModel: imageModel,
            musicModel: musicModel
        )
    }

    /// Creates a settings store.
    /// - Parameter persisting: When `true` (default), values are read from and written to `UserDefaults`.
    ///   Pass `false` for test isolation so no shared state leaks between runs.
    public init(persisting: Bool = true) {
        self.persisting = persisting
        let defaults = persisting ? UserDefaults.standard : UserDefaults(suiteName: UUID().uuidString)!
        self.apiKey = defaults.string(forKey: Keys.apiKey) ?? MiniMaxConfig.defaults.apiKey
        self.baseURL = defaults.string(forKey: Keys.baseURL) ?? MiniMaxConfig.defaults.baseURL
        self.chatModel = defaults.string(forKey: Keys.chatModel) ?? MiniMaxConfig.defaults.chatModel
        self.speechModel = defaults.string(forKey: Keys.speechModel) ?? MiniMaxConfig.defaults.speechModel
        self.imageModel = defaults.string(forKey: Keys.imageModel) ?? MiniMaxConfig.defaults.imageModel
        self.musicModel = defaults.string(forKey: Keys.musicModel) ?? MiniMaxConfig.defaults.musicModel
    }

    public func resetToDefaults() {
        baseURL = MiniMaxConfig.defaults.baseURL
        chatModel = MiniMaxConfig.defaults.chatModel
        speechModel = MiniMaxConfig.defaults.speechModel
        imageModel = MiniMaxConfig.defaults.imageModel
        musicModel = MiniMaxConfig.defaults.musicModel
    }
}

/// Backward-compatibility alias.
@available(*, deprecated, renamed: "MiniMaxSettingsStore")
public typealias MiniMaxProvider = MiniMaxSettingsStore
