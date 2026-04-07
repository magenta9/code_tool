import AppKit
import CodeToolUI
import SwiftUI
import UniformTypeIdentifiers

public struct ClaudeChatView: View {
    @Environment(\.toolVisibilityContext) private var toolVisibilityContext
    @Bindable private var settings = ClaudeCLISettingsStore.shared
    private static let defaultWorkingDirectory = FileManager.default.homeDirectoryForCurrentUser.path
    private static let streamingCommitIntervalNs: UInt64 = 50_000_000

    @State private var client = ClaudeCLIClient()
    @State private var messages: [ClaudeChatMessage] = []
    @State private var inputText: String = ""
    @State private var isStreaming: Bool = false
    @State private var streamingText: String = ""
    @State private var streamingThinking: String = ""
    @State private var errorMessage: String = ""
    @State private var sessionId: String = ""
    @State private var currentModel: String = ""
    @State private var totalCostUSD: Double = 0
    @State private var inputTokens: Int = 0
    @State private var outputTokens: Int = 0
    @State private var totalDurationMs: Int = 0
    @State private var activeReferenceID: String = ""
    @State private var showThinking: Set<UUID> = []
    @State private var showToolDetails: Set<UUID> = []
    @State private var toolNamesByUseID: [String: String] = [:]
    @State private var showHistory = false
    @State private var chatHistory: [ClaudeChatHistoryRecord] = []
    @State private var chatHistoryHasMore = false
    @State private var historyDrawerOpenedAt: Date?
    @State private var cancellationRequested = false
    @State private var workingDirectory: String = Self.defaultWorkingDirectory
    @State private var pendingStreamingText: String = ""
    @State private var pendingStreamingThinking: String = ""
    @State private var streamingFlushTask: Task<Void, Never>?
    @State private var streamingScrollRevision = 0

    private let historyPageSize = 20

    // Stable ID for the streaming message placeholder (avoids view recreation on each delta)
    private static let streamingMessageID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    // Conversation-scoped history identity
    @State private var activeConversationRecordID: UUID?
    @State private var activeConversationCreatedAt: Date?

    // Image attachment state
    @State private var composerImages: [ClaudeComposerImage] = []
    @State private var composerHasVisibleText = false
    @State private var attachmentWarning: String = ""

    private static let starterPrompts: [ClaudeStarterPrompt] = [
        ClaudeStarterPrompt(
            title: "Review my latest changes",
            detail: "Inspect the current diff and surface only the risky bugs or regressions.",
            prompt: "Review my latest changes and call out risky bugs or regressions."
        ),
        ClaudeStarterPrompt(
            title: "Trace a feature flow",
            detail: "Follow the request path through the codebase and explain how the pieces fit.",
            prompt: "Trace this feature flow through the codebase and explain how the pieces fit together."
        ),
        ClaudeStarterPrompt(
            title: "Refactor a rough module",
            detail: "Suggest a cleaner structure, then implement the safest first pass.",
            prompt: "Help me refactor this rough module into a cleaner, easier-to-maintain shape."
        ),
        ClaudeStarterPrompt(
            title: "Summarize this repo",
            detail: "Map the architecture, important entry points, and where to make changes.",
            prompt: "Summarize this repository architecture and highlight the best entry points for new changes."
        ),
    ]

