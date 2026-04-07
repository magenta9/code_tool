import AppKit
import CodeToolUI
import SwiftUI
import UniformTypeIdentifiers

public struct HermesAgentView: View {
    @Environment(\.toolVisibilityContext) private var toolVisibilityContext
    @Environment(\.toolSettingsPresenter) private var toolSettingsPresenter
    @Bindable private var settings = HermesSettingsStore.shared

    @State private var client = HermesCLIClient()
    @State private var viewState = HermesAgentViewState()
    @State private var streamingOutput = ""
    @State private var availableSessions: [HermesSessionSummary] = []
    @State private var showResumeSheet = false
    @State private var resumeErrorMessage = ""
    @State private var isFileDropTargeted = false
    @State private var streamingScrollRevision = 0

    public init() {}

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Hermes CLI",
            title: "Hermes Agent",
            description: "A local Hermes CLI wrapper with file references, resume, and diagnostics tracing.",
            systemImage: "command",
            statusItems: statusItems
        ) {
            StyledButton("New Chat", systemImage: "plus.bubble", variant: .ghost) {
                newChat()
            }
            if viewState.isRunning {
                StyledButton("Stop", systemImage: "stop.fill", variant: .destructive) {
                    client.cancel()
                }
            }
            StyledButton("Resume", systemImage: "clock.arrow.circlepath", variant: .secondary) {
                openResumeSheet()
            }
            StyledButton("Settings", systemImage: "gearshape", variant: .secondary) {
                toolSettingsPresenter.open(.hermes)
            }
        } content: {
            VStack(spacing: 0) {
                bannerStack
                contentArea
            }
            .safeAreaInset(edge: .bottom) {
                composerArea
                    .padding(.horizontal, AppTheme.Spacing.xxl)
                    .padding(.top, AppTheme.Spacing.lg)
                    .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .onAppear {
            if settings.capabilityMatrix == nil {
                settings.discoverCLI()
            }
        }
        .onChange(of: toolVisibilityContext.isVisible) { _, isVisible in
            guard isVisible else {
                return
            }

            streamingScrollRevision += 1
        }
        .sheet(isPresented: $showResumeSheet) {
            resumeSheet
        }
    }

    private var conversationRenderState: HermesConversationRenderState {
        HermesConversationRenderState.make(
            messages: viewState.messages,
            streamingText: streamingOutput,
            timelineEntries: viewState.timelineEntries,
            composerAttachmentCount: viewState.attachments.count,
            draftText: viewState.draftText,
            isToolVisible: toolVisibilityContext.isVisible,
            streamingScrollRevision: streamingScrollRevision
        )
    }

    private var statusItems: [ToolStatusItem] {
        var items: [ToolStatusItem] = [
            ToolStatusItem(
                title: settings.isAvailable ? "CLI Found" : "CLI Not Found",
                systemImage: settings.isAvailable ? "checkmark.circle" : "xmark.circle",
                tint: settings.isAvailable ? AppTheme.success : AppTheme.error,
                action: { toolSettingsPresenter.open(.hermes) }
            )
        ]

        if let version = settings.capabilityMatrix?.versionString, !version.isEmpty {
            items.append(ToolStatusItem(title: version, systemImage: "tag", tint: AppTheme.accent))
        }

        if let sessionID = viewState.activeSessionID, !sessionID.isEmpty {
            items.append(ToolStatusItem(title: sessionID, systemImage: "clock", tint: AppTheme.accentWarm))
        }

        if !viewState.attachments.isEmpty {
            items.append(
                ToolStatusItem(
                    title: "\(viewState.attachments.count) files",
                    systemImage: "paperclip",
                    tint: AppTheme.textSecondary
                )
            )
        }

        if viewState.isRunning {
            items.append(ToolStatusItem(title: "Running", systemImage: "ellipsis.circle", tint: AppTheme.success))
        }

        return items
    }

    private var bannerStack: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if !settings.isAvailable {
                ToolMessageBanner(
                    systemImage: "exclamationmark.triangle",
                    message: settings.lastProbeError.isEmpty
                        ? "Hermes CLI was not found. Open Settings and detect the binary or set its path manually."
                        : settings.lastProbeError,
                    tint: AppTheme.warning
                )
            }

            if !viewState.errorBanner.isEmpty {
                ToolMessageBanner(
                    systemImage: "xmark.octagon",
                    message: viewState.errorBanner,
                    tint: AppTheme.error
                )
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xxl)
        .padding(.top, AppTheme.Spacing.sm)
    }

    private var contentArea: some View {
        HermesConversationPane(
            state: conversationRenderState,
            messagesPanel: { messagesPanel },
            timelinePanel: { timelinePanel }
        )
        .equatable()
    }

    private var messagesPanel: some View {
        StyledPanel(title: "Conversation") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                if viewState.messages.isEmpty && streamingOutput.isEmpty {
                    Text("Start a new Hermes conversation, stage files, then send a prompt.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(viewState.messages) { message in
                        messageBubble(message)
                    }

                    if !streamingOutput.isEmpty {
                        messageBubble(.assistant(streamingOutput))
                    }
                }
            }
        }
    }

    private func messageBubble(_ message: HermesChatMessage) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Label(
                message.role == .user ? "Prompt" : "Hermes",
                systemImage: message.role == .user ? "arrow.up.right" : "sparkles"
            )
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(message.role == .user ? AppTheme.textSecondary : AppTheme.accentWarm)

            if !message.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(message.attachments) { attachment in
                            attachmentChip(attachment)
                        }
                    }
                }
            }

            ClaudeMarkdownView(markdown: message.content)
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .fill(message.role == .user ? AppTheme.surface.opacity(0.72) : AppTheme.surfaceRaised.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
    }

    private func attachmentChip(_ attachment: HermesAttachmentReference) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(attachment.displayName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
            Text(attachment.kindDescription)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.surface.opacity(0.82))
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(AppTheme.border, lineWidth: 1)
        )
    }

    private var timelinePanel: some View {
        StyledPanel(title: "Timeline") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                if viewState.timelineEntries.isEmpty {
                    Text("Process phases appear here once Hermes starts a turn.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textMuted)
                } else {
                    ForEach(viewState.timelineEntries) { entry in
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            HStack {
                                Text(entry.phase.label)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Spacer()
                                Text(entry.status.rawValue.capitalized)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(timelineTint(entry.status))
                            }
                            Text(entry.detail)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .padding(AppTheme.Spacing.md)
                        .background(AppTheme.surface.opacity(0.66))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                .strokeBorder(AppTheme.border, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private var composerArea: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if !viewState.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(viewState.attachments) { attachment in
                            HStack(spacing: AppTheme.Spacing.xs) {
                                attachmentChip(attachment)
                                Button {
                                    viewState.attachments.removeAll { $0.id == attachment.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(AppTheme.textMuted)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            StyledTextEditor(
                text: $viewState.draftText,
                placeholder: "Ask Hermes to inspect code, explain a flow, or reason about the attached files."
            )
            .frame(minHeight: 110)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isFileDropTargeted) { providers in
                handleDrop(providers: providers)
            }
            .onPasteCommand(of: [UTType.fileURL]) { providers in
                ingestPastedFiles(providers: providers)
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .strokeBorder(
                        isFileDropTargeted ? AppTheme.accentWarm.opacity(0.8) : Color.clear,
                        style: StrokeStyle(lineWidth: 1.5, dash: [8, 5])
                    )
            )

            HStack(spacing: AppTheme.Spacing.sm) {
                StyledButton("Add Files", systemImage: "paperclip", variant: .secondary) {
                    openFiles()
                }
                StyledButton("Clear Files", systemImage: "trash", variant: .ghost) {
                    viewState.attachments = []
                }
                Spacer()
                StyledButton("Send", systemImage: "arrow.up.circle.fill", variant: .primary) {
                    sendMessage()
                }
                .disabled(
                    HermesAgentViewState.sendDisabled(
                        draftText: viewState.draftText,
                        attachments: viewState.attachments,
                        isRunning: viewState.isRunning,
                        isAvailable: settings.isAvailable
                    )
                )
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: 960)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl)
                .fill(AppTheme.backgroundRaised.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl)
                .strokeBorder(AppTheme.borderHover, lineWidth: 1)
        )
    }

    private var resumeSheet: some View {
        NavigationStack {
            List {
                if !resumeErrorMessage.isEmpty {
                    ToolMessageBanner(
                        systemImage: "exclamationmark.triangle",
                        message: resumeErrorMessage,
                        tint: AppTheme.warning
                    )
                }

                ForEach(availableSessions) { session in
                    Button {
                        viewState.activeSessionID = session.id
                        showResumeSheet = false
                    } label: {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text(session.title ?? session.preview)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(session.preview)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                            Text(session.updatedAtText)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(AppTheme.textMuted)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Resume Session")
        }
        .frame(minWidth: 520, minHeight: 360)
    }

    private func timelineTint(_ status: HermesTimelineStatus) -> Color {
        switch status {
        case .running:
            return AppTheme.accent
        case .completed:
            return AppTheme.success
        case .cancelled:
            return AppTheme.warning
        case .failed:
            return AppTheme.error
        case .warning:
            return AppTheme.warning
        }
    }

    private func newChat() {
        if viewState.isRunning {
            client.cancel()
        }
        streamingOutput = ""
        viewState.resetForNewChat()
    }

    private func openResumeSheet() {
        guard let capabilities = settings.capabilityMatrix else {
            resumeErrorMessage = "Hermes CLI is not available."
            showResumeSheet = true
            return
        }

        Task {
            let result = await HermesSessionDiscovery.discover(capabilities: capabilities)
            await MainActor.run {
                switch result {
                case .success(let sessions):
                    availableSessions = sessions
                    resumeErrorMessage = sessions.isEmpty ? "No resumable sessions were returned by Hermes." : ""
                case .failure(let error):
                    availableSessions = []
                    resumeErrorMessage = error.localizedDescription
                }
                showResumeSheet = true
            }
        }
    }

    private func openFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else { return }
        appendAttachments(FileReferenceImportSupport.attachments(from: panel.urls))
    }

    private func ingestPastedFiles(providers: [NSItemProvider]) {
        let handled = FileReferenceImportSupport.loadAttachments(from: providers) { attachments, requestedLoads in
            if attachments.isEmpty && requestedLoads == 0 {
                appendAttachments(FileReferenceImportSupport.attachments())
                return
            }
            appendAttachments(attachments)
        }

        if !handled {
            appendAttachments(FileReferenceImportSupport.attachments())
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        FileReferenceImportSupport.loadAttachments(from: providers) { attachments, requestedLoads in
            appendAttachments(attachments)
            if attachments.isEmpty && requestedLoads > 0 {
                viewState.errorBanner = "Some dropped items could not be imported as readable files."
            }
        }
    }

    private func appendAttachments(_ attachments: [HermesAttachmentReference]) {
        guard !attachments.isEmpty else { return }
        var combined = viewState.attachments
        combined.append(contentsOf: attachments)
        var seen = Set<String>()
        viewState.attachments = combined.filter { attachment in
            seen.insert(attachment.fileURL.standardizedFileURL.path).inserted
        }
        viewState.errorBanner = ""
    }

    private func sendMessage() {
        guard let capabilities = settings.capabilityMatrix else {
            viewState.errorBanner = settings.lastProbeError.isEmpty
                ? "Hermes CLI is not available."
                : settings.lastProbeError
            return
        }

        let draftText = viewState.draftText
        let attachments = viewState.attachments

        do {
            let prompt = try HermesPromptComposer.compose(
                text: draftText,
                attachments: attachments,
                capabilities: capabilities
            )

            let referenceID = AppLogger.makeReferenceID()
            viewState.activeReferenceID = referenceID
            viewState.errorBanner = ""
            viewState.isRunning = true
            streamingOutput = ""
            viewState.messages.append(
                .user(
                    draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "(files attached)"
                        : draftText,
                    attachments: attachments
                )
            )
            viewState.timelineEntries.append(
                HermesTimelineEntry(
                    phase: .preparingAttachments,
                    status: .running,
                    detail: "Prepared \(attachments.count) file reference(s)."
                )
            )
            viewState.draftText = ""
            viewState.attachments = []

            let request = HermesTurnRequest(
                prompt: prompt,
                resumeSessionID: viewState.activeSessionID,
                referenceID: referenceID,
                modelOrProfile: settings.resolvedModelOrProfile,
                extraArguments: settings.parsedExtraArguments
            )

            Task {
                await client.send(request: request, capabilities: capabilities) { event in
                    Task { @MainActor in
                        handleEvent(
                            event,
                            requestSummary: AppLogger.summarize(text: draftText, limit: 120),
                            attachmentCount: attachments.count
                        )
                    }
                }
            }
        } catch {
            viewState.errorBanner = error.localizedDescription
        }
    }

    private func handleEvent(
        _ event: HermesAgentEvent,
        requestSummary: String,
        attachmentCount: Int
    ) {
        switch event {
        case .phaseChanged(let phase):
            let status: HermesTimelineStatus
            switch phase {
            case .completed:
                status = .completed
            case .cancelled:
                status = .cancelled
            case .failed:
                status = .failed
            default:
                status = .running
            }

            viewState.timelineEntries.append(
                HermesTimelineEntry(
                    phase: phase,
                    status: status,
                    detail: phase.label
                )
            )

            if phase == .cancelled || phase == .failed {
                viewState.isRunning = false
            }

        case .outputDelta(let text):
            streamingOutput = text
            streamingScrollRevision += 1

        case .warning(let message):
            viewState.timelineEntries.append(
                HermesTimelineEntry(
                    phase: .waitingForResponse,
                    status: .warning,
                    detail: message
                )
            )

        case .failed(let message):
            if !streamingOutput.isEmpty {
                viewState.messages.append(.assistant(streamingOutput))
                streamingOutput = ""
            }
            viewState.errorBanner = message
            viewState.isRunning = false
            saveDiagnosticsRecord(
                requestSummary: requestSummary,
                outputSummary: message,
                attachmentCount: attachmentCount,
                durationMs: nil,
                status: "failed"
            )

        case .completed(let result):
            if !streamingOutput.isEmpty {
                viewState.messages.append(.assistant(streamingOutput))
                streamingOutput = ""
            } else if !result.output.isEmpty {
                viewState.messages.append(.assistant(result.output))
            }

            viewState.activeSessionID = result.sessionID ?? viewState.activeSessionID
            viewState.isRunning = false

            saveDiagnosticsRecord(
                requestSummary: requestSummary,
                outputSummary: AppLogger.summarize(text: result.output, limit: 160),
                attachmentCount: attachmentCount,
                durationMs: result.durationMs,
                status: result.status.rawValue
            )
        }
    }

    private func saveDiagnosticsRecord(
        requestSummary: String,
        outputSummary: String,
        attachmentCount: Int,
        durationMs: Int?,
        status: String
    ) {
        let record = HermesAgentDiagnosticsRecord(
            sessionID: viewState.activeSessionID,
            modelOrProfile: settings.resolvedModelOrProfile,
            requestSummary: requestSummary.isEmpty ? "Attachment-only request" : requestSummary,
            outputSummary: outputSummary,
            attachmentCount: attachmentCount,
            durationMs: durationMs,
            status: status,
            referenceID: viewState.activeReferenceID.isEmpty ? AppLogger.makeReferenceID() : viewState.activeReferenceID
        )

        Task {
            do {
                try await HistoryStore.shared.save(record)
            } catch {
                await AppLogger.shared.log(
                    level: .error,
                    category: .hermesagent,
                    event: "hermes_diagnostics_save_failed",
                    referenceID: record.referenceID,
                    message: "Failed to save Hermes diagnostics record.",
                    metadata: ["status": status],
                    stackTrace: []
                )
            }
        }
    }
}

struct HermesConversationRenderState: Equatable {
    let messages: [HermesChatMessage]
    let streamingText: String
    let timelineEntries: [HermesTimelineEntry]
    let composerReservedSpace: CGFloat
    let isToolVisible: Bool
    let streamingScrollRevision: Int

    static func make(
        messages: [HermesChatMessage] = [],
        streamingText: String = "",
        timelineEntries: [HermesTimelineEntry] = [],
        composerAttachmentCount: Int,
        draftText: String,
        isToolVisible: Bool,
        streamingScrollRevision: Int
    ) -> HermesConversationRenderState {
        _ = draftText

        return HermesConversationRenderState(
            messages: messages,
            streamingText: streamingText,
            timelineEntries: timelineEntries,
            composerReservedSpace: composerAttachmentCount == 0 ? 220 : 292,
            isToolVisible: isToolVisible,
            streamingScrollRevision: streamingScrollRevision
        )
    }
}

private struct HermesConversationPane<MessagesPanel: View, TimelinePanel: View>: View, Equatable {
    let state: HermesConversationRenderState
    let messagesPanel: () -> MessagesPanel
    let timelinePanel: () -> TimelinePanel

    static func ==(
        lhs: HermesConversationPane<MessagesPanel, TimelinePanel>,
        rhs: HermesConversationPane<MessagesPanel, TimelinePanel>
    ) -> Bool {
        lhs.state == rhs.state
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    messagesPanel()
                    timelinePanel()

                    Color.clear
                        .frame(height: state.composerReservedSpace)
                        .id("bottom")
                }
                .frame(maxWidth: 960)
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
            .onChange(of: state.timelineEntries.count) {
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

#if DEBUG
    struct HermesAgentView_Previews: PreviewProvider {
        static var previews: some View {
            HermesAgentView()
                .frame(width: 1000, height: 760)
        }
    }
#endif