import CodeToolUI
import SwiftUI

#if canImport(AppKit)
    import AppKit
#endif

public struct ClaudeCLISettingsView: View {
    @Bindable private var settings = ClaudeCLISettingsStore.shared
    @State private var showAPIKey = false
    @State private var draft = ClaudeCLISettingsDraft(store: ClaudeCLISettingsStore.shared)

    public init() {}

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Configuration",
            title: "Claude CLI Settings",
            description: "Configure the local Claude CLI backend used by AI Chat.",
            systemImage: "terminal",
            statusItems: statusItems
        ) {
            StyledButton("Reset Defaults", systemImage: "arrow.counterclockwise", variant: .ghost) {
                settings.resetToDefaults()
                draft.reload(from: settings)
            }
            StyledButton("Detect CLI", systemImage: "magnifyingglass", variant: .primary) {
                commitDraft(discoverCLI: true)
            }
        } content: {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    cliPathSection
                    apiKeySection
                    modelSection
                    limitsSection
                    permissionsSection
                    systemPromptSection
                }
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.top, AppTheme.Spacing.xl)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .onAppear {
            draft.reload(from: settings)
            settings.discoverCLI()
            settings.refreshAvailableModels()
        }
        .onSubmit {
            commitDraft(discoverCLI: true)
        }
        .onDisappear {
            commitDraft()
        }
    }

    private var statusItems: [ToolStatusItem] {
        var items = [
            ToolStatusItem(
                title: settings.isAvailable ? "CLI Found" : "CLI Not Found",
                systemImage: settings.isAvailable ? "checkmark.circle" : "xmark.circle",
                tint: settings.isAvailable ? AppTheme.success : AppTheme.error
            )
        ]

        items.append(
            ToolStatusItem(
                title: settings.model,
                systemImage: "cpu",
                tint: AppTheme.accent
            )
        )

        return items
    }

    private var cliPathSection: some View {
        StyledPanel(title: "Claude CLI") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Provide a custom Claude binary path or leave it blank to use automatic discovery.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)

                TextField("/opt/homebrew/bin/claude", text: $draft.claudePath)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(AppTheme.Spacing.md)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .strokeBorder(AppTheme.border, lineWidth: 1)
                    )

                ToolMessageBanner(
                    systemImage: settings.isAvailable ? "checkmark.shield" : "exclamationmark.triangle",
                    message: settings.isAvailable
                        ? "Resolved binary: \(settings.resolvedClaudePath)"
                        : "No executable Claude binary was found in the configured search paths.",
                    tint: settings.isAvailable ? AppTheme.success : AppTheme.warning
                )
            }
        }
    }

    private var apiKeySection: some View {
        StyledPanel(title: "Anthropic API Key") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Optional override for ANTHROPIC_API_KEY. Leave blank to use your shell environment.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)

                HStack(spacing: AppTheme.Spacing.sm) {
                    Group {
                        if showAPIKey {
                            TextField("sk-ant-...", text: $draft.apiKey)
                        } else {
                            SecureField("sk-ant-...", text: $draft.apiKey)
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

                    StyledIconButton(showAPIKey ? "eye.slash" : "eye") {
                        showAPIKey.toggle()
                    }
                }
            }
        }
    }

    private var modelSection: some View {
        StyledPanel(title: "Model") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Choose the default Claude model passed to the CLI.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)

                Picker("Model", selection: $settings.model) {
                    ForEach(settings.availableModels, id: \.self) { model in
                        Text(model)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .tag(model)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(
                    settings.isUsingFallbackModels
                        ? "Using the built-in default model list."
                        : "Loaded available models from ~/.claude/settings.json."
                )
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
            }
        }
    }

    private var limitsSection: some View {
        StyledPanel(title: "Limits") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack {
                        Text("Max Turns")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text("\(settings.maxTurns)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.textMuted)
                    }

                    Stepper(value: $settings.maxTurns, in: 1...50) {
                        EmptyView()
                    }
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("Max Budget (USD)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    TextField(
                        "Budget",
                        value: $settings.maxBudgetUSD,
                        format: .number.precision(.fractionLength(0...4))
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(AppTheme.Spacing.md)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .strokeBorder(AppTheme.border, lineWidth: 1)
                    )
                }

                Toggle(isOn: $settings.useBare) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                        Text("Use bare mode")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Runs the CLI with --bare to minimize extra wrapper output. This also skips automatic MCP/plugin loading.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textMuted)
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }

    private var permissionsSection: some View {
        StyledPanel(title: "Permissions") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("AI Chat uses Claude CLI print mode, so it cannot show interactive approval prompts. Choose how tool calls should be handled.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)

                ToolMessageBanner(
                    systemImage: "checkmark.shield",
                    message: "Bypass Permissions is the default for AI Chat so MCP tools can run without getting stuck behind interactive approval.",
                    tint: AppTheme.success
                )

                Picker("Permission Mode", selection: $settings.permissionMode) {
                    ForEach(ClaudeCLIPermissionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(settings.permissionMode.summary)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        settings.permissionMode == .bypassPermissions
                            ? AppTheme.warning : AppTheme.textMuted
                    )
            }
        }
    }

    private var systemPromptSection: some View {
        StyledPanel(title: "System Prompt") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Optional prompt appended to every Claude chat request.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)

                StyledTextEditor(
                    text: $draft.systemPrompt,
                    placeholder: "Be concise, inspect the repository before editing, and explain tool use briefly."
                )
                .frame(height: 120)
            }
        }
    }

    private func commitDraft(discoverCLI: Bool = false) {
        let shouldDiscoverCLI = discoverCLI || settings.claudePath != draft.claudePath
        draft.apply(to: settings)
        if shouldDiscoverCLI {
            settings.discoverCLI()
        }
    }
}

struct ClaudeCLISettingsDraft: Equatable {
    var claudePath: String
    var apiKey: String
    var systemPrompt: String

    init(
        claudePath: String = "",
        apiKey: String = "",
        systemPrompt: String = ""
    ) {
        self.claudePath = claudePath
        self.apiKey = apiKey
        self.systemPrompt = systemPrompt
    }

    init(store: ClaudeCLISettingsStore) {
        self.init(
            claudePath: store.claudePath,
            apiKey: store.apiKey,
            systemPrompt: store.systemPrompt
        )
    }

    mutating func reload(from store: ClaudeCLISettingsStore) {
        self = ClaudeCLISettingsDraft(store: store)
    }

    func apply(to store: ClaudeCLISettingsStore) {
        store.claudePath = claudePath
        store.apiKey = apiKey
        store.systemPrompt = systemPrompt
    }
}

#if DEBUG
    struct ClaudeCLISettingsView_Previews: PreviewProvider {
        static var previews: some View {
            ClaudeCLISettingsView()
                .frame(width: 900, height: 700)
        }
    }
#endif
