import CodeToolUI
import SwiftUI

/// A tool view that converts between Unix timestamps and human-readable dates.
public struct TimestampConverterView: View {
    @State private var timestampInput = ""
    @State private var selectedDate = Date()
    @State private var currentTimestamp: TimeInterval = Date().timeIntervalSince1970
    @State private var showHistory = false
    @State private var timestampHistory: [TimestampHistoryRecord] = []

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Time utilities",
            title: "Timestamp Converter",
            description: "Move between Unix timestamps and readable dates using the same card rhythm and feedback patterns as the other tools.",
            systemImage: "clock",
            statusItems: statusItems
        ) {
            StyledButton("Capture Now", systemImage: "clock.badge", variant: .primary) {
                timestampInput = "\(Int(currentTimestamp))"
                selectedDate = Date()
                saveTimestampHistory(direction: "timestampToDate", inputValue: "\(Int(currentTimestamp))")
            }
            StyledButton("History", systemImage: "clock.arrow.circlepath", variant: .secondary) {
                loadHistory()
                showHistory = true
            }
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    CurrentTimeSection(currentTimestamp: currentTimestamp)
                    TimestampToDateSection(timestampInput: $timestampInput, currentTimestamp: currentTimestamp)
                    DateToTimestampSection(selectedDate: $selectedDate)
                }
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.top, AppTheme.Spacing.xl)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .onReceive(timer) { _ in
            currentTimestamp = Date().timeIntervalSince1970
        }
        .overlay {
            if showHistory {
                HistoryDrawer(
                    isPresented: $showHistory,
                    title: "Timestamp History",
                    items: timestampHistory,
                    onSelect: { record in restoreTimestamp(record) },
                    onDelete: { record in deleteTimestampRecord(record) },
                    onClearAll: { clearTimestampHistory() }
                )
            }
        }
    }

    private var statusItems: [ToolStatusItem] {
        [
            ToolStatusItem(title: "\(Int(currentTimestamp)) s", systemImage: "clock.arrow.circlepath", tint: AppTheme.accent),
            ToolStatusItem(title: TimeZone.current.identifier, systemImage: "globe", tint: AppTheme.accentWarm)
        ]
    }

    // MARK: - History Helpers

    private func saveTimestampHistory(direction: String, inputValue: String) {
        let date: Date
        let iso8601: String
        let local: String
        let timestamp: String

        if direction == "timestampToDate", let parsed = Self.parseTimestampStatic(inputValue) {
            date = parsed.date
        } else {
            date = selectedDate
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso8601 = isoFormatter.string(from: date)

        let localFormatter = DateFormatter()
        localFormatter.dateStyle = .full
        localFormatter.timeStyle = .long
        localFormatter.timeZone = .current
        local = localFormatter.string(from: date)

        timestamp = "\(Int(date.timeIntervalSince1970))"

        let record = TimestampHistoryRecord(
            id: UUID(),
            createdAt: Date(),
            inputValue: inputValue,
            direction: direction,
            selectedDateISO8601: direction == "dateToTimestamp" ? iso8601 : nil,
            resultISO8601: iso8601,
            resultLocal: local,
            resultTimestamp: timestamp
        )
        Task { try? await HistoryStore.shared.save(record) }
    }

    private static func parseTimestampStatic(_ input: String) -> (date: Date, isMilliseconds: Bool)? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite else { return nil }
        let threshold: Double = 9_999_999_999
        let isMilliseconds = abs(value) > threshold
        let seconds = isMilliseconds ? value / 1000.0 : value
        return (Date(timeIntervalSince1970: seconds), isMilliseconds)
    }

    private func loadHistory() {
        Task {
            let records = (try? await HistoryStore.shared.listTimestamp()) ?? []
            await MainActor.run { timestampHistory = records }
        }
    }

    private func restoreTimestamp(_ record: TimestampHistoryRecord) {
        if record.direction == "timestampToDate" {
            timestampInput = record.inputValue
        } else if let iso = record.selectedDateISO8601 {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: iso) {
                selectedDate = date
            }
        }
    }

    private func deleteTimestampRecord(_ record: TimestampHistoryRecord) {
        Task {
            try? await HistoryStore.shared.deleteTimestamp(id: record.id)
            let records = (try? await HistoryStore.shared.listTimestamp()) ?? []
            await MainActor.run { timestampHistory = records }
        }
    }

    private func clearTimestampHistory() {
        Task {
            try? await HistoryStore.shared.clear(category: .timestampConverter)
            await MainActor.run { timestampHistory = [] }
        }
    }
}

// MARK: - Current Time Section

private struct CurrentTimeSection: View {
    let currentTimestamp: TimeInterval

