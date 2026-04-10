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

    public var body: some View {
        let settingsPresenter = ToolSettingsPresenter { tab in
            selectedSettingsTab = tab
            showSettings = true
        }

        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            SidebarPane(
                groups: filteredGroups,
                selectedTool: $selectedTool,
                openSettings: {
                    selectedSettingsTab = .minimax
                    showSettings = true
                }
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 290, max: 340)
        } detail: {
            ToolDetailCacheView(
                tools: tools,
                selectedTool: $selectedTool,
                retainedToolIDs: retainedToolIDs
            )
            .environment(\.toolSettingsPresenter, settingsPresenter)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search tools")
        .navigationTitle(selectedTool?.name ?? "CodeTool")
        .environment(\.toolSettingsPresenter, settingsPresenter)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help("切换侧边栏 (⌘\\)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    selectedTool = nil
                } label: {
                    Image(systemName: "house")
                }
                .help("返回工作台首页")

                Button {
                    selectedSettingsTab = .minimax
                    showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
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

private struct SidebarPane: View {
    let groups: [ToolGroup]
    @Binding var selectedTool: Tool?
    let openSettings: () -> Void

    var body: some View {
        Group {
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
                        Section(group.category.displayName) {
                            ForEach(group.tools) { tool in
                                SidebarRow(tool: tool, isSelected: selectedTool == tool)
                                    .tag(tool as Tool?)
                                    .listRowInsets(
                                        EdgeInsets(
                                            top: 4,
                                            leading: AppTheme.Spacing.md,
                                            bottom: 4,
                                            trailing: AppTheme.Spacing.md
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
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                Button(action: openSettings) {
                    Label("Provider Settings", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.vertical, AppTheme.Spacing.md)
                }
                .buttonStyle(.plain)
                .background(.regularMaterial)
            }
        }
    }
}

private struct SidebarRow: View {
    let tool: Tool
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                .frame(width: 22, height: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
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
        .padding(.horizontal, AppTheme.Spacing.xs)
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
