import SwiftUI

public struct ContentView: View {
    @State private var selectedTool: Tool?
    @State private var retainedToolNames: [String] = []
    @State private var sidebarCollapsed = false
    private let tools = ToolRegistry.defaults

    private enum Layout {
        static let sidebarWidth: CGFloat = 240
        static let sidebarCollapsedWidth: CGFloat = 64
        static let dividerWidth: CGFloat = 10
    }

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            SidebarView(tools: tools, selectedTool: $selectedTool, collapsed: $sidebarCollapsed)
                .frame(width: sidebarCollapsed ? Layout.sidebarCollapsedWidth : Layout.sidebarWidth)

            SidebarDivider(collapsed: $sidebarCollapsed)
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
        .background {
            // Invisible button to capture ⌘\ keyboard shortcut
            Button("") {
                withAnimation(AppTheme.Anim.normal) {
                    sidebarCollapsed.toggle()
                }
            }
            .keyboardShortcut("\\", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        }
        .onAppear {
            retainedToolNames = ToolViewCache.retainedToolNames(
                current: retainedToolNames,
                selectedToolName: selectedTool?.name
            )
        }
        .onChange(of: selectedTool?.name) { _, selectedToolName in
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
    @Binding var collapsed: Bool
    @State private var isHovered = false

    var body: some View {
        ZStack {
            AppTheme.sidebarBackground.opacity(0.92)

            AppTheme.border
                .frame(width: 1)

            AppTheme.accent.opacity(0.08)
                .frame(width: 1)
                .blur(radius: 3)

            // Toggle button overlay
            if isHovered {
                Button {
                    withAnimation(AppTheme.Anim.normal) {
                        collapsed.toggle()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(AppTheme.surfaceRaised)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .strokeBorder(AppTheme.borderHover, lineWidth: 1)
                            )
                        Image(systemName: collapsed ? "chevron.right" : "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(AppTheme.Anim.fast) { isHovered = hovering }
        }
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    let tools: [Tool]
    @Binding var selectedTool: Tool?
    @Binding var collapsed: Bool

    @State private var logoHovered = false
    @State private var showSettings = false

    private var groupedTools: [(category: ToolCategory, tools: [Tool])] {
        ToolCategory.allCases.compactMap { category in
            let matched = tools.filter { $0.category == category }
            return matched.isEmpty ? nil : (category, matched)
        }
    }

    @State private var toggleHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Logo / Home button + toggle
            HStack(spacing: 0) {
                Button {
                    selectedTool = nil
                } label: {
                    if collapsed {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .fill(AppTheme.accentGradient)
                            .frame(width: 36, height: 36)
                            .overlay {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(AppTheme.background)
                            }
                            .scaleEffect(logoHovered ? 1.06 : 1.0)
                    } else {
                        HStack(spacing: AppTheme.Spacing.md) {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                .fill(AppTheme.accentGradient)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(AppTheme.background)
                                }
                                .scaleEffect(logoHovered ? 1.06 : 1.0)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("CodeTool")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text("Developer utility deck")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .onHover { logoHovered = $0 }
                .animation(AppTheme.Anim.fast, value: logoHovered)

                if !collapsed {
                    Spacer(minLength: 0)
                }

                // Sidebar toggle button
                if !collapsed {
                    Button {
                        withAnimation(AppTheme.Anim.normal) {
                            collapsed.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(toggleHovered ? AppTheme.accent : AppTheme.textMuted)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                    .fill(toggleHovered ? AppTheme.surface.opacity(0.72) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                    .strokeBorder(toggleHovered ? AppTheme.borderHover : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { h in withAnimation(AppTheme.Anim.fast) { toggleHovered = h } }
                    .help("收起侧边栏 (⌘\\)")
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .padding(.horizontal, collapsed ? AppTheme.Spacing.sm : AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.xxl)
            .padding(.bottom, AppTheme.Spacing.lg)

            // Collapsed: show expand button
            if collapsed {
                Button {
                    withAnimation(AppTheme.Anim.normal) {
                        collapsed.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(toggleHovered ? AppTheme.accent : AppTheme.textMuted)
                        .frame(width: 36, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .fill(toggleHovered ? AppTheme.surface.opacity(0.72) : AppTheme.surface.opacity(0.32))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .strokeBorder(toggleHovered ? AppTheme.borderHover : AppTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .onHover { h in withAnimation(AppTheme.Anim.fast) { toggleHovered = h } }
                .help("展开侧边栏 (⌘\\)")
                .padding(.bottom, AppTheme.Spacing.sm)
            }

            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    ForEach(groupedTools, id: \.category) { group in
                        VStack(alignment: collapsed ? .center : .leading, spacing: AppTheme.Spacing.sm) {
                            if collapsed {
                                Divider()
                                    .background(AppTheme.border)
                                    .padding(.horizontal, AppTheme.Spacing.sm)
                            } else {
                                HStack(spacing: AppTheme.Spacing.sm) {
                                    Image(systemName: group.category.systemImage)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(AppTheme.textMuted)
                                    Text(group.category.displayName)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(AppTheme.textMuted)
                                        .textCase(.uppercase)
                                        .tracking(1.2)
                                }
                                .padding(.horizontal, AppTheme.Spacing.md + 4)
                            }

                            ForEach(group.tools) { tool in
                                SidebarRow(
                                    tool: tool,
                                    isSelected: selectedTool == tool,
                                    collapsed: collapsed,
                                    action: { selectedTool = tool }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, collapsed ? AppTheme.Spacing.xs : AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.lg)
            }

            if collapsed {
                // Collapsed: show only settings gear
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                .fill(AppTheme.surface.opacity(0.62))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                .strokeBorder(AppTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("MiniMax Settings")
                .padding(.bottom, AppTheme.Spacing.lg)
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    HStack {
                        Text("Unified surfaces")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("MiniMax Settings")
                    }
                    Text(
                        "Consistent actions, panels, status chips, and editor treatments across every tool."
                    )
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.sidebarBackground)
        .sheet(isPresented: $showSettings) {
            MiniMaxSettingsSheet()
        }
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let tool: Tool
    let isSelected: Bool
    var collapsed: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            if collapsed {
                // Collapsed: icon only
                Image(systemName: tool.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.background : AppTheme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .fill(
                                isSelected
                                    ? AnyShapeStyle(AppTheme.accentGradient)
                                    : AnyShapeStyle(
                                        isHovered ? AppTheme.surface.opacity(0.72) : AppTheme.surfaceRaised))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .strokeBorder(
                                isSelected
                                    ? AppTheme.borderHover : AppTheme.border.opacity(isHovered ? 1 : 0),
                                lineWidth: 1)
                    )
            } else {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: tool.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? AppTheme.background : AppTheme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                .fill(
                                    isSelected
                                        ? AnyShapeStyle(AppTheme.accentGradient)
                                        : AnyShapeStyle(AppTheme.surfaceRaised))
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
                        .foregroundStyle(
                            isSelected ? AppTheme.accentWarm : AppTheme.textMuted.opacity(0.7))
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                        .fill(
                            isSelected
                                ? AnyShapeStyle(AppTheme.selectionGradient)
                                : AnyShapeStyle(
                                    isHovered ? AppTheme.surface.opacity(0.72) : Color.clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                        .strokeBorder(
                            isSelected
                                ? AppTheme.borderHover : AppTheme.border.opacity(isHovered ? 1 : 0),
                            lineWidth: 1)
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
        }
        .buttonStyle(.plain)
        .help(collapsed ? tool.name : "")
        .onHover { hovering in withAnimation(AppTheme.Anim.fast) { isHovered = hovering } }
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
                .foregroundStyle(AppTheme.textPrimary)
            Text(tool.description)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackdrop())
    }
}

// MARK: - Welcome / Landing Page

private struct WelcomeView: View {
    let tools: [Tool]
    @Binding var selectedTool: Tool?

    @State private var appeared = false
    @State private var heroAnimated = false
    @State private var cardsAnimated = false

    private var devTools: [Tool] { tools.filter { $0.category == .devTools } }
    private var aiTools: [Tool] { tools.filter { $0.category == .aiTools } }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Hero Section
                heroSection
                    .padding(.bottom, AppTheme.Spacing.xxxl)

                // Dev Tools Section
                toolGroupSection(
                    eyebrow: "Essentials",
                    title: "Dev Tools",
                    subtitle: "Formatters, converters, and analyzers built for daily workflows.",
                    icon: "wrench.and.screwdriver",
                    accentColor: AppTheme.accent,
                    tools: devTools,
                    columns: 3,
                    delayBase: 0
                )
                .padding(.bottom, 56)

                // AI Tools Section
                toolGroupSection(
                    eyebrow: "Intelligence",
                    title: "AI Tools",
                    subtitle: "Chat, speech, image, and music powered by MiniMax.",
                    icon: "cpu",
                    accentColor: AppTheme.accentWarm,
                    tools: aiTools,
                    columns: 2,
                    delayBase: 6
                )
                .padding(.bottom, 56)

                // Footer
                footerSection
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackdrop())
        .opacity(appeared ? 1 : 0)
        .animation(AppTheme.Anim.slow, value: appeared)
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                heroAnimated = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                cardsAnimated = true
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer().frame(height: 60)

            // Decorative top line
            HStack(spacing: AppTheme.Spacing.md) {
                Rectangle()
                    .fill(AppTheme.accentGradient)
                    .frame(width: heroAnimated ? 48 : 0, height: 2)
                    .animation(.easeOut(duration: 0.6).delay(0.2), value: heroAnimated)

                Text("CodeTool")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(AppTheme.textMuted)
                    .textCase(.uppercase)
                    .tracking(3)
                    .opacity(heroAnimated ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.3), value: heroAnimated)

                Rectangle()
                    .fill(AppTheme.accentGradient)
                    .frame(width: heroAnimated ? 48 : 0, height: 2)
                    .animation(.easeOut(duration: 0.6).delay(0.2), value: heroAnimated)
            }

            // Main headline with gradient text
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("Your developer")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .opacity(heroAnimated ? 1 : 0)
                    .offset(y: heroAnimated ? 0 : 20)
                    .animation(.spring(duration: 0.5, bounce: 0.1).delay(0.1), value: heroAnimated)

                Text("utility cockpit.")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.accentGradient)
                    .opacity(heroAnimated ? 1 : 0)
                    .offset(y: heroAnimated ? 0 : 20)
                    .animation(.spring(duration: 0.5, bounce: 0.1).delay(0.2), value: heroAnimated)
            }

            Text("Ten tools. Two categories. One unified language.")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .opacity(heroAnimated ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.4), value: heroAnimated)

            // Stats row
            HStack(spacing: AppTheme.Spacing.xl) {
                LandingMetric(
                    value: "\(devTools.count)", label: "Dev Tools", color: AppTheme.accent
                )
                .opacity(heroAnimated ? 1 : 0)
                .offset(y: heroAnimated ? 0 : 12)
                .animation(.spring(duration: 0.4, bounce: 0.1).delay(0.45), value: heroAnimated)

                // Divider dot
                Circle()
                    .fill(AppTheme.textMuted.opacity(0.4))
                    .frame(width: 4, height: 4)

                LandingMetric(
                    value: "\(aiTools.count)", label: "AI Tools", color: AppTheme.accentWarm
                )
                .opacity(heroAnimated ? 1 : 0)
                .offset(y: heroAnimated ? 0 : 12)
                .animation(.spring(duration: 0.4, bounce: 0.1).delay(0.55), value: heroAnimated)

                Circle()
                    .fill(AppTheme.textMuted.opacity(0.4))
                    .frame(width: 4, height: 4)

                LandingMetric(value: "1", label: "Unified Layout", color: AppTheme.accentCoral)
                    .opacity(heroAnimated ? 1 : 0)
                    .offset(y: heroAnimated ? 0 : 12)
                    .animation(.spring(duration: 0.4, bounce: 0.1).delay(0.65), value: heroAnimated)
            }
            .padding(.top, AppTheme.Spacing.sm)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tool Group Section

    private func toolGroupSection(
        eyebrow: String,
        title: String,
        subtitle: String,
        icon: String,
        accentColor: Color,
        tools: [Tool],
        columns: Int,
        delayBase: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            // Section header
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accentColor)
                    Text(eyebrow)
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(accentColor)
                        .textCase(.uppercase)
                        .tracking(2)

                    Rectangle()
                        .fill(accentColor.opacity(0.25))
                        .frame(height: 1)
                }

                Text(title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            // Tool cards grid
            let gridColumns = Array(
                repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.lg), count: columns)
            LazyVGrid(columns: gridColumns, spacing: AppTheme.Spacing.lg) {
                ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                    LandingToolCard(tool: tool, accentColor: accentColor) {
                        selectedTool = tool
                    }
                    .opacity(cardsAnimated ? 1 : 0)
                    .offset(y: cardsAnimated ? 0 : 24)
                    .animation(
                        .spring(duration: 0.45, bounce: 0.12)
                            .delay(Double(delayBase + index) * 0.06),
                        value: cardsAnimated
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)
                .padding(.horizontal, 40)

            HStack {
                Text("Built with SwiftUI")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textMuted)
                    .tracking(0.8)
                Spacer()
                Text("Powered by MiniMax")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textMuted)
                    .tracking(0.8)
            }
        }
        .padding(.bottom, 40)
    }
}

// MARK: - Landing Metric

private struct LandingMetric: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(value)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
                .textCase(.uppercase)
                .tracking(0.8)
        }
    }
}

// MARK: - Landing Tool Card

private struct LandingToolCard: View {
    let tool: Tool
    let accentColor: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                // Icon + tag row
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .fill(accentColor.opacity(isHovered ? 0.22 : 0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: tool.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isHovered ? accentColor : AppTheme.textSecondary)
                    }

                    Spacer()

                    Text(tool.navigationTag)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColor.opacity(0.7))
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(accentColor.opacity(0.08))
                        )
                }

                // Name + description
                VStack(alignment: .leading, spacing: 6) {
                    Text(tool.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    Text(tool.description)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // CTA row
                HStack {
                    Text("Open")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(isHovered ? accentColor : AppTheme.textMuted)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isHovered ? accentColor : AppTheme.textMuted)
                        .offset(x: isHovered ? 3 : 0)
                }
            }
            .padding(AppTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl)
                    .fill(isHovered ? AppTheme.surfaceHover : AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl)
                    .strokeBorder(
                        isHovered ? accentColor.opacity(0.3) : AppTheme.border, lineWidth: 1)
            )
            .shadow(
                color: isHovered ? accentColor.opacity(0.08) : Color.black.opacity(0.10),
                radius: isHovered ? 24 : 12, y: 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(AppTheme.Anim.fast) { isHovered = hovering } }
    }
}
extension Tool {
    fileprivate var navigationTag: String {
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
        default:
            return "Tool"
        }
    }
}

// MARK: - MiniMax Settings Sheet

private struct MiniMaxSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.textMuted)
                }
                .buttonStyle(.plain)
                .padding(AppTheme.Spacing.md)
            }

            MiniMaxSettingsView()
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(AppTheme.background)
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
