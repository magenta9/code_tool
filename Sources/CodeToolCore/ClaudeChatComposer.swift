import AppKit
import SwiftUI

/// A chat composer backed by NSTextView for precise key event handling.
///
/// Supports:
/// - `Enter` to send
/// - `Shift+Enter` to insert newline
/// - `Cmd+V` to paste images (falls back to text paste)
/// - `Esc` callback
public struct ClaudeChatComposer: NSViewRepresentable {
    @Binding var text: String
    let isStreaming: Bool
    let onSubmit: () -> Void
    let onPasteImages: ([NSImage]) -> Void
    let onEscape: () -> Void

    static func configureTextView(_ textView: ComposerTextView, coordinator: Coordinator) {
        textView.composerDelegate = coordinator
        textView.delegate = coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.textContainer?.widthTracksTextView = true
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = ComposerTextView()
        Self.configureTextView(textView, coordinator: context.coordinator)

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposerTextView else { return }

        context.coordinator.isUpdating = true
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.isUpdating = false
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, NSTextViewDelegate, ComposerTextViewDelegate {
        var parent: ClaudeChatComposer
        weak var textView: NSTextView?
        var isUpdating = false

        init(_ parent: ClaudeChatComposer) {
            self.parent = parent
        }

        public func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView else { return }
            parent.text = textView.string
        }

        // MARK: - ComposerTextViewDelegate

        func composerDidPressEnter() {
            parent.onSubmit()
        }

        func composerDidPressEscape() {
            parent.onEscape()
        }

        func composerDidPasteImages(_ images: [NSImage]) {
            parent.onPasteImages(images)
        }
    }
}

// MARK: - ComposerTextViewDelegate Protocol

protocol ComposerTextViewDelegate: AnyObject {
    func composerDidPressEnter()
    func composerDidPressEscape()
    func composerDidPasteImages(_ images: [NSImage])
}

// MARK: - ComposerTextView

final class ComposerTextView: NSTextView {
    weak var composerDelegate: ComposerTextViewDelegate?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Enter (without Shift) → send
        if event.keyCode == 36 && !flags.contains(.shift) {
            composerDelegate?.composerDidPressEnter()
            return
        }

        // Shift+Enter → insert newline (default behavior)
        if event.keyCode == 36 && flags.contains(.shift) {
            super.keyDown(with: event)
            return
        }

        // Escape → callback
        if event.keyCode == 53 {
            composerDelegate?.composerDidPressEscape()
            return
        }

        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        // Check for images first
        let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]
        if pasteboard.canReadItem(withDataConformingToTypes: imageTypes.map(\.rawValue)) {
            var images: [NSImage] = []

            if let tiffData = pasteboard.data(forType: .tiff),
               let image = NSImage(data: tiffData) {
                images.append(image)
            } else if let pngData = pasteboard.data(forType: .png),
                      let image = NSImage(data: pngData) {
                images.append(image)
            }

            // Also check for file URLs pointing to images
            if images.isEmpty,
               let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
                   .urlReadingContentsConformToTypes: ["public.image"]
               ]) as? [URL] {
                for url in urls {
                    if let image = NSImage(contentsOf: url) {
                        images.append(image)
                    }
                }
            }

            if !images.isEmpty {
                composerDelegate?.composerDidPasteImages(images)
                return
            }
        }

        // Fallback to default text paste
        super.paste(sender)
    }
}
