import Foundation

public struct ClaudeConfigReader {
    private static let modelEnvKeys = [
        "ANTHROPIC_MODEL",
        "ANTHROPIC_SMALL_FAST_MODEL",
        "ANTHROPIC_DEFAULT_SONNET_MODEL",
        "ANTHROPIC_DEFAULT_OPUS_MODEL",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL",
    ]

    private let fileManager: FileManager
    private let settingsURL: URL

    public init(
        fileManager: FileManager = .default,
        settingsURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.settingsURL = settingsURL
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("settings.json", isDirectory: false)
    }

    public func availableModels() -> [String] {
        guard fileManager.fileExists(atPath: settingsURL.path),
              let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(ClaudeSettings.self, from: data),
              let env = settings.env
        else {
            return []
        }

        var models: [String] = []
        var seen = Set<String>()

        for key in Self.modelEnvKeys {
            guard let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  seen.insert(value).inserted
            else {
                continue
            }

            models.append(value)
        }

        return models
    }
}

private struct ClaudeSettings: Decodable {
    let env: [String: String]?
}
