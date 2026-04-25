import CodeToolFoundation
import CodeToolUI
import SwiftUI

enum ToolDestinationRegistry {
    typealias Factory = () -> AnyView

    private static var factories: [ToolID: Factory] = [
        .jsonTool: { AnyView(JSONToolView()) },
        .imageConverter: { AnyView(ImageConverterView()) },
        .jsonDiff: { AnyView(JSONDiffView()) },
        .timestampConverter: { AnyView(TimestampConverterView()) },
        .jwtTool: { AnyView(JWTToolView()) },
        .wordCloud: { AnyView(WordCloudView()) },
        .aiChat: { AnyView(MiniMaxChatView()) },
        .aiSpeech: { AnyView(AISpeechView()) },
        .aiImage: { AnyView(AIImageView()) },
        .aiMusic: { AnyView(AIMusicView()) },
    ]

    static var registeredToolIDs: Set<ToolID> {
        Set(factories.keys)
    }

    static func makeView(for toolID: ToolID) -> AnyView? {
        factories[toolID]?()
    }

    static func register(_ factory: @escaping Factory, for toolID: ToolID) {
        factories[toolID] = factory
    }
}

private struct ToolGroup: Identifiable {
    let category: ToolCategory
    let tools: [Tool]

    var id: ToolCategory { category }
}

public struct ContentView: View {
    @State private var selectedToolID: ToolID?
    @State private var retainedToolIDs: [ToolID] = []
    @State private var isSidebarVisible = true
    @State private var showSettings = false
    @State private var selectedSettingsTab: ToolSettingsTab = .minimax
    @State private var searchText = ""

    private let tools = ToolRegistry.defaults

    private enum Layout {
        static let sidebarWidth: CGFloat = 290
        static let minimumWindowWidth: CGFloat = 980
        static let minimumWindowHeight: CGFloat = 680
    }

    private var selectedTool: Tool? {
        tool(for: selectedToolID)
    }

    public init() {}

    private var filteredGroups: [ToolGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredTools: [Tool]

        if query.isEmpty {
            filteredTools = tools
        } else {
            filteredTools = tools.filter { tool in
                [tool.name, tool.description, tool.routeSlug, tool.category.displayName]
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(query)
            }
        }

        return ToolCategory.allCases.compactMap { category in
            let categoryTools = filteredTools.filter { $0.category == category }
            return categoryTools.isEmpty ? nil : ToolGroup(category: category, tools: categoryTools)
        }
    }

