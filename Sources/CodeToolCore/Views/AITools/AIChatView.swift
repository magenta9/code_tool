import CodeToolUI
import SwiftUI

#if canImport(AppKit)
    import AppKit
#endif

public struct AIChatView: View {
    private var settings = MiniMaxSettingsStore.shared

    @State private var messages: [(role: String, content: String)] = []
    @State private var inputText: String = ""
    @State private var isStreaming: Bool = false
    @State private var streamingContent: String = ""
    @State private var errorMessage: String = ""
    @State private var systemPrompt: String = ""
    @State private var showSystemPrompt: Bool = false
    @State private var lastPromptTokens: Int = 0
    @State private var lastCompletionTokens: Int = 0
    @State private var lastTotalTokens: Int = 0
    @State private var showHistory = false
    @State private var chatHistory: [ChatHistoryRecord] = []

    public init() {}

    public var body: some View {
        ToolWorkbench(
            eyebrow: "AI Assistant",
            title: "AI Chat",
            description: "Chat with MiniMax M2.7-highspeed model",
            systemImage: "bubble.left.and.bubble.right",
            statusItems: statusItems
        ) {
            StyledButton("History", systemImage: "clock.arrow.circlepath", variant: .secondary) {
                loadHistory()
                showHistory = true
            }
            StyledButton("Clear Chat", systemImage: "trash", variant: .ghost) {
                clearChat()
            }
            CopyButton("Copy Last", text: lastAssistantReply)
        } content: {
            VStack(spacing: 0) {
                if !settings.isConfigured {
                    ToolMessageBanner(
                        systemImage: "exclamationmark.triangle",
                        message:
                            "MiniMax API key is not configured. Please set it in MiniMax Settings.",
                        tint: AppTheme.warning
                    )
                    .padding(.horizontal, AppTheme.Spacing.xxl)
                    .padding(.top, AppTheme.Spacing.xl)
                }

                if !errorMessage.isEmpty {
                    ToolMessageBanner(
                        systemImage: "xmark.octagon",
                        message: errorMessage,
                        tint: AppTheme.error
                    )
                    .padding(.horizontal, AppTheme.Spacing.xxl)
                    .padding(.top, AppTheme.Spacing.sm)
                }

                // System prompt toggle
                systemPromptSection
                    .padding(.horizontal, AppTheme.Spacing.xxl)
                    .padding(.top, AppTheme.Spacing.xl)

                // Message list
                messageListView
                    .padding(.horizontal, AppTheme.Spacing.xxl)
                    .padding(.top, AppTheme.Spacing.md)

                // Input area
                inputArea
                    .padding(.horizontal, AppTheme.Spacing.xxl)
                    .padding(.top, AppTheme.Spacing.md)
                    .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .overlay {
            if showHistory {
                HistoryDrawer(
                    isPresented: $showHistory,
                    title: "Chat History",
                    items: chatHistory,
                    onSelect: { record in restoreChat(record) },
                    onDelete: { record in deleteChat(record) },
                    onClearAll: { clearChatHistory() }
                )
            }
        }
    }

    // MARK: - Status Items

    private var statusItems: [ToolStatusItem] {
        var items: [ToolStatusItem] = []
        if !messages.isEmpty {
            let count = messages.count
            items.append(
                ToolStatusItem(
                    title: "\(count) message\(count == 1 ? "" : "s")",
                    systemImage: "bubble.left.and.bubble.right",
                    tint: AppTheme.accent
                ))
        }
        if lastTotalTokens > 0 {
            items.append(
                ToolStatusItem(
                    title: "~\(lastTotalTokens) tokens",
                    systemImage: "number.circle",
                    tint: AppTheme.accentWarm
                ))
            items.append(
                ToolStatusItem(
                    title: "↑~\(lastPromptTokens) ↓~\(lastCompletionTokens)",
                    systemImage: "arrow.up.arrow.down",
                    tint: AppTheme.textMuted
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

    // MARK: - System Prompt

    private var systemPromptSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Button {
                withAnimation(AppTheme.Anim.normal) {
                    showSystemPrompt.toggle()
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: showSystemPrompt ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text("System Prompt")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("(optional)")
                        .font(.caption2)
                        .foregroundColor(AppTheme.textMuted)
                }
                .foregroundColor(AppTheme.textSecondary)
            }
            .buttonStyle(.plain)

            if showSystemPrompt {
                StyledTextEditor(
                    text: $systemPrompt,
                    placeholder: "Enter a system prompt to guide the AI behavior…"
                )
                .frame(height: 72)
            }
        }
    }

    // MARK: - Message List

    private var messageListView: some View {
        StyledPanel {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        if messages.isEmpty && !isStreaming {
                            emptyStateView
                        }

                        ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                            messageBubble(role: message.role, content: message.content, id: index)
                        }

                        // Streaming bubble
                        if isStreaming && !streamingContent.isEmpty {
                            messageBubble(role: "assistant", content: streamingContent, id: 0)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(AppTheme.Spacing.md)
                }
                .onChange(of: messages.count) {
                    withAnimation(AppTheme.Anim.fast) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: streamingContent) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .frame(minHeight: 200, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28))
                .foregroundColor(AppTheme.textMuted)
            Text("Start a conversation")
                .font(.subheadline)
                .foregroundColor(AppTheme.textMuted)
            Text("Type a message below to begin chatting with the AI.")
                .font(.caption)
                .foregroundColor(AppTheme.textMuted.opacity(0.7))
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(.vertical, AppTheme.Spacing.xl)
    }

    @ViewBuilder
    private func messageBubble(role: String, content: String, id: Int) -> some View {
        AIChatMessageBubble(role: role, content: content)
            .id(id)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: AppTheme.Spacing.sm) {
             ZStack(alignment: .topLeading) {
                 if inputText.isEmpty {
                    Text("Type a message… (Enter to send, Shift+Enter for newline)")
                        .font(.body)
                        .foregroundColor(AppTheme.textMuted)
                        .padding(.horizontal, AppTheme.Spacing.sm)
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .allowsHitTesting(false)
                 }

                ClaudeChatComposer(
                    text: $inputText,
                    isStreaming: isStreaming,
                    onSubmit: { sendMessage() },
                    onPasteImages: { _ in },
                    onEscape: {}
                )
            }
            .frame(minHeight: 36, maxHeight: 120)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(AppTheme.background.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )

            StyledIconButton("paperplane.fill", help: "Send message") {
                sendMessage()
            }
            .disabled(
                inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStreaming
            )
            .opacity(
                inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStreaming
                    ? 0.5 : 1.0)
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        messages.append((role: "user", content: trimmed))
        inputText = ""
        errorMessage = ""
        isStreaming = true
        streamingContent = ""
        let referenceID = AppLogger.makeReferenceID()

        Task {
            do {
                var apiMessages: [MiniMaxAPIClient.ChatMessage] = []

                let trimmedPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedPrompt.isEmpty {
                    apiMessages.append(
                        MiniMaxAPIClient.ChatMessage(role: "system", content: trimmedPrompt))
                }

                for msg in messages {
                    apiMessages.append(
                        MiniMaxAPIClient.ChatMessage(role: msg.role, content: msg.content))
                }

                try await MiniMaxAPIClient.shared.chatCompletionStream(
                    messages: apiMessages,
                    temperature: 0.7,
                    maxTokens: 2048,
                    referenceID: referenceID
                ) { delta in
                    Task { @MainActor in
                        streamingContent += delta
                    }
                }

                await MainActor.run {
                    let finalContent = streamingContent
                    messages.append((role: "assistant", content: finalContent))
                    streamingContent = ""
                    isStreaming = false

                    // Approximate token counts (streaming doesn't return usage)
                    let approxPrompt = apiMessages.reduce(0) { $0 + $1.content.count / 4 }
                    let approxCompletion = finalContent.count / 4
                    lastPromptTokens = approxPrompt
                    lastCompletionTokens = approxCompletion
                    lastTotalTokens = approxPrompt + approxCompletion
                }

                let (snapshotMessages, promptTk, completionTk, totalTk) = await MainActor.run {
                    (messages, lastPromptTokens, lastCompletionTokens, lastTotalTokens)
                }
                let record = ChatHistoryRecord(
                    id: UUID(),
                    createdAt: Date(),
                    systemPrompt: trimmedPrompt,
                    messages: snapshotMessages.map {
                        ChatMessageRecord(role: $0.role, content: $0.content)
                    },
                    model: MiniMaxSettingsStore.shared.chatModel,
                    promptTokens: promptTk,
                    completionTokens: completionTk,
                    totalTokens: totalTk,
                    referenceID: referenceID
                )
                try? await HistoryStore.shared.save(record)
            } catch {
                await MainActor.run {
                    if !streamingContent.isEmpty {
                        messages.append((role: "assistant", content: streamingContent))
                    }
                    streamingContent = ""
                    isStreaming = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func clearChat() {
        messages = []
        inputText = ""
        streamingContent = ""
        errorMessage = ""
        isStreaming = false
        lastPromptTokens = 0
        lastCompletionTokens = 0
        lastTotalTokens = 0
    }

    private var lastAssistantReply: String {
        messages.last(where: { $0.role == "assistant" })?.content ?? ""
    }

    // MARK: - History

    private func loadHistory() {
        Task {
            let records = (try? await HistoryStore.shared.listChat()) ?? []
            await MainActor.run { chatHistory = records }
        }
    }

    private func restoreChat(_ record: ChatHistoryRecord) {
        messages = record.messages.map { (role: $0.role, content: $0.content) }
        systemPrompt = record.systemPrompt
        lastPromptTokens = record.promptTokens
        lastCompletionTokens = record.completionTokens
        lastTotalTokens = record.totalTokens
        errorMessage = ""
        if !record.systemPrompt.isEmpty { showSystemPrompt = true }
    }

    private func deleteChat(_ record: ChatHistoryRecord) {
        Task {
            try? await HistoryStore.shared.deleteChat(id: record.id)
            let records = (try? await HistoryStore.shared.listChat()) ?? []
            await MainActor.run { chatHistory = records }
        }
    }

    private func clearChatHistory() {
        Task {
            try? await HistoryStore.shared.clear(category: .chat)
            await MainActor.run { chatHistory = [] }
        }
    }
}

// MARK: - Message Bubble

private struct AIChatMessageBubble: View {
    let role: String
    let content: String

    @State private var isHovered = false

    var body: some View {
        let isUser = role == "user"

        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: AppTheme.Spacing.xxs) {
                Text(isUser ? "You" : "Assistant")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundColor(isUser ? AppTheme.accent : AppTheme.accentWarm)

                Group {
                    if isUser {
                        Text(content)
                            .font(.body)
                            .foregroundColor(AppTheme.textPrimary)
                    } else {
                        ClaudeMarkdownView(markdown: content)
                    }
                }
                .textSelection(.enabled)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .fill(isUser ? AppTheme.accent.opacity(0.12) : AppTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .strokeBorder(
                            isUser ? AppTheme.accent.opacity(0.22) : AppTheme.border,
                            lineWidth: 1
                        )
                )

                if isHovered {
                    CopyButton(text: content)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: isUser ? .topTrailing : .topLeading)))
                }
            }
            .onHover { isHovered = $0 }
            .animation(AppTheme.Anim.fast, value: isHovered)

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

#if DEBUG
    struct AIChatView_Previews: PreviewProvider {
        static var previews: some View {
            AIChatView()
                .frame(width: 700, height: 600)
        }
    }
#endif
