import CodeToolFoundation
import CodeToolUI
import SwiftUI

public struct MiniMaxChatView: View {
    private static let streamingMessageID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    @State private var messages: [MiniMaxChatMessage] = []
    @State private var inputText = ""
    @State private var isStreaming = false
    @State private var streamingText = ""
    @State private var errorMessage = ""
    @State private var showHistory = false
    @State private var chatHistory: [ChatHistoryRecord] = []
    @State private var chatHistoryHasMore = false
    @State private var historyDrawerOpenedAt: Date?
    @State private var currentSession: AIExecutionSession?
    @State private var scrollAnchor = 0

    private let historyPageSize = 20

    public init() {}

    public var body: some View {
        ToolWorkbench(
            eyebrow: "MiniMax",
            title: "AI Chat",
            description: "Minimal MiniMax text chat with streaming responses and local history.",
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
            VStack(spacing: AppTheme.Spacing.lg) {
                bannerStack

                conversationView

                composer
            }
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .overlay {
            if showHistory {
                HistoryDrawer(
                    isPresented: $showHistory,
                    title: "AI Chat History",
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
    }

    private var statusItems: [ToolStatusItem] {
        var items: [ToolStatusItem] = [
            ToolStatusItem(
                id: "minimax-chat-model",
                title: MiniMaxSettingsStore.shared.chatModel,
                systemImage: "cpu",
                tint: AppTheme.accent
            )
        ]

        if MiniMaxSettingsStore.shared.isConfigured {
            items.append(
                ToolStatusItem(
                    id: "minimax-chat-configured",
                    title: "Configured",
                    systemImage: "checkmark.circle.fill",
                    tint: AppTheme.success
                )
            )
        } else {
            items.append(
                ToolStatusItem(
                    id: "minimax-chat-missing-key",
                    title: "API Key Required",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: AppTheme.warning
                )
            )
        }

        items.append(
            ToolStatusItem(
                id: "minimax-chat-message-count",
                title: "\(messages.count) item\(messages.count == 1 ? "" : "s")",
                systemImage: "text.bubble",
                tint: AppTheme.textSecondary
            )
        )

        if isStreaming {
            items.append(
                ToolStatusItem(
                    id: "minimax-chat-streaming",
                    title: "Streaming…",
                    systemImage: "ellipsis.circle",
                    tint: AppTheme.success
                )
            )
        }

        return items
    }

    @ViewBuilder
    private var bannerStack: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if !MiniMaxSettingsStore.shared.isConfigured {
                ToolMessageBanner(
                    systemImage: "key.fill",
                    message: "MiniMax API key is required. Open Provider Settings to configure MiniMax before sending a message.",
                    tint: AppTheme.warning
                )
            }

            if !errorMessage.isEmpty {
                ToolMessageBanner(
                    systemImage: "xmark.octagon.fill",
                    message: errorMessage,
                    tint: AppTheme.error
                )
            }
        }
    }

    private var conversationView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    if displayMessages.isEmpty {
                        emptyState
                    } else {
                        ForEach(displayMessages) { message in
                            messageBubble(message)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.Spacing.lg)
            }
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                    .fill(AppTheme.panelTintStrong.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )
            .onChange(of: scrollAnchor) {
                withAnimation(AppTheme.Anim.fast) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Start a MiniMax conversation")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text("This chat keeps only the essentials: text input, streaming text output, clear chat, and local history restore.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.xl)
        .glassSurface(cornerRadius: AppTheme.Radius.lg, tint: AppTheme.panelTintStrong)
    }

    private func messageBubble(_ message: MiniMaxChatMessage) -> some View {
        HStack {
            if message.role == "assistant" {
                bubble(message, tint: AppTheme.panelTintStrong)
                Spacer(minLength: 72)
            } else {
                Spacer(minLength: 72)
                bubble(message, tint: AppTheme.accent.opacity(0.12))
            }
        }
    }

    private func bubble(_ message: MiniMaxChatMessage, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(message.role == "assistant" ? "MiniMax" : "You")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(message.role == "assistant" ? AppTheme.accentWarm : AppTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(1.0)

            Text(message.content)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .textSelection(.enabled)

            if message.isStreaming {
                Text("Streaming…")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.success)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: 760, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .fill(tint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            StyledTextEditor(
                text: $inputText,
                placeholder: "Ask MiniMax something…"
            )
            .frame(minHeight: 120, maxHeight: 220)

            HStack {
                Text(isStreaming ? "Wait for the current response to finish before sending again." : "Enter your prompt and send it to MiniMax.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textMuted)

                Spacer()

                StyledButton("Send", systemImage: "arrow.up.circle.fill", variant: .primary) {
                    sendMessage()
                }
                .disabled(sendDisabled)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .glassSurface(cornerRadius: AppTheme.Radius.xl, tint: AppTheme.panelTintStrong)
    }

    private var displayMessages: [MiniMaxChatMessage] {
        guard isStreaming, !streamingText.isEmpty else {
            return messages
        }

        return messages + [
            MiniMaxChatMessage(
                id: Self.streamingMessageID,
                role: "assistant",
                content: streamingText,
                isStreaming: true
            )
        ]
    }

    private var sendDisabled: Bool {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || isStreaming
            || !MiniMaxSettingsStore.shared.isConfigured
    }

    private func sendMessage() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isStreaming else {
            return
        }

        errorMessage = ""
        messages.append(MiniMaxChatMessage(role: "user", content: prompt))
        inputText = ""
        isStreaming = true
        streamingText = ""
        scrollAnchor += 1

        let request = AIExecutionRequest(
            tool: .chat,
            payload: .chat(
                ChatExecutionPayload(
                    messages: requestMessages + [(role: "user", content: prompt)]
                )
            )
        )

        let session = AIExecutionSession(
            request: request,
            provider: MiniMaxChatExecutionProvider(),
            historySink: ChatHistoryExecutionSink(),
            diagnosticsSink: AppLoggerDiagnosticsSink(),
            eventSink: { event in
                if case .delta(let text) = event {
                    await MainActor.run {
                        streamingText.append(text)
                        scrollAnchor += 1
                    }
                }
            }
        )
        currentSession = session

        Task {
            await session.start()
            let state = await session.state
            let result = await session.latestResult

            await MainActor.run {
                currentSession = nil

                switch state {
                case .completed:
                    if let assistantContent = result?.metadata["assistantContent"], !assistantContent.isEmpty {
                        messages.append(MiniMaxChatMessage(role: "assistant", content: assistantContent))
                    } else if !streamingText.isEmpty {
                        messages.append(MiniMaxChatMessage(role: "assistant", content: streamingText))
                    }
                case .failed(let failure):
                    errorMessage = failure.message
                case .cancelled, .idle, .running:
                    break
                }

                streamingText = ""
                isStreaming = false
                scrollAnchor += 1
            }
        }
    }

    private var requestMessages: [(role: String, content: String)] {
        messages.map { (role: $0.role, content: $0.content) }
    }

    private func clearChat() {
        currentSession?.cancel()
        currentSession = nil
        messages = []
        inputText = ""
        isStreaming = false
        streamingText = ""
        errorMessage = ""
    }

    private func loadHistory(reset: Bool) {
        Task {
            let offset = reset ? 0 : chatHistory.count
            let records = (try? await HistoryStore.shared.listChat(limit: historyPageSize, offset: offset)) ?? []
            let totalCount = (try? await HistoryStore.shared.count(category: .chat)) ?? 0

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

    private func restoreChat(_ record: ChatHistoryRecord) {
        clearChat()
        messages = record.messages.map {
            MiniMaxChatMessage(role: $0.role, content: $0.content)
        }
    }

    private func deleteChat(_ record: ChatHistoryRecord) {
        Task {
            try? await HistoryStore.shared.deleteChat(id: record.id)
            let records = (try? await HistoryStore.shared.listChat(limit: historyPageSize, offset: 0)) ?? []
            let totalCount = (try? await HistoryStore.shared.count(category: .chat)) ?? 0

            await MainActor.run {
                chatHistory = records
                chatHistoryHasMore = records.count < totalCount
            }
        }
    }

    private func clearChatHistory() {
        Task {
            try? await HistoryStore.shared.clear(category: .chat)
            await MainActor.run {
                chatHistory = []
                chatHistoryHasMore = false
            }
        }
    }
}

struct MiniMaxChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: String
    var content: String
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
    }
}

#if DEBUG
    struct MiniMaxChatView_Previews: PreviewProvider {
        static var previews: some View {
            MiniMaxChatView()
                .frame(width: 900, height: 700)
        }
    }
#endif
