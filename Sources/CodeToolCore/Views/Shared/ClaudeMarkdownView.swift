import Foundation
import CodeToolUI
import Markdown
import SwiftUI

private struct ClaudeMarkdownInlineContent: Sendable {
    let attributed: AttributedString?
    let fallbackText: String
}

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
            return .paragraph(cleanMarkdown(inlineMarkdown(from: paragraph)))

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
                markdown: cleanMarkdown(inlineMarkdown(from: cell)),
                alignment: index < alignments.count ? mapAlignment(alignments[index]) : nil
            )
        }
    }

    private static func inlineMarkdown<Container: Markup>(from container: Container) -> String {
        container.children
            .compactMap { $0 as? any InlineMarkup }
            .map(renderInline)
            .joined()
    }

    private static func renderInline(_ inline: any InlineMarkup) -> String {
        switch inline {
        case let text as Markdown.Text:
            return text.string
        case let emphasis as Emphasis:
            return "*" + inlineMarkdown(from: emphasis) + "*"
        case let strong as Strong:
            return "**" + inlineMarkdown(from: strong) + "**"
        case let strikethrough as Strikethrough:
            return "~~" + inlineMarkdown(from: strikethrough) + "~~"
        case let inlineCode as InlineCode:
            return "`" + inlineCode.code + "`"
        case let inlineHTML as InlineHTML:
            return inlineHTML.rawHTML
        case let link as Markdown.Link:
            let label = inlineMarkdown(from: link)
            guard let destination = link.destination, !destination.isEmpty else {
                return label
            }
            if link.isAutolink, label == destination {
                return "<" + destination + ">"
            }
            if let title = link.title, !title.isEmpty {
                return "[\(label)](\(destination) \"\(title)\")"
            }
            return "[\(label)](\(destination))"
        case let image as Markdown.Image:
            let altText = inlineMarkdown(from: image)
            let source = image.source ?? ""
            if let title = image.title, !title.isEmpty {
                return "![\(altText)](\(source) \"\(title)\")"
            }
            return "![\(altText)](\(source))"
        case let symbolLink as SymbolLink:
            return "``" + (symbolLink.destination ?? "") + "``"
        case _ as SoftBreak:
            return " "
        case _ as LineBreak:
            return "  \n"
        default:
            return inline.plainText
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

private struct ClaudeMarkdownRenderModel: Sendable {
    let blocks: [Block]

    init(markdown: String) {
        blocks = Self.parseBlocks(from: Document(parsing: markdown))
    }

    enum Block: Sendable {
        case paragraph(ClaudeMarkdownInlineContent)
        case heading(level: Int, text: String)
        case unorderedList(items: [ListItem])
        case orderedList(startIndex: Int, items: [ListItem])
        case quote([Block])
        case codeBlock(language: String?, code: String)
        case table(header: [TableCell], rows: [[TableCell]])
        case thematicBreak
        case html(String)
    }

    struct ListItem: Sendable {
        let checkbox: CheckboxState?
        let blocks: [Block]
    }

    struct TableCell: Sendable {
        let content: ClaudeMarkdownInlineContent
        let alignment: TableAlignment?
    }

    enum CheckboxState: Sendable {
        case checked
        case unchecked
    }

    enum TableAlignment: Sendable {
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
            return .paragraph(inlineContent(from: paragraph))

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
            return .paragraph(inlineContent(from: block))
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
                content: inlineContent(from: cell),
                alignment: index < alignments.count ? mapAlignment(alignments[index]) : nil
            )
        }
    }

    private static func inlineContent<Container: Markup>(from container: Container) -> ClaudeMarkdownInlineContent {
        let markdown = cleanMarkdown(inlineMarkdown(from: container))
        return ClaudeMarkdownInlineContent(
            attributed: try? AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            ),
            fallbackText: markdown
        )
    }

    private static func inlineMarkdown<Container: Markup>(from container: Container) -> String {
        container.children
            .compactMap { $0 as? any InlineMarkup }
            .map(renderInline)
            .joined()
    }

    private static func renderInline(_ inline: any InlineMarkup) -> String {
        switch inline {
        case let text as Markdown.Text:
            return text.string
        case let emphasis as Emphasis:
            return "*" + inlineMarkdown(from: emphasis) + "*"
        case let strong as Strong:
            return "**" + inlineMarkdown(from: strong) + "**"
        case let strikethrough as Strikethrough:
            return "~~" + inlineMarkdown(from: strikethrough) + "~~"
        case let inlineCode as InlineCode:
            return "`" + inlineCode.code + "`"
        case let inlineHTML as InlineHTML:
            return inlineHTML.rawHTML
        case let link as Markdown.Link:
            let label = inlineMarkdown(from: link)
            guard let destination = link.destination, !destination.isEmpty else {
                return label
            }
            if link.isAutolink, label == destination {
                return "<" + destination + ">"
            }
            if let title = link.title, !title.isEmpty {
                return "[\(label)](\(destination) \"\(title)\")"
            }
            return "[\(label)](\(destination))"
        case let image as Markdown.Image:
            let altText = inlineMarkdown(from: image)
            let source = image.source ?? ""
            if let title = image.title, !title.isEmpty {
                return "![\(altText)](\(source) \"\(title)\")"
            }
            return "![\(altText)](\(source))"
        case let symbolLink as SymbolLink:
            return "``" + (symbolLink.destination ?? "") + "``"
        case _ as SoftBreak:
            return " "
        case _ as LineBreak:
            return "  \n"
        default:
            return inline.plainText
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

private actor ClaudeMarkdownRenderCache {
    static let shared = ClaudeMarkdownRenderCache()

    private var models: [String: ClaudeMarkdownRenderModel] = [:]

    func cachedModel(for markdown: String) -> ClaudeMarkdownRenderModel? {
        models[markdown]
    }

    func store(_ model: ClaudeMarkdownRenderModel, for markdown: String) {
        models[markdown] = model
    }
}

struct ClaudeMarkdownView: View {
    private let markdown: String
    @State private var renderModel: ClaudeMarkdownRenderModel?

    init(markdown: String) {
        self.markdown = markdown
    }

    var body: some View {
        Group {
            if let renderModel {
                ClaudeMarkdownBlocksView(blocks: renderModel.blocks)
            } else {
                Text(markdown)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(AppTheme.textPrimary)
            }
        }
            .textSelection(.enabled)
        .task(id: markdown) {
            await loadRenderModel()
        }
    }

    @MainActor
    private func loadRenderModel() async {
        let startedAt = Date()

        if let cached = await ClaudeMarkdownRenderCache.shared.cachedModel(for: markdown) {
            renderModel = cached
            RenderingPerformance.record(
                .claudeMarkdownRendered,
                durationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1000)),
                metadata: [
                    "cacheHit": "true",
                    "length": String(markdown.count),
                    "blockCount": String(cached.blocks.count)
                ]
            )
            return
        }

        let markdownSnapshot = markdown
        let model = await Task.detached(priority: .utility) {
            ClaudeMarkdownRenderModel(markdown: markdownSnapshot)
        }.value

        await ClaudeMarkdownRenderCache.shared.store(model, for: markdownSnapshot)
        renderModel = model
        RenderingPerformance.record(
            .claudeMarkdownRendered,
            durationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1000)),
            metadata: [
                "cacheHit": "false",
                "length": String(markdownSnapshot.count),
                "blockCount": String(model.blocks.count)
            ]
        )
    }
}