    public init() {}

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Claude CLI",
            title: "AI Chat",
            description: "Chat with Claude using the local CLI agent harness.",
            systemImage: "bubble.left.and.bubble.right",
            statusItems: statusItems
        ) {
            StyledButton("History", systemImage: "clock.arrow.circlepath", variant: .secondary) {
                historyDrawerOpenedAt = Date()
                loadHistory(reset: true)
                showHistory = true
            }
            StyledButton("Clear Chat", systemImage: "trash", variant: .ghost) {
                clearChat()
            }
        } content: {
            VStack(spacing: 0) {
                bannerStack
                messageListView
            }
            .safeAreaInset(edge: .bottom) {
                inputArea
                    .padding(.horizontal, AppTheme.Spacing.xxl)
                    .padding(.top, AppTheme.Spacing.lg)
                    .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .overlay {
            if showHistory {
                HistoryDrawer(
                    isPresented: $showHistory,
                    title: "Claude Chat History",
                    items: chatHistory,
                    onSelect: { record in restoreChat(record) },
                    onDelete: { record in deleteChat(record) },
                    onClearAll: { clearChatHistory() },
                    toolID: .aiChat,
                    openedAt: historyDrawerOpenedAt,
                    pageSize: historyPageSize,
                    hasMore: chatHistoryHasMore,
                    onLoadMore: { loadHistory(reset: false) }
                )
            }
        }
        .onAppear {
            if settings.resolvedClaudePath.isEmpty {
                settings.discoverCLI()
            }
            if currentModel.isEmpty {
                currentModel = settings.model
            }
        }
        .onChange(of: toolVisibilityContext.isVisible) { _, isVisible in
            guard isVisible else {
                return
            }

            flushPendingStreamingBuffers(triggerScroll: true)
        }
        .background {
            // Cmd+Shift+O: New chat
            Button("") { clearChat() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .hidden()

            // Cmd+L: Clear current chat
            Button("") { clearChat() }
                .keyboardShortcut("l", modifiers: .command)
                .hidden()
        }
    }

    private var bannerStack: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if !settings.isAvailable {
                ToolMessageBanner(
                    systemImage: "exclamationmark.triangle",
                    message: "Claude CLI was not found. Open Settings and detect the binary or set its path manually.",
                    tint: AppTheme.warning
                )
            }

            if !errorMessage.isEmpty {
                ToolMessageBanner(
                    systemImage: "xmark.octagon",
                    message: errorMessage,
                    tint: AppTheme.error
                )
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xxl)
        .padding(.top, AppTheme.Spacing.sm)
    }

    private var statusItems: [ToolStatusItem] {
        var items: [ToolStatusItem] = []

        items.append(
            ToolStatusItem(
                title: workingDirectoryTitle,
                systemImage: "folder",
                tint: AppTheme.textSecondary,
                help: workingDirectory,
                accessibilityLabel: "Working directory: \(workingDirectory)",
                action: chooseWorkingDirectory
            ))

        if !resolvedModelName.isEmpty {
            items.append(
                ToolStatusItem(
                    title: resolvedModelName,
                    systemImage: "cpu",
                    tint: AppTheme.accent
                ))
        }

        if totalCostUSD > 0 {
            items.append(
                ToolStatusItem(
                    title: String(format: "$%.4f", totalCostUSD),
                    systemImage: "dollarsign.circle",
                    tint: AppTheme.accentWarm
                ))
        }

        if inputTokens > 0 || outputTokens > 0 {
            items.append(
                ToolStatusItem(
                    title: "↑\(inputTokens) ↓\(outputTokens)",
                    systemImage: "arrow.up.arrow.down",
                    tint: AppTheme.textMuted
                ))
        }

        if !messages.isEmpty {
            items.append(
                ToolStatusItem(
                    title: "\(messages.count) item\(messages.count == 1 ? "" : "s")",
                    systemImage: "bubble.left.and.bubble.right",
                    tint: AppTheme.textSecondary
                ))
        }

        if isStreaming {
            items.append(
                ToolStatusItem(
                    title: "Streaming…",
                    systemImage: "ellipsis.circle",
                    tint: AppTheme.success
                ))
        }

        return items
    }

    private var messageListView: some View {
        ClaudeConversationPane(
            state: conversationRenderState,
            leadIn: { conversationLeadIn },
            emptyState: { emptyStateView },
            messageView: { message in messageView(for: message) }
        )
        .equatable()
    }

    private var conversationRenderState: ClaudeConversationRenderState {
        ClaudeConversationRenderState.make(
            messages: messages,
            streamingMessage: streamingMessage,
            isStreaming: isStreaming,
            workingDirectoryTitle: workingDirectoryTitle,
            hasSystemPrompt: normalizedSystemPrompt != nil,
            expandedThinkingIDs: showThinking,
            expandedToolDetailIDs: showToolDetails,
            composerImageCount: composerImages.count,
            draftText: inputText,
            hasVisibleDraftText: composerHasVisibleText,
            isToolVisible: toolVisibilityContext.isVisible,
            streamingScrollRevision: streamingScrollRevision
        )
    }

    private var conversationLeadIn: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
            ClaudeCapsuleTag(
                title: isStreaming ? "Live session" : "Workspace chat",
                systemImage: isStreaming ? "bolt.horizontal.circle" : "sparkles",
                tint: isStreaming ? AppTheme.success : AppTheme.textSecondary
            )

            if normalizedSystemPrompt != nil {
                ClaudeCapsuleTag(
                    title: "System prompt active",
                    systemImage: "wand.and.stars",
                    tint: AppTheme.accentWarm
                )
            }

            Spacer()

            ClaudeCapsuleTag(
                title: workingDirectoryTitle,
                systemImage: "folder",
                tint: AppTheme.textMuted
            )
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ClaudeCapsuleTag(
                        title: "Document-first chat",
                        systemImage: "text.alignleft",
                        tint: AppTheme.accentWarm
                    )
                    ClaudeCapsuleTag(
                        title: resolvedModelName,
                        systemImage: "cpu",
                        tint: AppTheme.accent
                    )
                }

                Text("Ask, inspect, and iterate in a calmer workspace.")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    "Responses read like a document, thinking stays tucked away until you need it, and the composer remains anchored like a workspace dock."
                )
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AppTheme.Spacing.md),
                    GridItem(.flexible(), spacing: AppTheme.Spacing.md),
                ],
                spacing: AppTheme.Spacing.md
            ) {
                ForEach(Self.starterPrompts) { prompt in
                    Button {
                        inputText = prompt.prompt
                        composerHasVisibleText = !prompt.prompt.isEmpty
                    } label: {
                        ClaudeStarterCard(prompt: prompt)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                ClaudeCapsuleTag(
                    title: "Enter to send",
                    systemImage: "arrow.up.circle",
                    tint: AppTheme.textMuted
                )
                ClaudeCapsuleTag(
                    title: "Shift+Enter for newline",
                    systemImage: "return",
                    tint: AppTheme.textMuted
                )
                ClaudeCapsuleTag(
                    title: "Cmd+V to paste images",
                    systemImage: "photo.on.rectangle",
                    tint: AppTheme.textMuted
                )
            }
        }
        .padding(AppTheme.Spacing.xxl)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.surfaceRaised.opacity(0.78),
                            AppTheme.surface.opacity(0.48),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .strokeBorder(AppTheme.borderHover.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 24, y: 12)
    }

    @ViewBuilder
    private func messageView(for message: ClaudeChatMessage) -> some View {
        switch message.role {
        case .user:
            userBubble(message)
        case .assistant:
            assistantBubble(message)
        case .toolUse, .toolResult:
            toolCard(message)
        }
    }

    @ViewBuilder
    private func userBubble(_ message: ClaudeChatMessage) -> some View {
        HStack(alignment: .top) {
            Spacer(minLength: 96)

            VStack(alignment: .trailing, spacing: AppTheme.Spacing.sm) {
                ClaudeCapsuleTag(
                    title: "Prompt",
                    systemImage: "arrow.up.right",
                    tint: AppTheme.textSecondary
                )

                VStack(alignment: .trailing, spacing: AppTheme.Spacing.sm) {
                    if !message.attachments.isEmpty {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(message.attachments) { attachment in
                                attachmentChip(attachment)
                            }
                        }
                    }

                    ClaudeMarkdownView(markdown: message.content)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.md)
                .frame(maxWidth: userBubbleWidth, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 18, y: 10)
                .hoverCopy(text: message.content)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: messageColumnWidth, alignment: .trailing)
    }

    @ViewBuilder
    private func attachmentChip(_ attachment: ClaudeChatAttachmentRecord) -> some View {
        ClaudeAttachmentThumbnailView(
            attachment: attachment,
            displayName: attachmentDisplayName(attachment)
        )
    }

    @ViewBuilder
    private func assistantBubble(_ message: ClaudeChatMessage) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ClaudeCapsuleTag(
                        title: "Claude",
                        systemImage: "sparkles",
                        tint: AppTheme.accentWarm
                    )

                    if message.isStreaming {
                        ClaudeCapsuleTag(
                            title: "Responding",
                            systemImage: "ellipsis.circle",
                            tint: AppTheme.success
                        )
                    }
                }

                if let thinking = message.thinkingContent, !thinking.isEmpty {
                    thinkingBlock(
                        thinking,
                        messageId: message.id,
                        isStreaming: message.isStreaming
                    )
                }

                if !message.content.isEmpty {
                    ClaudeMarkdownView(markdown: message.content)
                }
            }
            .frame(maxWidth: assistantColumnWidth, alignment: .leading)
            .hoverCopy(text: message.content)

            Spacer(minLength: 96)
        }
        .frame(maxWidth: messageColumnWidth, alignment: .leading)
    }

    @ViewBuilder
    private func thinkingBlock(_ text: String, messageId: UUID, isStreaming: Bool) -> some View {
        let isExpanded = showThinking.contains(messageId) || isStreaming

        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Button {
                withAnimation(AppTheme.Anim.normal) {
                    toggle(messageId, in: &showThinking)
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(isStreaming ? "Thinking..." : "Thinking complete")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    if isStreaming {
                        Circle()
                            .fill(AppTheme.accent)
                            .frame(width: 6, height: 6)
                            .modifier(PulseModifier())
                    }
                }
                .foregroundColor(AppTheme.textSecondary)
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            if isExpanded {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isStreaming ? AppTheme.accent : AppTheme.accent.opacity(0.4))
                        .frame(width: 3)
                        .modifier(BreathingModifier(isActive: isStreaming))

                    Text(text)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .italic()
                        .foregroundColor(AppTheme.textMuted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(AppTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .fill(AppTheme.surfaceRaised.opacity(0.56))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private func toolCard(_ message: ClaudeChatMessage) -> some View {
        let isExpanded = showToolDetails.contains(message.id) || message.isStreaming

        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                ClaudeCapsuleTag(
                    title: message.role == .toolResult ? "Tool result" : "Tool activity",
                    systemImage: toolIcon(for: message.toolName ?? ""),
                    tint: AppTheme.accentWarm
                )

                Button {
                    withAnimation(AppTheme.Anim.normal) {
                        toggle(message.id, in: &showToolDetails)
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.textMuted)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.toolName ?? "Tool")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.textPrimary)

                            Text(message.role == .toolResult ? "Finished step output" : "Running with live input")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textMuted)
                        }

                        Spacer(minLength: 0)

                        if message.isStreaming {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        }
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        if let input = message.toolInput, !input.isEmpty {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                Text("Input")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .textCase(.uppercase)
                                    .tracking(1)
                                    .foregroundStyle(AppTheme.textMuted)
                                Text(input)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(AppTheme.textSecondary)
                                    .textSelection(.enabled)
                            }
                        }

                        if !message.content.isEmpty {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                Text("Output")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .textCase(.uppercase)
                                    .tracking(1)
                                    .foregroundStyle(AppTheme.textMuted)
                                Text(message.content)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(AppTheme.textPrimary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
            .frame(maxWidth: 720, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                    .fill(AppTheme.surface.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )

            Spacer(minLength: 96)
        }
        .frame(maxWidth: messageColumnWidth, alignment: .leading)
    }

    private func toolIcon(for name: String) -> String {
        switch name.lowercased() {
        case "bash":
            return "terminal"
        case "read":
            return "doc.text"
        case "write", "edit":
            return "pencil.line"
        case "glob":
            return "folder.badge.gearshape"
        case "grep":
            return "magnifyingglass"
        default:
            return "wrench"
        }
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if !attachmentWarning.isEmpty {
                ToolMessageBanner(
                    systemImage: "exclamationmark.triangle",
                    message: attachmentWarning,
                    tint: AppTheme.warning
                )
            }

            if !composerImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(composerImages) { img in
                            composerImagePreview(img)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.xs)
                }
                .frame(height: 84)
            }

            ZStack(alignment: .topLeading) {
                if Self.shouldShowComposerPlaceholder(
                    inputText: inputText,
                    hasVisibleDraftText: composerHasVisibleText,
                    hasImages: !composerImages.isEmpty
                ) {
                    composerPlaceholder
                }

                ClaudeChatComposer(
                    text: $inputText,
                    isStreaming: isStreaming,
                    onSubmit: { sendMessage() },
                    onPasteImages: { images in handlePastedImages(images) },
                    onEscape: {
                        if isStreaming {
                            cancellationRequested = true
                            client.cancel()
                        }
                    },
                    onVisibleTextChange: { hasVisibleText in
                        composerHasVisibleText = hasVisibleText
                    }
                )
            }
            .frame(minHeight: 88, maxHeight: 220)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                    .fill(AppTheme.background.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )

            HStack(spacing: AppTheme.Spacing.sm) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    ClaudeComposerAccessoryButton(systemImage: "plus") {
                        attachmentWarning = "Paste images with Cmd+V to stage them in the composer."
                    }
                    .help("Paste images with Cmd+V")

                    ClaudeComposerAccessoryButton(systemImage: "folder") {
                        chooseWorkingDirectory()
                    }
                    .help("Choose working directory")

                    ClaudeComposerAccessoryButton(systemImage: "clock.arrow.circlepath") {
                        historyDrawerOpenedAt = Date()
                        loadHistory(reset: true)
                        showHistory = true
                    }
                    .help("Open chat history")
                }

                Spacer(minLength: AppTheme.Spacing.md)

                Text(isStreaming ? "Esc to stop generation" : "Enter to send · Shift+Enter for newline · Cmd+V to paste images")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textMuted)
                    .lineLimit(1)

                if normalizedSystemPrompt != nil {
                    ClaudeCapsuleTag(
                        title: "System",
                        systemImage: "wand.and.stars",
                        tint: AppTheme.accentWarm
                    )
                }

                ClaudeCapsuleTag(
                    title: resolvedModelName,
                    systemImage: "cpu",
                    tint: AppTheme.accent
                )

                if isStreaming {
                    StyledButton("Stop", systemImage: "stop.fill", variant: .destructive) {
                        cancellationRequested = true
                        client.cancel()
                    }
                } else {
                    ClaudeSendButton(disabled: sendDisabled) {
                        sendMessage()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: 960)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.backgroundRaised.opacity(0.96),
                            AppTheme.surface.opacity(0.86),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(composerBorderColor, lineWidth: 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                .padding(1)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 24, y: 14)
    }

    private var messageColumnWidth: CGFloat {
        920
    }

    private var assistantColumnWidth: CGFloat {
        760
    }

    private var userBubbleWidth: CGFloat {
        560
    }

    private var composerReservedSpace: CGFloat {
        composerImages.isEmpty ? 220 : 292
    }

    private var resolvedModelName: String {
        let name = currentModel.isEmpty ? settings.model : currentModel
        return name.isEmpty ? "Claude" : name
    }

    private var composerBorderColor: Color {
        if isStreaming {
            return AppTheme.accent.opacity(0.55)
        }
        if composerHasVisibleText || !inputText.isEmpty || !composerImages.isEmpty {
            return AppTheme.accent.opacity(0.34)
        }
        return AppTheme.borderHover
    }

    private func attachmentDisplayName(_ attachment: ClaudeChatAttachmentRecord) -> String {
        attachment.fileName.split(separator: "-").last.map(String.init) ?? attachment.fileName
    }

    private var sendDisabled: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImages = !composerImages.isEmpty
        return (!hasText && !hasImages) || !settings.isAvailable
    }

    private var streamingMessage: ClaudeChatMessage? {
        let currentStreamingText = streamingText + pendingStreamingText
        let currentStreamingThinking = streamingThinking + pendingStreamingThinking

        guard !currentStreamingText.isEmpty || !currentStreamingThinking.isEmpty else {
            return nil
        }

        return ClaudeChatMessage(
            id: Self.streamingMessageID,
            role: .assistant,
            content: currentStreamingText,
            thinkingContent: currentStreamingThinking.isEmpty ? nil : currentStreamingThinking,
            toolName: nil,
            toolInput: nil,
            isStreaming: true
        )
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentImages = composerImages
        guard (!trimmed.isEmpty || !currentImages.isEmpty), !isStreaming else { return }

        if !settings.isAvailable {
            errorMessage = "Claude CLI not found. Configure it in Settings first."
            return
        }

        // Persist attachment files and build attachment records
        var attachmentRecords: [ClaudeChatAttachmentRecord] = []
        var persistedPaths: [String] = []

        for img in currentImages {
            let recordID = activeConversationRecordID ?? UUID()
            let storedFileName = "\(recordID.uuidString)-\(img.fileName)"
            do {
                _ = try HistoryStore.syncSaveClaudeChatAttachment(data: img.data, fileName: storedFileName)
                let record = ClaudeChatAttachmentRecord(
                    type: "image",
                    fileName: storedFileName,
                    mimeType: img.mimeType,
                    sizeBytes: img.data.count
                )
                attachmentRecords.append(record)

                if let url = try? HistoryStore.syncClaudeChatAttachmentURL(fileName: storedFileName) {
                    persistedPaths.append(url.path)
                }
            } catch {
                attachmentWarning = "Failed to save attachment: \(error.localizedDescription)"
                let referenceID = activeReferenceID.isEmpty ? AppLogger.makeReferenceID() : activeReferenceID
                activeReferenceID = referenceID
                Task {
                    _ = await AppLogger.shared.error(
                        category: .claudechat,
                        event: "attachment_save_failed",
                        referenceID: referenceID,
                        message: "Failed to persist Claude chat attachment.",
                        metadata: [
                            "fileName": storedFileName,
                            "mimeType": img.mimeType
                        ],
                        error: error,
                        stackTrace: []
                    )
                }
            }
        }

        let prompt = ClaudeChatView.buildOutgoingPrompt(
            text: trimmed, imagePaths: persistedPaths)

        messages.append(
            ClaudeChatMessage(
                id: UUID(),
                role: .user,
                content: trimmed.isEmpty ? "(image attached)" : trimmed,
                thinkingContent: nil,
                toolName: nil,
                toolInput: nil,
                isStreaming: false,
                attachments: attachmentRecords
            ))
        inputText = ""
        composerHasVisibleText = false
        composerImages = []
        attachmentWarning = ""
        errorMessage = ""
        isStreaming = true
        streamingFlushTask?.cancel()
        streamingText = ""
        streamingThinking = ""
        pendingStreamingText = ""
        pendingStreamingThinking = ""
        cancellationRequested = false
        let requestReferenceID = AppLogger.makeReferenceID()
        activeReferenceID = requestReferenceID

        let outgoingSessionId = sessionId.isEmpty ? nil : sessionId

        Task {
            await client.send(
                request: ClaudeCLITurnRequest(
                    prompt: prompt,
                    sessionID: outgoingSessionId,
                    referenceID: requestReferenceID
                ),
                settings: settings,
                workingDirectory: workingDirectory
            ) { event in
                Task { @MainActor in
                    handleEvent(event)
                }
            }
        }
    }

    private func composerImagePreview(_ image: ClaudeComposerImage) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)

        return ZStack(alignment: .topTrailing) {
            Image(nsImage: image.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 76, height: 76)
                .clipShape(shape)
                .overlay(
                    shape
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                )

            Button {
                composerImages.removeAll { $0.id == image.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textMuted)
                    .background(Circle().fill(AppTheme.surface))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }

    private var composerPlaceholder: some View {
        Text("Use Claude to inspect the repo, debug an issue, or shape the next change...")
            .font(.system(size: AppTheme.Typography.composerInput, weight: .regular))
            .foregroundColor(AppTheme.textMuted)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm + 2)
            .allowsHitTesting(false)
    }

    /// Build the prompt string sent to Claude CLI, injecting image paths when present.
    static func buildOutgoingPrompt(text: String, imagePaths: [String]) -> String {
        guard !imagePaths.isEmpty else { return text }

        var parts: [String] = []
        parts.append("Attached images:")
        for path in imagePaths {
            parts.append("- \(path)")
        }
        parts.append("")
        parts.append("User request:")
        parts.append(text.isEmpty ? "Please describe and analyze the attached image(s)." : text)
        return parts.joined(separator: "\n")
    }

    static func shouldShowComposerPlaceholder(
        inputText: String,
        hasVisibleDraftText: Bool,
        hasImages: Bool
    ) -> Bool {
        inputText.isEmpty && !hasVisibleDraftText && !hasImages
    }

    @MainActor
    private func handleEvent(_ event: ClaudeCLIEvent) {
        switch event {
        case .initialized(let sid, let model):
            sessionId = sid
            currentModel = model

        case .thinkingDelta(let text):
            pendingStreamingThinking += text
            scheduleStreamingFlushIfNeeded()

        case .textDelta(let text):
            pendingStreamingText += text
            scheduleStreamingFlushIfNeeded()

        case .toolUseStart(let id, let name):
            finalizeStreamingAssistantIfNeeded()
            toolNamesByUseID[id] = name
            messages.append(
                ClaudeChatMessage(
                    id: UUID(),
                    role: .toolUse,
                    content: "",
                    thinkingContent: nil,
                    toolName: name,
                    toolInput: "",
                    isStreaming: true
                ))

        case .toolInputDelta(let text):
            guard let lastIndex = messages.indices.last,
                messages[lastIndex].role == .toolUse
            else {
                return
            }

            let currentInput = (messages[lastIndex].toolInput ?? "") + text
            messages[lastIndex].toolInput = currentInput

        case .toolResult(let toolUseId, let content):
            finalizeStreamingAssistantIfNeeded()
            messages.append(
                ClaudeChatMessage(
                    id: UUID(),
                    role: .toolResult,
                    content: content,
                    thinkingContent: nil,
                    toolName: toolNamesByUseID[toolUseId] ?? toolUseId,
                    toolInput: nil,
                    isStreaming: false
                ))

        case .blockStop:
            if let lastIndex = messages.indices.last,
                messages[lastIndex].role == .toolUse,
                messages[lastIndex].isStreaming
            {
                messages[lastIndex].isStreaming = false
            }

        case .result(let isError, let cost, let inTok, let outTok, let duration, let sid):
            finalizeStreamingAssistantIfNeeded()
            if !sid.isEmpty {
                sessionId = sid
            }
            totalCostUSD += cost
            inputTokens += inTok
            outputTokens += outTok
            totalDurationMs += duration
            isStreaming = false

            if isError {
                errorMessage = "Claude returned an error."
            }

            saveHistory()

        case .completed(let exitCode):
            if cancellationRequested {
                finalizeStreamingAssistantIfNeeded()
                isStreaming = false
                cancellationRequested = false
                return
            }

            if exitCode != 0 {
                finalizeStreamingAssistantIfNeeded()
                isStreaming = false
                if errorMessage.isEmpty {
                    errorMessage = "Claude CLI exited with code \(exitCode)."
                }
            }

        case .error(let message):
            if cancellationRequested {
                finalizeStreamingAssistantIfNeeded()
                isStreaming = false
                return
            }

            finalizeStreamingAssistantIfNeeded()
            isStreaming = false
            errorMessage = message
        }
    }

    private func finalizeStreamingAssistantIfNeeded() {
        streamingFlushTask?.cancel()
        streamingFlushTask = nil

        let finalStreamingText = streamingText + pendingStreamingText
        let finalStreamingThinking = streamingThinking + pendingStreamingThinking

        guard !finalStreamingText.isEmpty || !finalStreamingThinking.isEmpty else { return }

        let message = ClaudeChatMessage(
            id: UUID(),
            role: .assistant,
            content: finalStreamingText,
            thinkingContent: finalStreamingThinking.isEmpty ? nil : finalStreamingThinking,
            toolName: nil,
            toolInput: nil,
            isStreaming: false
        )
        messages.append(message)
        streamingText = ""
        streamingThinking = ""
        pendingStreamingText = ""
        pendingStreamingThinking = ""

        if toolVisibilityContext.isVisible {
            streamingScrollRevision += 1
        }
    }

    private var shouldPauseStreamingCommitsWhileHidden: Bool {
        toolVisibilityContext.isPausedWhileHidden
    }

    private func scheduleStreamingFlushIfNeeded() {
        guard streamingFlushTask == nil else {
            return
        }

        guard !(shouldPauseStreamingCommitsWhileHidden && !toolVisibilityContext.isVisible) else {
            return
        }

        streamingFlushTask = Task {
            do {
                try await Task.sleep(nanoseconds: Self.streamingCommitIntervalNs)
            } catch {
                return
            }

            await MainActor.run {
                flushPendingStreamingBuffers(triggerScroll: true)
            }
        }
    }

    @MainActor
    private func flushPendingStreamingBuffers(triggerScroll: Bool) {
        streamingFlushTask?.cancel()
        streamingFlushTask = nil

        guard !pendingStreamingText.isEmpty || !pendingStreamingThinking.isEmpty else {
            return
        }

        let textDeltaLength = pendingStreamingText.count
        let thinkingDeltaLength = pendingStreamingThinking.count

        streamingText += pendingStreamingText
        streamingThinking += pendingStreamingThinking
        pendingStreamingText = ""
        pendingStreamingThinking = ""

        RenderingPerformance.record(
            .claudeStreamBatchCommitted,
            toolID: .aiChat,
            referenceID: activeReferenceID.isEmpty ? nil : activeReferenceID,
            metadata: [
                "isVisible": String(toolVisibilityContext.isVisible),
                "textDeltaLength": String(textDeltaLength),
                "thinkingDeltaLength": String(thinkingDeltaLength)
            ]
        )

        if triggerScroll && toolVisibilityContext.isVisible {
            streamingScrollRevision += 1
        }
    }

    private func ensureConversationRecordIdentity() {
        if activeConversationRecordID == nil {
            activeConversationRecordID = UUID()
            activeConversationCreatedAt = Date()
        }
    }

    private func makeConversationRecord() -> ClaudeChatHistoryRecord {
        ensureConversationRecordIdentity()
        return ClaudeChatHistoryRecord(
            id: activeConversationRecordID!,
            createdAt: activeConversationCreatedAt!,
            systemPrompt: normalizedSystemPrompt,
            workingDirectory: workingDirectory,
            messages: messages.map { message in
                ClaudeChatMessageRecord(
                    role: message.role.rawValue,
                    content: message.content,
                    thinkingContent: message.thinkingContent,
                    toolName: message.toolName,
                    toolInput: message.toolInput,
                    attachments: message.attachments.isEmpty ? nil : message.attachments
                )
            },
            model: currentModel.isEmpty ? settings.model : currentModel,
            totalCostUSD: totalCostUSD > 0 ? totalCostUSD : nil,
            inputTokens: inputTokens > 0 ? inputTokens : nil,
            outputTokens: outputTokens > 0 ? outputTokens : nil,
            durationMs: totalDurationMs > 0 ? totalDurationMs : nil,
            sessionId: sessionId.isEmpty ? nil : sessionId,
            referenceID: activeReferenceID.isEmpty ? AppLogger.makeReferenceID() : activeReferenceID
        )
    }

    private func saveHistory() {
        let record = makeConversationRecord()
        Task {
            try? await HistoryStore.shared.save(record)
        }
    }

    private var normalizedSystemPrompt: String? {
        let trimmed = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func clearChat() {
        cancellationRequested = false
        client.cancel()
        messages = []
        inputText = ""
        composerHasVisibleText = false
        isStreaming = false
        streamingFlushTask?.cancel()
        streamingText = ""
        streamingThinking = ""
        pendingStreamingText = ""
        pendingStreamingThinking = ""
        errorMessage = ""
        sessionId = ""
        currentModel = settings.model
        totalCostUSD = 0
        inputTokens = 0
        outputTokens = 0
        totalDurationMs = 0
        activeReferenceID = ""
        showThinking = []
        showToolDetails = []
        toolNamesByUseID = [:]
        activeConversationRecordID = nil
        activeConversationCreatedAt = nil
        composerImages = []
        attachmentWarning = ""
        workingDirectory = Self.defaultWorkingDirectory
    }

    private func handlePastedImages(_ images: [NSImage]) {
        let pastedImages = images.compactMap { image -> ClaudeComposerImage? in
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:])
            else { return nil }

            return ClaudeComposerImage(
                image: image,
                fileName: "\(UUID().uuidString).png",
                data: pngData,
                mimeType: "image/png"
            )
        }

        composerImages.append(contentsOf: pastedImages)
    }

    private func loadHistory(reset: Bool) {
        Task {
            let offset = reset ? 0 : chatHistory.count
            let records = (try? await HistoryStore.shared.listClaudeChat(limit: historyPageSize, offset: offset)) ?? []
            let totalCount = (try? await HistoryStore.shared.count(category: .claudeChat)) ?? 0
            await MainActor.run {
                if reset {
                    chatHistory = records
                } else {
                    chatHistory.append(contentsOf: records)
                }
                chatHistoryHasMore = offset + records.count < totalCount
            }
        }
    }

    private func restoreChat(_ record: ClaudeChatHistoryRecord) {
        messages = record.messages.map { item in
            ClaudeChatMessage(
                id: UUID(),
                role: ClaudeChatMessageRole(rawValue: item.role) ?? .assistant,
                content: item.content,
                thinkingContent: item.thinkingContent,
                toolName: item.toolName,
                toolInput: item.toolInput,
                isStreaming: false,
                attachments: item.attachments ?? []
            )
        }

        showThinking = []
        toolNamesByUseID = [:]
        sessionId = record.sessionId ?? ""
        currentModel = record.model
        workingDirectory = record.workingDirectory ?? Self.defaultWorkingDirectory
        totalCostUSD = record.totalCostUSD ?? 0
        inputTokens = record.inputTokens ?? 0
        outputTokens = record.outputTokens ?? 0
        totalDurationMs = record.durationMs ?? 0
        activeReferenceID = record.referenceID
        errorMessage = ""
        inputText = ""
        composerHasVisibleText = false
        composerImages = []
        attachmentWarning = ""

        // Restore conversation identity so continued chat overwrites the same record
        activeConversationRecordID = record.id
        activeConversationCreatedAt = record.createdAt
    }

    private func deleteChat(_ record: ClaudeChatHistoryRecord) {
        Task {
            try? await HistoryStore.shared.deleteClaudeChat(id: record.id)
            let records = (try? await HistoryStore.shared.listClaudeChat(limit: historyPageSize, offset: 0)) ?? []
            let totalCount = (try? await HistoryStore.shared.count(category: .claudeChat)) ?? 0
            await MainActor.run {
                chatHistory = records
                chatHistoryHasMore = records.count < totalCount
            }
        }
    }

    private func clearChatHistory() {
        Task {
            try? await HistoryStore.shared.clear(category: .claudeChat)
            await MainActor.run {
                chatHistory = []
                chatHistoryHasMore = false
            }
        }
    }

    private var workingDirectoryTitle: String {
        let lastPathComponent = URL(fileURLWithPath: workingDirectory).lastPathComponent
        return lastPathComponent.isEmpty ? workingDirectory : lastPathComponent
    }

    private func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if FileManager.default.fileExists(atPath: workingDirectory) {
            panel.directoryURL = URL(fileURLWithPath: workingDirectory)
        }

        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }

    private func toggle(_ id: UUID, in set: inout Set<UUID>) {
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
    }
}

