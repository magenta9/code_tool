import AppKit
import CodeToolUI
import SwiftUI
import UniformTypeIdentifiers

public struct ImageConverterView: View {
    enum Mode: String, CaseIterable {
        case imageToBase64 = "Image → Base64"
        case base64ToImage = "Base64 → Image"
    }

    @State private var selectedMode: Mode = .imageToBase64
    @State private var base64Text = ""
    @State private var selectedImage: NSImage?
    @State private var imageInfo = ""
    @State private var errorMessage = ""
    @State private var sourceFilePath: String?
    @State private var showHistory = false
    @State private var converterHistory: [ImageConverterHistoryRecord] = []

    public init() {}

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Asset transport",
            title: "Image Converter",
            description:
                "Move between image files and Base64 strings with the same split workbench used across the app.",
            systemImage: "photo",
            statusItems: statusItems
        ) {
            StyledSegmentedPicker(
                options: Mode.allCases,
                selection: $selectedMode,
                label: { $0.rawValue }
            )
            if selectedImage != nil || !base64Text.isEmpty {
                StyledButton("Clear", systemImage: "trash", variant: .ghost) {
                    clearState()
                }
            }
            StyledButton("History", systemImage: "clock.arrow.circlepath", variant: .secondary) {
                loadHistory()
                showHistory = true
            }
        } content: {
            HSplitView {
                switch selectedMode {
                case .imageToBase64:
                    imageToBase64View
                case .base64ToImage:
                    base64ToImageView
                }
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
        .preferredColorScheme(.dark)
        .onChange(of: selectedMode) { clearState() }
        .overlay {
            if showHistory {
                HistoryDrawer(
                    isPresented: $showHistory,
                    title: "Image Converter History",
                    items: converterHistory,
                    onSelect: { record in restoreConverter(record) },
                    onDelete: { record in deleteConverterRecord(record) },
                    onClearAll: { clearConverterHistory() }
                )
            }
        }
    }

    private var statusItems: [ToolStatusItem] {
        var items = [
            ToolStatusItem(
                title: selectedMode.rawValue, systemImage: "arrow.left.arrow.right",
                tint: AppTheme.accentWarm)
        ]
        if selectedImage != nil {
            items.append(
                ToolStatusItem(
                    title: "Image ready", systemImage: "photo.fill", tint: AppTheme.accent))
        }
        if !errorMessage.isEmpty {
            items.append(
                ToolStatusItem(
                    title: "Action required", systemImage: "exclamationmark.triangle.fill",
                    tint: AppTheme.error))
        }
        return items
    }

    // MARK: - Image to Base64

    private var imageToBase64View: some View {
        HSplitView {
            StyledPanel(title: "Preview") {
                VStack(spacing: AppTheme.Spacing.md) {
                    imagePreviewArea
                    HStack(spacing: AppTheme.Spacing.sm) {
                        StyledButton(
                            "Select Image…", systemImage: "photo.badge.plus", variant: .primary
                        ) {
                            openImageFile()
                        }
                        if selectedImage != nil {
                            StyledButton("Clear", systemImage: "xmark", variant: .ghost) {
                                clearState()
                            }
                        }
                    }
                    if !imageInfo.isEmpty {
                        infoLabel
                    }
                }
            }
            .frame(minWidth: 300)

            StyledPanel(title: "Base64 Output") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack {
                        Text("Encoded string")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        if !base64Text.isEmpty {
                            Text("\(base64Text.count) chars")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(AppTheme.textMuted)
                            CopyButton("Copy", text: base64Text)
                        }
                    }
                    StyledTextEditor(
                        text: $base64Text, placeholder: "Base64 output will appear here",
                        isEditable: false)
                    if !errorMessage.isEmpty {
                        errorBanner
                    } else {
                        ToolMessageBanner(
                            systemImage: "text.below.photo",
                            message:
                                "Imported image bytes are encoded directly so the output stays lossless.",
                            tint: AppTheme.accent)
                    }
                }
            }
            .frame(minWidth: 360)
        }
    }

    // MARK: - Base64 to Image

    private var base64ToImageView: some View {
        HSplitView {
            StyledPanel(title: "Base64 Input") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    StyledTextEditor(
                        text: $base64Text, placeholder: "Paste Base64 string here", isEditable: true
                    )
                    HStack(spacing: AppTheme.Spacing.sm) {
                        StyledButton("Decode Image", systemImage: "photo", variant: .primary) {
                            decodeBase64ToImage()
                        }
                        .disabled(
                            base64Text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if !base64Text.isEmpty {
                            StyledButton("Clear", systemImage: "xmark", variant: .ghost) {
                                clearState()
                            }
                        }
                    }
                    if !errorMessage.isEmpty {
                        errorBanner
                    } else {
                        ToolMessageBanner(
                            systemImage: "sparkles",
                            message:
                                "Data URLs are supported. Any data URI prefix is stripped before decode.",
                            tint: AppTheme.accentWarm)
                    }
                }
            }
            .frame(minWidth: 360)

            StyledPanel(title: "Decoded Preview") {
                VStack(spacing: AppTheme.Spacing.md) {
                    imagePreviewArea
                    if selectedImage != nil {
                        StyledButton(
                            "Save Image…", systemImage: "square.and.arrow.down", variant: .secondary
                        ) {
                            saveImageToFile()
                        }
                    }
                    if !imageInfo.isEmpty {
                        infoLabel
                    }
                }
            }
            .frame(minWidth: 300)
        }
    }

    // MARK: - Shared Components

    private var imagePreviewArea: some View {
        Group {
            if let image = selectedImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(checkerboardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .strokeBorder(AppTheme.border)
                    )
            } else {
                VStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .overlay(
                            AppTheme.accentGradient.mask(
                                Image(systemName: "photo")
                                    .resizable()
                                    .scaledToFit()
                            ))
                    Text("No image loaded")
                        .font(.callout)
                        .foregroundStyle(AppTheme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .strokeBorder(
                            AppTheme.accent.opacity(0.3),
                            style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
                )
            }
        }
    }

    private var checkerboardBackground: some View {
        Canvas { context, size in
            let tileSize: CGFloat = 10
            for row in 0..<Int(size.height / tileSize) + 1 {
                for col in 0..<Int(size.width / tileSize) + 1 {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * tileSize,
                        y: CGFloat(row) * tileSize,
                        width: tileSize, height: tileSize)
                    context.fill(
                        Path(rect),
                        with: .color(
                            isLight ? Color.white.opacity(0.08) : Color.white.opacity(0.03)))
                }
            }
        }
    }

    private var infoLabel: some View {
        Text(imageInfo)
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.sm)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )
    }

    private var errorBanner: some View {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(AppTheme.error)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.sm)
            .background(AppTheme.error.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .strokeBorder(AppTheme.error.opacity(0.3), lineWidth: 1)
            )
    }

    // MARK: - Actions

    private func openImageFile() {
        let panel = NSOpenPanel()
        panel.title = "Select an Image"
        panel.allowedContentTypes = supportedImageTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            guard let image = NSImage(data: data) else {
                errorMessage = "Unable to load image from the selected file."
                return
            }
            errorMessage = ""
            selectedImage = image
            sourceFilePath = url.path
            base64Text = data.base64EncodedString()
            imageInfo = buildImageInfo(image: image, data: data, url: url)
            saveConverterHistory(mode: "imageToBase64", imageData: data)
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
        }
    }

    private func decodeBase64ToImage() {
        errorMessage = ""
        selectedImage = nil
        imageInfo = ""

        let cleaned =
            base64Text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: "data:image/[^;]+;base64,",
                with: "",
                options: .regularExpression)

        guard !cleaned.isEmpty else {
            errorMessage = "Base64 input is empty."
            return
        }

        guard let data = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters) else {
            errorMessage = "Invalid Base64 string. Please check the input."
            return
        }

        guard let image = NSImage(data: data) else {
            errorMessage = "Decoded data is not a supported image format (PNG, JPEG, GIF, WebP)."
            return
        }

        selectedImage = image
        imageInfo = buildImageInfo(image: image, data: data, url: nil)
        saveConverterHistory(mode: "base64ToImage", imageData: data)
    }

    private func saveImageToFile() {
        guard let image = selectedImage else { return }

        let panel = NSSavePanel()
        panel.title = "Save Image"
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "image.png"
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

    private func clearState() {
        base64Text = ""
        selectedImage = nil
        imageInfo = ""
        errorMessage = ""
        sourceFilePath = nil
    }

    // MARK: - Helpers

    private func buildImageInfo(image: NSImage, data: Data, url: URL?) -> String {
        var parts: [String] = []

        let pixelSize =
            image.representations.first.map {
                "\($0.pixelsWide) × \($0.pixelsHigh) px"
            } ?? "\(Int(image.size.width)) × \(Int(image.size.height)) pt"
        parts.append("Dimensions: \(pixelSize)")

        parts.append(
            "Size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
        )

        if let format = detectFormat(data: data) {
            parts.append("Format: \(format)")
        }

        if let path = url?.lastPathComponent {
            parts.append("File: \(path)")
        }

        return parts.joined(separator: "  •  ")
    }

    private func detectFormat(data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        let header = [UInt8](data.prefix(4))

        if header.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "PNG" }
        if header.starts(with: [0xFF, 0xD8, 0xFF]) { return "JPEG" }
        if header.starts(with: [0x47, 0x49, 0x46]) { return "GIF" }
        if header.starts(with: [0x52, 0x49, 0x46, 0x46]),
            data.count >= 12,
            [UInt8](data[8..<12]) == [0x57, 0x45, 0x42, 0x50]
        {
            return "WebP"
        }

        return nil
    }

    private var supportedImageTypes: [UTType] {
        [.png, .jpeg, .gif, .webP]
    }

    // MARK: - History

    private func saveConverterHistory(mode: String, imageData: Data?) {
        let recordID = UUID()
        let imageFileName: String? = imageData != nil ? "\(recordID.uuidString)-image.png" : nil
        let record = ImageConverterHistoryRecord(
            id: recordID,
            createdAt: Date(),
            mode: mode,
            base64Text: mode == "base64ToImage" ? base64Text : "",
            base64Preview: String(base64Text.prefix(500)),
            imageInfo: imageInfo,
            imageFileName: imageFileName
        )
        Task { try? await HistoryStore.shared.save(record, imageData: imageData) }
    }

    private func loadHistory() {
        Task {
            let records = (try? await HistoryStore.shared.listImageConverter()) ?? []
            await MainActor.run { converterHistory = records }
        }
    }

    private func restoreConverter(_ record: ImageConverterHistoryRecord) {
        let mode: Mode = record.mode == "imageToBase64" ? .imageToBase64 : .base64ToImage
        selectedMode = mode
        base64Text = record.base64Text
        imageInfo = record.imageInfo
        errorMessage = ""

        if let imageFileName = record.imageFileName {
            Task {
                if let data = try? await HistoryStore.shared.loadData(category: .imageConverter, fileName: imageFileName),
                   let image = NSImage(data: data) {
                    await MainActor.run { selectedImage = image }
                } else {
                    await MainActor.run {
                        selectedImage = nil
                        if record.base64Text.isEmpty {
                            errorMessage = "Image file missing — parameters restored."
                        }
                    }
                }
            }
        } else {
            selectedImage = nil
        }
    }

    private func deleteConverterRecord(_ record: ImageConverterHistoryRecord) {
        Task {
            try? await HistoryStore.shared.deleteImageConverter(id: record.id)
            let records = (try? await HistoryStore.shared.listImageConverter()) ?? []
            await MainActor.run { converterHistory = records }
        }
    }

    private func clearConverterHistory() {
        Task {
            try? await HistoryStore.shared.clear(category: .imageConverter)
            await MainActor.run { converterHistory = [] }
        }
    }
}

// MARK: - Previews

#if DEBUG
    struct ImageConverterView_Previews: PreviewProvider {
        static var previews: some View {
            ImageConverterView()
                .frame(width: 800, height: 500)
        }
    }
#endif
