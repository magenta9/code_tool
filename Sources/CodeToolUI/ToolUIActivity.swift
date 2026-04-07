import SwiftUI

public struct ToolUIActivity: Sendable, Equatable {
    public var isVisible: Bool

    public init(isVisible: Bool = true) {
        self.isVisible = isVisible
    }

    public var allowsInteractiveEffects: Bool {
        isVisible
    }

    public var allowsDecorativeAnimations: Bool {
        isVisible
    }
}

private struct ToolUIActivityEnvironmentKey: EnvironmentKey {
    static let defaultValue = ToolUIActivity()
}

public extension EnvironmentValues {
    var toolUIActivity: ToolUIActivity {
        get { self[ToolUIActivityEnvironmentKey.self] }
        set { self[ToolUIActivityEnvironmentKey.self] = newValue }
    }
}

private struct ToolHoverTrackingModifier: ViewModifier {
    @Environment(\.toolUIActivity) private var toolUIActivity
    @Binding var isHovered: Bool
    let animation: Animation?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard toolUIActivity.allowsInteractiveEffects else {
                    if isHovered {
                        isHovered = false
                    }
                    return
                }

                if let animation {
                    withAnimation(animation) {
                        isHovered = hovering
                    }
                } else {
                    isHovered = hovering
                }
            }
            .onChange(of: toolUIActivity.isVisible) { _, isVisible in
                guard !isVisible, isHovered else {
                    return
                }

                isHovered = false
            }
    }
}

public extension View {
    func toolHoverTracking(_ isHovered: Binding<Bool>, animation: Animation? = AppTheme.Anim.fast)
        -> some View
    {
        modifier(ToolHoverTrackingModifier(isHovered: isHovered, animation: animation))
    }
}