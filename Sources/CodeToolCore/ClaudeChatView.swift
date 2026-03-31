import SwiftUI

public struct ClaudeChatView: View {
    @Bindable private var settings = ClaudeCLISettingsStore.shared

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
    @State private var showThinking: Set<UUID> = []
    @State private var showToolDetails: Set<UUID> = []
    @State private var showHistory = false
    @State private var chatHistory: [ClaudeChatHistoryRecord] = []
    @State private var cancellationRequested = false

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
                loadHistory()
                showHistory = true
            }
            StyledButton("Clear Chat", systemImage: "trash", variant: .ghost) {
                clearChat()
            }
            CopyButton("Copy Last", text: lastAssistantReply)
        } content: {
            VStack(spacing: 0) {
                if !settings.isAvailable {
                    ToolMessageBanner(
                        systemImage: "exclamationmark.triangle",
                        message: "Claude CLI was not found. Open Settings and detect the binary or set its path manually.",
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

                messageListView
                    .padding(.horizontal, AppTheme.Spacing.xxl)
                    .padding(.top, AppTheme.Spacing.xl)

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
                    title: "Claude Chat History",
                    items: chatHistory,
                    onSelect: { record in restoreChat(record) },
                    onDelete: { record in deleteChat(record) },
                    onClearAll: { clearChatHistory() }
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
    }

    private var statusItems: [ToolStatusItem] {
        var items: [ToolStatusItem] = []

        let resolvedModel = currentModel.isEmpty ? settings.model : currentModel
        if !resolvedModel.isEmpty {
            items.append(
                ToolStatusItem(
                    title: resolvedModel,
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
        StyledPanel {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        if messages.isEmpty && streamingMessage == nil && !isStreaming {
                            emptyStateView
                        }

                        ForEach(messages) { message in
                            messageView(for: message)
                        }

                        if let streamingMessage {
                            messageView(for: streamingMessage)
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
                .onChange(of: streamingText) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: streamingThinking) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .frame(minHeight: 220, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "terminal")
                .font(.system(size: 28))
                .foregroundColor(AppTheme.textMuted)
            Text("Chat with Claude")
                .font(.subheadline)
                .foregroundColor(AppTheme.textMuted)
            Text("Send a message to start a conversation with Claude CLI.")
                .font(.caption)
                .foregroundColor(AppTheme.textMuted.opacity(0.7))
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(.vertical, AppTheme.Spacing.xl)
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
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: AppTheme.Spacing.xxs) {
                Text("You")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundColor(AppTheme.accent)
                Text(message.content)
                    .font(.body)
                    .foregroundColor(AppTheme.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .fill(AppTheme.accent.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .strokeBorder(AppTheme.accent.opacity(0.22), lineWidth: 1)
                    )
            }
        }
    }

    @ViewBuilder
    private func assistantBubble(_ message: ClaudeChatMessage) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text("Claude")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundColor(AppTheme.accentWarm)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    if let thinking = message.thinkingContent, !thinking.isEmpty {
                        thinkingBlock(
                            thinking,
                            messageId: message.id,
                            isStreaming: message.isStreaming
                        )
                    }

                    if !message.content.isEmpty {
                        Text(message.content)
                            .font(.body)
                            .foregroundColor(AppTheme.textPrimary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .fill(AppTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                )
            }

            Spacer(minLength: 60)
        }
    }

    @ViewBuilder
    private func thinkingBlock(_ text: String, messageId: UUID, isStreaming: Bool) -> some View {
        let isExpanded = showThinking.contains(messageId) || isStreaming

        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Button {
                withAnimation(AppTheme.Anim.normal) {
                    toggle(messageId, in: &showThinking)
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(isStreaming ? "Thinking…" : "Thinking")
                        .font(.caption2)
                        .fontWeight(.semibold)
                    if isStreaming {
                        Circle()
                            .fill(AppTheme.accent)
                            .frame(width: 6, height: 6)
                            .modifier(PulseModifier())
                    }
                }
                .foregroundColor(AppTheme.textMuted)
            }
            .buttonStyle(.plain)

            if isExpanded {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isStreaming ? AppTheme.accent : AppTheme.accent.opacity(0.4))
                        .frame(width: 3)
                        .modifier(BreathingModifier(isActive: isStreaming))

                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .italic()
                        .foregroundColor(AppTheme.textMuted)
                        .textSelection(.enabled)
                        .padding(.leading, AppTheme.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(AppTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .fill(AppTheme.surfaceRaised.opacity(0.6))
                )
            }
        }
    }

    @ViewBuilder
    private func toolCard(_ message: ClaudeChatMessage) -> some View {
        let isExpanded = showToolDetails.contains(message.id) || message.isStreaming

        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(message.role == .toolResult ? "Result" : "Tool")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundColor(AppTheme.accentWarm)

                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(AppTheme.accentWarm)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        Button {
                            withAnimation(AppTheme.Anim.normal) {
                                toggle(message.id, in: &showToolDetails)
                            }
                        } label: {
                            HStack(spacing: AppTheme.Spacing.xs) {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(AppTheme.textMuted)
                                Image(systemName: toolIcon(for: message.toolName ?? ""))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppTheme.accentWarm)
                                Text(message.toolName ?? "Tool")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer(minLength: 0)
                                if message.isStreaming {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(width: 12, height: 12)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        if isExpanded {
                            if let input = message.toolInput, !input.isEmpty {
                                Text(input)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(AppTheme.textMuted)
                                    .textSelection(.enabled)
                            }

                            if !message.content.isEmpty {
                                Text(message.content)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(AppTheme.textPrimary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xs)
                }
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .fill(AppTheme.surface.opacity(0.8))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                )
            }

            Spacer(minLength: 60)
        }
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
        HStack(alignment: .bottom, spacing: AppTheme.Spacing.sm) {
            ZStack(alignment: .topLeading) {
                if inputText.isEmpty {
                    Text("Type a message…")
                        .font(.body)
                        .foregroundColor(AppTheme.textMuted)
                        .padding(.horizontal, AppTheme.Spacing.sm)
                        .padding(.vertical, AppTheme.Spacing.sm)
                }

                TextEditor(text: $inputText)
                    .font(.body)
                    .foregroundColor(AppTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, AppTheme.Spacing.xs)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .onSubmit {
                        sendMessage()
                    }
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

            if isStreaming {
                StyledButton("Stop", systemImage: "stop.fill", variant: .destructive) {
                    cancellationRequested = true
                    client.cancel()
                }
            } else {
                StyledIconButton("paperplane.fill", help: "Send message") {
                    sendMessage()
                }
                .disabled(sendDisabled)
                .opacity(sendDisabled ? 0.5 : 1.0)
            }
        }
    }

    private var sendDisabled: Bool {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !settings.isAvailable
    }

    private var streamingMessage: ClaudeChatMessage? {
        guard !streamingText.isEmpty || !streamingThinking.isEmpty else {
            return nil
        }

        return ClaudeChatMessage(
            role: .assistant,
            content: streamingText,
            thinkingContent: streamingThinking.isEmpty ? nil : streamingThinking,
            toolName: nil,
            toolInput: nil,
            isStreaming: true
        )
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        if !settings.isAvailable {
            errorMessage = "Claude CLI not found. Configure it in Settings first."
            return
        }

        messages.append(
            ClaudeChatMessage(
                role: .user,
                content: trimmed,
                thinkingContent: nil,
                toolName: nil,
                toolInput: nil,
                isStreaming: false
            ))
        inputText = ""
        errorMessage = ""
        isStreaming = true
        streamingText = ""
        streamingThinking = ""
        cancellationRequested = false

        let outgoingSessionId = sessionId.isEmpty ? nil : sessionId

        Task {
            await client.send(
                message: trimmed,
                settings: settings,
                sessionId: outgoingSessionId
            ) { event in
                Task { @MainActor in
                    handleEvent(event)
                }
            }
        }
    }

    @MainActor
    private func handleEvent(_ event: ClaudeCLIEvent) {
        switch event {
        case .initialized(let sid, let model):
            sessionId = sid
            currentModel = model

        case .thinkingDelta(let text):
            streamingThinking += text

        case .textDelta(let text):
            streamingText += text

        case .toolUseStart(_, let name):
            finalizeStreamingAssistantIfNeeded()
            messages.append(
                ClaudeChatMessage(
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
                    role: .toolResult,
                    content: content,
                    thinkingContent: nil,
                    toolName: toolUseId,
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
        guard !streamingText.isEmpty || !streamingThinking.isEmpty else { return }

        let message = ClaudeChatMessage(
            role: .assistant,
            content: streamingText,
            thinkingContent: streamingThinking.isEmpty ? nil : streamingThinking,
            toolName: nil,
            toolInput: nil,
            isStreaming: false
        )
        if let thinkingContent = message.thinkingContent, !thinkingContent.isEmpty {
            showThinking.insert(message.id)
        }
        messages.append(message)
        streamingText = ""
        streamingThinking = ""
    }

    private func saveHistory() {
        let record = ClaudeChatHistoryRecord(
            systemPrompt: normalizedSystemPrompt,
            messages: messages.map { message in
                ClaudeChatMessageRecord(
                    role: message.role.rawValue,
                    content: message.content,
                    thinkingContent: message.thinkingContent,
                    toolName: message.toolName,
                    toolInput: message.toolInput
                )
            },
            model: currentModel.isEmpty ? settings.model : currentModel,
            totalCostUSD: totalCostUSD > 0 ? totalCostUSD : nil,
            inputTokens: inputTokens > 0 ? inputTokens : nil,
            outputTokens: outputTokens > 0 ? outputTokens : nil,
            durationMs: totalDurationMs > 0 ? totalDurationMs : nil,
            sessionId: sessionId.isEmpty ? nil : sessionId,
            referenceID: AppLogger.makeReferenceID()
        )

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
        isStreaming = false
        streamingText = ""
        streamingThinking = ""
        errorMessage = ""
        sessionId = ""
        currentModel = settings.model
        totalCostUSD = 0
        inputTokens = 0
        outputTokens = 0
        totalDurationMs = 0
        showThinking = []
        showToolDetails = []
    }

    private var lastAssistantReply: String {
        messages.last(where: { $0.role == .assistant })?.content ?? ""
    }

    private func loadHistory() {
        Task {
            let records = (try? await HistoryStore.shared.listClaudeChat()) ?? []
            await MainActor.run {
                chatHistory = records
            }
        }
    }

    private func restoreChat(_ record: ClaudeChatHistoryRecord) {
        messages = record.messages.map { item in
            ClaudeChatMessage(
                role: ClaudeChatMessageRole(rawValue: item.role) ?? .assistant,
                content: item.content,
                thinkingContent: item.thinkingContent,
                toolName: item.toolName,
                toolInput: item.toolInput,
                isStreaming: false
            )
        }

        showThinking = Set(
            messages
                .filter { ($0.thinkingContent ?? "").isEmpty == false }
                .map(\.id)
        )
        sessionId = record.sessionId ?? ""
        currentModel = record.model
        totalCostUSD = record.totalCostUSD ?? 0
        inputTokens = record.inputTokens ?? 0
        outputTokens = record.outputTokens ?? 0
        totalDurationMs = record.durationMs ?? 0
        errorMessage = ""
    }

    private func deleteChat(_ record: ClaudeChatHistoryRecord) {
        Task {
            try? await HistoryStore.shared.deleteClaudeChat(id: record.id)
            let records = (try? await HistoryStore.shared.listClaudeChat()) ?? []
            await MainActor.run {
                chatHistory = records
            }
        }
    }

    private func clearChatHistory() {
        Task {
            try? await HistoryStore.shared.clear(category: .claudeChat)
            await MainActor.run {
                chatHistory = []
            }
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

private enum ClaudeChatMessageRole: String {
    case user
    case assistant
    case toolUse
    case toolResult
}

private struct ClaudeChatMessage: Identifiable {
    let id: UUID
    let role: ClaudeChatMessageRole
    var content: String
    var thinkingContent: String?
    var toolName: String?
    var toolInput: String?
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: ClaudeChatMessageRole,
        content: String,
        thinkingContent: String?,
        toolName: String?,
        toolInput: String?,
        isStreaming: Bool
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.toolName = toolName
        self.toolInput = toolInput
        self.isStreaming = isStreaming
    }
}

private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

private struct BreathingModifier: ViewModifier {
    let isActive: Bool
    @State private var isBreathing = false

    func body(content: Content) -> some View {
        content
            .opacity(isActive && isBreathing ? 0.4 : 1.0)
            .animation(
                isActive
                    ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                    : .default,
                value: isBreathing
            )
            .onAppear {
                if isActive {
                    isBreathing = true
                }
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