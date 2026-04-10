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
        .aiChat: { AnyView(ClaudeChatView()) },
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
    @State private var selectedTool: Tool?
    @State private var retainedToolIDs: [ToolID] = []
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var showSettings = false
    @State private var selectedSettingsTab: ToolSettingsTab = .minimax
    @State private var searchText = ""

    private let tools = ToolRegistry.defaults

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

    private var activeToolTitle: String {
        selectedTool?.name ?? "CodeTool"
    }

    private var activeToolSubtitle: String {
        if let selectedTool {
            return selectedTool.description
        }

        return "A calmer desktop deck for daily dev utilities and AI workflows."
    }

    public var body: some View {
        let settingsPresenter = ToolSettingsPresenter { tab in
            selectedSettingsTab = tab
            showSettings = true
        }

        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            SidebarPane(
                groups: filteredGroups,
                selectedTool: $selectedTool,
                totalToolCount: tools.count,
                searchText: searchText,
                openSettings: {
                    selectedSettingsTab = .minimax
                    showSettings = true
                }
            )
        } detail: {
            ToolDetailCacheView(
                tools: tools,
                selectedTool: $selectedTool,
                retainedToolIDs: retainedToolIDs
            )
            .environment(\.toolSettingsPresenter, settingsPresenter)
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search tools")
        .environment(\.toolSettingsPresenter, settingsPresenter)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help("切换侧边栏 (⌘\\)")
            }

            ToolbarItem(placement: .principal) {
                ToolbarTitleView(title: activeToolTitle, subtitle: activeToolSubtitle)
            }

            ToolbarItemGroup {
                Button {
                    selectedTool = nil
                } label: {
                    Label("Home", systemImage: "square.grid.2x2")
                }
                .help("返回工作台首页")

                Button {
                    selectedSettingsTab = .minimax
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .help("打开 Provider 设置")
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .background(AppBackdrop())
        .background {
            Button("") {
                toggleSidebar()
            }
            .keyboardShortcut("\\", modifiers: .command)
            .hidden()
        }
        .onAppear {
            ClaudeCLISettingsStore.shared.discoverCLI()
            ObservabilitySystem.shared.rootViewReady()
            RenderingPerformance.configureCaptureIfNeeded()
            retainedToolIDs = ToolViewCache.retainedToolIDs(
                current: retainedToolIDs,
                selectedToolID: selectedTool?.toolID
            )
            RenderingPerformance.toolCacheSnapshot(
                selectedToolID: selectedTool?.toolID,
                retainedToolIDs: retainedToolIDs
            )
        }
        .onChange(of: selectedTool?.toolID) { previousToolID, selectedToolID in
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
            sidebarVisibility = sidebarVisibility == .detailOnly ? .all : .detailOnly
        }
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

private struct ToolbarTitleView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)

            Text(subtitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: 360)
    }
}

private struct SidebarPane: View {
    let groups: [ToolGroup]
    @Binding var selectedTool: Tool?
    let totalToolCount: Int
    let searchText: String
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeroCard(
                totalToolCount: totalToolCount,
                selectedTool: selectedTool,
                searchText: searchText
            )
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.sm)

            if groups.isEmpty {
                ContentUnavailableView(
                    "No Matching Tools",
                    systemImage: "magnifyingglass",
                    description: Text("Try a broader keyword or clear the current search.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedTool) {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.tools) { tool in
                                SidebarRow(tool: tool, isSelected: selectedTool == tool)
                                    .tag(tool as Tool?)
                                    .listRowInsets(
                                        EdgeInsets(
                                            top: 5,
                                            leading: AppTheme.Spacing.md,
                                            bottom: 5,
                                            trailing: AppTheme.Spacing.md
                                        )
                                    )
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                        } header: {
                            Label(group.category.displayName, systemImage: group.category.systemImage)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.textMuted)
                                .textCase(.uppercase)
                                .tracking(1.0)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .safeAreaInset(edge: .bottom) {
            SidebarFooterCard(openSettings: openSettings)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.lg)
        }
    }
}

private struct SidebarHeroCard: View {
    let totalToolCount: Int
    let selectedTool: Tool?
    let searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .fill(AppTheme.accentGradient)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: selectedTool?.systemImage ?? "square.grid.2x2")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.78))
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedTool?.name ?? "CodeTool")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(selectedTool?.routeSlug ?? "Desktop utility deck")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textMuted)
                        .textCase(.uppercase)
                        .tracking(1.1)
                }
            }

            Text(selectedTool?.description ?? "Elegant utility workflows built around consistent surfaces, lighter chrome, and a calmer reading rhythm.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppTheme.Spacing.sm) {
                infoCapsule(title: "\(totalToolCount) tools", tint: AppTheme.accent)

                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    infoCapsule(title: "Filtered", tint: AppTheme.accentWarm)
                } else {
                    infoCapsule(title: "Ready", tint: AppTheme.success)
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .glassSurface(cornerRadius: AppTheme.Radius.hero, tint: AppTheme.panelTintStrong)
    }

    private func infoCapsule(title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, AppTheme.Spacing.sm + 2)
            .padding(.vertical, AppTheme.Spacing.xs + 2)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule().fill(tint.opacity(0.10))
                    }
            }
            .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 1))
    }
}