enum ClaudeChatMessageRole: String {
    case user
    case assistant
    case toolUse
    case toolResult
}

struct ClaudeChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ClaudeChatMessageRole
    var content: String
    var thinkingContent: String?
    var toolName: String?
    var toolInput: String?
    var isStreaming: Bool
    var attachments: [ClaudeChatAttachmentRecord]

    init(
        id: UUID,
        role: ClaudeChatMessageRole,
        content: String,
        thinkingContent: String?,
        toolName: String?,
        toolInput: String?,
        isStreaming: Bool,
        attachments: [ClaudeChatAttachmentRecord] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.toolName = toolName
        self.toolInput = toolInput
        self.isStreaming = isStreaming
        self.attachments = attachments
    }
}

extension ClaudeChatAttachmentRecord: Equatable {
    public static func ==(lhs: ClaudeChatAttachmentRecord, rhs: ClaudeChatAttachmentRecord) -> Bool {
        lhs.id == rhs.id
            && lhs.type == rhs.type
            && lhs.fileName == rhs.fileName
            && lhs.mimeType == rhs.mimeType
            && lhs.sizeBytes == rhs.sizeBytes
    }
}

struct ClaudeConversationRenderState: Equatable {
    let messages: [ClaudeChatMessage]
    let streamingMessage: ClaudeChatMessage?
    let isStreaming: Bool
    let workingDirectoryTitle: String
    let hasSystemPrompt: Bool
    let expandedThinkingIDs: Set<UUID>
    let expandedToolDetailIDs: Set<UUID>
    let composerReservedSpace: CGFloat
    let isToolVisible: Bool
    let streamingScrollRevision: Int

