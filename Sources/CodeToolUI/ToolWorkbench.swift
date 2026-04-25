import SwiftUI

public struct ToolStatusItem: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let tint: Color
    public let help: String?
    public let accessibilityLabel: String?
    public let action: (() -> Void)?

    public init(
        id: String = UUID().uuidString,
        title: String,
        systemImage: String,
        tint: Color = AppTheme.accent,
        help: String? = nil,
        accessibilityLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.help = help
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }
}

public struct ToolWorkbench<Actions: View, Content: View>: View {
    let eyebrow: String
    let title: String
    let description: String
    let systemImage: String
    let statusItems: [ToolStatusItem]
    let actions: Actions
    let content: Content

    public init(
        eyebrow: String,
        title: String,
        description: String,
        systemImage: String,
        statusItems: [ToolStatusItem] = [],
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.description = description
        self.systemImage = systemImage
        self.statusItems = statusItems
        self.actions = actions()
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .themedToolView()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.md) {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .fill(AppTheme.accentGradient)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: systemImage)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                                .strokeBorder(AppTheme.accentBright.opacity(0.34), lineWidth: 1)
                        )
                        .shadow(color: AppTheme.accent.opacity(0.20), radius: 8, y: 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(eyebrow)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textMuted)
                            .textCase(.uppercase)
                            .tracking(1.1)

                        Text(title)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(description)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: AppTheme.Spacing.lg)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppTheme.Spacing.sm) { actions }
                    VStack(alignment: .trailing, spacing: AppTheme.Spacing.sm) { actions }
                }
            }

            if !statusItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        ForEach(statusItems) { item in
                            statusItemView(item)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.vertical, AppTheme.Spacing.lg)
        .glassSurface(cornerRadius: AppTheme.Radius.xxl, tint: AppTheme.panelTintStrong, stroke: AppTheme.borderHover, shadowOpacity: 0.08)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.top, AppTheme.Spacing.lg)
    }

    @ViewBuilder
    private func statusItemView(_ item: ToolStatusItem) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
        let badge = Label(item.title, systemImage: item.systemImage)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(item.tint)
            .padding(.horizontal, AppTheme.Spacing.sm + 2)
            .padding(.vertical, AppTheme.Spacing.xs + 2)
            .background {
                shape.fill(item.tint.opacity(0.095))
            }
            .overlay(shape.strokeBorder(item.tint.opacity(0.24), lineWidth: 1))

        if let action = item.action {
            Button(action: action) {
                badge
            }
            .buttonStyle(.plain)
            .contentShape(shape)
            .help(item.help ?? "")
            .accessibilityLabel(item.accessibilityLabel ?? item.title)
        } else {
            badge
                .help(item.help ?? "")
                .accessibilityLabel(item.accessibilityLabel ?? item.title)
        }
    }
}

public struct ToolMessageBanner: View {
    let systemImage: String
    let message: String
    let tint: Color

    public init(systemImage: String, message: String, tint: Color) {
        self.systemImage = systemImage
        self.message = message
        self.tint = tint
    }

    public var body: some View {
        Label(message, systemImage: systemImage)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: AppTheme.Radius.lg, tint: tint.opacity(0.12), stroke: tint.opacity(0.22), shadowOpacity: 0.05)
    }
}
