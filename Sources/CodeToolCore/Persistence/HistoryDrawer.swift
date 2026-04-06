import CodeToolUI
import SwiftUI

@MainActor
private enum HistoryDrawerFormatterCache {
    static let relativeTime: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

// MARK: - HistoryDrawerItem Protocol

/// Protocol for items displayed in the HistoryDrawer.
public protocol HistoryDrawerItem: Identifiable {
    var id: UUID { get }
    var drawerTitle: String { get }
    var drawerSubtitle: String { get }
    var drawerTimestamp: Date { get }
    var drawerIcon: String { get }
}

// MARK: - Unified HistoryEntry Conformance

extension HistoryEntry: HistoryDrawerItem {
    public var drawerTitle: String { summary.title }
    public var drawerSubtitle: String { summary.subtitle }
    public var drawerTimestamp: Date { createdAt }
    public var drawerIcon: String { summary.icon }
}

// MARK: - Legacy Record Conformances (kept for backward compatibility with existing call sites)

extension ChatHistoryRecord: HistoryDrawerItem {
    public var drawerTitle: String {
        let lastUserMsg = messages.last(where: { $0.role == "user" })?.content ?? "Chat session"
        return String(lastUserMsg.prefix(60))
    }
    public var drawerSubtitle: String {
        "\(messages.count) messages · ~\(totalTokens) tokens"
    }
    public var drawerTimestamp: Date { createdAt }
    public var drawerIcon: String { "bubble.left.and.bubble.right" }
}

extension ClaudeChatHistoryRecord: HistoryDrawerItem {
    public var drawerTitle: String {
        let lastUserMsg = messages.last(where: { $0.role == "user" })?.content ?? "Chat session"
        return String(lastUserMsg.prefix(60))
    }
    public var drawerSubtitle: String {
        let costStr = totalCostUSD.map { String(format: "$%.4f", $0) } ?? ""
        let tokStr = [inputTokens.map { "↑\($0)" }, outputTokens.map { "↓\($0)" }]
            .compactMap { $0 }.joined(separator: " ")
        let attachmentCount = messages.reduce(0) { $0 + ($1.attachments?.count ?? 0) }
        let attachStr = attachmentCount > 0 ? "\(attachmentCount) 📎" : ""
        return ["\(messages.count) msgs", attachStr, costStr, tokStr]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
    public var drawerTimestamp: Date { createdAt }
    public var drawerIcon: String { "bubble.left.and.bubble.right" }
}

extension SpeechHistoryRecord: HistoryDrawerItem {
    public var drawerTitle: String {
        String(inputText.prefix(60))
    }
    public var drawerSubtitle: String {
        "\(voice) · \(outputFormat) · \(durationMs / 1000)s"
    }
    public var drawerTimestamp: Date { createdAt }
    public var drawerIcon: String { "waveform" }
}

extension ImageHistoryRecord: HistoryDrawerItem {
    public var drawerTitle: String {
        String(prompt.prefix(60))
    }
    public var drawerSubtitle: String {
        "\(referenceImages.count) ref\(referenceImages.count == 1 ? "" : "s") · \(sizeSummary) · \(imageCount) output\(imageCount == 1 ? "" : "s")"
    }
    public var drawerTimestamp: Date { createdAt }
    public var drawerIcon: String { "photo.artframe" }
}

extension MusicHistoryRecord: HistoryDrawerItem {
    public var drawerTitle: String {
        String(prompt.prefix(60))
    }
    public var drawerSubtitle: String {
        "\(isInstrumental ? "Instrumental" : "Vocal") · \(outputFormat)"
    }
    public var drawerTimestamp: Date { createdAt }
    public var drawerIcon: String { "music.note" }
}

// MARK: - Dev Record Conformances

extension JSONToolHistoryRecord: HistoryDrawerItem {
    public var drawerTitle: String {
        String(inputText.prefix(60))
    }
    public var drawerSubtitle: String {
        "\(operation) · \(stats)"
    }
    public var drawerTimestamp: Date { createdAt }
    public var drawerIcon: String { "curlybraces" }
}

extension ImageConverterHistoryRecord: HistoryDrawerItem {
    public var drawerTitle: String {
        imageInfo.isEmpty ? "Base64 conversion" : String(imageInfo.prefix(60))
    }
    public var drawerSubtitle: String {
        mode == "imageToBase64" ? "Image → Base64" : "Base64 → Image"
    }
    public var drawerTimestamp: Date { createdAt }
    public var drawerIcon: String { "photo" }
}

extension JSONDiffHistoryRecord: HistoryDrawerItem {
    public var drawerTitle: String {
        "Diff: \(totalDiffs) difference\(totalDiffs == 1 ? "" : "s")"
    }
    public var drawerSubtitle: String {
        "+\(addedCount) −\(removedCount) ≠\(modifiedCount)"
    }
    public var drawerTimestamp: Date { createdAt }
    public var drawerIcon: String { "arrow.left.arrow.right" }
}

extension TimestampHistoryRecord: HistoryDrawerItem {
    public var drawerTitle: String {
        String(inputValue.prefix(60))
    }
    public var drawerSubtitle: String {
        "\(direction == "timestampToDate" ? "Timestamp → Date" : "Date → Timestamp") → \(resultISO8601)"
    }
    public var drawerTimestamp: Date { createdAt }
    public var drawerIcon: String { "clock" }
}

extension JWTHistoryRecord: HistoryDrawerItem {
    public var drawerTitle: String {
        String(payloadJSON.prefix(60))
    }
    public var drawerSubtitle: String {
        "\(mode) · \(expirationInfo)"
    }
    public var drawerTimestamp: Date { createdAt }
    public var drawerIcon: String { "key" }
}

extension WordCloudHistoryRecord: HistoryDrawerItem {
    public var drawerTitle: String {
        String(inputPreview.prefix(60))
    }
    public var drawerSubtitle: String {
        let firstWord = topWords.split(separator: ",").first.map(String.init) ?? ""
        return "\(firstWord) · \(maxWords) words max"
    }
    public var drawerTimestamp: Date { createdAt }
    public var drawerIcon: String { "cloud" }
}

// MARK: - HistoryDrawer

public struct HistoryDrawer<Item: HistoryDrawerItem>: View {
    @Binding var isPresented: Bool
    let title: String
    let items: [Item]
    let onSelect: (Item) -> Void
    let onDelete: (Item) -> Void
    let onClearAll: () -> Void

