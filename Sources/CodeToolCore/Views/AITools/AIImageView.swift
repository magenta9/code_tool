import AppKit
import CodeToolUI
import SwiftUI
import UniformTypeIdentifiers

public struct AIImageView: View {
    @Environment(\.toolVisibilityContext) private var toolVisibilityContext

    private enum GenerationMode: String, CaseIterable {
        case textOnly
        case referenceGuided

        var title: String {
            switch self {
            case .textOnly:
                return "Text Only"
            case .referenceGuided:
                return "Reference Guided"
            }
        }

        var subtitle: String {
            switch self {
            case .textOnly:
                return "Pure prompt-to-image generation."
            case .referenceGuided:
                return "Guide the shot with one or more reference frames."
            }
        }
    }

    private enum ParameterMode: String, CaseIterable {
        case aspectRatio
        case customSize

        var title: String {
            switch self {
            case .aspectRatio:
                return "Aspect Ratio"
            case .customSize:
                return "Custom Size"
            }
        }
    }

    private struct AIImageReferenceItem: Identifiable {
        let id: UUID
        let image: NSImage
        let pngData: Data
        let fileName: String
        let mimeType: String
        let sizeBytes: Int

        init(
            id: UUID = UUID(),
            image: NSImage,
            pngData: Data,
            fileName: String,
            mimeType: String,
            sizeBytes: Int
        ) {
            self.id = id
            self.image = image
            self.pngData = pngData
            self.fileName = fileName
            self.mimeType = mimeType
            self.sizeBytes = sizeBytes
        }

        init(asset: ImportedImageAsset) {
            self.init(
                image: asset.image,
                pngData: asset.pngData,
                fileName: asset.fileName,
                mimeType: asset.mimeType,
                sizeBytes: asset.sizeBytes
            )
        }

        var fileSizeLabel: String {
            ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
        }

        var dimensionsLabel: String {
            if let representation = image.representations.first {
                return "\(representation.pixelsWide)×\(representation.pixelsHigh)"
            }
            return "\(Int(image.size.width))×\(Int(image.size.height))"
        }
    }

    private var settings = MiniMaxSettingsStore.shared

    @State private var promptText = ""
    @State private var isGenerating = false
    @State private var generatedImages: [NSImage] = []
    @State private var errorMessage = ""
    @State private var warningMessage = ""
    @State private var generationMode: GenerationMode = .textOnly
    @State private var parameterMode: ParameterMode = .aspectRatio
    @State private var aspectRatio = "1:1"
    @State private var customWidthText = "1024"
    @State private var customHeightText = "1024"
    @State private var imageCount = 1
    @State private var seedText = ""
    @State private var promptOptimizer = false
    @State private var latestReferenceID = ""
    @State private var showHistory = false
    @State private var imageHistory: [ImageHistoryRecord] = []
    @State private var imageHistoryHasMore = false
    @State private var historyDrawerOpenedAt: Date?
    @State private var referenceImages: [AIImageReferenceItem] = []
    @State private var selectedReferenceImageID: UUID?
    @State private var selectedOutputIndex = 0
    @State private var isReferenceDropTargeted = false

    private let aspectRatios = ["1:1", "16:9", "9:16", "4:3", "3:4", "3:2", "2:3", "21:9"]
    private let historyPageSize = 20

