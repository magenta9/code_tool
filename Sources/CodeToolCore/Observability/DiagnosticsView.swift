import CodeToolUI
import SwiftUI

#if canImport(AppKit)
    import AppKit
    import UniformTypeIdentifiers
#endif

public struct DiagnosticsView: View {
    @State private var recentIssues: [AppLogEntry] = []
    @State private var recentMetrics: [DiagnosticsMetricSummary] = []
    @State private var relatedEvents: [AppLogEntry] = []
    @State private var historyMatches: [DiagnosticsHistoryMatch] = []
    @State private var traceSummary: DiagnosticsTraceSummary?
    @State private var searchReferenceID = ""
    @State private var selectedReferenceID = ""
    @State private var bannerMessage = ""
    @State private var isExporting = false

    public init() {}

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Diagnostics",
            title: "Observability",
            description: "Inspect recent faults, trace a reference ID across logs and history, and export a local diagnostics package.",
            systemImage: "stethoscope",
            statusItems: statusItems
        ) {
            StyledButton("Refresh", systemImage: "arrow.clockwise", variant: .secondary) {
                reload()
            }
            StyledButton("Export", systemImage: "square.and.arrow.up", variant: .primary) {
                exportDiagnostics()
            }
            .disabled(isExporting)
        } content: {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    if !bannerMessage.isEmpty {
                        ToolMessageBanner(
                            systemImage: "info.circle",
                            message: bannerMessage,
                            tint: AppTheme.accent
                        )
                    }

                    searchPanel
                    recentIssuesPanel
                    detailPanels
                    recentMetricsPanel
                }
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.top, AppTheme.Spacing.xl)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .onAppear {
            reload()
        }
    }

    private var statusItems: [ToolStatusItem] {
        var items = [
            ToolStatusItem(
                title: "\(recentIssues.count) recent issue\(recentIssues.count == 1 ? "" : "s")",
                systemImage: "exclamationmark.bubble",
                tint: recentIssues.isEmpty ? AppTheme.textMuted : AppTheme.warning
            )
        ]

        if !selectedReferenceID.isEmpty {
            items.append(
                ToolStatusItem(
                    title: selectedReferenceID,
                    systemImage: "number",
                    tint: AppTheme.accent
                )
            )
        }

        if let traceSummary {
            items.append(
                ToolStatusItem(
                    title: "\(traceSummary.eventCount) trace events",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    tint: AppTheme.success
                )
            )
        }

        return items
    }

    private var searchPanel: some View {
        StyledPanel(title: "Reference ID Search") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Search a user-visible reference ID to aggregate related logs, derived trace details, MetricKit summaries, and HistoryStore records.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)

                HStack(spacing: AppTheme.Spacing.sm) {
                    TextField("reference-id", text: $searchReferenceID)
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

                    StyledButton("Search", systemImage: "magnifyingglass", variant: .primary) {
                        loadReference(searchReferenceID)
                    }
                    .disabled(searchReferenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var recentIssuesPanel: some View {
        StyledPanel(title: "Recent Faults & Errors") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                if recentIssues.isEmpty {
                    Text("No recent fault/error events were indexed.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textMuted)
                } else {
                    ForEach(recentIssues) { entry in
                        Button {
                            if let referenceID = entry.referenceID, !referenceID.isEmpty {
                                searchReferenceID = referenceID
                                loadReference(referenceID)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                                HStack {
                                    Text(entry.event)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Spacer()
                                    Text(Self.relativeDateLabel(for: entry.timestampDate))
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppTheme.textMuted)
                                }

                                Text(entry.message ?? "No message")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.textSecondary)

                                HStack(spacing: AppTheme.Spacing.sm) {
                                    Label(entry.category.rawValue, systemImage: "folder")
                                    if let referenceID = entry.referenceID, !referenceID.isEmpty {
                                        Label(referenceID, systemImage: "number")
                                    }
                                }
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppTheme.textMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppTheme.Spacing.md)
                            .background(AppTheme.surface.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                    .strokeBorder(AppTheme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled((entry.referenceID ?? "").isEmpty)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailPanels: some View {
        if selectedReferenceID.isEmpty {
            StyledPanel(title: "Trace Details") {
                Text("Select a recent issue or search a reference ID to inspect the related diagnostics chain.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textMuted)
            }
        } else {
            StyledPanel(title: "Trace Summary") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    if let traceSummary {
                        Label("Reference ID: \(traceSummary.referenceID)", systemImage: "number")
                        Label("Started: \(Self.absoluteDateLabel(for: traceSummary.startedAt))", systemImage: "clock")
                        Label("Updated: \(Self.absoluteDateLabel(for: traceSummary.lastUpdatedAt))", systemImage: "arrow.clockwise")
                        Label("Events: \(traceSummary.eventCount)", systemImage: "list.bullet.rectangle")
                        if let totalDurationMs = traceSummary.totalDurationMs {
                            Label("Duration: \(totalDurationMs) ms", systemImage: "timer")
                        }
                        if !traceSummary.stages.isEmpty {
                            Text("Stages: \(traceSummary.stages.joined(separator: ", "))")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    } else {
                        Text("No trace summary was derived for this reference ID yet.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textMuted)
                    }
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
            }

            StyledPanel(title: "Related Events") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    if relatedEvents.isEmpty {
                        Text("No indexed events matched this reference ID.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textMuted)
                    } else {
                        ForEach(relatedEvents) { entry in
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                                HStack {
                                    Text(entry.event)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Spacer()
                                    Text(Self.absoluteDateLabel(for: entry.timestampDate))
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(AppTheme.textMuted)
                                }

                                if let message = entry.message, !message.isEmpty {
                                    Text(message)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppTheme.textSecondary)
                                }

                                if !entry.metadata.isEmpty {
                                    Text(entry.metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " · "))
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(AppTheme.textMuted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppTheme.Spacing.md)
                            .background(AppTheme.surface.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                    .strokeBorder(AppTheme.border, lineWidth: 1)
                            )
                        }
                    }
                }
            }

            StyledPanel(title: "Related History") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    if historyMatches.isEmpty {
                        Text("No HistoryStore records matched this reference ID.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textMuted)
                    } else {
                        ForEach(historyMatches) { match in
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                                HStack {
                                    Text(match.title)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Spacer()
                                    Text(Self.absoluteDateLabel(for: match.createdAt))
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(AppTheme.textMuted)
                                }

                                Text(match.detail)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.textSecondary)

                                Text(match.category + (match.sessionID.map { " · session=\($0)" } ?? ""))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(AppTheme.textMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppTheme.Spacing.md)
                            .background(AppTheme.surface.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                    .strokeBorder(AppTheme.border, lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }

    private var recentMetricsPanel: some View {
        StyledPanel(title: "Recent Metric Summaries") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                if recentMetrics.isEmpty {
                    Text("No MetricKit payload summaries were captured yet.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textMuted)
                } else {
                    ForEach(recentMetrics) { metric in
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                            HStack {
                                Text(metric.kind)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Spacer()
                                Text(Self.absoluteDateLabel(for: metric.createdAt))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(AppTheme.textMuted)
                            }

                            Text(metric.metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " · "))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.Spacing.md)
                        .background(AppTheme.surface.opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .strokeBorder(AppTheme.border, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private func reload() {
        Task {
            let summary = try? await DiagnosticsCaseService.shared.recentSummary(issuesLimit: 12, metricsLimit: 6)

            await MainActor.run {
                recentIssues = summary?.recentIssues ?? []
                recentMetrics = summary?.metricSummaries ?? []
                bannerMessage = "Diagnostics index refreshed."
            }

            if !selectedReferenceID.isEmpty {
                await loadReferenceDetails(selectedReferenceID)
            }
        }
    }

    private func loadReference(_ referenceID: String) {
        let trimmed = referenceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        selectedReferenceID = trimmed
        Task {
            await loadReferenceDetails(trimmed)
        }
    }

    @MainActor
    private func loadReferenceDetails(_ referenceID: String) async {
        let snap = try? await DiagnosticsCaseService.shared.snapshot(referenceID: referenceID)

        relatedEvents = snap?.relatedEvents ?? []
        traceSummary = snap?.traceSummary
        historyMatches = snap?.historyMatches ?? []
        bannerMessage = (snap?.relatedEvents.isEmpty ?? true) && (snap?.historyMatches.isEmpty ?? true)
            ? "No diagnostics data matched \(referenceID)."
            : "Loaded diagnostics for \(referenceID)."
    }

    private func exportDiagnostics() {
        isExporting = true
        Task {
            let referenceID = selectedReferenceID.isEmpty ? nil : selectedReferenceID
            defer {
                Task { @MainActor in isExporting = false }
            }

            do {
                let exportURL = try await DiagnosticsCaseService.shared.export(referenceID: referenceID)
                #if canImport(AppKit)
                    let destinationURL: URL? = await MainActor.run {
                        let panel = NSSavePanel()
                        panel.nameFieldStringValue = exportURL.lastPathComponent
                        panel.allowedContentTypes = [.json]
                        guard panel.runModal() == .OK else { return nil }
                        return panel.url
                    }
                    if let destinationURL {
                        if FileManager.default.fileExists(atPath: destinationURL.path) {
                            try FileManager.default.removeItem(at: destinationURL)
                        }
                        try FileManager.default.copyItem(at: exportURL, to: destinationURL)
                    }
                #endif

                await MainActor.run {
                    bannerMessage = "Diagnostics package exported."
                }
            } catch {
                await MainActor.run {
                    bannerMessage = "Failed to export diagnostics: \(error.localizedDescription)"
                }
            }
        }
    }

    private static func relativeDateLabel(for date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private static func absoluteDateLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

#if DEBUG
    struct DiagnosticsView_Previews: PreviewProvider {
        static var previews: some View {
            DiagnosticsView()
                .frame(width: 960, height: 720)
        }
    }
#endif
