import SwiftUI

// MARK: - Design Tokens

public enum AppTheme {

    // MARK: Colors

    public static let background = Color(red: 0.035, green: 0.041, blue: 0.051)
    public static let backgroundRaised = Color(red: 0.052, green: 0.064, blue: 0.081)
    public static let surface = Color(red: 0.070, green: 0.084, blue: 0.106)
    public static let surfaceRaised = Color(red: 0.092, green: 0.112, blue: 0.142)
    public static let surfaceHover = Color(red: 0.180, green: 0.470, blue: 0.920).opacity(0.105)
    public static let sidebarBackground = Color(red: 0.044, green: 0.052, blue: 0.064)
    public static let panelTint = Color(red: 0.500, green: 0.720, blue: 1.000).opacity(0.030)
    public static let panelTintStrong = Color(red: 0.500, green: 0.720, blue: 1.000).opacity(0.050)

    public static let foreground = Color(red: 0.930, green: 0.950, blue: 0.980)
    public static let foregroundMuted = Color(red: 0.635, green: 0.675, blue: 0.725)
    public static let foregroundDim = Color(red: 0.410, green: 0.465, blue: 0.540)

    public static let textPrimary = foreground
    public static let textSecondary = foregroundMuted
    public static let textMuted = foregroundDim

    public static let card = Color(red: 0.058, green: 0.071, blue: 0.090)
    public static let cardRaised = Color(red: 0.078, green: 0.096, blue: 0.122)
    public static let popover = Color(red: 0.068, green: 0.083, blue: 0.106)
    public static let secondary = Color(red: 0.500, green: 0.720, blue: 1.000).opacity(0.060)
    public static let muted = Color(red: 0.500, green: 0.720, blue: 1.000).opacity(0.045)
    public static let input = Color(red: 0.500, green: 0.720, blue: 1.000).opacity(0.075)

    public static let border = Color(red: 0.650, green: 0.780, blue: 1.000).opacity(0.080)
    public static let borderHover = Color(red: 0.650, green: 0.780, blue: 1.000).opacity(0.160)
    public static let ring = Color(red: 0.160, green: 0.480, blue: 0.960)
    public static let glow = ring
    public static let innerGlow = Color.white.opacity(0.090)
    public static let shadow = Color.black.opacity(0.42)

    public static let accent = Color(red: 0.120, green: 0.420, blue: 0.940)
    public static let accentBright = Color(red: 0.360, green: 0.670, blue: 1.000)
    public static let accentWarm = Color(red: 0.420, green: 0.760, blue: 1.000)
    public static let accentCoral = Color(red: 0.955, green: 0.294, blue: 0.294)

    public static let info = Color(red: 0.231, green: 0.510, blue: 0.965)
    public static let success = Color(red: 0.133, green: 0.773, blue: 0.369)
    public static let error = Color(red: 0.957, green: 0.267, blue: 0.267)
    public static let destructive = error
    public static let warning = Color(red: 0.961, green: 0.620, blue: 0.043)

    // MARK: Gradients

    public static let accentGradient = LinearGradient(
        colors: [accentBright, accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let heroGradient = LinearGradient(
        colors: [accent.opacity(0.22), Color.white.opacity(0.035)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let selectionGradient = LinearGradient(
        colors: [accent.opacity(0.24), accent.opacity(0.12)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let cardGradient = LinearGradient(
        colors: [cardRaised, card],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let ambientGradient = LinearGradient(
        colors: [backgroundRaised, background, Color(red: 0.020, green: 0.026, blue: 0.034)],
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
        public static let xs: CGFloat = 6
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 8
        public static let lg: CGFloat = 10
        public static let xl: CGFloat = 14
        public static let xxl: CGFloat = 18
        public static let hero: CGFloat = 18
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

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.075), Color.clear, Color.black.opacity(0.24)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            noiseTexture
                .opacity(0.024)
                .blendMode(.screen)
        }
        .ignoresSafeArea()
    }

    private var noiseTexture: some View {
        Canvas { context, size in
            let step: CGFloat = 3
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let seed = Int((x * 17 + y * 31).truncatingRemainder(dividingBy: 11))
                    let opacity = seed.isMultiple(of: 3) ? 0.42 : 0.12
                    context.fill(
                        Path(CGRect(x: x, y: y, width: 1, height: 1)),
                        with: .color(Color.white.opacity(opacity))
                    )
                    x += step
                }
                y += step
            }
        }
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
        shadowOpacity: Double = 0.10
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
                    .fill(AppTheme.card)
                    .overlay { shape.fill(tint) }
                    .overlay {
                        LinearGradient(
                            colors: [Color.white.opacity(0.040), Color.clear, Color.black.opacity(0.075)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(shape)
                    }
                    .overlay(alignment: .top) {
                        shape
                            .stroke(Color.white.opacity(0.070), lineWidth: 1)
                            .mask(
                                LinearGradient(
                                    colors: [Color.white, Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .overlay { shape.strokeBorder(stroke, lineWidth: 1) }
            }
            .shadow(color: AppTheme.shadow.opacity(shadowOpacity), radius: 12, y: 5)
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
        shadowOpacity: Double = 0.10
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