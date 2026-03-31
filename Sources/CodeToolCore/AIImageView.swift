import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct AIImageView: View {
    private var settings = MiniMaxSettingsStore.shared

    @State private var promptText: String = ""
    @State private var isGenerating: Bool = false
    @State private var generatedImages: [NSImage] = []
    @State private var errorMessage: String = ""
    @State private var aspectRatio: String = "1:1"
    @State private var imageCount: Int = 1
    @State private var latestReferenceID: String = ""

    private let aspectRatios = ["1:1", "16:9", "9:16", "4:3", "3:4"]

    public init() {}

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Image Generation",
            title: "AI Image",
            description: "Generate images from text prompts using the MiniMax image-01 model.",
            systemImage: "photo.artframe",
            statusItems: statusItems
        ) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Menu {
                    ForEach(aspectRatios, id: \.self) { ratio in
                        Button {
                            aspectRatio = ratio
                        } label: {
                            HStack {
                                Text(ratio)
                                if ratio == aspectRatio {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "aspectratio")
                            .font(.caption)
                        Text(aspectRatio)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(AppTheme.surfaceRaised)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(AppTheme.border))
                }
                .menuStyle(.borderlessButton)
                .foregroundStyle(AppTheme.textSecondary)

                Menu {
                    ForEach(1...4, id: \.self) { count in
                        Button {
                            imageCount = count
                        } label: {
                            HStack {
                                Text("\(count) image\(count > 1 ? "s" : "")")
                                if count == imageCount {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "square.grid.2x2")
                            .font(.caption)
                        Text("×\(imageCount)")
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(AppTheme.surfaceRaised)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(AppTheme.border))
                }
                .menuStyle(.borderlessButton)
                .foregroundStyle(AppTheme.textSecondary)

                StyledButton("Generate", systemImage: "sparkles", variant: .primary) {
                    generateImages()
                }
                .disabled(
                    promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isGenerating || !settings.isConfigured)

                StyledButton("Save Image", systemImage: "square.and.arrow.down") {
                    saveImage()
                }
                .disabled(generatedImages.isEmpty)

                StyledButton("Clear", systemImage: "trash", variant: .ghost) {
                    clearAll()
                }
                .disabled(promptText.isEmpty && generatedImages.isEmpty && errorMessage.isEmpty)
            }
        } content: {
            VStack(spacing: 0) {
                if !settings.isConfigured {
                    ToolMessageBanner(
                        systemImage: "exclamationmark.triangle.fill",
                        message:
                            "MiniMax API key not configured. Go to Settings to add your API key.",
                        tint: AppTheme.warning
                    )
                }

                if !errorMessage.isEmpty {
                    ToolMessageBanner(
                        systemImage: "exclamationmark.triangle.fill",
                        message: errorMessage,
                        tint: AppTheme.error
                    )
                }

                HSplitView {
                    promptPanel
                        .frame(minWidth: 280)

                    imagePanel
                        .frame(minWidth: 320)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
    }

    // MARK: - Status Items

    private var statusItems: [ToolStatusItem] {
        var items: [ToolStatusItem] = []

        items.append(
            ToolStatusItem(
                title: aspectRatio,
                systemImage: "aspectratio",
                tint: AppTheme.accentWarm
            ))

        if imageCount > 1 {
            items.append(
                ToolStatusItem(
                    title: "\(imageCount) images",
                    systemImage: "square.grid.2x2",
                    tint: AppTheme.accent
                ))
        }

        if isGenerating {
            items.append(
                ToolStatusItem(
                    title: "Generating…",
                    systemImage: "hourglass",
                    tint: AppTheme.accent
                ))
        } else if !generatedImages.isEmpty {
            items.append(
                ToolStatusItem(
                    title: "\(generatedImages.count) generated",
                    systemImage: "checkmark.circle.fill",
                    tint: AppTheme.success
                ))
        }

        if !errorMessage.isEmpty {
            items.append(
                ToolStatusItem(
                    title: "Error",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: AppTheme.error
                ))
        }

        return items
    }

    // MARK: - Panels

    private var promptPanel: some View {
        StyledPanel(title: "Prompt") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                StyledTextEditor(
                    text: $promptText,
                    placeholder: "Describe the image you want to generate…"
                )

                HStack {
                    Text("Model: \(settings.imageModel)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textMuted)

                    Spacer()

                    Text("\(promptText.count) chars")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textMuted)
                }
            }
        }
    }

    private var imagePanel: some View {
        StyledPanel(title: "Output") {
            if isGenerating {
                generatingPlaceholder
            } else if generatedImages.isEmpty {
                emptyState
            } else if generatedImages.count == 1, let image = generatedImages.first {
                singleImageView(image)
            } else {
                imageGrid
            }
        }
    }

    // MARK: - Image Display

    private var generatingPlaceholder: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(AppTheme.accent)
            Text("Generating image…")
                .font(.callout)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .strokeBorder(AppTheme.accent.opacity(0.3))
        )
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "photo.artframe")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .overlay(
                    AppTheme.accentGradient.mask(
                        Image(systemName: "photo.artframe")
                            .resizable()
                            .scaledToFit()
                    )
                )
            Text("No images generated yet")
                .font(.callout)
                .foregroundStyle(AppTheme.textMuted)
            Text("Enter a prompt and click Generate")
                .font(.caption)
                .foregroundStyle(AppTheme.textMuted.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .strokeBorder(
                    AppTheme.accent.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 3])
                )
        )
    }

    private func singleImageView(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .strokeBorder(AppTheme.border)
            )
    }

    private var imageGrid: some View {
        let columns =
            generatedImages.count <= 2
            ? Array(
                repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.sm),
                count: generatedImages.count)
            : Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.sm), count: 2)

        return ScrollView {
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.sm) {
                ForEach(Array(generatedImages.enumerated()), id: \.offset) { index, image in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .strokeBorder(AppTheme.border)
                        )
                        .contextMenu {
                            Button("Save This Image…") {
                                saveSpecificImage(image, index: index)
                            }
                        }
                }
            }
        }
    }

    // MARK: - Actions

    private func generateImages() {
        guard !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isGenerating = true
        errorMessage = ""
        latestReferenceID = ""

        Task {
            do {
                let response = try await MiniMaxAPIClient.shared.generateImage(
                    prompt: promptText.trimmingCharacters(in: .whitespacesAndNewlines),
                    aspectRatio: aspectRatio,
                    n: imageCount
                )

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
                            "aspectRatio": aspectRatio,
                        ],
                        error: MiniMaxError.invalidResponse
                    )

                    await MainActor.run {
                        latestReferenceID = response.referenceID
                        generatedImages = []
                        isGenerating = false
                        errorMessage =
                            "Image generation failed. Reference ID: \(resolvedReferenceID)"
                    }
                    return
                }

                await MainActor.run {
                    latestReferenceID = response.referenceID
                    generatedImages = images
                    isGenerating = false
                }

                let recordID = UUID()
                let imageFileNames = (0..<response.images.count).map {
                    "\(recordID.uuidString)_\($0).png"
                }
                let record = ImageHistoryRecord(
                    id: recordID,
                    createdAt: Date(),
                    prompt: promptText,
                    aspectRatio: aspectRatio,
                    imageCount: response.images.count,
                    model: MiniMaxSettingsStore.shared.imageModel,
                    imageFileNames: imageFileNames,
                    referenceID: response.referenceID
                )
                try? await HistoryStore.shared.save(record, images: response.images)
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func saveImage() {
        guard let image = generatedImages.first else { return }
        saveSpecificImage(image, index: 0)
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

    private func clearAll() {
        promptText = ""
        generatedImages = []
        errorMessage = ""
        latestReferenceID = ""
    }
}

// MARK: - Preview

#if DEBUG
    struct AIImageView_Previews: PreviewProvider {
        static var previews: some View {
            AIImageView()
                .frame(width: 900, height: 600)
        }
    }
#endif
