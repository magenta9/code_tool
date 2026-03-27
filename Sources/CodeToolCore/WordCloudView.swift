import SwiftUI

// MARK: - Word Cloud View

public struct WordCloudView: View {
    @State private var inputText: String = ""
    @State private var wordCounts: [(word: String, count: Int)] = []
    @State private var minWordLength: Int = 2
    @State private var maxWords: Int = 50
    @State private var ignoreStopWords: Bool = true

    private let colors: [Color] = [
        Color(red: 0.55, green: 0.36, blue: 0.97),  // violet
        Color(red: 0.93, green: 0.28, blue: 0.60),  // pink
        Color(red: 0.13, green: 0.77, blue: 0.37),  // green
        Color(red: 0.96, green: 0.62, blue: 0.04),  // amber
        Color(red: 0.24, green: 0.65, blue: 0.96),  // blue
        Color(red: 0.94, green: 0.27, blue: 0.27),  // red
        Color(red: 0.17, green: 0.82, blue: 0.76),  // teal
        Color(red: 0.44, green: 0.36, blue: 0.96),  // indigo
        Color(red: 0.08, green: 0.80, blue: 0.63),  // emerald
        Color(red: 0.98, green: 0.80, blue: 0.08),  // yellow
    ]

    private let stopWords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "shall", "can", "need", "dare", "ought",
        "used", "to", "of", "in", "for", "on", "with", "at", "by", "from",
        "as", "into", "through", "during", "before", "after", "above", "below",
        "between", "out", "off", "over", "under", "again", "further", "then",
        "once", "and", "but", "or", "nor", "not", "so", "yet", "both",
        "either", "neither", "each", "every", "all", "any", "few", "more",
        "most", "other", "some", "such", "no", "only", "own", "same", "than",
        "too", "very", "just", "because", "if", "when", "where", "how", "what",
        "which", "who", "whom", "this", "that", "these", "those", "i", "me",
        "my", "myself", "we", "our", "ours", "ourselves", "you", "your",
        "yours", "yourself", "yourselves", "he", "him", "his", "himself",
        "she", "her", "hers", "herself", "it", "its", "itself", "they", "them",
        "their", "theirs", "themselves"
    ]

    public init() {}

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Text signals",
            title: "Word Cloud",
            description: "Generate a weighted word map and ranked frequency list inside the same studio layout used by the other tools.",
            systemImage: "cloud",
            statusItems: statusItems
        ) {
            StyledButton("Generate", systemImage: "wand.and.stars", variant: .primary) {
                generateWordCloud()
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !wordCounts.isEmpty {
                CopyButton("Copy Stats", text: wordCounts.map { "\($0.word): \($0.count)" }.joined(separator: "\n"))
                StyledButton("Reset", systemImage: "trash", variant: .ghost) {
                    inputText = ""
                    wordCounts = []
                }
            }
        } content: {
            HSplitView {
                leftPanel
                    .frame(minWidth: 280, idealWidth: 340)
                rightPanel
                    .frame(minWidth: 420)
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
        .frame(minHeight: 500)
    }

    private var statusItems: [ToolStatusItem] {
        var items = [
            ToolStatusItem(title: "Min length \(minWordLength)", systemImage: "line.3.horizontal.decrease.circle", tint: AppTheme.accentWarm),
            ToolStatusItem(title: "Max \(maxWords)", systemImage: "number.circle", tint: AppTheme.accent)
        ]
        if !wordCounts.isEmpty {
            items.append(ToolStatusItem(title: "\(wordCounts.count) words", systemImage: "textformat.abc", tint: AppTheme.success))
        }
        return items
    }

    // MARK: - Left Panel (Input & Settings)

    private var leftPanel: some View {
        StyledPanel(title: "Input Text") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                StyledTextEditor(text: $inputText, placeholder: "Enter or paste text to analyze…")
                    .frame(minHeight: 180)

                settingsSection

                if !wordCounts.isEmpty {
                    frequencyTable
                } else {
                    ToolMessageBanner(systemImage: "sparkles", message: "Paste text, tune filters, then generate to build the cloud and frequency table.", tint: AppTheme.accentWarm)
                }
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("SETTINGS")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
                .textCase(.uppercase)
                .tracking(1.0)

            HStack {
                Text("Min word length:")
                    .foregroundStyle(AppTheme.textSecondary)
                Stepper(value: $minWordLength, in: 1...10) {
                    Text("\(minWordLength)")
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .frame(width: 120)
            }

            HStack {
                Text("Max words:")
                    .foregroundStyle(AppTheme.textSecondary)
                Stepper(value: $maxWords, in: 5...200, step: 5) {
                    Text("\(maxWords)")
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .frame(width: 120)
            }

            Toggle(isOn: $ignoreStopWords) {
                Text("Ignore common stop words")
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md).strokeBorder(AppTheme.border))
    }

    // MARK: - Right Panel (Word Cloud)

    private var rightPanel: some View {
        StyledPanel(title: "Word Cloud") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                if wordCounts.isEmpty {
                    emptyState
                } else {
                    wordCloudContent
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Spacer()
            Image(systemName: "cloud")
                .font(.system(size: 48))
                .overlay(AppTheme.accentGradient)
                .mask(
                    Image(systemName: "cloud")
                        .font(.system(size: 48))
                )
            Text("Enter text and click Generate")
                .foregroundStyle(AppTheme.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var wordCloudContent: some View {
        ScrollView {
            FlowLayout(spacing: 8) {
                ForEach(Array(wordCounts.enumerated()), id: \.offset) { index, entry in
                    Text(entry.word)
                        .font(.system(size: fontSize(for: entry.count)))
                        .fontWeight(fontWeight(for: entry.count))
                        .foregroundStyle(colors[index % colors.count])
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }
            }
            .padding()
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(AppTheme.border)
        )
    }

    // MARK: - Frequency Table

    private var frequencyTable: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("WORD FREQUENCIES")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(wordCounts.enumerated()), id: \.offset) { index, entry in
                        HStack {
                            Text(entry.word)
                                .foregroundStyle(colors[index % colors.count])
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(entry.count)")
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.textMuted)
                        }
                        .padding(.horizontal, AppTheme.Spacing.xs)
                        .padding(.vertical, 1)
                        if index < wordCounts.count - 1 {
                            StyledDivider()
                        }
                    }
                }
                .padding(.vertical, AppTheme.Spacing.xs)
            }
            .frame(maxHeight: 200)
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md).strokeBorder(AppTheme.border))
    }

    // MARK: - Logic

    private func generateWordCloud() {
        let tokens = tokenize(inputText)
        var frequencies: [String: Int] = [:]

        for token in tokens {
            guard token.count >= minWordLength else { continue }
            if ignoreStopWords && stopWords.contains(token) { continue }
            frequencies[token, default: 0] += 1
        }

        wordCounts = frequencies
            .sorted { $0.value > $1.value }
            .prefix(maxWords)
            .map { (word: $0.key, count: $0.value) }
    }

    private func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        var words: [String] = []
        var current = ""

        for char in lowered {
            if char.isLetter || char.isNumber {
                current.append(char)
            } else {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
            }
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words
    }

    private func fontSize(for count: Int) -> CGFloat {
        guard let maxCount = wordCounts.first?.count,
              let minCount = wordCounts.last?.count,
              maxCount > minCount else {
            return 24
        }
        let ratio = CGFloat(count - minCount) / CGFloat(maxCount - minCount)
        return 12 + ratio * 36 // range: 12pt – 48pt
    }

    private func fontWeight(for count: Int) -> Font.Weight {
        guard let maxCount = wordCounts.first?.count,
              let minCount = wordCounts.last?.count,
              maxCount > minCount else {
            return .regular
        }
        let ratio = CGFloat(count - minCount) / CGFloat(maxCount - minCount)
        if ratio > 0.7 { return .bold }
        if ratio > 0.4 { return .semibold }
        return .regular
    }

    private func copyStats() {
        let text = wordCounts
            .map { "\($0.word): \($0.count)" }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight
            if index < rows.count - 1 {
                height += spacing
            }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX

            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(
                    at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width + spacing > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentRowWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentRowWidth += size.width + spacing
        }
        return rows
    }
}

// MARK: - Preview

#if DEBUG
struct WordCloudView_Previews: PreviewProvider {
    static var previews: some View {
        WordCloudView()
            .preferredColorScheme(.dark)
    }
}
#endif
