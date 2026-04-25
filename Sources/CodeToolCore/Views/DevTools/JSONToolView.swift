import CodeToolUI
import SwiftUI

#if canImport(AppKit)
    import AppKit
#endif

public struct JSONToolView: View {
    @State private var inputText = ""
    @State private var outputText = ""
    @State private var errorMessage = ""
    @State private var stats = ""
    @State private var showHistory = false
    @State private var jsonHistory: [JSONToolHistoryRecord] = []

    public init() {}

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Structured data",
            title: "JSON Workspace",
            description: "Format, minify and validate JSON inside a shared dual-panel editor.",
            systemImage: "curlybraces",
            statusItems: statusItems
        ) {
            StyledButton("Format", systemImage: "text.alignleft", variant: .primary) {
                formatJSON()
            }
            StyledButton("Minify", systemImage: "arrow.down.right.and.arrow.up.left") {
                minifyJSON()
            }
            StyledButton("Validate", systemImage: "checkmark.shield") {
                validateJSON()
            }
            if !outputText.isEmpty {
                CopyButton("Copy Output", text: outputText)
            }
            StyledButton("History", systemImage: "clock.arrow.circlepath", variant: .secondary) {
                loadHistory()
                showHistory = true
            }
            StyledButton("Clear", systemImage: "trash", variant: .ghost) {
                clearAll()
            }
            .disabled(inputText.isEmpty && outputText.isEmpty)
        } content: {
            VStack(spacing: AppTheme.Spacing.lg) {
                HSplitView {
                    inputPanel
                    outputPanel
                }
                statusBanner
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
        .overlay {
            if showHistory {
                HistoryDrawer(
                    isPresented: $showHistory,
                    title: "JSON Tool History",
                    items: jsonHistory,
                    onSelect: { record in restoreJSON(record) },
                    onDelete: { record in deleteJSONRecord(record) },
                    onClearAll: { clearJSONHistory() }
                )
            }
        }
    }

    // MARK: - Panels

    private var inputPanel: some View {
        StyledPanel(title: "Source JSON") {
            StyledTextEditor(
                text: $inputText,
                placeholder: "Paste or type JSON here…"
            )
        }
        .frame(minWidth: 280)
    }

    private var outputPanel: some View {
        StyledPanel(title: "Result") {
            StyledTextEditor(
                text: $outputText,
                placeholder: "Formatted output will appear here…",
                isEditable: false
            )
        }
        .frame(minWidth: 280)
    }

    private var statusItems: [ToolStatusItem] {
        if !errorMessage.isEmpty {
            return [
                ToolStatusItem(
                    title: "Invalid input", systemImage: "exclamationmark.triangle.fill",
                    tint: AppTheme.error)
            ]
        }
        if !stats.isEmpty {
            return [
                ToolStatusItem(
                    title: stats, systemImage: "chart.bar.doc.horizontal", tint: AppTheme.accent)
            ]
        }
        return [
            ToolStatusItem(
                title: "Object, array, or fragment", systemImage: "checkmark.shield",
                tint: AppTheme.accentBright),
            ToolStatusItem(
                title: "Sorted output supported", systemImage: "arrow.up.arrow.down",
                tint: AppTheme.accent),
        ]
    }

    private var statusBanner: some View {
        Group {
            if !errorMessage.isEmpty {
                ToolMessageBanner(
                    systemImage: "exclamationmark.triangle.fill", message: errorMessage,
                    tint: AppTheme.error)
            } else if !stats.isEmpty {
                ToolMessageBanner(
                    systemImage: "waveform.path.ecg", message: stats, tint: AppTheme.accent)
            } else {
                ToolMessageBanner(
                    systemImage: "sparkles",
                    message:
                        "Paste JSON on the left, then format, minify or validate from the shared action bar.",
                    tint: AppTheme.accentBright)
            }
        }
    }

    // MARK: - Actions

    private func formatJSON() {
        errorMessage = ""
        outputText = ""
        stats = ""

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Input is empty"
            return
        }

        guard let data = trimmed.data(using: .utf8) else {
            errorMessage = "Unable to encode input as UTF-8"
            return
        }

        do {
            let object = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            let formatted = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
            )
            // JSONSerialization escapes slashes by default; undo that for readability.
            let raw = String(data: formatted, encoding: .utf8) ?? ""
            outputText = raw.replacingOccurrences(of: "\\/", with: "/")
            updateStats(object: object, dataSize: data.count)
            saveToHistory(operation: "format")
        } catch {
            outputText = ""
            errorMessage = error.localizedDescription
        }
    }

    private func minifyJSON() {
        errorMessage = ""
        outputText = ""
        stats = ""

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Input is empty"
            return
        }

        guard let data = trimmed.data(using: .utf8) else {
            errorMessage = "Unable to encode input as UTF-8"
            return
        }

        do {
            let object = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            let minified = try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys, .fragmentsAllowed]
            )
            let raw = String(data: minified, encoding: .utf8) ?? ""
            outputText = raw.replacingOccurrences(of: "\\/", with: "/")
            updateStats(object: object, dataSize: data.count)
            saveToHistory(operation: "minify")
        } catch {
            outputText = ""
            errorMessage = error.localizedDescription
        }
    }

    private func validateJSON() {
        errorMessage = ""
        outputText = ""
        stats = ""

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Input is empty"
            return
        }

        guard let data = trimmed.data(using: .utf8) else {
            errorMessage = "Unable to encode input as UTF-8"
            return
        }

        do {
            let object = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            let typeName: String
            if object is [String: Any] {
                typeName = "Object"
            } else if object is [Any] {
                typeName = "Array"
            } else {
                typeName = "Fragment"
            }
            outputText = "✅ Valid JSON (\(typeName))"
            updateStats(object: object, dataSize: data.count)
            saveToHistory(operation: "validate")
        } catch {
            outputText = "❌ Invalid JSON"
            errorMessage = error.localizedDescription
        }
    }

    private func clearAll() {
        inputText = ""
        outputText = ""
        errorMessage = ""
        stats = ""
    }

    // MARK: - Statistics

    private func updateStats(object: Any, dataSize: Int) {
        let keyCount = countKeys(in: object)
        let depth = nestingDepth(of: object)
        let sizeString = ByteCountFormatter.string(
            fromByteCount: Int64(dataSize), countStyle: .file)
        stats = "Keys: \(keyCount) · Depth: \(depth) · Size: \(sizeString)"
    }

    private func countKeys(in value: Any) -> Int {
        if let dict = value as? [String: Any] {
            return dict.count + dict.values.reduce(0) { $0 + countKeys(in: $1) }
        } else if let array = value as? [Any] {
            return array.reduce(0) { $0 + countKeys(in: $1) }
        }
        return 0
    }

    private func nestingDepth(of value: Any) -> Int {
        if let dict = value as? [String: Any] {
            let childMax = dict.values.map { nestingDepth(of: $0) }.max() ?? 0
            return 1 + childMax
        } else if let array = value as? [Any] {
            let childMax = array.map { nestingDepth(of: $0) }.max() ?? 0
            return 1 + childMax
        }
        return 0
    }

    // MARK: - History

    private func saveToHistory(operation: String) {
        let record = JSONToolHistoryRecord(
            id: UUID(),
            createdAt: Date(),
            operation: operation,
            inputText: inputText,
            outputText: outputText,
            stats: stats
        )
        Task { try? await HistoryStore.shared.upsert(record, using: JSONToolHistoryCodec()) }
    }

    private func loadHistory() {
        Task {
            let records = (try? await HistoryStore.shared.payloads(using: JSONToolHistoryCodec())) ?? []
            await MainActor.run { jsonHistory = records }
        }
    }

    private func restoreJSON(_ record: JSONToolHistoryRecord) {
        inputText = record.inputText
        outputText = ""
        errorMessage = ""
        stats = ""
    }

    private func deleteJSONRecord(_ record: JSONToolHistoryRecord) {
        Task {
            try? await HistoryStore.shared.delete(toolID: .jsonTool, id: record.id)
            let records = (try? await HistoryStore.shared.payloads(using: JSONToolHistoryCodec())) ?? []
            await MainActor.run { jsonHistory = records }
        }
    }

    private func clearJSONHistory() {
        Task {
            try? await HistoryStore.shared.clear(toolID: .jsonTool)
            await MainActor.run { jsonHistory = [] }
        }
    }
}

// MARK: - Previews

#if DEBUG
    struct JSONToolView_Previews: PreviewProvider {
        static var previews: some View {
            JSONToolView()
                .frame(width: 800, height: 500)
                .preferredColorScheme(.dark)
        }
    }
#endif
