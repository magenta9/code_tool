import Foundation
import Markdown
import SwiftUI

struct ClaudeMarkdownDocumentModel: Equatable {
    let blocks: [Block]

    init(markdown: String) {
        blocks = Self.parseBlocks(from: Document(parsing: markdown))
    }

    enum Block: Equatable {
        case paragraph(String)
        case heading(level: Int, text: String)
        case unorderedList(items: [ListItem])
        case orderedList(startIndex: Int, items: [ListItem])
        case quote([Block])
        case codeBlock(language: String?, code: String)
        case table(header: [TableCell], rows: [[TableCell]])
        case thematicBreak
        case html(String)
    }

    struct ListItem: Equatable {
        let checkbox: CheckboxState?
        let blocks: [Block]
    }

    struct TableCell: Equatable {
        let markdown: String
        let alignment: TableAlignment?
    }

    enum CheckboxState: Equatable {
        case checked
        case unchecked
    }

    enum TableAlignment: Equatable {
        case left
        case center
        case right
    }

    private static func parseBlocks(from markup: Markup) -> [Block] {
        markup.children.compactMap { child in
            guard let block = child as? BlockMarkup else {
                return nil
            }
            return parseBlock(block)
        }
    }

    private static func parseBlock(_ block: BlockMarkup) -> Block {
        switch block {
        case let heading as Heading:
            return .heading(level: heading.level, text: heading.plainText)

        case let paragraph as Paragraph:
            return .paragraph(cleanMarkdown(paragraph.format()))

        case let unorderedList as UnorderedList:
            let items = unorderedList.children.compactMap { child in
                (child as? Markdown.ListItem).map(parseListItem)
            }
            return .unorderedList(items: items)

        case let orderedList as OrderedList:
            let items = orderedList.children.compactMap { child in
                (child as? Markdown.ListItem).map(parseListItem)
            }
            return .orderedList(startIndex: Int(orderedList.startIndex), items: items)

        case let blockQuote as BlockQuote:
            return .quote(parseBlocks(from: blockQuote))

        case let codeBlock as CodeBlock:
            return .codeBlock(
                language: codeBlock.language,
                code: codeBlock.code.trimmingCharacters(in: CharacterSet.newlines)
            )

        case _ as ThematicBreak:
            return .thematicBreak

        case let table as Markdown.Table:
            let headerCells = table.head.children.compactMap { $0 as? Markdown.Table.Cell }
            let header = parseTableCells(headerCells, alignments: table.columnAlignments)
            let rows = Array(table.body.rows).map { row in
                let rowCells = row.children.compactMap { $0 as? Markdown.Table.Cell }
                return parseTableCells(rowCells, alignments: table.columnAlignments)
            }
            return .table(header: header, rows: rows)

        case let html as HTMLBlock:
            return .html(cleanMarkdown(html.format()))

        default:
            return .paragraph(cleanMarkdown(block.format()))
        }
    }

    private static func parseListItem(_ item: Markdown.ListItem) -> ListItem {
        let checkbox: CheckboxState?
        switch item.checkbox {
        case .checked:
            checkbox = .checked
        case .unchecked:
            checkbox = .unchecked
        case nil:
            checkbox = nil
        }

        return ListItem(checkbox: checkbox, blocks: parseBlocks(from: item))
    }

    private static func parseTableCells(
        _ cells: [Markdown.Table.Cell],
        alignments: [Markdown.Table.ColumnAlignment?]
    ) -> [TableCell] {
        cells.enumerated().map { index, cell in
            TableCell(
                markdown: cleanMarkdown(cell.format()),
                alignment: index < alignments.count ? mapAlignment(alignments[index]) : nil
            )
        }
    }

    private static func mapAlignment(_ alignment: Markdown.Table.ColumnAlignment?) -> TableAlignment? {
        guard let alignment else {
            return nil
        }

        switch alignment {
        case .left:
            return .left
        case .center:
            return .center
        case .right:
            return .right
        }
    }