    public init() {}

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Reference Workbench",
            title: "AI Image",
            description: "Generate with text alone or guide MiniMax with reference frames, cinematic composition controls, and replayable history.",
            systemImage: "photo.artframe",
            statusItems: statusItems
        ) {
            StyledButton("Generate", systemImage: "sparkles", variant: .primary) {
                generateImages()
            }
            .disabled(!canGenerate)

            StyledButton("Save Selected", systemImage: "square.and.arrow.down") {
                saveSelectedImage()
            }
            .disabled(selectedOutputImage == nil)

            StyledButton("Clear", systemImage: "trash", variant: .ghost) {
                clearWorkspace()
            }
            .disabled(promptText.isEmpty && generatedImages.isEmpty && referenceImages.isEmpty && errorMessage.isEmpty && warningMessage.isEmpty)

            StyledButton("History", systemImage: "clock.arrow.circlepath", variant: .secondary) {
                historyDrawerOpenedAt = Date()
                loadHistory(reset: true)
                showHistory = true
            }
        } content: {
            VStack(spacing: AppTheme.Spacing.md) {
                if !settings.isConfigured {
                    ToolMessageBanner(
                        systemImage: "exclamationmark.triangle.fill",
                        message: "MiniMax API key not configured. Open Settings to add your credentials before generating images.",
                        tint: AppTheme.warning
                    )
                }

                if !warningMessage.isEmpty {
                    ToolMessageBanner(
                        systemImage: "exclamationmark.triangle.fill",
                        message: warningMessage,
                        tint: AppTheme.warning
                    )
                }

                if !errorMessage.isEmpty {
                    ToolMessageBanner(
                        systemImage: "xmark.octagon.fill",
                        message: errorMessage,
                        tint: AppTheme.error
                    )
                }

                HSplitView {
                    referenceBoard
                        .frame(minWidth: 300, idealWidth: 340)

                    controlsBoard
                        .frame(minWidth: 320, idealWidth: 360)

                    outputBoard
                        .frame(minWidth: 360, idealWidth: 440)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
        .overlay {
            if showHistory {
                HistoryDrawer(
                    isPresented: $showHistory,
                    title: "Image History",
                    items: imageHistory,
                    onSelect: { record in restoreImage(record) },
                    onDelete: { record in deleteImageRecord(record) },
                    onClearAll: { clearImageHistory() },
                    toolID: .aiImage,
                    openedAt: historyDrawerOpenedAt,
                    pageSize: historyPageSize,
                    hasMore: imageHistoryHasMore,
                    onLoadMore: { loadHistory(reset: false) }
                )
            }
        }
    }

    // MARK: - Status

    private var statusItems: [ToolStatusItem] {
        var items: [ToolStatusItem] = [
            ToolStatusItem(
                title: generationMode.title,
                systemImage: generationMode == .referenceGuided ? "photo.stack.fill" : "text.quote",
                tint: generationMode == .referenceGuided ? AppTheme.accentBright : AppTheme.accent
            ),
            ToolStatusItem(
                title: sizeSummary,
                systemImage: parameterMode == .customSize ? "rectangle.expand.vertical" : "aspectratio",
                tint: AppTheme.textSecondary
            ),
            ToolStatusItem(
                title: "\(imageCount) output\(imageCount == 1 ? "" : "s")",
                systemImage: "square.grid.2x2",
                tint: AppTheme.textSecondary
            )
        ]

        if !referenceImages.isEmpty {
            items.append(
                ToolStatusItem(
                    title: "\(referenceImages.count) ref\(referenceImages.count == 1 ? "" : "s")",
                    systemImage: "photo.on.rectangle.angled",
                    tint: AppTheme.accentBright
                )
            )
        }

        if isGenerating {
            items.append(
                ToolStatusItem(
                    title: "Generating…",
                    systemImage: "hourglass",
                    tint: AppTheme.accent
                )
            )
        } else if !generatedImages.isEmpty {
            items.append(
                ToolStatusItem(
                    title: "\(generatedImages.count) ready",
                    systemImage: "checkmark.circle.fill",
                    tint: AppTheme.success
                )
            )
        }

        if promptOptimizer {
            items.append(
                ToolStatusItem(
                    title: "Optimizer on",
                    systemImage: "wand.and.stars",
                    tint: AppTheme.accentBright
                )
            )
        }

        if !errorMessage.isEmpty {
            items.append(
                ToolStatusItem(
                    title: "Error",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: AppTheme.error
                )
            )
        }

        return items
    }

    // MARK: - Panels

    private var referenceBoard: some View {
        StyledPanel(title: "Reference Board") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                referenceHero

                HStack(spacing: AppTheme.Spacing.sm) {
                    StyledButton("Add Images…", systemImage: "plus") {
                        openReferenceFiles()
                    }

                    StyledButton("Paste", systemImage: "doc.on.clipboard", variant: .secondary) {
                        ingestPasteboardImages()
                    }

                    if !referenceImages.isEmpty {
                        StyledButton("Clear Refs", systemImage: "xmark", variant: .ghost) {
                            clearReferenceImages()
                        }
                    }
                }

                Text("Drag frames in, click Add Images…, or press Cmd+V in the prompt editor or here to build a subject board.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textMuted)

                referenceStrip
            }
        }
    }

    private var referenceHero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    AppTheme.surfaceRaised.opacity(isReferenceDropTargeted ? 0.92 : 0.78),
                    AppTheme.background.opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let item = selectedReferenceImage {
                Image(nsImage: item.image)
                    .resizable()
                    .scaledToFit()
                    .padding(AppTheme.Spacing.lg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    GradientBadge("Selected reference", color: AppTheme.accentBright)
                    Text(item.fileName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    Text("\(item.dimensionsLabel) px · \(item.fileSizeLabel)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(AppTheme.Spacing.lg)
            } else {
                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: isReferenceDropTargeted ? "square.and.arrow.down.fill" : "photo.stack")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(isReferenceDropTargeted ? AppTheme.accentBright : AppTheme.accent)

                    VStack(spacing: AppTheme.Spacing.xs) {
                        Text(isReferenceDropTargeted ? "Release to stage the reference frame" : "Build a director’s light table")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("Use clean subject references for character consistency, wardrobe continuity, or art-direction lockups.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 240)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(AppTheme.Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(
                    isReferenceDropTargeted ? AppTheme.accentBright.opacity(0.9) : AppTheme.borderHover,
                    style: StrokeStyle(lineWidth: 1.2, dash: [8, 5])
                )
        )
        .overlay(alignment: .topTrailing) {
            if let selectedReferenceImage {
                Button {
                    removeReferenceImage(id: selectedReferenceImage.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(10)
                        .background(AppTheme.background.opacity(0.82))
                        .clipShape(Circle())
                        .overlay(
                            Circle().strokeBorder(AppTheme.borderHover, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(AppTheme.Spacing.md)
            }
        }
        .onDrop(
            of: [UTType.fileURL.identifier, UTType.image.identifier],
            isTargeted: $isReferenceDropTargeted
        ) { providers in
            handleDrop(providers: providers)
        }
    }

    @ViewBuilder
    private var referenceStrip: some View {
        if referenceImages.isEmpty {
            HStack(spacing: AppTheme.Spacing.md) {
                referenceHintCard(
                    title: "Drag & drop",
                    subtitle: "Finder images or screenshots",
                    systemImage: "hand.draw"
                )
                referenceHintCard(
                    title: "Multi-select",
                    subtitle: "Batch import PNG, JPEG, GIF, WebP",
                    systemImage: "rectangle.stack.badge.plus"
                )
                referenceHintCard(
                    title: "Paste",
                    subtitle: "Cmd+V keeps text paste normal otherwise",
                    systemImage: "doc.on.clipboard"
                )
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: AppTheme.Spacing.md) {
                    ForEach(Array(referenceImages.enumerated()), id: \.element.id) { index, item in
                        referenceThumbnail(item: item, index: index)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 118)
        }
    }

    private func referenceHintCard(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.accentBright)
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
    }

    private func referenceThumbnail(item: AIImageReferenceItem, index: Int) -> some View {
        Button {
            selectedReferenceImageID = item.id
        } label: {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                ZStack(alignment: .topLeading) {
                    Image(nsImage: item.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 108, height: 72)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))

                    Text("#\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.background)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(AppTheme.accentBright)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous))
                        .padding(8)

                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                removeReferenceImage(id: item.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .background(Circle().fill(AppTheme.background.opacity(0.84)))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(6)
                }

                Text(item.fileName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text("\(item.dimensionsLabel) · \(item.fileSizeLabel)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textMuted)
                    .lineLimit(1)
            }
            .padding(AppTheme.Spacing.sm)
            .frame(width: 126, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                    .fill(
                        selectedReferenceImageID == item.id
                            ? AnyShapeStyle(AppTheme.selectionGradient)
                            : AnyShapeStyle(AppTheme.surface.opacity(0.72))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                    .strokeBorder(
                        selectedReferenceImageID == item.id ? AppTheme.accentBright.opacity(0.7) : AppTheme.border,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var controlsBoard: some View {
        StyledPanel(title: "Prompt & Controls") {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    promptSection
                    modeSection
                    compositionSection
                    advancedSection
                }
            }
        }
    }

    private var promptSection: some View {
        sectionCard(
            title: "Prompt",
            systemImage: "text.quote"
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                ReferencePromptEditor(
                    text: $promptText,
                    placeholder: "Describe the shot, lens language, subject treatment, mood, and what should change from the references…",
                    onPasteAssets: { assets in appendReferenceAssets(assets) }
                )
                .frame(minHeight: 180)

                HStack {
                    Text("Model: \(settings.imageModel)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textMuted)
                    Spacer()
                    Text("\(promptText.count) chars")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textMuted)
                }
            }
        }
    }

    private var modeSection: some View {
        sectionCard(
            title: "Mode",
            systemImage: "dial.medium"
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                StyledSegmentedPicker(
                    options: GenerationMode.allCases,
                    selection: $generationMode,
                    label: { $0.title }
                )

                Text(generationMode.subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textMuted)

                if generationMode == .referenceGuided && referenceImages.isEmpty {
                    ToolMessageBanner(
                        systemImage: "photo.on.rectangle.angled",
                        message: "Reference Guided mode needs at least one staged image.",
                        tint: AppTheme.warning
                    )
                }
            }
        }
    }

    private var compositionSection: some View {
        sectionCard(
            title: "Composition",
            systemImage: "crop"
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("Canvas")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)

                    StyledSegmentedPicker(
                        options: ParameterMode.allCases,
                        selection: $parameterMode,
                        label: { $0.title }
                    )
                }

                if parameterMode == .aspectRatio {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("Aspect Ratio")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                ForEach(aspectRatios, id: \.self) { ratio in
                                    Button {
                                        aspectRatio = ratio
                                    } label: {
                                        Text(ratio)
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(aspectRatio == ratio ? AppTheme.background : AppTheme.textSecondary)
                                            .padding(.horizontal, AppTheme.Spacing.md)
                                            .padding(.vertical, AppTheme.Spacing.sm)
                                            .background(
                                                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                                                    .fill(aspectRatio == ratio ? AnyShapeStyle(AppTheme.accent) : AnyShapeStyle(AppTheme.surfaceRaised))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                                                    .strokeBorder(aspectRatio == ratio ? Color.white.opacity(0.16) : AppTheme.border, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } else {
                    HStack(spacing: AppTheme.Spacing.md) {
                        parameterField(
                            title: "Width",
                            text: $customWidthText,
                            placeholder: "1024"
                        )
                        parameterField(
                            title: "Height",
                            text: $customHeightText,
                            placeholder: "1024"
                        )
                    }

                    Text("Custom dimensions must be 512–2048 px and divisible by 8.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textMuted)
                }

                HStack(spacing: AppTheme.Spacing.md) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        Text("Outputs")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                        Stepper(value: $imageCount, in: 1...9) {
                            Text("\(imageCount) image\(imageCount == 1 ? "" : "s")")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private var advancedSection: some View {
        sectionCard(
            title: "Advanced",
            systemImage: "slider.horizontal.3"
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                parameterField(
                    title: "Seed",
                    text: $seedText,
                    placeholder: "Optional reproducible seed"
                )

                Toggle(isOn: $promptOptimizer) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Prompt Optimizer")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Let MiniMax refine the prompt before generation.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textMuted)
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }

    private func parameterField(
        title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(AppTheme.background.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                )
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            StyledSectionHeader(title, systemImage: systemImage)
            content()
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.surface.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
    }

    private var outputBoard: some View {
        StyledPanel(title: "Output Gallery") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                outputHero
                outputMetaBar
                outputContactSheet
            }
        }
    }

    private var outputHero: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.surfaceRaised.opacity(0.74), AppTheme.background.opacity(0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if isGenerating {
                VStack(spacing: AppTheme.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.4)
                        .tint(AppTheme.accent)
                    Text("Developing contact sheet…")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("MiniMax is rendering the current shot with \(generationMode == .referenceGuided ? "\(referenceImages.count) reference frame\(referenceImages.count == 1 ? "" : "s")" : "text-only direction").")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let image = selectedOutputImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(AppTheme.Spacing.lg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "photo.artframe")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text("No render yet")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(
                        generationMode == .referenceGuided
                            ? "Stage reference material, direct the prompt, and render a new frame."
                            : "Describe the shot and render a fresh frame with MiniMax."
                    )
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 250)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(AppTheme.borderHover, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            if selectedOutputImage != nil {
                HStack(spacing: AppTheme.Spacing.sm) {
                    GradientBadge("Hero preview", color: AppTheme.accent)
                    Text("\(selectedOutputIndex + 1)/\(generatedImages.count)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(AppTheme.Spacing.md)
            }
        }
    }

    private var outputMetaBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            outputMetaChip(
                title: generationMode == .referenceGuided ? "Guided" : "Text only",
                systemImage: generationMode == .referenceGuided ? "photo.stack.fill" : "text.quote",
                tint: generationMode == .referenceGuided ? AppTheme.accentBright : AppTheme.accent
            )
            outputMetaChip(
                title: sizeSummary,
                systemImage: parameterMode == .customSize ? "rectangle.expand.vertical" : "aspectratio",
                tint: AppTheme.textSecondary
            )
            outputMetaChip(
                title: "\(referenceImages.count) refs",
                systemImage: "photo.on.rectangle.angled",
                tint: AppTheme.textSecondary
            )
            outputMetaChip(
                title: "\(generatedImages.count) ready",
                systemImage: "square.grid.2x2",
                tint: generatedImages.isEmpty ? AppTheme.textMuted : AppTheme.success
            )
        }
    }

    private func outputMetaChip(title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(tint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var outputContactSheet: some View {
        if generatedImages.isEmpty {
            Text("Rendered frames appear here as a contact sheet. Click any thumbnail to promote it to the hero preview.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let columns = Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.sm), count: min(2, max(generatedImages.count, 1)))

            ScrollView {
                LazyVGrid(columns: columns, spacing: AppTheme.Spacing.sm) {
                    ForEach(Array(generatedImages.enumerated()), id: \.offset) { index, image in
                        Button {
                            selectedOutputIndex = index
                        } label: {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .padding(6)
                                .background(AppTheme.surface.opacity(0.72))
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                        .strokeBorder(
                                            selectedOutputIndex == index ? AppTheme.accent.opacity(0.8) : AppTheme.border,
                                            lineWidth: 1
                                        )
                                )
                                .overlay(alignment: .topLeading) {
                                    Text("#\(index + 1)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(AppTheme.background)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background(selectedOutputIndex == index ? AppTheme.accent : AppTheme.surfaceRaised)
                                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous))
                                        .padding(8)
                                }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Save This Image…") {
                                saveSpecificImage(image, index: index)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Derived State

    private var selectedReferenceImage: AIImageReferenceItem? {
        if let selectedReferenceImageID,
           let selected = referenceImages.first(where: { $0.id == selectedReferenceImageID }) {
            return selected
        }
        return referenceImages.first
    }

    private var selectedOutputImage: NSImage? {
        guard generatedImages.indices.contains(selectedOutputIndex) else {
            return generatedImages.first
        }
        return generatedImages[selectedOutputIndex]
    }

    private var canGenerate: Bool {
        !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isGenerating
            && settings.isConfigured
            && (generationMode == .textOnly || !referenceImages.isEmpty)
    }

    private var sizeSummary: String {
        if parameterMode == .aspectRatio {
            return aspectRatio
        }

        let width = customWidthText.trimmingCharacters(in: .whitespacesAndNewlines)
        let height = customHeightText.trimmingCharacters(in: .whitespacesAndNewlines)
        return width.isEmpty || height.isEmpty ? "Custom" : "\(width)x\(height)"
    }

    // MARK: - Actions

    private func openReferenceFiles() {
        let panel = NSOpenPanel()
        panel.title = "Select Reference Images"
        panel.allowedContentTypes = ImageImportSupport.supportedImageTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }

        let importedAssets = ImageImportSupport.importAssets(from: panel.urls)
        appendReferenceAssets(importedAssets)

        if importedAssets.count != panel.urls.count {
            warningMessage = "Some selected files were skipped. Only PNG, JPEG, GIF, and WebP images are supported."
        }
    }

    private func ingestPasteboardImages() {
        let importedAssets = ImageImportSupport.importAssets()
        guard !importedAssets.isEmpty else {
            warningMessage = "Clipboard does not currently contain a supported image."
            return
        }
        appendReferenceAssets(importedAssets)
    }

    private func appendReferenceAssets(_ assets: [ImportedImageAsset]) {
        guard !assets.isEmpty else { return }

        let items = assets.map(AIImageReferenceItem.init(asset:))
        let previousSelection = selectedReferenceImageID
        referenceImages.append(contentsOf: items)
        generationMode = .referenceGuided
        warningMessage = ""

        if let previousSelection,
           referenceImages.contains(where: { $0.id == previousSelection }) {
            selectedReferenceImageID = previousSelection
        } else {
            selectedReferenceImageID = referenceImages.first?.id
        }
    }

    private func clearReferenceImages() {
        referenceImages = []
        selectedReferenceImageID = nil
        generationMode = .textOnly
    }

    private func removeReferenceImage(id: UUID) {
        referenceImages.removeAll { $0.id == id }

        if selectedReferenceImageID == id {
            selectedReferenceImageID = referenceImages.first?.id
        }

        if referenceImages.isEmpty {
            generationMode = .textOnly
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        let state = DropImportState()
        var requestedLoads = 0

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                requestedLoads += 1
                state.group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { state.group.leave() }

                    let url: URL?
                    switch item {
                    case let data as Data:
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    case let urlValue as URL:
                        url = urlValue
                    case let nsURL as NSURL:
                        url = nsURL as URL
                    case let string as String:
                        url = URL(string: string)
                    default:
                        url = nil
                    }

                    guard let url else { return }
                    if let asset = try? ImageImportSupport.importAsset(from: url) {
                        state.append(asset)
                    }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                requestedLoads += 1
                state.group.enter()
                provider.loadObject(ofClass: NSImage.self) { item, _ in
                    defer { state.group.leave() }
                    guard let image = item as? NSImage,
                          let asset = try? ImageImportSupport.importAsset(from: image, suggestedFileName: "dropped-image.png")
                    else {
                        return
                    }
                    state.append(asset)
                }
            }
        }

        state.group.notify(queue: .main) {
            let assets = state.assets
            if assets.isEmpty {
                warningMessage = requestedLoads == 0
                    ? "Only image files can be used as references."
                    : "Drop import failed. Use PNG, JPEG, GIF, or WebP images."
                return
            }

            appendReferenceAssets(assets)

            if assets.count < requestedLoads {
                warningMessage = "Some dropped items were skipped because they were not supported image files."
            }
        }

        return requestedLoads > 0
    }

    private func generateImages() {
        guard let request = validatedRequest() else { return }

        isGenerating = true
        errorMessage = ""
        warningMessage = ""
        latestReferenceID = ""

        Task {
            do {
                let response = try await MiniMaxAPIClient.shared.generateImage(request: request)
                let images = response.images.compactMap { NSImage(data: $0) }

                if images.isEmpty {
                    let resolvedReferenceID = await AppLogger.shared.error(
                        category: .aiimage,
                        event: "image_decode_failed",
                        referenceID: response.referenceID,
                        message: "Failed to decode generated image data.",
                        metadata: [
                            "stage": "decode_generated_images",
                            "imageCount": String(response.images.count),
                            "size": request.aspectRatio ?? "\(request.width ?? 0)x\(request.height ?? 0)",
                        ],
                        error: MiniMaxError.invalidResponse
                    )

                    await MainActor.run {
                        latestReferenceID = response.referenceID
                        generatedImages = []
                        isGenerating = false
                        errorMessage = "Image generation failed. Reference ID: \(resolvedReferenceID)"
                    }
                    return
                }

                let recordID = UUID()
                let referenceRecords = referenceImages.enumerated().map { index, item in
                    ImageReferenceRecord(
                        fileName: "\(recordID.uuidString)-ref-\(index).png",
                        mimeType: item.mimeType,
                        sizeBytes: item.sizeBytes
                    )
                }
                let outputImageFileNames = (0..<response.images.count).map {
                    "\(recordID.uuidString)-out-\($0).png"
                }
                let record = ImageHistoryRecord(
                    id: recordID,
                    createdAt: Date(),
                    prompt: request.prompt,
                    aspectRatio: request.aspectRatio,
                    width: request.width,
                    height: request.height,
                    imageCount: response.images.count,
                    seed: request.seed,
                    promptOptimizer: request.promptOptimizer,
                    model: MiniMaxSettingsStore.shared.imageModel,
                    referenceImages: referenceRecords,
                    outputImageFileNames: outputImageFileNames,
                    referenceID: response.referenceID
                )

                try? await HistoryStore.shared.save(
                    record,
                    outputImages: response.images,
                    referenceImageData: referenceImages.map(\.pngData)
                )

                await MainActor.run {
                    latestReferenceID = response.referenceID
                    generatedImages = images
                    selectedOutputIndex = 0
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = error.localizedDescription
                    warningMessage = ""
                }
            }
        }
    }

    private func validatedRequest() -> MiniMaxAPIClient.MiniMaxImageGenerationRequest? {
        let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            errorMessage = "Please describe the image you want to generate."
            return nil
        }

        if generationMode == .referenceGuided && referenceImages.isEmpty {
            errorMessage = "Reference Guided mode needs at least one staged image."
            return nil
        }

        let resolvedSeed: Int?
        let trimmedSeed = seedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSeed.isEmpty {
            resolvedSeed = nil
        } else if let seed = Int(trimmedSeed) {
            resolvedSeed = seed
        } else {
            errorMessage = "Seed must be a whole number."
            return nil
        }

        let aspectRatio: String?
        let width: Int?
        let height: Int?

        switch parameterMode {
        case .aspectRatio:
            aspectRatio = self.aspectRatio
            width = nil
            height = nil
        case .customSize:
            guard let parsedWidth = Int(customWidthText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let parsedHeight = Int(customHeightText.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                errorMessage = "Custom size requires numeric width and height."
                return nil
            }

            guard (512...2048).contains(parsedWidth), (512...2048).contains(parsedHeight) else {
                errorMessage = "Custom dimensions must stay between 512 and 2048 pixels."
                return nil
            }

            guard parsedWidth.isMultiple(of: 8), parsedHeight.isMultiple(of: 8) else {
                errorMessage = "Custom dimensions must be divisible by 8."
                return nil
            }

            aspectRatio = nil
            width = parsedWidth
            height = parsedHeight
        }

        let subjectReferences =
            generationMode == .referenceGuided
            ? referenceImages.map {
                MiniMaxAPIClient.MiniMaxSubjectReference(
                    imageBase64: $0.pngData.base64EncodedString()
                )
            }
            : []

        return MiniMaxAPIClient.MiniMaxImageGenerationRequest(
            prompt: trimmedPrompt,
            aspectRatio: aspectRatio,
            width: width,
            height: height,
            imageCount: imageCount,
            seed: resolvedSeed,
            promptOptimizer: promptOptimizer,
            subjectReferences: subjectReferences
        )
    }

    private func saveSelectedImage() {
        guard let image = selectedOutputImage else { return }
        saveSpecificImage(image, index: selectedOutputIndex)
    }

    private func saveSpecificImage(_ image: NSImage, index: Int) {
        let panel = NSSavePanel()
        panel.title = "Save Generated Image"
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "ai-image-\(index + 1).png"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            errorMessage = "Failed to encode image as PNG."
            return
        }

        do {
            try pngData.write(to: url)
            errorMessage = ""
        } catch {
            errorMessage = "Failed to save file: \(error.localizedDescription)"
        }
    }

    private func clearWorkspace() {
        promptText = ""
        generatedImages = []
        errorMessage = ""
        warningMessage = ""
        latestReferenceID = ""
        selectedOutputIndex = 0
        clearReferenceImages()
    }

    // MARK: - History

    private func loadHistory(reset: Bool) {
        Task {
            let offset = reset ? 0 : imageHistory.count
            let records = (try? await HistoryStore.shared.listImage(limit: historyPageSize, offset: offset)) ?? []
            let totalCount = (try? await HistoryStore.shared.count(category: .image)) ?? 0
            await MainActor.run {
                if reset {
                    imageHistory = records
                } else {
                    imageHistory.append(contentsOf: records)
                }
                imageHistoryHasMore = offset + records.count < totalCount
            }
        }
    }

    private func restoreImage(_ record: ImageHistoryRecord) {
        let restoreStartedAt = Date()
        let shouldApplyIncrementalUpdates = toolVisibilityContext.isVisible || !toolVisibilityContext.isPausedWhileHidden

        promptText = record.prompt
        aspectRatio = record.aspectRatio ?? "1:1"
        customWidthText = record.width.map(String.init) ?? customWidthText
        customHeightText = record.height.map(String.init) ?? customHeightText
        parameterMode = (record.width != nil && record.height != nil) ? .customSize : .aspectRatio
        imageCount = record.imageCount
        seedText = record.seed.map(String.init) ?? ""
        promptOptimizer = record.promptOptimizer
        generationMode = record.referenceImages.isEmpty ? .textOnly : .referenceGuided
        latestReferenceID = record.referenceID
        errorMessage = ""
        warningMessage = ""
        referenceImages = []
        selectedReferenceImageID = nil
        generatedImages = []
        selectedOutputIndex = 0

        Task {
            var restoredReferenceImages: [AIImageReferenceItem] = []
            var restoredOutputs: [NSImage] = []
            var missingReferenceCount = 0
            var missingOutputCount = 0
            var didReportFirstPreview = false

            func reportFirstPreviewIfNeeded() {
                guard !didReportFirstPreview,
                      !restoredReferenceImages.isEmpty || !restoredOutputs.isEmpty
                else {
                    return
                }

                didReportFirstPreview = true
                RenderingPerformance.record(
                    .imageRestoreFirstPreviewReady,
                    toolID: .aiImage,
                    referenceID: record.referenceID,
                    durationMs: max(0, Int(Date().timeIntervalSince(restoreStartedAt) * 1000)),
                    metadata: [
                        "referenceCount": String(restoredReferenceImages.count),
                        "outputCount": String(restoredOutputs.count),
                        "incremental": String(shouldApplyIncrementalUpdates)
                    ]
                )
            }

            for referenceRecord in record.referenceImages {
                guard let data = try? await HistoryStore.shared.loadData(category: .image, fileName: referenceRecord.fileName),
                      let image = NSImage(data: data)
                else {
                    missingReferenceCount += 1
                    continue
                }

                restoredReferenceImages.append(
                    AIImageReferenceItem(
                        image: image,
                        pngData: data,
                        fileName: referenceRecord.fileName,
                        mimeType: referenceRecord.mimeType,
                        sizeBytes: referenceRecord.sizeBytes
                    )
                )

                reportFirstPreviewIfNeeded()

                if shouldApplyIncrementalUpdates {
                    let snapshot = restoredReferenceImages
                    await MainActor.run {
                        referenceImages = snapshot
                        selectedReferenceImageID = snapshot.first?.id
                    }
                }
            }

            for fileName in record.outputImageFileNames {
                if let data = try? await HistoryStore.shared.loadData(category: .image, fileName: fileName),
                   let image = NSImage(data: data) {
                    restoredOutputs.append(image)
                    reportFirstPreviewIfNeeded()

                    if shouldApplyIncrementalUpdates {
                        let snapshot = restoredOutputs
                        await MainActor.run {
                            generatedImages = snapshot
                            selectedOutputIndex = 0
                        }
                    }
                } else {
                    missingOutputCount += 1
                }
            }

            await MainActor.run {
                referenceImages = restoredReferenceImages
                selectedReferenceImageID = restoredReferenceImages.first?.id
                generatedImages = restoredOutputs
                selectedOutputIndex = 0

                let restoreWarnings = restoreWarningMessage(
                    missingReferenceCount: missingReferenceCount,
                    missingOutputCount: missingOutputCount
                )
                if let restoreWarnings {
                    warningMessage = restoreWarnings
                }
            }

            RenderingPerformance.record(
                .imageRestoreCompleted,
                toolID: .aiImage,
                referenceID: record.referenceID,
                durationMs: max(0, Int(Date().timeIntervalSince(restoreStartedAt) * 1000)),
                metadata: [
                    "referenceCount": String(restoredReferenceImages.count),
                    "outputCount": String(restoredOutputs.count),
                    "missingReferenceCount": String(missingReferenceCount),
                    "missingOutputCount": String(missingOutputCount),
                    "incremental": String(shouldApplyIncrementalUpdates)
                ]
            )
        }
    }

    private func restoreWarningMessage(
        missingReferenceCount: Int,
        missingOutputCount: Int
    ) -> String? {
        var fragments: [String] = []

        if missingReferenceCount > 0 {
            fragments.append("\(missingReferenceCount) reference image\(missingReferenceCount == 1 ? "" : "s") missing")
        }

        if missingOutputCount > 0 {
            fragments.append("\(missingOutputCount) generated image\(missingOutputCount == 1 ? "" : "s") missing")
        }

        guard !fragments.isEmpty else { return nil }
        return fragments.joined(separator: " · ") + " — prompt and parameters were restored."
    }

    private func deleteImageRecord(_ record: ImageHistoryRecord) {
        Task {
            try? await HistoryStore.shared.deleteImage(id: record.id)
            let records = (try? await HistoryStore.shared.listImage(limit: historyPageSize, offset: 0)) ?? []
            let totalCount = (try? await HistoryStore.shared.count(category: .image)) ?? 0
            await MainActor.run {
                imageHistory = records
                imageHistoryHasMore = records.count < totalCount
            }
        }
    }

    private func clearImageHistory() {
        Task {
            try? await HistoryStore.shared.clear(category: .image)
            await MainActor.run {
                imageHistory = []
                imageHistoryHasMore = false
            }
        }
    }
}

private final class DropImportState: @unchecked Sendable {
    let group = DispatchGroup()
    private let lock = NSLock()
    private var storage: [ImportedImageAsset] = []

    func append(_ asset: ImportedImageAsset) {
        lock.lock()
        storage.append(asset)
        lock.unlock()
    }

    var assets: [ImportedImageAsset] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private struct ReferencePromptEditor: View {
    @Binding var text: String
    let placeholder: String
    let onPasteAssets: ([ImportedImageAsset]) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ReferencePromptTextView(
                text: $text,
                onPasteAssets: onPasteAssets
            )
            .padding(AppTheme.Spacing.md)

            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: AppTheme.Typography.textInput, weight: .medium))
                    .foregroundStyle(AppTheme.textMuted)
                    .padding(AppTheme.Spacing.md)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
        }
        .background(AppTheme.background.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
    }
}

private struct ReferencePromptTextView: NSViewRepresentable {
    @Binding var text: String
    let onPasteAssets: ([ImportedImageAsset]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = PromptNSTextView()
        textView.promptDelegate = context.coordinator
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: AppTheme.Typography.textInput, weight: .medium)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.textContainer?.widthTracksTextView = true
        CodeToolTextInputConfiguration.configure(textView)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PromptNSTextView else { return }
        context.coordinator.parent = self
        if textView.string != text, !textView.hasMarkedText() {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, PromptNSTextViewDelegate {
        var parent: ReferencePromptTextView
        weak var textView: NSTextView?

        init(_ parent: ReferencePromptTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = (notification.object as? NSTextView) ?? textView else { return }
            guard !textView.hasMarkedText() else { return }
            parent.text = textView.string
        }

        func promptTextViewDidPaste(_ assets: [ImportedImageAsset]) {
            parent.onPasteAssets(assets)
        }
    }
}

private protocol PromptNSTextViewDelegate: AnyObject {
    func promptTextViewDidPaste(_ assets: [ImportedImageAsset])
}

private final class PromptNSTextView: NSTextView {
    weak var promptDelegate: PromptNSTextViewDelegate?

    override func paste(_ sender: Any?) {
        let assets = ImageImportSupport.importAssets()
        if !assets.isEmpty {
            promptDelegate?.promptTextViewDidPaste(assets)
            return
        }

        super.paste(sender)
    }
}

// MARK: - Preview

#if DEBUG
    struct AIImageView_Previews: PreviewProvider {
        static var previews: some View {
            AIImageView()
                .frame(width: 1320, height: 760)
        }
    }
#endif
