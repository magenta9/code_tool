import SwiftUI

// MARK: - Design Tokens

public enum AppTheme {

    // MARK: Colors

    public static let background = Color(red: 0.031, green: 0.051, blue: 0.071)
    public static let backgroundRaised = Color(red: 0.055, green: 0.082, blue: 0.102)
    public static let surface = Color(red: 0.082, green: 0.122, blue: 0.153)
    public static let surfaceRaised = Color(red: 0.110, green: 0.161, blue: 0.196)
    public static let surfaceHover = Color(red: 0.145, green: 0.208, blue: 0.239)
    public static let sidebarBackground = Color(red: 0.051, green: 0.075, blue: 0.094)
    public static let panelTint = Color(red: 0.122, green: 0.173, blue: 0.212)
    public static let panelTintStrong = Color(red: 0.167, green: 0.227, blue: 0.271)

    public static let textPrimary = Color(red: 0.941, green: 0.965, blue: 0.973)
    public static let textSecondary = Color(red: 0.675, green: 0.741, blue: 0.776)
    public static let textMuted = Color(red: 0.463, green: 0.541, blue: 0.592)

    public static let border = Color.white.opacity(0.11)
    public static let borderHover = Color.white.opacity(0.20)
    public static let glow = Color(red: 0.165, green: 0.812, blue: 0.835)
    public static let innerGlow = Color.white.opacity(0.15)
    public static let shadow = Color.black.opacity(0.34)

    public static let accent = Color(red: 0.184, green: 0.780, blue: 0.824)
    public static let accentBright = Color(red: 0.294, green: 0.918, blue: 0.902)
    public static let accentWarm = Color(red: 0.973, green: 0.694, blue: 0.329)
    public static let accentCoral = Color(red: 0.937, green: 0.451, blue: 0.353)

    public static let success = Color(red: 0.400, green: 0.831, blue: 0.624)
    public static let error = Color(red: 0.937, green: 0.451, blue: 0.353)
    public static let warning = Color(red: 0.973, green: 0.694, blue: 0.329)

    // MARK: Gradients

    public static let accentGradient = LinearGradient(
        colors: [accentBright, accentWarm],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let heroGradient = LinearGradient(
        colors: [accent.opacity(0.30), accentWarm.opacity(0.12), accentCoral.opacity(0.06)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let selectionGradient = LinearGradient(
        colors: [accent.opacity(0.22), accentWarm.opacity(0.08)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let cardGradient = LinearGradient(
        colors: [panelTintStrong.opacity(0.92), panelTint.opacity(0.74)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let ambientGradient = LinearGradient(
        colors: [
            backgroundRaised.opacity(0.95),
            background.opacity(0.88),
            Color.black.opacity(0.82),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Spacing

    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let xxxl: CGFloat = 48
    }

    // MARK: Corner Radius

    public enum Radius {
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 18
        public static let xl: CGFloat = 24
        public static let hero: CGFloat = 32
    }

    // MARK: Typography

    public enum Typography {
        public static let textInput: CGFloat = 13
        public static let composerInput: CGFloat = 16
    }

    // MARK: Animations

    public enum Anim {
        public static let hover = Animation.linear(duration: 0.08)
        public static let fast = Animation.easeOut(duration: 0.16)
        public static let normal = Animation.spring(duration: 0.28, bounce: 0.14)
        public static let slow = Animation.spring(duration: 0.42, bounce: 0.12)
        public static let settle = Animation.spring(duration: 0.55, bounce: 0.10)
    }
}

// MARK: - Background

public struct AppBackdrop: View {
    public init() {}

    public var body: some View {
        ZStack {
            AppTheme.ambientGradient

            Circle()
                .fill(AppTheme.accent.opacity(0.16))
                .frame(width: 460, height: 460)
                .blur(radius: 120)
                .offset(x: -300, y: -240)

            Circle()
                .fill(AppTheme.accentWarm.opacity(0.12))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: 300, y: -200)

            Circle()
                .fill(AppTheme.accentCoral.opacity(0.10))
                .frame(width: 300, height: 300)
                .blur(radius: 110)
                .offset(x: 300, y: 280)

            Circle()
                .fill(AppTheme.accentBright.opacity(0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 90)
                .offset(x: -40, y: 260)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.05), Color.clear, Color.black.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Color.white.opacity(0.03), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .blendMode(.screen)
        }
        .ignoresSafeArea()
    }
}

// MARK: - View Modifiers

public struct GlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color
    let stroke: Color
    let shadowOpacity: Double

    public init(
        cornerRadius: CGFloat = AppTheme.Radius.lg,
        tint: Color = AppTheme.panelTint,
        stroke: Color = AppTheme.border,
        shadowOpacity: Double = 0.18
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.stroke = stroke
        self.shadowOpacity = shadowOpacity
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        shape
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.12),
                                        tint.opacity(0.26),
                                        Color.black.opacity(0.14),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        shape.strokeBorder(stroke, lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        shape
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                            .blur(radius: 0.4)
                            .mask {
                                LinearGradient(
                                    colors: [Color.white, Color.white.opacity(0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            }
                    }
            }
            .shadow(color: AppTheme.shadow.opacity(shadowOpacity), radius: 24, y: 14)
    }
}

public struct ThemedPanelModifier: ViewModifier {
    var padding: CGFloat = AppTheme.Spacing.lg

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .glassSurface()
    }
}

public struct ThemedToolViewModifier: ViewModifier {
    public func body(content: Content) -> some View {
        ZStack {
            AppBackdrop()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

public extension View {
    func themedPanel(padding: CGFloat = AppTheme.Spacing.lg) -> some View {
        modifier(ThemedPanelModifier(padding: padding))
    }

    func glassSurface(
        cornerRadius: CGFloat = AppTheme.Radius.lg,
        tint: Color = AppTheme.panelTint,
        stroke: Color = AppTheme.border,
        shadowOpacity: Double = 0.18
    ) -> some View {
        modifier(
            GlassSurfaceModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                stroke: stroke,
                shadowOpacity: shadowOpacity
            )
        )
    }

    func themedToolView() -> some View {
        modifier(ThemedToolViewModifier())
    }
}
