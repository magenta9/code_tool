import Foundation

/// Manages MiniMax API provider configuration with UserDefaults persistence.
public final class MiniMaxProvider: ObservableObject {
    public static let shared = MiniMaxProvider()

    private enum Keys {
        static let apiKey = "minimax_api_key"
        static let baseURL = "minimax_base_url"
        static let chatModel = "minimax_chat_model"
        static let speechModel = "minimax_speech_model"
        static let imageModel = "minimax_image_model"
        static let musicModel = "minimax_music_model"
    }

    public struct Defaults {
        public static let baseURL = "https://api.minimaxi.com/v1"
        public static let chatModel = "MiniMax-M2.7"
        public static let speechModel = "speech-2.8-hd"
        public static let imageModel = "image-01"
        public static let musicModel = "music-2.5+"
    }

    @Published public var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: Keys.apiKey) }
    }

    @Published public var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Keys.baseURL) }
    }

    @Published public var chatModel: String {
        didSet { UserDefaults.standard.set(chatModel, forKey: Keys.chatModel) }
    }

    @Published public var speechModel: String {
        didSet { UserDefaults.standard.set(speechModel, forKey: Keys.speechModel) }
    }

    @Published public var imageModel: String {
        didSet { UserDefaults.standard.set(imageModel, forKey: Keys.imageModel) }
    }

    @Published public var musicModel: String {
        didSet { UserDefaults.standard.set(musicModel, forKey: Keys.musicModel) }
    }

    public var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        let defaults = UserDefaults.standard
        self.apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
        self.baseURL = defaults.string(forKey: Keys.baseURL) ?? Defaults.baseURL
        self.chatModel = defaults.string(forKey: Keys.chatModel) ?? Defaults.chatModel
        self.speechModel = defaults.string(forKey: Keys.speechModel) ?? Defaults.speechModel
        self.imageModel = defaults.string(forKey: Keys.imageModel) ?? Defaults.imageModel
        self.musicModel = defaults.string(forKey: Keys.musicModel) ?? Defaults.musicModel
    }

    public func resetToDefaults() {
        baseURL = Defaults.baseURL
        chatModel = Defaults.chatModel
        speechModel = Defaults.speechModel
        imageModel = Defaults.imageModel
        musicModel = Defaults.musicModel
    }
}
