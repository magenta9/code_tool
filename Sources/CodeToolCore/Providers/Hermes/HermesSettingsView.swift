import CodeToolUI
import SwiftUI

public struct HermesSettingsView: View {
    @Bindable private var settings = HermesSettingsStore.shared
    @State private var draft = HermesSettingsDraft(store: HermesSettingsStore.shared)

    public init() {}

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Configuration",
            title: "Hermes Settings",
            description: "Configure the local Hermes CLI backend used by Hermes Agent.",
            systemImage: "command",
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
                    cliSection
                    capabilitySection
                    optionSection
                }
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.top, AppTheme.Spacing.xl)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .onAppear {
            draft.reload(from: settings)
            settings.discoverCLI()
        }
        .onSubmit {
            commitDraft(discoverCLI: true)
        }
        .onDisappear {
            commitDraft()
        }
    }

    private var statusItems: [ToolStatusItem] {
        var items: [ToolStatusItem] = [
            ToolStatusItem(
                title: settings.isAvailable ? "CLI Found" : "CLI Not Found",
                systemImage: settings.isAvailable ? "checkmark.circle" : "xmark.circle",
                tint: settings.isAvailable ? AppTheme.success : AppTheme.error
            )
        ]

        if let version = settings.capabilityMatrix?.versionString, !version.isEmpty {
            items.append(
                ToolStatusItem(
                    title: version,
                    systemImage: "tag",
                    tint: AppTheme.accent
                )
            )
        }

        if let outputMode = settings.capabilityMatrix?.outputMode {
            items.append(
                ToolStatusItem(
                    title: outputMode.rawValue,
                    systemImage: "waveform.path.ecg",
                    tint: AppTheme.accentWarm
                )
            )
        }

        return items
    }

    private var cliSection: some View {
        StyledPanel(title: "Hermes CLI") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Provide a custom Hermes binary path or leave it blank to use automatic discovery.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)

                TextField("/opt/homebrew/bin/hermes", text: $draft.hermesPath)
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
                        ? "Resolved binary: \(settings.resolvedHermesPath)"
                        : (settings.lastProbeError.isEmpty
                            ? "No executable Hermes binary was found in the configured search paths."
                            : settings.lastProbeError),
                    tint: settings.isAvailable ? AppTheme.success : AppTheme.warning
                )
            }
        }
    }

    private var capabilitySection: some View {
        StyledPanel(title: "Capabilities") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                if let capabilities = settings.capabilityMatrix {
                    capabilityRow("Query flag", enabled: capabilities.supportsChatQuery)
                    capabilityRow("Quiet output", enabled: capabilities.supportsQuietOutput)
                    capabilityRow("Resume by ID", enabled: capabilities.supportsResumeFlag)
                    capabilityRow("Continue latest", enabled: capabilities.supportsContinueFlag)
                    capabilityRow("Sessions list", enabled: capabilities.supportsSessionsList)
                    capabilityRow("Model flag", enabled: capabilities.supportsModelFlag)
                    capabilityRow("Profile flag", enabled: capabilities.supportsProfileFlag)
                    capabilityRow("Context references", enabled: capabilities.supportsContextReferences)
                } else {
                    Text("Run Detect CLI to load Hermes capability metadata.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textMuted)
                }
            }
        }
    }

    private var optionSection: some View {
        StyledPanel(title: "Request Defaults") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                if settings.capabilityMatrix?.supportsModelFlag == true {
                    labeledField(title: "Model", text: $draft.model, placeholder: "Optional model")
                }

                if settings.capabilityMatrix?.supportsProfileFlag == true {
                    labeledField(title: "Profile", text: $draft.profile, placeholder: "Optional profile")
                }

                labeledField(
                    title: "Extra Arguments",
                    text: $draft.extraArguments,
                    placeholder: "Optional raw CLI flags"
                )
            }
        }
    }

    private func labeledField(
        title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            TextField(placeholder, text: text)
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
    }

    private func capabilityRow(_ title: String, enabled: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Label(enabled ? "Available" : "Unavailable", systemImage: enabled ? "checkmark.circle" : "xmark.circle")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(enabled ? AppTheme.success : AppTheme.textMuted)
        }
    }

    private func commitDraft(discoverCLI: Bool = false) {
        let shouldDiscoverCLI = discoverCLI || settings.hermesPath != draft.hermesPath
        draft.apply(to: settings)
        if shouldDiscoverCLI {
            settings.discoverCLI()
        }
    }
}

#if DEBUG
    struct HermesSettingsView_Previews: PreviewProvider {
        static var previews: some View {
            HermesSettingsView()
                .frame(width: 900, height: 700)
        }
    }
#endif