    static func make(
        messages: [ClaudeChatMessage] = [],
        streamingMessage: ClaudeChatMessage? = nil,
        isStreaming: Bool,
        workingDirectoryTitle: String,
        hasSystemPrompt: Bool,
        expandedThinkingIDs: Set<UUID> = [],
        expandedToolDetailIDs: Set<UUID> = [],
        composerImageCount: Int,
        draftText: String,
        hasVisibleDraftText: Bool,
        isToolVisible: Bool,
        streamingScrollRevision: Int
    ) -> ClaudeConversationRenderState {
        ClaudeConversationRenderState(
            messages: messages,
            streamingMessage: streamingMessage,
            isStreaming: isStreaming,
            workingDirectoryTitle: workingDirectoryTitle,
            hasSystemPrompt: hasSystemPrompt,
            expandedThinkingIDs: expandedThinkingIDs,
            expandedToolDetailIDs: expandedToolDetailIDs,
            composerReservedSpace: composerImageCount == 0 ? 220 : 292,
            isToolVisible: isToolVisible,
            streamingScrollRevision: streamingScrollRevision
        )
    }
}

/// An image staged in the composer, not yet sent.
struct ClaudeComposerImage: Identifiable {
    let id = UUID()
    let image: NSImage
    let fileName: String
    let data: Data
    let mimeType: String
}

