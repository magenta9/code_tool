import CodeToolFoundation
import Foundation
import Observation

@Observable
public final class HermesSettingsStore: UserDefaultsStorage {
    public static let shared = HermesSettingsStore()

    public enum Keys: UserDefaultsStorageKeys {
        static let hermesPath = "hermesAgent_path"
        static let model = "hermesAgent_model"
        static let profile = "hermesAgent_profile"
        static let extraArguments = "hermesAgent_extra_arguments"
        static let capabilityCache = "hermesAgent_capability_cache"
        static let lastProbeError = "hermesAgent_last_probe_error"
    }

    public var hermesPath: String {
        didSet { setValue(hermesPath, forKey: Keys.hermesPath) }
    }
    public var model: String {
        didSet { setValue(model, forKey: Keys.model) }
    }
    public var profile: String {
        didSet { setValue(profile, forKey: Keys.profile) }
    }
    public var extraArguments: String {
        didSet { setValue(extraArguments, forKey: Keys.extraArguments) }
    }

    public private(set) var resolvedHermesPath: String
    public private(set) var capabilityMatrix: HermesCapabilityMatrix? {
        didSet {
            if let capabilityMatrix,
               let data = try? JSONEncoder().encode(capabilityMatrix) {
                setValue(data, forKey: Keys.capabilityCache)
            } else {
                setValue(nil, forKey: Keys.capabilityCache)
            }
        }
    }
    public private(set) var lastProbeError: String {
        didSet { setValue(lastProbeError, forKey: Keys.lastProbeError) }
    }

    public var isAvailable: Bool {
        capabilityMatrix != nil
    }

    public var resolvedModelOrProfile: String? {
        if let capabilityMatrix, capabilityMatrix.supportsProfileFlag {
            let trimmedProfile = profile.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedProfile.isEmpty {
                return trimmedProfile
            }
        }

        if let capabilityMatrix, capabilityMatrix.supportsModelFlag {
            let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedModel.isEmpty {
                return trimmedModel
            }
        }

        return nil
    }

    public var parsedExtraArguments: [String] {
        extraArguments
            .split(whereSeparator: \ .isWhitespace)
            .map(String.init)
    }

    private init() {
        let defaults = UserDefaults.standard
        hermesPath = defaults.string(forKey: Keys.hermesPath) ?? ""
        model = defaults.string(forKey: Keys.model) ?? ""
        profile = defaults.string(forKey: Keys.profile) ?? ""
        extraArguments = defaults.string(forKey: Keys.extraArguments) ?? ""
        lastProbeError = defaults.string(forKey: Keys.lastProbeError) ?? ""
        resolvedHermesPath = ""

        if let data = defaults.data(forKey: Keys.capabilityCache),
           let cachedMatrix = try? JSONDecoder().decode(HermesCapabilityMatrix.self, from: data) {
            capabilityMatrix = cachedMatrix
            resolvedHermesPath = cachedMatrix.binaryPath
        } else {
            capabilityMatrix = nil
        }
    }

    public func discoverCLI() {
        let result = HermesCLIContractProbe.probe(customPath: hermesPath)
        resolvedHermesPath = result.resolvedBinaryPath
        capabilityMatrix = result.capabilityMatrix
        lastProbeError = result.errorMessage ?? ""
    }

    public func resetToDefaults() {
        hermesPath = ""
        model = ""
        profile = ""
        extraArguments = ""
        lastProbeError = ""
        capabilityMatrix = nil
        resolvedHermesPath = ""
    }
}

struct HermesSettingsDraft: Equatable {
    var hermesPath: String
    var model: String
    var profile: String
    var extraArguments: String

    init(
        hermesPath: String = "",
        model: String = "",
        profile: String = "",
        extraArguments: String = ""
    ) {
        self.hermesPath = hermesPath
        self.model = model
        self.profile = profile
        self.extraArguments = extraArguments
    }

    init(store: HermesSettingsStore) {
        self.init(
            hermesPath: store.hermesPath,
            model: store.model,
            profile: store.profile,
            extraArguments: store.extraArguments
        )
    }

    mutating func reload(from store: HermesSettingsStore) {
        self = HermesSettingsDraft(store: store)
    }

    func apply(to store: HermesSettingsStore) {
        store.hermesPath = hermesPath
        store.model = model
        store.profile = profile
        store.extraArguments = extraArguments
    }
}