import CodeToolUI
import SwiftUI

/// Settings view for configuring MiniMax API settings.
public struct MiniMaxSettingsView: View {
    @Bindable private var settings = MiniMaxSettingsStore.shared
    @State private var showAPIKey = false
    @State private var testStatus: TestStatus = .idle
    @State private var draft = MiniMaxSettingsDraft(store: MiniMaxSettingsStore.shared)

    private enum TestStatus: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    public init() {}

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Configuration",
            title: "MiniMax Settings",
            description: "Configure your MiniMax API provider for AI-powered tools.",
            systemImage: "gearshape.2",
            statusItems: statusItems
        ) {
            StyledButton("Reset Defaults", systemImage: "arrow.counterclockwise", variant: .ghost) {
                settings.resetToDefaults()
                draft.reload(from: settings)
            }
            StyledButton(
                "Test Connection", systemImage: "antenna.radiowaves.left.and.right",
                variant: .primary
            ) {
                commitDraft()
                testConnection()
            }
            .disabled(!draft.isConfigured || testStatus == .testing)
        } content: {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    apiKeySection
                    baseURLSection
                    modelsSection
                    statusBanner
                }
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.top, AppTheme.Spacing.xl)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .onAppear {
            draft.reload(from: settings)
        }
        .onSubmit {
            commitDraft()
        }
        .onDisappear {
            commitDraft()
        }
    }

    // MARK: - Sections

    private var apiKeySection: some View {
        StyledPanel(title: "API Key") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Enter your MiniMax Token Plan API Key. Get it from platform.minimaxi.com")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)

                HStack(spacing: AppTheme.Spacing.sm) {
                    Group {
                        if showAPIKey {
                            TextField("sk-...", text: $draft.apiKey)
                        } else {
                            SecureField("sk-...", text: $draft.apiKey)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(AppTheme.Spacing.md)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .strokeBorder(AppTheme.border, lineWidth: 1)
                    )

                    StyledIconButton(
                        showAPIKey ? "eye.slash" : "eye",
                        action: { showAPIKey.toggle() }
                    )
                }
            }
        }
    }

    private var baseURLSection: some View {
        StyledPanel(title: "Base URL") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("MiniMax API base URL. Change only if using a custom endpoint.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)

                TextField("https://api.minimaxi.com/v1", text: $draft.baseURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(AppTheme.Spacing.md)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .strokeBorder(AppTheme.border, lineWidth: 1)
                    )
            }
        }
    }

    private var modelsSection: some View {
        StyledPanel(title: "Models") {
            VStack(spacing: AppTheme.Spacing.lg) {
                modelField(
                    label: "Chat Model", value: $draft.chatModel,
                    placeholder: MiniMaxConfig.defaults.chatModel,
                    icon: "bubble.left.and.bubble.right")
                modelField(
                    label: "Speech Model", value: $draft.speechModel,
                    placeholder: MiniMaxConfig.defaults.speechModel, icon: "waveform")
                modelField(
                    label: "Image Model", value: $draft.imageModel,
                    placeholder: MiniMaxConfig.defaults.imageModel, icon: "photo.artframe")
                modelField(
                    label: "Music Model", value: $draft.musicModel,
                    placeholder: MiniMaxConfig.defaults.musicModel, icon: "music.note")
            }
        }
    }

    private func modelField(
        label: String, value: Binding<String>, placeholder: String, icon: String
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28)

            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 120, alignment: .leading)

            TextField(placeholder, text: value)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                )
        }
    }

    // MARK: - Status

    private var statusItems: [ToolStatusItem] {
        if draft.isConfigured {
            return [
                ToolStatusItem(
                    title: "API Key configured", systemImage: "checkmark.circle.fill",
                    tint: AppTheme.success)
            ]
        }
        return [
            ToolStatusItem(
                title: "API Key required", systemImage: "exclamationmark.triangle.fill",
                tint: AppTheme.warning)
        ]
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch testStatus {
        case .idle:
            if !draft.isConfigured {
                ToolMessageBanner(
                    systemImage: "key.fill",
                    message:
                        "Enter your MiniMax API Key to enable AI tools. Visit platform.minimaxi.com to get one.",
                    tint: AppTheme.warning)
            } else {
                ToolMessageBanner(
                    systemImage: "checkmark.shield",
                    message: "Provider configured. Use 'Test Connection' to verify your API key.",
                    tint: AppTheme.success)
            }
        case .testing:
            ToolMessageBanner(
                systemImage: "arrow.triangle.2.circlepath", message: "Testing connection...",
                tint: AppTheme.accent)
        case .success:
            ToolMessageBanner(
                systemImage: "checkmark.circle.fill",
                message: "Connection successful! Your API key is valid.", tint: AppTheme.success)
        case .failure(let msg):
            ToolMessageBanner(
                systemImage: "xmark.circle.fill", message: "Connection failed: \(msg)",
                tint: AppTheme.error)
        }
    }

    // MARK: - Actions

    private func commitDraft() {
        draft.apply(to: settings)
    }

    private func testConnection() {
        testStatus = .testing
        Task {
            do {
                let messages = [MiniMaxAPIClient.ChatMessage(role: "user", content: "Hi")]
                _ = try await MiniMaxAPIClient.shared.chatCompletion(
                    messages: messages, maxTokens: 10)
                await MainActor.run { testStatus = .success }
            } catch {
                await MainActor.run { testStatus = .failure(error.localizedDescription) }
            }
        }
    }
}

struct MiniMaxSettingsDraft: Equatable {
    var apiKey: String
    var baseURL: String
    var chatModel: String
    var speechModel: String
    var imageModel: String
    var musicModel: String

    init(
        apiKey: String = "",
        baseURL: String = MiniMaxConfig.defaults.baseURL,
        chatModel: String = MiniMaxConfig.defaults.chatModel,
        speechModel: String = MiniMaxConfig.defaults.speechModel,
        imageModel: String = MiniMaxConfig.defaults.imageModel,
        musicModel: String = MiniMaxConfig.defaults.musicModel
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.chatModel = chatModel
        self.speechModel = speechModel
        self.imageModel = imageModel
        self.musicModel = musicModel
    }

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(store: MiniMaxSettingsStore) {
        self.init(
            apiKey: store.apiKey,
            baseURL: store.baseURL,
            chatModel: store.chatModel,
            speechModel: store.speechModel,
            imageModel: store.imageModel,
            musicModel: store.musicModel
        )
    }

    mutating func reload(from store: MiniMaxSettingsStore) {
        self = MiniMaxSettingsDraft(store: store)
    }

    func apply(to store: MiniMaxSettingsStore) {
        store.apiKey = apiKey
        store.baseURL = baseURL
        store.chatModel = chatModel
        store.speechModel = speechModel
        store.imageModel = imageModel
        store.musicModel = musicModel
    }
}