private struct ClaudeMarkdownBlocksView: View {
    let blocks: [ClaudeMarkdownRenderModel.Block]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: ClaudeMarkdownRenderModel.Block) -> some View {
        switch block {
        case .paragraph(let content):
            ClaudeMarkdownInlineText(content: content, font: .body)

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
    private func listItemView(_ item: ClaudeMarkdownRenderModel.ListItem, marker: String?) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            listMarker(item.checkbox, marker: marker)
                .frame(width: 28, alignment: .leading)
                .padding(.top, 1)

            ClaudeMarkdownBlocksView(blocks: item.blocks)
        }
    }

    @ViewBuilder
    private func listMarker(_ checkbox: ClaudeMarkdownRenderModel.CheckboxState?, marker: String?) -> some View {
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
    let content: ClaudeMarkdownInlineContent
    let font: Font

    var body: some View {
        Group {
            if let attributed = content.attributed {
                Text(attributed)
            } else {
                Text(content.fallbackText)
            }
        }
        .font(font)
        .foregroundColor(AppTheme.textPrimary)
        .tint(AppTheme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ClaudeMarkdownTableView: View {
    let header: [ClaudeMarkdownRenderModel.TableCell]
    let rows: [[ClaudeMarkdownRenderModel.TableCell]]

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

    private func tableCellView(_ cell: ClaudeMarkdownRenderModel.TableCell, isHeader: Bool) -> some View {
        ClaudeMarkdownInlineText(
            content: cell.content,
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

    private func alignment(for alignment: ClaudeMarkdownRenderModel.TableAlignment?) -> SwiftUI.Alignment {
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
