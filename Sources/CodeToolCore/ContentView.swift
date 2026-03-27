import SwiftUI

public struct ContentView: View {
    @State private var selectedTool: Tool?
    @State private var retainedToolNames: [String] = []
    private let tools = ToolRegistry.defaults

    private enum Layout {
        static let sidebarWidth: CGFloat = 240
        static let dividerWidth: CGFloat = 10
    }

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            SidebarView(tools: tools, selectedTool: $selectedTool)
                .frame(width: Layout.sidebarWidth)

            SidebarDivider()
                .frame(width: Layout.dividerWidth)

            ToolDetailCacheView(
                tools: tools,
                selectedTool: $selectedTool,
                retainedToolNames: retainedToolNames
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(AppTheme.background)
        .onAppear {
            retainedToolNames = ToolViewCache.retainedToolNames(
                current: retainedToolNames,
                selectedToolName: selectedTool?.name
            )
        }
        .onChange(of: selectedTool?.name) { selectedToolName in
            retainedToolNames = ToolViewCache.retainedToolNames(
                current: retainedToolNames,
                selectedToolName: selectedToolName
            )
        }
    }
}

enum ToolViewCache {
    static func retainedToolNames(current: [String], selectedToolName: String?) -> [String] {
        guard let selectedToolName else {
            return current
        }

        guard !current.contains(selectedToolName) else {
            return current
        }

        return current + [selectedToolName]
    }
}

private struct SidebarDivider: View {
    var body: some View {
        ZStack {
            AppTheme.sidebarBackground.opacity(0.92)

            AppTheme.border
                .frame(width: 1)

            AppTheme.accent.opacity(0.08)
                .frame(width: 1)
                .blur(radius: 3)
        }
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    let tools: [Tool]
    @Binding var selectedTool: Tool?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.md) {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .fill(AppTheme.accentGradient)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(AppTheme.background)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("CodeTool")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Developer utility deck")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                Text("11 tools, one interaction model")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.accentWarm)
                    .textCase(.uppercase)
                    .tracking(1.1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.xxl)
            .padding(.bottom, AppTheme.Spacing.lg)

            ScrollView {
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(tools) { tool in
                        SidebarRow(
                            tool: tool,
                            isSelected: selectedTool == tool,
                            action: { selectedTool = tool }
                        )
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.lg)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("Unified surfaces")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Consistent actions, panels, status chips, and editor treatments across every tool.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppTheme.Spacing.lg)
            .background(AppTheme.surface.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.sidebarBackground)
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let tool: Tool
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.background : AppTheme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .fill(isSelected ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(AppTheme.surfaceRaised))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    Text(tool.navigationTag)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? AppTheme.accentWarm : AppTheme.textMuted)
                        .textCase(.uppercase)
                        .tracking(0.9)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? AppTheme.accentWarm : AppTheme.textMuted.opacity(0.7))
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                    .fill(isSelected
                          ? AnyShapeStyle(AppTheme.selectionGradient)
                          : AnyShapeStyle(isHovered ? AppTheme.surface.opacity(0.72) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                    .strokeBorder(isSelected ? AppTheme.borderHover : AppTheme.border.opacity(isHovered ? 1 : 0), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(AppTheme.accentGradient)
                        .frame(width: 4, height: 28)
                        .offset(x: -6)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(AppTheme.Anim.fast, value: isHovered)
        .animation(AppTheme.Anim.fast, value: isSelected)
    }
}

// MARK: - Tool Detail

private struct ToolDetailCacheView: View {
    let tools: [Tool]
    @Binding var selectedTool: Tool?
    let retainedToolNames: [String]

    var body: some View {
        ZStack {
            WelcomeView(tools: tools, selectedTool: $selectedTool)
                .opacity(selectedTool == nil ? 1 : 0)
                .allowsHitTesting(selectedTool == nil)

            ForEach(cachedTools) { tool in
                ToolDetailView(tool: tool)
                    .opacity(selectedTool == tool ? 1 : 0)
                    .allowsHitTesting(selectedTool == tool)
            }
        }
    }

    private var cachedTools: [Tool] {
        retainedToolNames.compactMap { retainedToolName in
            tools.first { $0.name == retainedToolName }
        }
    }
}

private struct ToolDetailView: View {
    let tool: Tool

    var body: some View {
        Group {
            switch tool.name {
            case "JSON Tool":
                JSONToolView()
            case "Image Converter":
                ImageConverterView()
            case "JSON Diff":
                JSONDiffView()
            case "Timestamp Converter":
                TimestampConverterView()
            case "JWT Tool":
                JWTToolView()
            case "Word Cloud":
                WordCloudView()
            case "AI Chat":
                AIChatView()
            case "AI Speech":
                AISpeechView()
            case "AI Image":
                AIImageView()
            case "AI Music":
                AIMusicView()
            case "MiniMax Settings":
                MiniMaxSettingsView()
            default:
                placeholderView
            }
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: tool.systemImage)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundStyle(AppTheme.accent)
            Text(tool.name)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.textPrimary)
            Text(tool.description)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackdrop())
    }
}

