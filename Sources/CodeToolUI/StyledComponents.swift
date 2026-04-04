import SwiftUI

#if canImport(AppKit)
    import AppKit

    // A plain NSTextView wrapper that disables macOS smart-quote / smart-dash substitution.
    private struct PlainNSTextEditor: NSViewRepresentable {
        @Binding var text: String

        func makeCoordinator() -> Coordinator { Coordinator(self) }

        func makeNSView(context: Context) -> NSScrollView {
            let scrollView = NSTextView.scrollableTextView()
            guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isRichText = false
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.textContainer?.widthTracksTextView = true
            textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            textView.textColor = NSColor.labelColor
            textView.backgroundColor = .clear
            textView.drawsBackground = false
            textView.delegate = context.coordinator
            return scrollView
        }

        func updateNSView(_ nsView: NSScrollView, context: Context) {
            guard let textView = nsView.documentView as? NSTextView else { return }
            if textView.string != text {
                textView.string = text
            }
        }

        class Coordinator: NSObject, NSTextViewDelegate {
            var parent: PlainNSTextEditor
            init(_ parent: PlainNSTextEditor) { self.parent = parent }
            func textDidChange(_ notification: Notification) {
                guard let tv = notification.object as? NSTextView else { return }
                parent.text = tv.string
            }
        }
    }
#endif

public struct StyledToolbar<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            content
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
    }
}

public enum StyledButtonVariant {
    case primary
    case secondary
    case ghost
    case destructive
}

public struct StyledButton: View {
    let title: String
    let systemImage: String?
    let variant: StyledButtonVariant
    let action: () -> Void

    @State private var isHovered = false

    public init(
        _ title: String, systemImage: String? = nil, variant: StyledButtonVariant = .secondary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.variant = variant
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.xs + 2) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm + 1)
            .foregroundStyle(foregroundColor)
            .background(backgroundView)
            .clipShape(Capsule())
            .overlay(overlayView)
            .shadow(color: shadowColor, radius: isHovered ? 18 : 10, y: 8)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .onHover { hovering in withAnimation(AppTheme.Anim.fast) { isHovered = hovering } }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary:
            return AppTheme.background
        case .secondary:
            return AppTheme.textPrimary
        case .ghost:
            return AppTheme.textSecondary
        case .destructive:
            return AppTheme.error
        }
    }

    private var shadowColor: Color {
        switch variant {
        case .primary:
            return AppTheme.accent.opacity(0.18)
        case .destructive:
            return AppTheme.error.opacity(0.10)
        case .secondary, .ghost:
            return .clear
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch variant {
        case .primary:
            AppTheme.accentGradient.opacity(isHovered ? 1.0 : 0.92)
        case .secondary:
            AppTheme.surfaceRaised.opacity(isHovered ? 1.0 : 0.82)
        case .ghost:
            Color.white.opacity(isHovered ? 0.08 : 0.03)
        case .destructive:
            AppTheme.error.opacity(isHovered ? 0.16 : 0.10)
        }
    }

    @ViewBuilder
    private var overlayView: some View {
        switch variant {
        case .primary:
            Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        case .secondary, .ghost:
            Capsule().strokeBorder(AppTheme.border, lineWidth: 1)
        case .destructive:
            Capsule().strokeBorder(AppTheme.error.opacity(0.24), lineWidth: 1)
        }
    }
}

public struct StyledIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    public init(_ systemImage: String, help: String = "", action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 30, height: 30)
                .background(AppTheme.surfaceRaised.opacity(isHovered ? 0.95 : 0.72))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(AppTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in withAnimation(AppTheme.Anim.fast) { isHovered = hovering } }
    }
}

public struct CopyButton: View {
    let text: String
    let label: String

    @State private var showCheck = false

    public init(_ label: String = "Copy", text: String) {
        self.label = label
        self.text = text
    }