    public var body: some View {
        let settingsPresenter = ToolSettingsPresenter { tab in
            selectedSettingsTab = tab
            showSettings = true
        }

        HStack(spacing: 0) {
            if isSidebarVisible {
                SidebarPane(
                    groups: filteredGroups,
                    selectedToolID: $selectedToolID,
                    openSettings: {
                        selectedSettingsTab = .minimax
                        showSettings = true
                    }
                )
                .frame(width: Layout.sidebarWidth)

                SidebarDivider()
            }

            ToolDetailCacheView(
                tools: tools,
                selectedToolID: $selectedToolID,
                retainedToolIDs: retainedToolIDs
            )
            .environment(\.toolSettingsPresenter, settingsPresenter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search tools")
        .environment(\.toolSettingsPresenter, settingsPresenter)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help("切换侧边栏 (⌘\\)")
            }

            ToolbarItemGroup {
                Button {
                    showLanding()
                } label: {
                    Image(systemName: "house")
                }
                .help("返回工作台首页 (⌘0)")

                Button {
                    selectedSettingsTab = .minimax
                    showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("打开 Provider 设置")
            }
        }
        .frame(minWidth: Layout.minimumWindowWidth, minHeight: Layout.minimumWindowHeight)
        .background(AppBackdrop())
        .focusedSceneValue(
            \.workspaceCommandActions,
            WorkspaceCommandActions(
                showLanding: showLanding,
                toggleSidebar: toggleSidebar
            )
        )
        .onAppear {
            ObservabilitySystem.shared.rootViewReady()
            RenderingPerformance.configureCaptureIfNeeded()
            retainedToolIDs = ToolViewCache.retainedToolIDs(
                current: retainedToolIDs,
                selectedToolID: selectedToolID
            )
            RenderingPerformance.toolCacheSnapshot(
                selectedToolID: selectedToolID,
                retainedToolIDs: retainedToolIDs
            )
        }
        .onChange(of: selectedToolID) { previousToolID, selectedToolID in
            let existingRetainedIDs = retainedToolIDs
            let cacheHit = selectedToolID.map(existingRetainedIDs.contains) ?? false
            let startedAt = Date()

            RenderingPerformance.toolSwitchStarted(
                from: previousToolID,
                to: selectedToolID,
                retainedCount: existingRetainedIDs.count,
                cacheHit: cacheHit
            )

            if let previousToolID {
                RenderingPerformance.toolVisibilityChanged(
                    toolID: previousToolID,
                    isVisible: false,
                    policy: ToolVisibilityPolicyRegistry.policy(for: previousToolID),
                    retained: existingRetainedIDs.contains(previousToolID)
                )
            }

            if let selectedToolID {
                RenderingPerformance.toolVisibilityChanged(
                    toolID: selectedToolID,
                    isVisible: true,
                    policy: ToolVisibilityPolicyRegistry.policy(for: selectedToolID),
                    retained: true
                )
            }

            retainedToolIDs = ToolViewCache.retainedToolIDs(
                current: retainedToolIDs,
                selectedToolID: selectedToolID
            )
            RenderingPerformance.toolCacheSnapshot(
                selectedToolID: selectedToolID,
                retainedToolIDs: retainedToolIDs
            )

            DispatchQueue.main.async {
                RenderingPerformance.toolSwitchFinished(
                    from: previousToolID,
                    to: selectedToolID,
                    retainedCount: retainedToolIDs.count,
                    durationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(selectedTab: $selectedSettingsTab)
        }
    }

    private func toggleSidebar() {
        withAnimation(AppTheme.Anim.settle) {
            isSidebarVisible.toggle()
        }
    }

    private func showLanding() {
        selectedToolID = nil
    }

    private func tool(for toolID: ToolID?) -> Tool? {
        guard let toolID else {
            return nil
        }

        return tools.first { $0.toolID == toolID }
    }
}

private struct SidebarDivider: View {
    var body: some View {
        ZStack {
            AppTheme.sidebarBackground

            AppTheme.border
                .frame(width: 1)
        }
        .frame(width: 1)
    }
}

enum ToolViewCache {
    static let maximumRetainedToolCount = 3

    static func retainedToolIDs(current: [ToolID], selectedToolID: ToolID?) -> [ToolID] {
        guard let selectedToolID else {
            return current
        }

        var updated = current.filter { $0 != selectedToolID }
        updated.append(selectedToolID)

        while updated.count > maximumRetainedToolCount {
            updated.removeFirst()
        }

        return updated
    }
}

private struct SidebarPane: View {
    let groups: [ToolGroup]
    @Binding var selectedToolID: ToolID?
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SidebarBrandHeader()

            if groups.isEmpty {
                ContentUnavailableView(
                    "No Matching Tools",
                    systemImage: "magnifyingglass",
                    description: Text("Try a broader keyword or clear the current search.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedToolID) {
                    ForEach(groups) { group in
                        Section(group.category.displayName) {
                            ForEach(group.tools) { tool in
                                SidebarRow(tool: tool, isSelected: selectedToolID == tool.toolID)
                                    .tag(tool.toolID)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedToolID = tool.toolID
                                    }
                                    .listRowInsets(
                                        EdgeInsets(
                                            top: 3,
                                            leading: AppTheme.Spacing.sm,
                                            bottom: 3,
                                            trailing: AppTheme.Spacing.sm
                                        )
                                    )
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.sidebarBackground)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                AppTheme.border.frame(height: 1)
                Button(action: openSettings) {
                    Label("Provider Settings", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.vertical, AppTheme.Spacing.sm + 2)
                }
                .buttonStyle(.plain)
                .background(AppTheme.sidebarBackground)
            }
        }
    }
}

private struct SidebarBrandHeader: View {
    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text("CT")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 28, height: 28)
                .background(AppTheme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                        .strokeBorder(AppTheme.accentBright.opacity(0.34), lineWidth: 1)
                )
                .shadow(color: AppTheme.accent.opacity(0.20), radius: 8, y: 3)

            HStack(spacing: AppTheme.Spacing.xs) {
                Text("CodeTool")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .tracking(-0.1)

                Text("LOCAL")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textMuted)
                    .tracking(1.2)
                    .padding(.horizontal, AppTheme.Spacing.xs + 1)
                    .padding(.vertical, 2)
                    .background(AppTheme.muted)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.sm)
        .overlay(alignment: .bottom) {
            AppTheme.border.frame(height: 1)
        }
    }
}

private struct SidebarRow: View {
    let tool: Tool
    let isSelected: Bool