    @State private var hoveredItemID: UUID?
    @State private var appeared = false

    public init(
        isPresented: Binding<Bool>,
        title: String,
        items: [Item],
        onSelect: @escaping (Item) -> Void,
        onDelete: @escaping (Item) -> Void,
        onClearAll: @escaping () -> Void
    ) {
        self._isPresented = isPresented
        self.title = title
        self.items = items
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onClearAll = onClearAll
    }

    public var body: some View {
        HStack(spacing: 0) {
            Spacer()

            // Semi-transparent backdrop tap to dismiss
            Color.black.opacity(appeared ? 0.3 : 0.0)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
                .frame(maxWidth: .infinity)

            drawerContent
                .frame(width: 380)
                .offset(x: appeared ? 0 : 380)
        }
        .animation(.spring(duration: 0.38, bounce: 0.14), value: appeared)
        .onAppear { appeared = true }
    }

    // MARK: - Drawer Content

    private var drawerContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("\(items.count) record\(items.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textMuted)
                }

                Spacer()

                if !items.isEmpty {
                    StyledButton("Clear All", systemImage: "trash", variant: .destructive) {
                        onClearAll()
                    }
                }

                StyledIconButton("xmark", help: "Close") {
                    dismiss()
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.lg)
            .background(AppTheme.surface.opacity(0.95))
            .overlay(alignment: .bottom) {
                AppTheme.border.frame(height: 1)
            }

            // Content
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            historyCard(item: item, index: index, isLast: index == items.count - 1)
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.md)
                }
            }

            // Footer
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textMuted)
                Text("History stored locally")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textMuted)
                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppTheme.surface.opacity(0.95))
            .overlay(alignment: .top) {
                AppTheme.border.frame(height: 1)
            }
        }
        .background(AppTheme.backgroundRaised)
        .overlay(alignment: .leading) {
            AppTheme.border.frame(width: 1)
        }
    }

    // MARK: - History Card

    private func historyCard(item: Item, index: Int, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            // Timeline element
            VStack(spacing: 0) {
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 8, height: 8)
                    .shadow(color: AppTheme.accent.opacity(0.4), radius: 4)

                if !isLast {
                    Rectangle()
                        .fill(AppTheme.border)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 8)
            .padding(.top, 6)

            // Card content
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                // Timestamp
                Text(relativeTimeString(item.drawerTimestamp))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textMuted)

                // Title
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: item.drawerIcon)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.accent)
                    Text(item.drawerTitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                }

                // Subtitle
                Text(item.drawerSubtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)

                // Actions
                HStack(spacing: AppTheme.Spacing.sm) {
                    Button {
                        onSelect(item)
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Load")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, AppTheme.Spacing.sm)
                        .padding(.vertical, AppTheme.Spacing.xs)
                        .background(AppTheme.accent.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDelete(item)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.error.opacity(0.7))
                            .padding(AppTheme.Spacing.xs)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.top, AppTheme.Spacing.xxs)
            }
            .padding(.vertical, AppTheme.Spacing.sm)
            .padding(.trailing, AppTheme.Spacing.md)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                .fill(hoveredItemID == item.id ? AppTheme.surfaceHover.opacity(0.5) : .clear)
        )
        .animation(AppTheme.Anim.hover, value: hoveredItemID)
        .onHover { hovering in
            hoveredItemID = hovering ? item.id : nil
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 36))
                .foregroundStyle(AppTheme.textMuted.opacity(0.5))
            Text("No history yet")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
            Text("Completed operations will appear here")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(AppTheme.textMuted.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func dismiss() {
        appeared = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isPresented = false
        }
    }

    private func relativeTimeString(_ date: Date) -> String {
        HistoryDrawerFormatterCache.relativeTime.localizedString(for: date, relativeTo: Date())
    }
}
