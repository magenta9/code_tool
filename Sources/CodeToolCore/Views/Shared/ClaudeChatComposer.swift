import AppKit
import SwiftUI

/// A chat composer backed by NSTextView for precise key event handling.
///
/// Supports:
/// - `Enter` to send
/// - `Shift+Enter` to insert newline
/// - `Cmd+V` to paste images from the clipboard (falls back to text paste)
/// - `Esc` callback
public struct ClaudeChatComposer: NSViewRepresentable {
    @Binding var text: String
    let isStreaming: Bool
    let onSubmit: () -> Void
    let onPasteImages: ([NSImage]) -> Void
    let onEscape: () -> Void
    let onVisibleTextChange: (Bool) -> Void

    init(
        text: Binding<String>,
        isStreaming: Bool,
        onSubmit: @escaping () -> Void,
        onPasteImages: @escaping ([NSImage]) -> Void,
        onEscape: @escaping () -> Void,
        onVisibleTextChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self._text = text
        self.isStreaming = isStreaming
        self.onSubmit = onSubmit
        self.onPasteImages = onPasteImages
        self.onEscape = onEscape
        self.onVisibleTextChange = onVisibleTextChange
    }

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
        context.coordinator.updateVisibleTextState(for: textView)

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposerTextView else { return }
        let hasMarkedText = textView.hasMarkedText()

        context.coordinator.parent = self
        context.coordinator.isUpdating = true
        if textView.string != text && !hasMarkedText {
            textView.string = text
        }
        if !hasMarkedText {
            context.coordinator.lastCommittedText = textView.string
        }
        context.coordinator.isUpdating = false
        context.coordinator.updateVisibleTextState(for: textView)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, NSTextViewDelegate, ComposerTextViewDelegate {
        var parent: ClaudeChatComposer
        weak var textView: NSTextView?
        var isUpdating = false
        var lastCommittedText: String
        var lastReportedHasVisibleText: Bool?

        init(_ parent: ClaudeChatComposer) {
            self.parent = parent
            self.lastCommittedText = parent.text
        }

        public func textDidChange(_ notification: Notification) {
            guard !isUpdating else { return }
            guard let textView = (notification.object as? NSTextView) ?? textView else { return }
            updateVisibleTextState(for: textView)
            guard !textView.hasMarkedText() else { return }

            let committedText = textView.string
            guard committedText != lastCommittedText else { return }

            lastCommittedText = committedText
            parent.text = committedText
        }

        func updateVisibleTextState(for textView: NSTextView) {
            let hasVisibleText = !textView.string.isEmpty
            guard hasVisibleText != lastReportedHasVisibleText else { return }
            lastReportedHasVisibleText = hasVisibleText
            parent.onVisibleTextChange(hasVisibleText)
        }

        public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }

            if commandSelector == #selector(NSText.insertNewline(_:))
                || commandSelector == #selector(NSText.insertNewlineIgnoringFieldEditor(_:))
            {
                parent.onSubmit()
                return true
            }

            return false
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
        // During IME composition (marked text), let the input method handle all keys
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if isSubmitKeyEvent(event) {
            if flags.contains(.shift) {
                insertText("\n", replacementRange: selectedRange())
            } else {
                composerDelegate?.composerDidPressEnter()
            }
            return
        }

        // Escape → callback
        if event.keyCode == 53 {
            composerDelegate?.composerDidPressEscape()
            return
        }

        super.keyDown(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        if hasMarkedText() {
            super.insertNewline(sender)
            return
        }

        composerDelegate?.composerDidPressEnter()
    }

    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        if hasMarkedText() {
            super.insertNewlineIgnoringFieldEditor(sender)
            return
        }

        composerDelegate?.composerDidPressEnter()
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

    private func isSubmitKeyEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == 36 || event.keyCode == 76 {
            return true
        }

        guard let characters = event.charactersIgnoringModifiers else { return false }
        return characters == "\r" || characters == "\u{3}"
    }
}
