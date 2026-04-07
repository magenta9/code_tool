import SwiftUI

// MARK: - ScrollingLyricsView

public struct ScrollingLyricsView: View {
    @Environment(\.toolUIActivity) private var toolUIActivity

    let text: String
    let title: String?
    @Binding var highlightedLine: Int?

    @State private var hoveredLine: Int? = nil
    @State private var lines: [LyricLine]

    public init(text: String, title: String? = nil, highlightedLine: Binding<Int?>) {
        self.text = text
        self.title = title
        self._highlightedLine = highlightedLine
        self._lines = State(initialValue: Self.buildLines(from: text))
    }

    private static func isSectionTag(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[") && trimmed.hasSuffix("]") else { return false }
        let inner = trimmed.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        return !inner.isEmpty
    }

    private static func buildLines(from text: String) -> [LyricLine] {
        text.components(separatedBy: .newlines).enumerated().map { index, content in
            LyricLine(
                id: index,
                text: content,
                isSectionTag: isSectionTag(content),
                isEmpty: content.trimmingCharacters(in: .whitespaces).isEmpty
            )
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1.2)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            lineRow(line)
                                .id(line.id)
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }
                .onChange(of: highlightedLine) { _, newValue in
                    if let lineID = newValue {
                        withAnimation(AppTheme.Anim.normal) {
                            proxy.scrollTo(lineID, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.cardGradient.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
        .task(id: text) {
            lines = Self.buildLines(from: text)
        }
        .onChange(of: toolUIActivity.isVisible) { _, isVisible in
            if !isVisible {
                hoveredLine = nil
            }
        }
    }

    // MARK: - Line Row

    @ViewBuilder
    private func lineRow(_ line: LyricLine) -> some View {
        if line.isEmpty {
            Spacer()
                .frame(height: AppTheme.Spacing.md)
        } else if line.isSectionTag {
            sectionTagRow(line)
        } else {
            textLineRow(line)
        }
    }

    private func sectionTagRow(_ line: LyricLine) -> some View {
        let tagText = line.text
            .trimmingCharacters(in: .whitespaces)
            .dropFirst().dropLast()
            .trimmingCharacters(in: .whitespaces)

        return Text(tagText.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.accentWarm)
            .tracking(1.0)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xxs)
            .background(AppTheme.accentWarm.opacity(0.10))
            .clipShape(Capsule())
            .padding(.vertical, AppTheme.Spacing.xs)
            .padding(.horizontal, AppTheme.Spacing.sm)
    }

    private func textLineRow(_ line: LyricLine) -> some View {
        let isHighlighted = highlightedLine == line.id
        let isHovered = hoveredLine == line.id

        return HStack(spacing: AppTheme.Spacing.sm) {
            Text("\(line.id + 1)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textMuted.opacity(0.5))
                .frame(width: 24, alignment: .trailing)

            Text(line.text)
                .font(.system(size: 14, weight: isHighlighted ? .semibold : .regular, design: .rounded))
                .foregroundStyle(isHighlighted ? AppTheme.textPrimary : AppTheme.textSecondary)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                .fill(
                    isHighlighted
                        ? AppTheme.accent.opacity(0.12)
                        : isHovered
                            ? AppTheme.surfaceHover.opacity(0.3)
                            : Color.clear
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(AppTheme.Anim.fast) {
                highlightedLine = isHighlighted ? nil : line.id
            }
        }
        .onHover { h in
            guard toolUIActivity.allowsInteractiveEffects else {
                hoveredLine = nil
                return
            }

            withAnimation(AppTheme.Anim.hover) { hoveredLine = h ? line.id : nil }
        }
    }
}

// MARK: - LyricLine Model

private struct LyricLine: Identifiable {
    let id: Int
    let text: String
    let isSectionTag: Bool
    let isEmpty: Bool
}

// MARK: - Preview

#if DEBUG
    struct ScrollingLyricsView_Previews: PreviewProvider {
        struct PreviewWrapper: View {
            @State var highlighted: Int? = 2

            var body: some View {
                ScrollingLyricsView(
                    text: """
                        [Intro]
                        La la la la la

                        [Verse]
                        Walking through the morning light
                        The city wakes beneath the sky
                        Every step a brand new sight
                        As clouds go drifting by

                        [Chorus]
                        Sing it loud and sing it clear
                        Let the music fill your ears
                        Every note a memory dear
                        Dancing through the years
                        """,
                    title: "Lyrics",
                    highlightedLine: $highlighted
                )
                .frame(width: 400, height: 500)
                .background(AppTheme.background)
            }
        }

        static var previews: some View {
            PreviewWrapper()
        }
    }
#endif