private struct ClaudeStarterPrompt: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let prompt: String
}

private struct ClaudeConversationPane<LeadIn: View, EmptyState: View, MessageContent: View>: View, Equatable {
    let state: ClaudeConversationRenderState
    let leadIn: () -> LeadIn
    let emptyState: () -> EmptyState
    let messageView: (ClaudeChatMessage) -> MessageContent

    static func ==(
        lhs: ClaudeConversationPane<LeadIn, EmptyState, MessageContent>,
        rhs: ClaudeConversationPane<LeadIn, EmptyState, MessageContent>
    ) -> Bool {
        lhs.state == rhs.state
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxxl) {
                    if state.messages.isEmpty && state.streamingMessage == nil && !state.isStreaming {
                        emptyState()
                    } else {
                        leadIn()

                        LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xxxl) {
                            ForEach(state.messages) { message in
                                messageView(message)
                            }

                            if let streamingMessage = state.streamingMessage {
                                messageView(streamingMessage)
                            }
                        }
                    }

                    Color.clear
                        .frame(height: state.composerReservedSpace)
                        .id("bottom")
                }
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.top, AppTheme.Spacing.xl)
                .padding(.bottom, AppTheme.Spacing.md)
            }
            .onChange(of: state.messages.count) {
                guard state.isToolVisible else {
                    return
                }

                withAnimation(AppTheme.Anim.fast) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: state.streamingScrollRevision) {
                guard state.isToolVisible else {
                    return
                }

                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        .frame(minHeight: 220, maxHeight: .infinity)
    }
}

