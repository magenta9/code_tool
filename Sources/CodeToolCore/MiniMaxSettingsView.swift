import SwiftUI

/// Settings view for configuring MiniMax API provider.
public struct MiniMaxSettingsView: View {
    @ObservedObject private var provider = MiniMaxProvider.shared
    @State private var showAPIKey = false
    @State private var testStatus: TestStatus = .idle

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
                provider.resetToDefaults()
            }
            StyledButton("Test Connection", systemImage: "antenna.radiowaves.left.and.right", variant: .primary) {
                testConnection()
            }
            .disabled(!provider.isConfigured || testStatus == .testing)
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
                            TextField("sk-...", text: $provider.apiKey)
                        } else {
                            SecureField("sk-...", text: $provider.apiKey)
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

                TextField("https://api.minimaxi.com/v1", text: $provider.baseURL)
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
                modelField(label: "Chat Model", value: $provider.chatModel, placeholder: MiniMaxProvider.Defaults.chatModel, icon: "bubble.left.and.bubble.right")
                modelField(label: "Speech Model", value: $provider.speechModel, placeholder: MiniMaxProvider.Defaults.speechModel, icon: "waveform")
                modelField(label: "Image Model", value: $provider.imageModel, placeholder: MiniMaxProvider.Defaults.imageModel, icon: "photo.artframe")
                modelField(label: "Music Model", value: $provider.musicModel, placeholder: MiniMaxProvider.Defaults.musicModel, icon: "music.note")
            }
        }
    }

    private func modelField(label: String, value: Binding<String>, placeholder: String, icon: String) -> some View {
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
        if provider.isConfigured {
            return [ToolStatusItem(title: "API Key configured", systemImage: "checkmark.circle.fill", tint: AppTheme.success)]
        }
        return [ToolStatusItem(title: "API Key required", systemImage: "exclamationmark.triangle.fill", tint: AppTheme.warning)]
    }

    private var statusBanner: some View {
        Group {
            switch testStatus {
            case .idle:
                if !provider.isConfigured {
                    ToolMessageBanner(systemImage: "key.fill", message: "Enter your MiniMax API Key to enable AI tools. Visit platform.minimaxi.com to get one.", tint: AppTheme.warning)
                } else {
                    ToolMessageBanner(systemImage: "checkmark.shield", message: "Provider configured. Use 'Test Connection' to verify your API key.", tint: AppTheme.success)
                }
            case .testing:
                ToolMessageBanner(systemImage: "arrow.triangle.2.circlepath", message: "Testing connection...", tint: AppTheme.accent)
            case .success:
                ToolMessageBanner(systemImage: "checkmark.circle.fill", message: "Connection successful! Your API key is valid.", tint: AppTheme.success)
            case .failure(let msg):
                ToolMessageBanner(systemImage: "xmark.circle.fill", message: "Connection failed: \(msg)", tint: AppTheme.error)
            }
        }
    }

    // MARK: - Actions

    private func testConnection() {
        testStatus = .testing
        Task {
            do {
                let messages = [MiniMaxAPIClient.ChatMessage(role: "user", content: "Hi")]
                _ = try await MiniMaxAPIClient.shared.chatCompletion(messages: messages, maxTokens: 10)
                await MainActor.run { testStatus = .success }
            } catch {
                await MainActor.run { testStatus = .failure(error.localizedDescription) }
            }
        }
    }
}
