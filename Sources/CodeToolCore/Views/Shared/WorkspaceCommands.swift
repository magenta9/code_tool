import SwiftUI

public struct WorkspaceCommandActions {
    public let showLanding: () -> Void
    public let toggleSidebar: () -> Void

    public init(
        showLanding: @escaping () -> Void = {},
        toggleSidebar: @escaping () -> Void = {}
    ) {
        self.showLanding = showLanding
        self.toggleSidebar = toggleSidebar
    }
}

private struct WorkspaceCommandActionsFocusedValueKey: FocusedValueKey {
    typealias Value = WorkspaceCommandActions
}

public extension FocusedValues {
    var workspaceCommandActions: WorkspaceCommandActions? {
        get { self[WorkspaceCommandActionsFocusedValueKey.self] }
        set { self[WorkspaceCommandActionsFocusedValueKey.self] = newValue }
    }
}