import AppKit
import CodeToolUI
import SwiftUI

@MainActor
private enum ClaudeAttachmentThumbnailCache {
    static let images = NSCache<NSString, NSImage>()
}

struct ClaudeAttachmentThumbnailView: View {
    let attachment: ClaudeChatAttachmentRecord
    let displayName: String

    @State private var image: NSImage?
    @State private var didAttemptLoad = false

    var body: some View {
        Group {
            if let image {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 86, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))

                    Text(displayName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(AppTheme.surface.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                )
            } else {
                HStack(spacing: 4) {
                    Image(systemName: didAttemptLoad ? "photo" : "hourglass")
                        .font(.system(size: 10))
                    Text(displayName)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(AppTheme.textMuted)
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, AppTheme.Spacing.xs)
                .background(
                    Capsule().fill(AppTheme.surface)
                )
            }
        }
        .task(id: attachment.fileName) {
            await loadThumbnail()
        }
    }

    @MainActor
    private func loadThumbnail() async {
        if let cached = ClaudeAttachmentThumbnailCache.images.object(forKey: attachment.fileName as NSString) {
            image = cached
            didAttemptLoad = true
            return
        }

        guard let url = try? HistoryStore.syncClaudeChatAttachmentURL(fileName: attachment.fileName) else {
            didAttemptLoad = true
            return
        }

        let data = await Task.detached(priority: .utility) {
            try? Data(contentsOf: url)
        }.value

        guard let data, let decodedImage = NSImage(data: data) else {
            didAttemptLoad = true
            return
        }

        ClaudeAttachmentThumbnailCache.images.setObject(decodedImage, forKey: attachment.fileName as NSString)
        image = decodedImage
        didAttemptLoad = true
    }
}