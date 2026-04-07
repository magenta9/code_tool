import CodeToolFoundation
import SwiftUI

enum ToolVisibilityPolicy: String, Sendable {
    case keepAliveOnHide
    case pauseOnHide
    case unloadOnHide
}

struct ToolVisibilityContext: Sendable {
    var toolID: ToolID?
    var isVisible: Bool
    var policy: ToolVisibilityPolicy

    var isPausedWhileHidden: Bool {
        !isVisible && policy == .pauseOnHide
    }

    var shouldUnloadWhenHidden: Bool {
        !isVisible && policy == .unloadOnHide
    }
}

enum ToolVisibilityPolicyRegistry {
    private static let pausedToolIDs: Set<ToolID> = [.aiChat, .aiSpeech, .aiImage, .aiMusic]

    static func policy(for toolID: ToolID?) -> ToolVisibilityPolicy {
        guard let toolID else {
            return .keepAliveOnHide
        }

        return pausedToolIDs.contains(toolID) ? .pauseOnHide : .keepAliveOnHide
    }
}

struct ToolVisibilityState {
    let selectedToolID: ToolID?

    func isVisible(toolID: ToolID?) -> Bool {
        guard let selectedToolID, let toolID else {
            return false
        }

        return selectedToolID == toolID
    }

    func context(for toolID: ToolID?) -> ToolVisibilityContext {
        ToolVisibilityContext(
            toolID: toolID,
            isVisible: isVisible(toolID: toolID),
            policy: ToolVisibilityPolicyRegistry.policy(for: toolID)
        )
    }
}

private struct ToolVisibilityContextEnvironmentKey: EnvironmentKey {
    static let defaultValue = ToolVisibilityContext(
        toolID: nil,
        isVisible: true,
        policy: .keepAliveOnHide
    )
}

extension EnvironmentValues {
    var toolVisibilityContext: ToolVisibilityContext {
        get { self[ToolVisibilityContextEnvironmentKey.self] }
        set { self[ToolVisibilityContextEnvironmentKey.self] = newValue }
    }

    var isToolVisible: Bool {
        get { toolVisibilityContext.isVisible }
        set {
            var context = toolVisibilityContext
            context.isVisible = newValue
            toolVisibilityContext = context
        }
    }
}