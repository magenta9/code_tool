import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

public struct AIMusicView: View {

    @ObservedObject private var provider = MiniMaxProvider.shared

    @State private var promptText: String = ""
    @State private var lyricsText: String = ""
    @State private var isGenerating: Bool = false
    @State private var audioData: Data? = nil
    @State private var audioPlayer: AVAudioPlayer? = nil
    @State private var isPlaying: Bool = false
    @State private var errorMessage: String = ""
    @State private var outputFormat: String = "mp3"
    @State private var sampleRate: Int = 44100
    @State private var bitrate: Int = 256000

    public init() {}

    // MARK: - Status Items

    private var statusItems: [ToolStatusItem] {
        var items: [ToolStatusItem] = []
        if let player = audioPlayer {
            let duration = String(format: "%.1fs", player.duration)
            items.append(ToolStatusItem(title: duration, systemImage: "clock"))
        }
        if audioData != nil {
            let size = ByteCountFormatter.string(fromByteCount: Int64(audioData!.count), countStyle: .file)
            items.append(ToolStatusItem(title: size, systemImage: "doc.fill"))
        }
        items.append(ToolStatusItem(
            title: provider.musicModel,
            systemImage: "cpu",
            tint: provider.isConfigured ? AppTheme.success : AppTheme.error
        ))
        return items
    }