    private static func cleanMarkdown(_ markdown: String) -> String {
        markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ClaudeMarkdownView: View {
    private let document: ClaudeMarkdownDocumentModel

    init(markdown: String) {
        document = ClaudeMarkdownDocumentModel(markdown: markdown)
    }

    var body: some View {
        ClaudeMarkdownBlocksView(blocks: document.blocks)
            .textSelection(.enabled)
    }
}

private struct ClaudeMarkdownBlocksView: View {
    let blocks: [ClaudeMarkdownDocumentModel.Block]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: ClaudeMarkdownDocumentModel.Block) -> some View {
        switch block {
        case .paragraph(let markdown):
            ClaudeMarkdownInlineText(markdown: markdown, font: .body)

        case .heading(let level, let text):
            Text(text)
                .font(font(forHeadingLevel: level))
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listItemView(item, marker: nil)
                }
            }

        case .orderedList(let startIndex, let items):
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    listItemView(item, marker: "\(startIndex + index).")
                }
            }

        case .quote(let blocks):
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(AppTheme.accentWarm.opacity(0.7))
                    .frame(width: 3)

                ClaudeMarkdownBlocksView(blocks: blocks)
                    .padding(.vertical, AppTheme.Spacing.xs)
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(AppTheme.surfaceRaised.opacity(0.45))
            )

        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.textMuted)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.Spacing.sm)
                }
            }
            .padding(AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(AppTheme.background.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )

        case .table(let header, let rows):
            ClaudeMarkdownTableView(header: header, rows: rows)

        case .thematicBreak:
            Rectangle()
                .fill(AppTheme.borderHover)
                .frame(height: 1)
                .padding(.vertical, AppTheme.Spacing.xs)

        case .html(let html):
            Text(html)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(AppTheme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .fill(AppTheme.surfaceRaised.opacity(0.35))
                )
        }
    }

    @ViewBuilder
    private func listItemView(_ item: ClaudeMarkdownDocumentModel.ListItem, marker: String?) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            listMarker(item.checkbox, marker: marker)
                .frame(width: 28, alignment: .leading)
                .padding(.top, 1)

            ClaudeMarkdownBlocksView(blocks: item.blocks)
        }
    }

    @ViewBuilder
    private func listMarker(_ checkbox: ClaudeMarkdownDocumentModel.CheckboxState?, marker: String?) -> some View {
        if let checkbox {
            Image(systemName: checkbox == .checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(checkbox == .checked ? AppTheme.success : AppTheme.textSecondary)
        } else if let marker {
            Text(marker)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
        } else {
            Text("•")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func font(forHeadingLevel level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: 24, weight: .bold, design: .rounded)
        case 2:
            return .system(size: 20, weight: .bold, design: .rounded)
        case 3:
            return .system(size: 17, weight: .semibold, design: .rounded)
        default:
            return .system(size: 15, weight: .semibold, design: .rounded)
        }
    }
}

private struct ClaudeMarkdownInlineText: View {
    let markdown: String
    let font: Font

    var body: some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            ) {
                Text(attributed)
            } else {
                Text(markdown)
            }
        }
        .font(font)
        .foregroundColor(AppTheme.textPrimary)
        .tint(AppTheme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ClaudeMarkdownTableView: View {
    let header: [ClaudeMarkdownDocumentModel.TableCell]
    let rows: [[ClaudeMarkdownDocumentModel.TableCell]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        tableCellView(cell, isHeader: true)
                    }
                }

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            tableCellView(cell, isHeader: false)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(AppTheme.surface.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )
        }
    }

    private func tableCellView(_ cell: ClaudeMarkdownDocumentModel.TableCell, isHeader: Bool) -> some View {
        ClaudeMarkdownInlineText(
            markdown: cell.markdown,
            font: .system(size: 13, weight: isHeader ? .semibold : .regular, design: .rounded)
        )
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .frame(minWidth: 120, alignment: alignment(for: cell.alignment))
        .background(isHeader ? AppTheme.surfaceRaised.opacity(0.68) : Color.clear)
        .overlay(
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func alignment(for alignment: ClaudeMarkdownDocumentModel.TableAlignment?) -> SwiftUI.Alignment {
        switch alignment {
        case .center:
            return .center
        case .right:
            return .trailing
        case .left, nil:
            return .leading
        }
    }
}
