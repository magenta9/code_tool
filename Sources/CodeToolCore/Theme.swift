import SwiftUI

// MARK: - Design Tokens

public enum AppTheme {

    // MARK: Colors

    public static let background = Color(red: 0.031, green: 0.055, blue: 0.071)
    public static let backgroundRaised = Color(red: 0.051, green: 0.082, blue: 0.102)
    public static let surface = Color(red: 0.071, green: 0.110, blue: 0.133)
    public static let surfaceRaised = Color(red: 0.094, green: 0.149, blue: 0.180)
    public static let surfaceHover = Color(red: 0.118, green: 0.188, blue: 0.224)
    public static let sidebarBackground = Color(red: 0.039, green: 0.067, blue: 0.082)

    public static let textPrimary = Color(red: 0.941, green: 0.965, blue: 0.973)
    public static let textSecondary = Color(red: 0.675, green: 0.741, blue: 0.776)
    public static let textMuted = Color(red: 0.463, green: 0.541, blue: 0.592)

    public static let border = Color.white.opacity(0.08)
    public static let borderHover = Color.white.opacity(0.16)
    public static let glow = Color(red: 0.165, green: 0.812, blue: 0.835)

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
        colors: [accent.opacity(0.26), accentWarm.opacity(0.12)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let selectionGradient = LinearGradient(
        colors: [accent.opacity(0.22), accentWarm.opacity(0.10)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let cardGradient = LinearGradient(
        colors: [surfaceRaised, surface],
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
    }

    // MARK: Animations

    public enum Anim {
        public static let hover = Animation.linear(duration: 0.08)
        public static let fast = Animation.easeOut(duration: 0.16)
        public static let normal = Animation.spring(duration: 0.28, bounce: 0.14)
        public static let slow = Animation.spring(duration: 0.42, bounce: 0.12)
    }
}

// MARK: - Background

public struct AppBackdrop: View {
    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.backgroundRaised, AppTheme.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(AppTheme.accent.opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(x: -260, y: -220)

            Circle()
                .fill(AppTheme.accentWarm.opacity(0.12))
                .frame(width: 360, height: 360)
                .blur(radius: 100)
                .offset(x: 280, y: -180)

            Circle()
                .fill(AppTheme.accentCoral.opacity(0.08))
                .frame(width: 260, height: 260)
                .blur(radius: 80)
                .offset(x: 260, y: 260)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.02), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .ignoresSafeArea()
    }
}

// MARK: - View Modifiers

public struct ThemedPanelModifier: ViewModifier {
    var padding: CGFloat = AppTheme.Spacing.lg

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.cardGradient)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )
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

    func themedToolView() -> some View {
        modifier(ThemedToolViewModifier())
    }
}
