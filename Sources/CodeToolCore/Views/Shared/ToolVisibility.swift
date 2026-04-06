import CodeToolFoundation
import SwiftUI

struct ToolVisibilityState {
    let selectedToolID: ToolID?

    func isVisible(toolID: ToolID?) -> Bool {
        guard let selectedToolID, let toolID else {
            return false
        }

        return selectedToolID == toolID
    }
}

private struct ToolVisibilityEnvironmentKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var isToolVisible: Bool {
        get { self[ToolVisibilityEnvironmentKey.self] }
        set { self[ToolVisibilityEnvironmentKey.self] = newValue }
    }
}