    @State private var isHovered = false

    private var backgroundFill: Color {
        if isSelected { return AppTheme.accent.opacity(0.20) }
        if isHovered { return AppTheme.muted }
        return .clear
    }

    private var borderColor: Color {
        isSelected ? AppTheme.accent.opacity(0.26) : .clear
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isSelected ? AppTheme.accentBright : Color.clear)
                .frame(width: 3, height: 28)

            Image(systemName: tool.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? AppTheme.accentBright : AppTheme.textMuted)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Text(tool.description)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs + 2)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .toolHoverTracking($isHovered)
    }
}

private struct ToolDetailCacheView: View {
    let tools: [Tool]
    @Binding var selectedToolID: ToolID?
    let retainedToolIDs: [ToolID]

    private var visibilityState: ToolVisibilityState {
        ToolVisibilityState(selectedToolID: selectedToolID)
    }

    private var selectedTool: Tool? {
        guard let selectedToolID else {
            return nil
        }

        return tools.first { $0.toolID == selectedToolID }
    }

    var body: some View {
        ZStack {
            if selectedTool == nil {
                WelcomeView(tools: tools, selectedToolID: $selectedToolID)
            }

            ForEach(cachedTools) { tool in
                let visibilityContext = visibilityState.context(for: tool.toolID)
                let isSelected = selectedToolID == tool.toolID

                ToolDetailView(tool: tool)
                    .environment(\.toolVisibilityContext, visibilityContext)
                    .environment(
                        \.toolUIActivity,
                        ToolUIActivity(isVisible: visibilityContext.isVisible)
                    )
                    .modifier(CachedToolPresentationModifier(isVisible: isSelected))
            }
        }
    }

    private var cachedTools: [Tool] {
        retainedToolIDs.compactMap { retainedID in
            guard let tool = tools.first(where: { $0.toolID == retainedID }) else {
                return nil
            }

            let context = visibilityState.context(for: tool.toolID)
            if context.shouldUnloadWhenHidden {
                return nil
            }

            return tool
        }
    }
}

private struct CachedToolPresentationModifier: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        Group {
            if isVisible {
                content
            } else {
                content.hidden()
            }
        }
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .zIndex(isVisible ? 1 : 0)
    }
}

private struct ToolDetailView: View {
    let tool: Tool

    var body: some View {
        Group {
            if let toolID = tool.toolID {
                if let destination = ToolDestinationRegistry.makeView(for: toolID) {
                    destination
                } else {
                    placeholderView
                }
            } else {
                placeholderView
            }
        }
    }

    private var placeholderView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(AppTheme.accent)

            Text(tool.name)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text(tool.description)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(AppTheme.Spacing.xxxl)
        .glassSurface(cornerRadius: AppTheme.Radius.xxl, tint: AppTheme.panelTintStrong, shadowOpacity: 0.08)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackdrop())
    }
}

private struct WelcomeView: View {
    let tools: [Tool]
    @Binding var selectedToolID: ToolID?

    @State private var appeared = false

