import SwiftUI

// MARK: - AudioPlayerView

public struct AudioPlayerView: View {
    @Environment(\.toolUIActivity) private var toolUIActivity

    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isStreaming: Bool
    let canSeek: Bool

    let format: String?
    let fileSize: Int?
    let sampleRate: Int?

    let onPlayPause: () -> Void
    let onStop: () -> Void
    let onSeek: ((TimeInterval) -> Void)?

    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var isHoveredPlay = false
    @State private var isHoveredStop = false
    @State private var isHoveredTrack = false
    @State private var shimmerPhase = false

    public init(
        isPlaying: Bool,
        currentTime: TimeInterval,
        duration: TimeInterval,
        isStreaming: Bool = false,
        canSeek: Bool = true,
        format: String? = nil,
        fileSize: Int? = nil,
        sampleRate: Int? = nil,
        onPlayPause: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onSeek: ((TimeInterval) -> Void)? = nil
    ) {
        self.isPlaying = isPlaying
        self.currentTime = currentTime
        self.duration = duration
        self.isStreaming = isStreaming
        self.canSeek = canSeek
        self.format = format
        self.fileSize = fileSize
        self.sampleRate = sampleRate
        self.onPlayPause = onPlayPause
        self.onStop = onStop
        self.onSeek = onSeek
    }

    public var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            controlsRow
            progressSection
            if hasMetadata {
                metadataRow
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.cardGradient.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
    }

    // MARK: - Controls Row