    public var body: some View {
        Button {
            #if canImport(AppKit)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            #endif
            showCheck = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                showCheck = false
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: showCheck ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(showCheck ? AppTheme.success : AppTheme.textSecondary)
                if !label.isEmpty {
                    Text(showCheck ? "Copied" : label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(showCheck ? AppTheme.success : AppTheme.textSecondary)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.sm + 2)
            .padding(.vertical, AppTheme.Spacing.xs + 2)
            .background(AppTheme.surfaceRaised.opacity(0.72))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(AppTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(AppTheme.Anim.fast, value: showCheck)
    }
}

// MARK: - Hover Copy Overlay

public struct HoverCopyOverlay: ViewModifier {
    let text: String

    @State private var isHovered = false

    public func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if isHovered
                    && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    CopyButton("", text: text)
                        .padding(AppTheme.Spacing.xs)
                        .transition(
                            .opacity.combined(
                                with: .scale(scale: 0.9, anchor: .bottomTrailing)))
                }
            }
            .onHover { isHovered = $0 }
            .animation(AppTheme.Anim.fast, value: isHovered)
    }
}

extension View {
    public func hoverCopy(text: String) -> some View {
        modifier(HoverCopyOverlay(text: text))
    }
}

public struct StyledPanel<Content: View>: View {
    let title: String?
    let content: Content

    public init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
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
            content
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.cardGradient.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 18, y: 10)
    }
}

public struct StyledTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let isEditable: Bool

    public init(text: Binding<String>, placeholder: String = "", isEditable: Bool = true) {
        self._text = text
        self.placeholder = placeholder
        self.isEditable = isEditable
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if isEditable {
                #if canImport(AppKit)
                PlainNSTextEditor(text: $text)
                    .padding(AppTheme.Spacing.md)
                #else
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(AppTheme.Spacing.md)
                #endif
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(AppTheme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.Spacing.md)
                }
            }

            if text.isEmpty && !placeholder.isEmpty {
                Text(placeholder)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(AppTheme.textMuted)
                    .padding(AppTheme.Spacing.md)
                    .padding(.leading, isEditable ? 4 : 0)
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

public struct StyledStatusBar<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            content
            Spacer()
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface.opacity(0.76))
        .overlay(alignment: .top) {
            AppTheme.border.frame(height: 1)
        }
    }
}

public struct StyledSectionHeader: View {
    let title: String
    let systemImage: String?

    public init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accentWarm)
            }
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }
}

public struct GradientBadge: View {
    let text: String
    let color: Color

    public init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .textCase(.uppercase)
            .tracking(0.7)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xxs + 2)
            .foregroundStyle(.white)
            .background(color.gradient)
            .clipShape(Capsule())
    }
}

public struct StyledDivider: View {
    let vertical: Bool

    public init(vertical: Bool = false) {
        self.vertical = vertical
    }

    public var body: some View {
        if vertical {
            AppTheme.border.frame(width: 1).padding(.vertical, AppTheme.Spacing.xs)
        } else {
            AppTheme.border.frame(height: 1)
        }
    }
}

public struct StyledSegmentedPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    @Namespace private var pickerNamespace

    public init(options: [T], selection: Binding<T>, label: @escaping (T) -> String) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(AppTheme.Anim.normal) {
                        selection = option
                    }
                } label: {
                    Text(label(option))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            selection == option ? AppTheme.background : AppTheme.textMuted
                        )
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .background {
                            if selection == option {
                                Capsule()
                                    .fill(AppTheme.accentGradient)
                                    .matchedGeometryEffect(
                                        id: "picker-selection", in: pickerNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AppTheme.surfaceRaised.opacity(0.72))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(AppTheme.border, lineWidth: 1))
    }
}

public struct ThemedValueCard: View {
    let label: String
    let value: String
    let copyable: Bool

    @State private var showCheck = false

    public init(label: String, value: String, copyable: Bool = true) {
        self.label = label
        self.value = value
        self.copyable = copyable
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
                .textCase(.uppercase)
                .tracking(1.0)

            HStack(spacing: AppTheme.Spacing.sm) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                if copyable {
                    Spacer()
                    Button {
                        #if canImport(AppKit)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(value, forType: .string)
                        #endif
                        showCheck = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { showCheck = false }
                    } label: {
                        Image(systemName: showCheck ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(showCheck ? AppTheme.success : AppTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .animation(AppTheme.Anim.fast, value: showCheck)
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.heroGradient.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
    }
}

public struct ThemedConversionRow: View {
    let label: String
    let value: String

    @State private var showCheck = false

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .textSelection(.enabled)

            Spacer()

            Button {
                #if canImport(AppKit)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                #endif
                showCheck = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { showCheck = false }
            } label: {
                Image(systemName: showCheck ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(showCheck ? AppTheme.success : AppTheme.textMuted)
            }
            .buttonStyle(.plain)
            .animation(AppTheme.Anim.fast, value: showCheck)
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}