    var body: some View {
        StyledPanel(title: "Current Time") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                StyledSectionHeader("Live Clock", systemImage: "clock")

                HStack(spacing: AppTheme.Spacing.lg) {
                    ThemedValueCard(label: "Seconds", value: "\(Int(currentTimestamp))")
                    ThemedValueCard(label: "Milliseconds", value: "\(Int(currentTimestamp * 1000))")
                }

                ToolMessageBanner(
                    systemImage: "calendar",
                    message: formatDate(Date(), timeZone: .current),
                    tint: AppTheme.accentWarm
                )
            }
        }
    }
}

// MARK: - Timestamp → Date Section

private struct TimestampToDateSection: View {
    @Binding var timestampInput: String
    let currentTimestamp: TimeInterval

    var body: some View {
        StyledPanel(title: "Timestamp to Date") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                StyledSectionHeader("Timestamp Input", systemImage: "arrow.right")

                HStack {
                    TextField("Enter Unix timestamp…", text: $timestampInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(AppTheme.Spacing.md)
                        .background(AppTheme.background.opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md).strokeBorder(AppTheme.border))

                    StyledButton("Now", variant: .secondary) {
                        timestampInput = "\(Int(currentTimestamp))"
                    }

                    StyledIconButton("xmark.circle.fill", help: "Clear") {
                        timestampInput = ""
                    }
                    .disabled(timestampInput.isEmpty)
                }

                if let result = parseTimestamp(timestampInput) {
                    let detected = result.isMilliseconds ? "Detected as milliseconds" : "Detected as seconds"
                    ToolMessageBanner(systemImage: "scope", message: detected, tint: AppTheme.accent)

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        ThemedConversionRow(label: "ISO 8601", value: formatISO8601(result.date))
                        ThemedConversionRow(label: "UTC", value: formatDate(result.date, timeZone: TimeZone(identifier: "UTC")!))
                        ThemedConversionRow(label: "Local (\(TimeZone.current.abbreviation() ?? ""))", value: formatDate(result.date, timeZone: .current))
                        ThemedConversionRow(label: "Relative", value: formatRelative(result.date))
                    }
                    .padding(AppTheme.Spacing.md)
                    .background(AppTheme.surface.opacity(0.66))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
                    .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.lg).strokeBorder(AppTheme.border))
                } else if !timestampInput.isEmpty {
                    ToolMessageBanner(systemImage: "exclamationmark.triangle.fill", message: "Invalid timestamp", tint: AppTheme.error)
                }
            }
        }
    }
}

// MARK: - Date → Timestamp Section

private struct DateToTimestampSection: View {
    @Binding var selectedDate: Date

    var body: some View {
        StyledPanel(title: "Date to Timestamp") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                StyledSectionHeader("Date Picker", systemImage: "arrow.left")

                HStack {
                    DatePicker("Select date", selection: $selectedDate)
                        .labelsHidden()

                    StyledButton("Now", variant: .secondary) {
                        selectedDate = Date()
                    }
                }

                let ts = selectedDate.timeIntervalSince1970

                HStack(spacing: AppTheme.Spacing.lg) {
                    ThemedValueCard(label: "Seconds", value: "\(Int(ts))")
                    ThemedValueCard(label: "Milliseconds", value: "\(Int(ts * 1000))")
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    ThemedConversionRow(label: "ISO 8601", value: formatISO8601(selectedDate))
                    ThemedConversionRow(label: "UTC", value: formatDate(selectedDate, timeZone: TimeZone(identifier: "UTC")!))
                    ThemedConversionRow(label: "Local (\(TimeZone.current.abbreviation() ?? ""))", value: formatDate(selectedDate, timeZone: .current))
                }
                .padding(AppTheme.Spacing.md)
                .background(AppTheme.surface.opacity(0.66))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.lg).strokeBorder(AppTheme.border))
            }
        }
    }
}

// MARK: - Parsing & Formatting Helpers

private struct ParsedTimestamp {
    let date: Date
    let isMilliseconds: Bool
}

/// Parses a timestamp string, auto-detecting seconds vs milliseconds.
/// Values with more than 10 digits are treated as milliseconds.
/// Supports negative timestamps (before epoch).
private func parseTimestamp(_ input: String) -> ParsedTimestamp? {
    let trimmed = input.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite else {
        return nil
    }

    let threshold: Double = 9_999_999_999
    let isMilliseconds = abs(value) > threshold
    let seconds = isMilliseconds ? value / 1000.0 : value

    return ParsedTimestamp(date: Date(timeIntervalSince1970: seconds), isMilliseconds: isMilliseconds)
}

private func formatISO8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func formatDate(_ date: Date, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .full
    formatter.timeStyle = .long
    formatter.timeZone = timeZone
    return formatter.string(from: date)
}

private func formatRelative(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
}

// MARK: - Previews

#if DEBUG
struct TimestampConverterView_Previews: PreviewProvider {
    static var previews: some View {
        TimestampConverterView()
            .frame(width: 600, height: 700)
            .preferredColorScheme(.dark)
    }
}
#endif