private struct ClaudeStarterCard: View {
    let prompt: ClaudeStarterPrompt

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text(prompt.title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text(prompt.detail)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: AppTheme.Spacing.xs) {
                Text("Use prompt")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(1)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(AppTheme.accentWarm)
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(isHovered ? AppTheme.surfaceHover.opacity(0.72) : AppTheme.surface.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .strokeBorder(AppTheme.borderHover.opacity(isHovered ? 1.0 : 0.7), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isHovered ? 0.16 : 0.08), radius: 16, y: 10)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .toolHoverTracking($isHovered)
    }
}

private struct ClaudeCapsuleTag: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(tint.opacity(0.10))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct ClaudeComposerAccessoryButton: View {
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 32, height: 32)
                .background(isHovered ? AppTheme.surfaceHover.opacity(0.82) : AppTheme.surfaceRaised.opacity(0.62))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .toolHoverTracking($isHovered)
    }
}

private struct ClaudeSendButton: View {
    let disabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.background)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(AppTheme.accentGradient)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: AppTheme.accent.opacity(isHovered ? 0.30 : 0.18), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .scaleEffect(disabled ? 1 : (isHovered ? 1.03 : 1.0))
        .toolHoverTracking($isHovered)
    }
}

private struct PulseModifier: ViewModifier {
    @Environment(\.toolUIActivity) private var toolUIActivity
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(
                toolUIActivity.allowsDecorativeAnimations
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : nil,
                value: isPulsing
            )
            .onAppear {
                isPulsing = toolUIActivity.allowsDecorativeAnimations
            }
            .onChange(of: toolUIActivity.isVisible) { _, isVisible in
                isPulsing = isVisible
            }
    }
}

private struct BreathingModifier: ViewModifier {
    @Environment(\.toolUIActivity) private var toolUIActivity
    let isActive: Bool
    @State private var isBreathing = false

    func body(content: Content) -> some View {
        content
            .opacity(isActive && isBreathing ? 0.4 : 1.0)
            .animation(
                isActive && toolUIActivity.allowsDecorativeAnimations
                    ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                    : nil,
                value: isBreathing
            )
            .onAppear {
                isBreathing = isActive && toolUIActivity.allowsDecorativeAnimations
            }
            .onChange(of: isActive) { _, newValue in
                isBreathing = newValue && toolUIActivity.allowsDecorativeAnimations
            }
            .onChange(of: toolUIActivity.isVisible) { _, isVisible in
                isBreathing = isVisible && isActive
            }
    }
}

#if DEBUG
    struct ClaudeChatView_Previews: PreviewProvider {
        static var previews: some View {
            ClaudeChatView()
                .frame(width: 900, height: 700)
        }
    }
#endif
