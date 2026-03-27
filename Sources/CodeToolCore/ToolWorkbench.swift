import SwiftUI

public struct ToolStatusItem: Identifiable {
    public let id = UUID()
    public let title: String
    public let systemImage: String
    public let tint: Color

    public init(title: String, systemImage: String, tint: Color = AppTheme.accent) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                HStack(spacing: AppTheme.Spacing.md) {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                        .fill(AppTheme.heroGradient)
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: systemImage)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        Text(eyebrow)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.accentWarm)
                            .textCase(.uppercase)
                            .tracking(1.4)

                        Text(title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(description)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 24)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        actions
                    }
                    VStack(alignment: .trailing, spacing: AppTheme.Spacing.sm) {
                        actions
                    }
                }
            }

            if !statusItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(statusItems) { item in
                            Label(item.title, systemImage: item.systemImage)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(item.tint)
                                .padding(.horizontal, AppTheme.Spacing.md)
                                .padding(.vertical, AppTheme.Spacing.sm)
                                .background(item.tint.opacity(0.10))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(item.tint.opacity(0.25), lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xxl)
        .padding(.top, AppTheme.Spacing.xxl)
        .padding(.bottom, AppTheme.Spacing.xl)
        .background(Color.black.opacity(0.10))
        .overlay(alignment: .bottom) {
            AppTheme.border.frame(height: 1)
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
            .background(tint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 1)
            )
    }
}