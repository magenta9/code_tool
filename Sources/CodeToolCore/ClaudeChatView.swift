import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var activeReferenceID: String = ""
    @State private var showThinking: Set<UUID> = []
    @State private var showToolDetails: Set<UUID> = []
    @State private var showHistory = false
    @State private var chatHistory: [ClaudeChatHistoryRecord] = []
    @State private var cancellationRequested = false

    // Conversation-scoped history identity
    @State private var activeConversationRecordID: UUID?
    @State private var activeConversationCreatedAt: Date?

    // Image attachment state
    @State private var composerImages: [ClaudeComposerImage] = []
    @State private var attachmentWarning: String = ""

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

                VStack(alignment: .trailing, spacing: AppTheme.Spacing.xs) {
                    // Attachment previews
                    if !message.attachments.isEmpty {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            ForEach(message.attachments) { attachment in
                                attachmentChip(attachment)
                            }
                        }
                    }

                    ClaudeMarkdownView(markdown: message.content)
                }
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
    private func attachmentChip(_ attachment: ClaudeChatAttachmentRecord) -> some View {
        Group {
            if let url = try? HistoryStore.syncClaudeChatAttachmentURL(fileName: attachment.fileName),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .strokeBorder(AppTheme.accent.opacity(0.3), lineWidth: 1)
                    )
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.system(size: 10))
                    Text(attachment.fileName.split(separator: "-").last.map(String.init) ?? attachment.fileName)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(AppTheme.textMuted)
                .padding(.horizontal, AppTheme.Spacing.xs)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(AppTheme.surface)
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
                        ClaudeMarkdownView(markdown: message.content)
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
        VStack(spacing: AppTheme.Spacing.xs) {
            // Attachment warning
            if !attachmentWarning.isEmpty {
                Text(attachmentWarning)
                    .font(.caption)
                    .foregroundColor(AppTheme.warning)
            }

            // Composer image thumbnails
            if !composerImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(composerImages) { img in
                            ZStack(alignment: .topTrailing) {
                                Image(nsImage: img.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                            .strokeBorder(AppTheme.border, lineWidth: 1)
                                    )

                                Button {
                                    composerImages.removeAll { $0.id == img.id }
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
                    }
                    .padding(.horizontal, AppTheme.Spacing.xs)
                }
                .frame(height: 64)
            }

            HStack(alignment: .bottom, spacing: AppTheme.Spacing.sm) {
                // Image picker button
                if !isStreaming {
                    Button {
                        pickImageFile()
                    } label: {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Attach image")
                }

                ZStack(alignment: .topLeading) {
                    if inputText.isEmpty && composerImages.isEmpty {
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
                        onPasteImages: { images in handlePastedImages(images) },
                        onEscape: {
                            if isStreaming {
                                cancellationRequested = true
                                client.cancel()
                            }
                        }
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
    }

    private var sendDisabled: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImages = !composerImages.isEmpty
        return (!hasText && !hasImages) || !settings.isAvailable
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
                role: .user,
                content: trimmed.isEmpty ? "(image attached)" : trimmed,
                thinkingContent: nil,
                toolName: nil,
                toolInput: nil,
                isStreaming: false,
                attachments: attachmentRecords
            ))
        inputText = ""
        composerImages = []
        attachmentWarning = ""
        errorMessage = ""
        isStreaming = true
        streamingText = ""
        streamingThinking = ""
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
                settings: settings
            ) { event in
                Task { @MainActor in
                    handleEvent(event)
                }
            }
        }
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
        activeReferenceID = ""
        showThinking = []
        showToolDetails = []
        activeConversationRecordID = nil
        activeConversationCreatedAt = nil
        composerImages = []
        attachmentWarning = ""
    }

    private var lastAssistantReply: String {
        messages.last(where: { $0.role == .assistant })?.content ?? ""
    }

    private func pickImageFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .bmp, .webP]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Select images to attach"

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard let data = try? Data(contentsOf: url),
                  let image = NSImage(data: data) else { continue }

            let ext = url.pathExtension.lowercased()
            let mimeType: String
            switch ext {
            case "png": mimeType = "image/png"
            case "jpg", "jpeg": mimeType = "image/jpeg"
            case "gif": mimeType = "image/gif"
            case "webp": mimeType = "image/webp"
            case "tiff", "tif": mimeType = "image/tiff"
            case "bmp": mimeType = "image/bmp"
            default: mimeType = "image/png"
            }

            let fileName = "\(UUID().uuidString).\(ext)"
            composerImages.append(
                ClaudeComposerImage(
                    image: image, fileName: fileName, data: data, mimeType: mimeType))
        }
    }

    private func handlePastedImages(_ images: [NSImage]) {
        for image in images {
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:])
            else { continue }

            let fileName = "\(UUID().uuidString).png"
            composerImages.append(
                ClaudeComposerImage(
                    image: image, fileName: fileName, data: pngData, mimeType: "image/png"))
        }
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
                isStreaming: false,
                attachments: item.attachments ?? []
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
        activeReferenceID = record.referenceID
        errorMessage = ""

        // Restore conversation identity so continued chat overwrites the same record
        activeConversationRecordID = record.id
        activeConversationCreatedAt = record.createdAt
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
    var attachments: [ClaudeChatAttachmentRecord]

    init(
        id: UUID = UUID(),
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

/// An image staged in the composer, not yet sent.
struct ClaudeComposerImage: Identifiable {
    let id = UUID()
    let image: NSImage
    let fileName: String
    let data: Data
    let mimeType: String
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