// MARK: - Welcome

private struct WelcomeView: View {
    let tools: [Tool]
    @Binding var selectedTool: Tool?

    @State private var appeared = false

    private let columns = [
        GridItem(.flexible(), spacing: AppTheme.Spacing.lg),
        GridItem(.flexible(), spacing: AppTheme.Spacing.lg)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xxl) {
                Spacer().frame(height: AppTheme.Spacing.xxxl)

                Text("Modern utility cockpit")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.accentWarm)
                    .textCase(.uppercase)
                    .tracking(1.6)

                Text("Eleven tools. One visual language.")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Switch between formatters, converters and analyzers without relearning the interface. Every workspace now shares the same action rhythm, panel geometry and feedback states.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 680)

                HStack(spacing: AppTheme.Spacing.md) {
                    WelcomeMetric(title: "11", subtitle: "Core tools")
                    WelcomeMetric(title: "1", subtitle: "Unified layout")
                    WelcomeMetric(title: "0", subtitle: "Purple gradients")
                }

                LazyVGrid(columns: columns, spacing: AppTheme.Spacing.lg) {
                    ForEach(tools) { tool in
                        ToolCard(tool: tool) {
                            selectedTool = tool
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.xxxl)

                Spacer().frame(height: AppTheme.Spacing.xxl)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackdrop())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(AppTheme.Anim.slow, value: appeared)
        .onAppear { appeared = true }
    }
}

// MARK: - Tool Card

private struct ToolCard: View {
    let tool: Tool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .fill(AppTheme.heroGradient)
                        .frame(width: 42, height: 42)
                        .overlay {
                            Image(systemName: tool.systemImage)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                    Spacer()

                    Text(tool.navigationTag)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.accentWarm)
                        .textCase(.uppercase)
                        .tracking(1.0)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(tool.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(tool.description)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(3)
                }

                HStack {
                    Text("Open workspace")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .padding(AppTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl)
                    .fill(isHovered ? AppTheme.surfaceHover : AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl)
                    .strokeBorder(isHovered ? AppTheme.borderHover : AppTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.18 : 0.10), radius: isHovered ? 26 : 16, y: 10)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(AppTheme.Anim.fast, value: isHovered)
    }
}

private struct WelcomeMetric: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
                .textCase(.uppercase)
                .tracking(1.0)
        }
        .frame(width: 132)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(AppTheme.surface.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
    }
}

private extension Tool {
    var navigationTag: String {
        switch name {
        case "JSON Tool":
            return "Format"
        case "Image Converter":
            return "Convert"
        case "JSON Diff":
            return "Compare"
        case "Timestamp Converter":
            return "Time"
        case "JWT Tool":
            return "Inspect"
        case "Word Cloud":
            return "Visualize"
        case "AI Chat":
            return "Chat"
        case "AI Speech":
            return "Speech"
        case "AI Image":
            return "Image"
        case "AI Music":
            return "Music"
        case "MiniMax Settings":
            return "Config"
        default:
            return "Tool"
        }
    }
}

// MARK: - Previews

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
