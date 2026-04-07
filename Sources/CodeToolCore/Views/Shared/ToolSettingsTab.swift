import SwiftUI

enum ToolSettingsTab: String, CaseIterable, Hashable {
    case minimax
    case claude
    case hermes
    case diagnostics

    var title: String {
        switch self {
        case .minimax:
            return "MiniMax"
        case .claude:
            return "Claude CLI"
        case .hermes:
            return "Hermes"
        case .diagnostics:
            return "Diagnostics"
        }
    }
}

struct ToolSettingsPresenter {
    let open: (ToolSettingsTab) -> Void

    init(open: @escaping (ToolSettingsTab) -> Void = { _ in }) {
        self.open = open
    }
}

private struct ToolSettingsPresenterEnvironmentKey: EnvironmentKey {
    static let defaultValue = ToolSettingsPresenter()
}

extension EnvironmentValues {
    var toolSettingsPresenter: ToolSettingsPresenter {
        get { self[ToolSettingsPresenterEnvironmentKey.self] }
        set { self[ToolSettingsPresenterEnvironmentKey.self] = newValue }
    }
}