private struct SidebarFooterCard: View {
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Provider Settings")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Tune your model providers without leaving the current workspace.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            StyledButton("Open", systemImage: "slider.horizontal.3", variant: .secondary, action: openSettings)
        }
        .padding(AppTheme.Spacing.lg)
        .glassSurface(cornerRadius: AppTheme.Radius.xl, tint: AppTheme.panelTint)
    }
}

private struct SidebarRow: View {
    let tool: Tool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: 34, height: 34)
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(isSelected ? AppTheme.accentGradient : AppTheme.heroGradient)
                        .padding(2)
                        .overlay {
                            Image(systemName: tool.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.black.opacity(0.78) : AppTheme.textSecondary)
                        }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Text(tool.description)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(tool.routeSlug)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? AppTheme.accentWarm : AppTheme.textMuted)
                .textCase(.uppercase)
                .tracking(0.8)
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.sm)
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
    }
}

private struct ToolDetailCacheView: View {
    let tools: [Tool]
    @Binding var selectedTool: Tool?
    let retainedToolIDs: [ToolID]

    private var visibilityState: ToolVisibilityState {
        ToolVisibilityState(selectedToolID: selectedTool?.toolID)
    }

    var body: some View {
        ZStack {
            if selectedTool == nil {
                WelcomeView(tools: tools, selectedTool: $selectedTool)
            }

            ForEach(cachedTools) { tool in
                let visibilityContext = visibilityState.context(for: tool.toolID)
                let isSelected = selectedTool == tool

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
        .glassSurface(cornerRadius: AppTheme.Radius.hero, tint: AppTheme.panelTintStrong)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackdrop())
    }
}

private struct WelcomeView: View {
    let tools: [Tool]
    @Binding var selectedTool: Tool?

    @State private var appeared = false

    private var devTools: [Tool] { tools.filter { $0.category == .devTools } }
    private var aiTools: [Tool] { tools.filter { $0.category == .aiTools } }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxxl) {
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
                    subtitle: "Speech, image, music, and CLI-native chat brought into the same visual language.",
                    tools: aiTools,
                    accentColor: AppTheme.accentWarm
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
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Elegant tools for the everyday macOS workflow.")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("A more refined desktop shell with lighter chrome, calmer focus, and shared glass surfaces across every utility.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: 680, alignment: .leading)
            }

            HStack(spacing: AppTheme.Spacing.lg) {
                LandingMetric(value: "\(devTools.count)", label: "Dev Tools", color: AppTheme.accent)
                LandingMetric(value: "\(aiTools.count)", label: "AI Tools", color: AppTheme.accentWarm)
                LandingMetric(value: "1", label: "Shared Language", color: AppTheme.accentCoral)
            }

            HStack(spacing: AppTheme.Spacing.md) {
                if let jsonTool = tool(with: .jsonTool) {
                    StyledButton("Open JSON Tool", systemImage: jsonTool.systemImage, variant: .primary) {
                        selectedTool = jsonTool
                    }
                }

                if let aiChat = tool(with: .aiChat) {
                    StyledButton("Launch AI Chat", systemImage: aiChat.systemImage, variant: .secondary) {
                        selectedTool = aiChat
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.xxxl)
        .glassSurface(cornerRadius: AppTheme.Radius.hero, tint: AppTheme.panelTintStrong, shadowOpacity: 0.22)
    }

    private func toolGroupSection(
        eyebrow: String,
        title: String,
        subtitle: String,
        tools: [Tool],
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text(eyebrow)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)
                    .textCase(.uppercase)
                    .tracking(1.4)

                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
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
                        selectedTool = tool
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
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
                .textCase(.uppercase)
                .tracking(0.8)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .glassSurface(cornerRadius: AppTheme.Radius.lg, tint: color.opacity(0.16), stroke: color.opacity(0.18), shadowOpacity: 0.10)
    }
}

private struct LandingToolCard: View {
    let tool: Tool
    let accentColor: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 42, height: 42)
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                .fill(accentColor.opacity(isHovered ? 0.24 : 0.16))
                                .padding(2)
                                .overlay {
                                    Image(systemName: tool.systemImage)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(isHovered ? accentColor : AppTheme.textSecondary)
                                }
                        }

                    Spacer()

                    Text(tool.routeSlug)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .textCase(.uppercase)
                        .tracking(1.0)
                        .padding(.horizontal, AppTheme.Spacing.sm)
                        .padding(.vertical, AppTheme.Spacing.xs + 1)
                        .background {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Capsule().fill(accentColor.opacity(0.10))
                                }
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
            .padding(AppTheme.Spacing.xl)
            .glassSurface(cornerRadius: AppTheme.Radius.xl, tint: AppTheme.panelTintStrong, stroke: isHovered ? accentColor.opacity(0.30) : AppTheme.border, shadowOpacity: isHovered ? 0.22 : 0.14)
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
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Keep diagnostics, providers, and local CLI integrations inside the same visual rhythm as the main workspace.")
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
            .glassSurface(cornerRadius: AppTheme.Radius.lg, tint: AppTheme.panelTintStrong, shadowOpacity: 0.08)

            Group {
                if selectedTab == .minimax {
                    MiniMaxSettingsView()
                } else if selectedTab == .claude {
                    ClaudeCLISettingsView()
                } else {
                    DiagnosticsView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
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
