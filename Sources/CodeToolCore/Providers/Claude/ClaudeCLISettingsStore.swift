import CodeToolFoundation
import Foundation
import Observation

@Observable
public final class ClaudeCLISettingsStore: UserDefaultsStorage {
    public static let shared = ClaudeCLISettingsStore()
    public static let fallbackModels = [
        "claude-sonnet-4-20250514",
        "claude-opus-4-20250514",
        "claude-haiku-3-5-20241022",
    ]
    public static let defaultPermissionMode: ClaudeCLIPermissionMode = .bypassPermissions

    public enum Keys: UserDefaultsStorageKeys {
        static let claudePath = "claudeCLI_path"
        static let apiKey = "claudeCLI_api_key"
        static let model = "claudeCLI_model"
        static let systemPrompt = "claudeCLI_system_prompt"
        static let maxTurns = "claudeCLI_max_turns"
        static let maxBudgetUSD = "claudeCLI_max_budget_usd"
        static let useBare = "claudeCLI_use_bare"
        static let permissionMode = "claudeCLI_permission_mode"
    }

    public var claudePath: String {
        didSet { setValue(claudePath, forKey: Keys.claudePath) }
    }
    public var apiKey: String {
        didSet { setValue(apiKey, forKey: Keys.apiKey) }
    }
    public var model: String {
        didSet {
            setValue(model, forKey: Keys.model)
            availableModels = Self.resolvedModels(
                discoveredModels: discoveredModels,
                currentModel: model
            )
        }
    }
    public var systemPrompt: String {
        didSet { setValue(systemPrompt, forKey: Keys.systemPrompt) }
    }
    public var maxTurns: Int {
        didSet { setValue(maxTurns, forKey: Keys.maxTurns) }
    }
    public var maxBudgetUSD: Double {
        didSet { setValue(maxBudgetUSD, forKey: Keys.maxBudgetUSD) }
    }
    public var useBare: Bool {
        didSet { setValue(useBare, forKey: Keys.useBare) }
    }
    public var permissionMode: ClaudeCLIPermissionMode {
        didSet { setValue(permissionMode.rawValue, forKey: Keys.permissionMode) }
    }

    /// Whether a valid claude binary has been discovered
    public var isAvailable: Bool { !resolvedClaudePath.isEmpty }

    /// Resolved path after discovery
    public var resolvedClaudePath: String = ""
    public private(set) var availableModels: [String]
    public private(set) var isUsingFallbackModels: Bool

    private var discoveredModels: [String]

    private init() {
        let defaults = UserDefaults.standard
        self.claudePath = defaults.string(forKey: Keys.claudePath) ?? ""
        self.apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
        self.model = defaults.string(forKey: Keys.model) ?? Self.fallbackModels[0]
        self.systemPrompt = defaults.string(forKey: Keys.systemPrompt) ?? ""
        self.maxTurns = defaults.object(forKey: Keys.maxTurns) as? Int ?? 10
        self.maxBudgetUSD = defaults.object(forKey: Keys.maxBudgetUSD) as? Double ?? 5.0
        self.useBare = defaults.object(forKey: Keys.useBare) as? Bool ?? true
        self.permissionMode =
            ClaudeCLIPermissionMode(
                rawValue: defaults.string(forKey: Keys.permissionMode) ?? ""
            ) ?? Self.defaultPermissionMode
        self.discoveredModels = []
        self.availableModels = Self.fallbackModels
        self.isUsingFallbackModels = true
        refreshAvailableModels()
    }

    /// Discover claude binary. Call on app launch or settings change.
    public func discoverCLI() {
        let searchPaths: [String]
        if !claudePath.isEmpty {
            searchPaths = [claudePath]
        } else {
            searchPaths = [
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
                NSHomeDirectory() + "/.local/bin/claude",
                NSHomeDirectory() + "/.claude/local/claude",
            ]
        }

        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                resolvedClaudePath = path
                return
            }
        }

        // Fallback: which claude
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
                    resolvedClaudePath = path
                    return
                }
            }
        } catch {}

        resolvedClaudePath = ""
    }

    public func resetToDefaults() {
        claudePath = ""
        apiKey = ""
        model = Self.fallbackModels[0]
        systemPrompt = ""
        maxTurns = 10
        maxBudgetUSD = 5.0
        useBare = true
        permissionMode = Self.defaultPermissionMode
        discoverCLI()
        refreshAvailableModels()
    }

    public func refreshAvailableModels() {
        let discoveredModels = ClaudeConfigReader().availableModels()
        self.discoveredModels = discoveredModels
        isUsingFallbackModels = discoveredModels.isEmpty
        availableModels = Self.resolvedModels(
            discoveredModels: discoveredModels,
            currentModel: model
        )
    }

    private static func resolvedModels(
        discoveredModels: [String],
        currentModel: String
    ) -> [String] {
        var models = discoveredModels.isEmpty ? fallbackModels : discoveredModels
        let trimmedCurrentModel = currentModel.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedCurrentModel.isEmpty && !models.contains(trimmedCurrentModel) {
            models.insert(trimmedCurrentModel, at: 0)
        }

        return models
    }
}

public enum ClaudeCLIPermissionMode: String, CaseIterable, Identifiable {
    case auto
    case `default`
    case acceptEdits
    case dontAsk
    case bypassPermissions
    case plan

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .default:
            return "Default"
        case .acceptEdits:
            return "Accept Edits"
        case .dontAsk:
            return "Don't Ask"
        case .bypassPermissions:
            return "Bypass Permissions"
        case .plan:
            return "Plan"
        }
    }

    var summary: String {
        switch self {
        case .auto:
            return "Auto-approve only low-risk tools. MCP calls may still be blocked in print mode."
        case .default:
            return "Use Claude's default permission checks."
        case .acceptEdits:
            return "Allow edits without prompts, but still gate higher-risk tools."
        case .dontAsk:
            return "Deny anything that is not already pre-approved."
        case .bypassPermissions:
            return "Recommended for AI Chat. Run tools without approval prompts in this trusted workspace."
        case .plan:
            return "Planning-oriented mode that avoids executing tools."
        }
    }
}