    private var controlsRow: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            playButton
            stopButton
            Spacer()
            timeDisplay
        }
    }

    private var playButton: some View {
        Button(action: onPlayPause) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isPlaying ? AppTheme.background : AppTheme.textPrimary)
                .frame(width: 40, height: 40)
                .background(
                    Group {
                        if isPlaying {
                            AppTheme.accentGradient
                        } else {
                            AppTheme.surfaceRaised.opacity(isHoveredPlay ? 0.95 : 0.72)
                        }
                    }
                )
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(
                        isPlaying ? Color.white.opacity(0.18) : AppTheme.border,
                        lineWidth: 1
                    )
                )
                .shadow(
                    color: isPlaying ? AppTheme.accent.opacity(0.18) : .clear,
                    radius: 8, y: 2
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHoveredPlay ? 1.04 : 1.0)
        .toolHoverTracking($isHoveredPlay)
    }

    private var stopButton: some View {
        Button(action: onStop) {
            Image(systemName: "stop.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 30, height: 30)
                .background(AppTheme.surfaceRaised.opacity(isHoveredStop ? 0.95 : 0.72))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(AppTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isPlaying)
        .opacity(isPlaying ? 1.0 : 0.5)
        .toolHoverTracking($isHoveredStop)
    }

    private var timeDisplay: some View {
        Group {
            if isStreaming && duration <= 0 {
                HStack(spacing: AppTheme.Spacing.xs) {
                    streamingDots
                    Text("Streaming…")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.accentWarm)
                }
            } else {
                Text("\(formatTime(displayTime)) / \(formatTime(duration))")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var streamingDots: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(AppTheme.accentWarm)
                    .frame(width: 4, height: 4)
                    .opacity(shimmerPhase ? (i == 0 ? 1.0 : i == 1 ? 0.6 : 0.3) : (i == 0 ? 0.3 : i == 1 ? 0.6 : 1.0))
            }
        }
        .onAppear { updateShimmerPhase() }
        .onChange(of: toolUIActivity.isVisible) { _, _ in
            updateShimmerPhase()
        }
        .animation(
            toolUIActivity.allowsDecorativeAnimations
                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : nil,
            value: shimmerPhase
        )
    }

    // MARK: - Progress Section

    @ViewBuilder
    private var progressSection: some View {
        if isStreaming && duration <= 0 {
            streamingBar
        } else {
            seekableProgressBar
        }
    }

    private var streamingBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.surfaceRaised)
                    .frame(height: 4)

                Capsule()
                    .fill(AppTheme.accentGradient)
                    .frame(width: geo.size.width * 0.3, height: 4)
                    .offset(x: shimmerPhase ? geo.size.width * 0.7 : 0)
            }
        }
        .frame(height: 4)
        .clipShape(Capsule())
        .onAppear { updateShimmerPhase() }
        .onChange(of: toolUIActivity.isVisible) { _, _ in
            updateShimmerPhase()
        }
        .animation(
            toolUIActivity.allowsDecorativeAnimations
                ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : nil,
            value: shimmerPhase
        )
    }

    private var seekableProgressBar: some View {
        GeometryReader { geo in
            let progress = duration > 0 ? (isDragging ? dragProgress : currentTime / duration) : 0
            let clampedProgress = max(0, min(1, progress))

            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(AppTheme.surfaceRaised)
                    .frame(height: 4)

                // Filled portion
                Capsule()
                    .fill(AppTheme.accentGradient)
                    .frame(width: max(0, geo.size.width * clampedProgress), height: 4)

                // Thumb
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: isHoveredTrack || isDragging ? 14 : 8, height: isHoveredTrack || isDragging ? 14 : 8)
                    .shadow(color: AppTheme.accent.opacity(0.3), radius: 4, y: 1)
                    .offset(x: max(0, min(geo.size.width - 14, geo.size.width * clampedProgress - 7)))
                    .animation(AppTheme.Anim.fast, value: isHoveredTrack)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .toolHoverTracking($isHoveredTrack, animation: nil)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard canSeek && duration > 0 else { return }
                        isDragging = true
                        dragProgress = max(0, min(1, value.location.x / geo.size.width))
                    }
                    .onEnded { _ in
                        guard isDragging else { return }
                        let seekTime = dragProgress * duration
                        isDragging = false
                        onSeek?(seekTime)
                    }
            )
            .disabled(!canSeek)
        }
        .frame(height: 20)
    }

    // MARK: - Metadata Row

    private var hasMetadata: Bool {
        format != nil || fileSize != nil || sampleRate != nil
    }

    private var metadataRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if let format {
                metadataBadge(format.uppercased(), systemImage: "waveform")
            }
            if let fileSize {
                metadataBadge(
                    ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file),
                    systemImage: "internaldrive"
                )
            }
            if let sampleRate {
                let displayRate = sampleRate >= 1000
                    ? "\(sampleRate / 1000)kHz"
                    : "\(sampleRate)Hz"
                metadataBadge(displayRate, systemImage: "metronome")
            }
            Spacer()
        }
    }

    private func metadataBadge(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(AppTheme.textMuted)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xxs)
        .background(AppTheme.surfaceRaised.opacity(0.5))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(AppTheme.border, lineWidth: 1))
    }

    // MARK: - Helpers

    private var displayTime: TimeInterval {
        isDragging ? dragProgress * duration : currentTime
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(0, time))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func updateShimmerPhase() {
        shimmerPhase = isStreaming && toolUIActivity.allowsDecorativeAnimations
    }
}

// MARK: - Preview

#if DEBUG
    struct AudioPlayerView_Previews: PreviewProvider {
        static var previews: some View {
            VStack(spacing: 20) {
                AudioPlayerView(
                    isPlaying: true,
                    currentTime: 42,
                    duration: 195,
                    format: "mp3",
                    fileSize: 3_145_728,
                    sampleRate: 44100,
                    onPlayPause: {},
                    onStop: {}
                )

                AudioPlayerView(
                    isPlaying: false,
                    currentTime: 0,
                    duration: 0,
                    isStreaming: true,
                    canSeek: false,
                    onPlayPause: {},
                    onStop: {}
                )
            }
            .padding()
            .background(AppTheme.background)
            .frame(width: 400)
        }
    }
#endif