    // MARK: - Body

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Music Generation",
            title: "AI Music",
            description: "Generate original music with MiniMax's Music-2.5 model — describe a style or provide lyrics",
            systemImage: "music.note",
            statusItems: statusItems
        ) {
            StyledButton("Generate Music", systemImage: "wand.and.stars", variant: .primary) {
                generateMusic()
            }

            if audioData != nil {
                StyledButton("Save Audio", systemImage: "square.and.arrow.down") {
                    saveAudio()
                }
            }

            StyledButton("Clear", systemImage: "trash", variant: .ghost) {
                clearAll()
            }
        } content: {
            HSplitView {
                leftPanel
                    .frame(minWidth: 280, idealWidth: 340)
                rightPanel
                    .frame(minWidth: 320)
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            StyledPanel(title: "Prompt") {
                StyledTextEditor(
                    text: $promptText,
                    placeholder: "Describe the style and mood, e.g. \"Mandopop, Festive, Upbeat\""
                )
                .frame(minHeight: 100)
            }

            StyledPanel(title: "Lyrics (optional)") {
                StyledTextEditor(
                    text: $lyricsText,
                    placeholder: "Add lyrics with section tags:\n[Intro]\n[Verse]\n[Chorus]\n[Bridge]\n[Outro]"
                )
                .frame(minHeight: 160)
            }

            settingsPanel
        }
    }

    // MARK: - Settings

    private var settingsPanel: some View {
        StyledPanel(title: "Settings") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                settingsRow("Format") {
                    StyledSegmentedPicker(
                        options: ["mp3", "wav"],
                        selection: $outputFormat,
                        label: { $0.uppercased() }
                    )
                }

                StyledDivider()

                settingsRow("Sample Rate") {
                    StyledSegmentedPicker(
                        options: [44100, 32000],
                        selection: $sampleRate,
                        label: { "\($0 / 1000)kHz" }
                    )
                }

                StyledDivider()

                settingsRow("Bitrate") {
                    StyledSegmentedPicker(
                        options: [128000, 256000, 320000],
                        selection: $bitrate,
                        label: { "\($0 / 1000)k" }
                    )
                }
            }
        }
    }

    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            content()
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            if !provider.isConfigured {
                ToolMessageBanner(
                    systemImage: "exclamationmark.triangle.fill",
                    message: "MiniMax API is not configured. Add your API key in Settings.",
                    tint: AppTheme.warning
                )
            }

            if !errorMessage.isEmpty {
                ToolMessageBanner(
                    systemImage: "xmark.octagon.fill",
                    message: errorMessage,
                    tint: AppTheme.error
                )
            }

            if isGenerating {
                generatingPanel
            }

            if audioData != nil {
                playbackPanel
            }

            if !isGenerating && audioData == nil {
                emptyStatePanel
            }
        }
    }

    // MARK: - Generating Panel

    private var generatingPanel: some View {
        StyledPanel {
            VStack(spacing: AppTheme.Spacing.lg) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)
                    .tint(AppTheme.accent)

                Text("Generating music…")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)

                Text("This may take a moment")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AppTheme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.xxl)
        }
    }

    // MARK: - Playback Panel

    private var playbackPanel: some View {
        StyledPanel(title: "Playback") {
            VStack(spacing: AppTheme.Spacing.lg) {
                HStack(spacing: AppTheme.Spacing.md) {
                    StyledIconButton(isPlaying ? "pause.fill" : "play.fill", help: isPlaying ? "Pause" : "Play") {
                        togglePlayback()
                    }

                    StyledIconButton("stop.fill", help: "Stop") {
                        stopPlayback()
                    }

                    Spacer()

                    if let player = audioPlayer {
                        Text(String(format: "Duration: %.1fs", player.duration))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                if let data = audioData {
                    HStack(spacing: AppTheme.Spacing.md) {
                        ToolStatusItem(
                            title: outputFormat.uppercased(),
                            systemImage: "waveform"
                        ).asLabel

                        ToolStatusItem(
                            title: ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file),
                            systemImage: "internaldrive"
                        ).asLabel

                        ToolStatusItem(
                            title: "\(sampleRate / 1000)kHz",
                            systemImage: "metronome"
                        ).asLabel
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStatePanel: some View {
        StyledPanel {
            VStack(spacing: AppTheme.Spacing.lg) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 36))
                    .foregroundStyle(AppTheme.textMuted.opacity(0.5))

                Text("Enter a prompt and generate music")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.xxxl)
        }
    }

    // MARK: - Actions

    private func generateMusic() {
        guard !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter a prompt describing the music style."
            return
        }
        guard provider.isConfigured else {
            errorMessage = "MiniMax API is not configured. Add your API key in Settings."
            return
        }

        isGenerating = true
        errorMessage = ""
        stopPlayback()
        audioData = nil

        Task {
            do {
                let lyrics = lyricsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : lyricsText
                let response = try await MiniMaxAPIClient.shared.generateMusic(
                    prompt: promptText,
                    lyrics: lyrics,
                    format: outputFormat,
                    sampleRate: sampleRate,
                    bitrate: bitrate
                )

                var data = response.audioData
                if data == nil, let urlString = response.audioURL {
                    data = try await MiniMaxAPIClient.shared.downloadAudio(from: urlString)
                }

                await MainActor.run {
                    audioData = data
                    isGenerating = false
                    preparePlayer()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func preparePlayer() {
        guard let data = audioData else { return }
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.prepareToPlay()
        } catch {
            errorMessage = "Failed to prepare audio playback: \(error.localizedDescription)"
        }
    }

    private func togglePlayback() {
        guard let player = audioPlayer else {
            preparePlayer()
            audioPlayer?.play()
            isPlaying = true
            return
        }

        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
    }

    private func saveAudio() {
        guard let data = audioData else { return }

        let panel = NSSavePanel()
        panel.title = "Save Audio"
        panel.nameFieldStringValue = "generated_music.\(outputFormat)"
        panel.canCreateDirectories = true

        if outputFormat == "wav" {
            panel.allowedContentTypes = [.wav]
        } else {
            panel.allowedContentTypes = [.mp3]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url)
        } catch {
            errorMessage = "Failed to save audio: \(error.localizedDescription)"
        }
    }

    private func clearAll() {
        stopPlayback()
        promptText = ""
        lyricsText = ""
        audioData = nil
        audioPlayer = nil
        errorMessage = ""
    }
}

// MARK: - ToolStatusItem Label Helper

private extension ToolStatusItem {
    var asLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundStyle(AppTheme.textMuted)
    }
}

// MARK: - Preview

#if DEBUG
struct AIMusicView_Previews: PreviewProvider {
    static var previews: some View {
        AIMusicView()
            .frame(width: 900, height: 700)
    }
}
#endif