    private var devTools: [Tool] { tools.filter { $0.category == .devTools } }
    private var aiTools: [Tool] { tools.filter { $0.category == .aiTools } }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                heroSection
                toolGroupSection(
                    eyebrow: "Development",
                    title: "Precision utilities",
                    subtitle: "Fast daily workflows for inspection, conversion, formatting, and diagnosis.",
                    tools: devTools,
                    accentColor: AppTheme.accent
                )
                toolGroupSection(
                    eyebrow: "AI Workspace",
                    title: "Agentic surfaces",
                    subtitle: "Speech, image, music, and MiniMax chat brought into the same visual language.",
                    tools: aiTools,
                    accentColor: AppTheme.accentBright
                )
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
            .padding(.top, AppTheme.Spacing.xxl)
            .padding(.bottom, AppTheme.Spacing.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppBackdrop())
        .opacity(appeared ? 1 : 0.84)
        .offset(y: appeared ? 0 : 12)
        .animation(AppTheme.Anim.settle, value: appeared)
        .onAppear {
            appeared = true
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.xl) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Text("CodeTool")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)

                        Text("LOCAL SUITE")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.accentBright)
                            .tracking(1.3)
                            .padding(.horizontal, AppTheme.Spacing.sm)
                            .padding(.vertical, 3)
                            .background(AppTheme.accent.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous))
                    }

                    Text("Quiet tools for fast local work.")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("A compact macOS workspace for conversion, inspection, and AI generation close at hand.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: 650, alignment: .leading)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    LandingMetric(value: "\(devTools.count)", label: "Dev Tools", color: AppTheme.accent)
                    LandingMetric(value: "\(aiTools.count)", label: "AI Tools", color: AppTheme.accentBright)
                    LandingMetric(value: "1", label: "Shell", color: AppTheme.textMuted)
                }
            }

            HStack(spacing: AppTheme.Spacing.md) {
                if let jsonTool = tool(with: .jsonTool) {
                    StyledButton("Open JSON Tool", systemImage: jsonTool.systemImage, variant: .primary) {
                        selectedToolID = jsonTool.toolID
                    }
                }

                if let aiChat = tool(with: .aiChat) {
                    StyledButton("Launch AI Chat", systemImage: aiChat.systemImage, variant: .outline) {
                        selectedToolID = aiChat.toolID
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.xxl)
        .glassSurface(cornerRadius: AppTheme.Radius.xxl, tint: AppTheme.accent.opacity(0.045), stroke: AppTheme.borderHover, shadowOpacity: 0.12)
    }

    private func toolGroupSection(
        eyebrow: String,
        title: String,
        subtitle: String,
        tools: [Tool],
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text(eyebrow)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)
                    .textCase(.uppercase)
                    .tracking(1.4)

                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: AppTheme.Spacing.lg)],
                spacing: AppTheme.Spacing.lg
            ) {
                ForEach(tools) { tool in
                    LandingToolCard(tool: tool, accentColor: accentColor) {
                        selectedToolID = tool.toolID
                    }
                }
            }
        }
    }

    private func tool(with id: ToolID) -> Tool? {
        tools.first { $0.toolID == id }
    }
}

private struct LandingMetric: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
                .textCase(.uppercase)
                .tracking(0.8)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .glassSurface(cornerRadius: AppTheme.Radius.lg, tint: color.opacity(0.10), stroke: AppTheme.border, shadowOpacity: 0.05)
    }
}

private struct LandingToolCard: View {
    let tool: Tool
    let accentColor: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(accentColor.opacity(isHovered ? 0.18 : 0.12))
                        .frame(width: 42, height: 42)
                        .overlay {
                            Image(systemName: tool.systemImage)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(isHovered ? accentColor : AppTheme.textSecondary)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                .strokeBorder(accentColor.opacity(0.18), lineWidth: 1)
                        )

                    Spacer()

                    Text(tool.routeSlug)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .textCase(.uppercase)
                        .tracking(1.0)
                        .padding(.horizontal, AppTheme.Spacing.sm)
                        .padding(.vertical, AppTheme.Spacing.xs + 1)
                        .background {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous)
                                .fill(AppTheme.muted)
                        }
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs + 2) {
                    Text(tool.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Text(tool.description)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }

                HStack {
                    Text("Open")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(isHovered ? accentColor : AppTheme.textMuted)

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isHovered ? accentColor : AppTheme.textMuted)
                        .offset(x: isHovered ? 4 : 0)
                }
            }
            .padding(AppTheme.Spacing.lg)
            .glassSurface(cornerRadius: AppTheme.Radius.xl, tint: isHovered ? accentColor.opacity(0.070) : AppTheme.panelTintStrong, stroke: isHovered ? accentColor.opacity(0.30) : AppTheme.border, shadowOpacity: isHovered ? 0.12 : 0.06)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .toolHoverTracking($isHovered)
    }
}

private struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTab: ToolSettingsTab

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Provider Settings")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Manage diagnostics, providers, and local CLI integrations from one workspace.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer(minLength: 0)

                StyledIconButton("xmark", help: "Close") {
                    dismiss()
                }
            }

            Picker("", selection: $selectedTab) {
                ForEach(ToolSettingsTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(6)
            .glassSurface(cornerRadius: AppTheme.Radius.lg, tint: AppTheme.panelTintStrong, shadowOpacity: 0.05)

            Group {
                if selectedTab == .minimax {
                    MiniMaxSettingsView()
                } else {
                    DiagnosticsView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xxl, style: .continuous))
        }
        .padding(AppTheme.Spacing.xxl)
        .frame(minWidth: 760, minHeight: 620)
        .background(AppBackdrop())
    }
}

#if DEBUG
    struct ContentView_Previews: PreviewProvider {
        static var previews: some View {
            ContentView()
        }
    }
#endif
