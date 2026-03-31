import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct AISpeechView: View {
    private var settings = MiniMaxSettingsStore.shared

    @State private var inputText: String = ""
    @State private var isGenerating: Bool = false
    @State private var audioData: Data? = nil
    @State private var audioPlayer: AVAudioPlayer? = nil
    @State private var isPlaying: Bool = false
    @State private var errorMessage: String = ""
    @State private var selectedVoice: String = "male-qn-qingse"
    @State private var speed: Double = 1.0
    @State private var volume: Double = 1.0
    @State private var pitch: Double = 0
    @State private var outputFormat: String = "mp3"
    @State private var latestReferenceID: String = ""
    @State private var showHistory = false
    @State private var speechHistory: [SpeechHistoryRecord] = []

    private let voices: [(id: String, name: String)] = [
        ("male-qn-qingse", "青涩青年"),
        ("female-shaonv", "少女"),
        ("female-yujie", "御姐"),
        ("male-qn-jingying", "精英青年"),
        ("presenter_male", "男主持"),
        ("presenter_female", "女主持"),
        ("audiobook_male_1", "有声书男"),
        ("audiobook_female_1", "有声书女"),
    ]

    private let outputFormats = ["mp3", "wav", "flac"]

    public init() {}

    // MARK: - Body

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Text to Speech",
            title: "AI Speech",
            description: "Generate natural speech from text using MiniMax Speech 2.8 model.",
            systemImage: "waveform",
            statusItems: statusItems
        ) {
            StyledButton("Generate Speech", systemImage: "waveform.path", variant: .primary) {
                generateSpeech()
            }
            .disabled(
                inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating
                    || !settings.isConfigured)

            if audioData != nil {
                StyledButton("Save Audio", systemImage: "square.and.arrow.down") {
                    saveAudio()
                }
            }

            StyledButton("History", systemImage: "clock.arrow.circlepath", variant: .secondary) {
                loadHistory()
                showHistory = true
            }

            StyledButton("Clear", systemImage: "trash", variant: .ghost) {
                clearAll()
            }
            .disabled(inputText.isEmpty && audioData == nil)
        } content: {
            VStack(spacing: AppTheme.Spacing.lg) {
                HSplitView {
                    inputPanel
                        .frame(minWidth: 280, idealWidth: 400)
                    controlPanel
                        .frame(minWidth: 300, idealWidth: 360)
                }

                statusBanner
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
        .frame(minHeight: 500)
        .overlay {
            if showHistory {
                HistoryDrawer(
                    isPresented: $showHistory,
                    title: "Speech History",
                    items: speechHistory,
                    onSelect: { record in restoreSpeech(record) },
                    onDelete: { record in deleteSpeechRecord(record) },
                    onClearAll: { clearSpeechHistory() }
                )
            }
        }
    }

    // MARK: - Status Items

    private var statusItems: [ToolStatusItem] {
        var items: [ToolStatusItem] = []

        items.append(
            ToolStatusItem(
                title: "\(inputText.count) chars",
                systemImage: "character.cursor.ibeam",
                tint: AppTheme.accent
            ))

        if isGenerating {
            items.append(
                ToolStatusItem(
                    title: "Generating…",
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: AppTheme.accentWarm
                ))
        }

        if audioData != nil {
            items.append(
                ToolStatusItem(
                    title: isPlaying ? "Playing" : "Audio ready",
                    systemImage: isPlaying ? "speaker.wave.3.fill" : "checkmark.circle.fill",
                    tint: isPlaying ? AppTheme.accentWarm : AppTheme.success
                ))
        }

        if !settings.isConfigured {
            items.append(
                ToolStatusItem(
                    title: "Not configured",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: AppTheme.warning
                ))
        }

        return items
    }

    // MARK: - Input Panel

    private var inputPanel: some View {
        StyledPanel(title: "Input Text") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                StyledTextEditor(
                    text: $inputText,
                    placeholder: "Enter the text you want to convert to speech…"
                )
                .frame(minHeight: 200)

                HStack {
                    Text("\(inputText.count) characters")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textMuted)
                    Spacer()
                    if !inputText.isEmpty {
                        CopyButton("Copy", text: inputText)
                    }
                }
            }
        }
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        StyledPanel(title: "Settings & Playback") {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    voiceSection
                    parameterSection
                    formatSection
                    if audioData != nil {
                        playbackSection
                    }
                }
            }
        }
    }

    // MARK: - Voice Section

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("VOICE")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
                .tracking(1.2)

            Picker("Voice", selection: $selectedVoice) {
                ForEach(voices, id: \.id) { voice in
                    Text("\(voice.name) (\(voice.id))")
                        .tag(voice.id)
                }
            }
            .labelsHidden()
        }
    }

    // MARK: - Parameter Section

    private var parameterSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("PARAMETERS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
                .tracking(1.2)

            sliderRow(label: "Speed", value: $speed, range: 0.5...2.0, format: "%.1f×")
            sliderRow(label: "Volume", value: $volume, range: 0.1...10.0, format: "%.1f")
            sliderRow(label: "Pitch", value: $pitch, range: -12...12, format: "%+.0f st")
        }
    }

    private func sliderRow(
        label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.accent)
            }
            Slider(value: value, in: range)
                .tint(AppTheme.accent)
        }
    }

    // MARK: - Format Section

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("OUTPUT FORMAT")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
                .tracking(1.2)

            Picker("Format", selection: $outputFormat) {
                ForEach(outputFormats, id: \.self) { fmt in
                    Text(fmt.uppercased()).tag(fmt)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Playback Section

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("PLAYBACK")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
                .tracking(1.2)

            HStack(spacing: AppTheme.Spacing.md) {
                StyledIconButton(
                    isPlaying ? "pause.fill" : "play.fill",
                    help: isPlaying ? "Pause" : "Play"
                ) {
                    togglePlayback()
                }

                StyledIconButton("stop.fill", help: "Stop") {
                    stopPlayback()
                }
                .disabled(!isPlaying)

                Spacer()

                if let data = audioData {
                    Text(formattedSize(data.count))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textMuted)
                }
            }
        }
    }

    // MARK: - Status Banner

    @ViewBuilder
    private var statusBanner: some View {
        if !settings.isConfigured {
            ToolMessageBanner(
                systemImage: "key.fill",
                message: "MiniMax API key is required. Configure it in MiniMax Settings.",
                tint: AppTheme.warning
            )
        } else if isGenerating {
            ToolMessageBanner(
                systemImage: "arrow.triangle.2.circlepath",
                message: "Generating speech…",
                tint: AppTheme.accent
            )
        } else if !errorMessage.isEmpty {
            ToolMessageBanner(
                systemImage: "exclamationmark.triangle.fill",
                message: errorMessage,
                tint: AppTheme.error
            )
        } else if audioData != nil {
            ToolMessageBanner(
                systemImage: "checkmark.circle.fill",
                message:
                    "Audio generated successfully. Use the playback controls or save to file.",
                tint: AppTheme.success
            )
        } else {
            ToolMessageBanner(
                systemImage: "sparkles",
                message:
                    "Enter text and select a voice, then generate speech using MiniMax Speech 2.8.",
                tint: AppTheme.accentWarm
            )
        }
    }

    // MARK: - Actions

    private func generateSpeech() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isGenerating = true
        errorMessage = ""
        latestReferenceID = ""
        stopPlayback()

        Task {
            do {
                let response = try await MiniMaxAPIClient.shared.textToSpeech(
                    text: inputText,
                    voiceId: selectedVoice,
                    speed: speed,
                    vol: volume,
                    pitch: Int(pitch),
                    format: outputFormat
                )
                await MainActor.run {
                    audioData = response.audioData
                    latestReferenceID = response.referenceID
                    isGenerating = false
                }

                let recordID = UUID()
                let audioFileName = "\(recordID.uuidString).\(outputFormat)"
                let record = SpeechHistoryRecord(
                    id: recordID,
                    createdAt: Date(),
                    inputText: inputText,
                    voice: selectedVoice,
                    speed: speed,
                    volume: volume,
                    pitch: pitch,
                    outputFormat: outputFormat,
                    model: MiniMaxSettingsStore.shared.speechModel,
                    durationMs: response.durationMs,
                    audioFileName: audioFileName,
                    referenceID: response.referenceID
                )
                try? await HistoryStore.shared.save(record, audioData: response.audioData)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func togglePlayback() {
        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
        } else {
            playAudio()
        }
    }

    private func playAudio() {
        guard let data = audioData else { return }

        do {
            let player = try AVAudioPlayer(data: data)
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            isPlaying = true
        } catch {
            let playbackError = error
            let referenceID = latestReferenceID
            Task {
                let resolvedReferenceID = await AppLogger.shared.error(
                    category: .aispeech,
                    event: "player_prepare_failed",
                    referenceID: referenceID.isEmpty ? nil : referenceID,
                    message: "Failed to prepare generated speech for playback.",
                    metadata: [
                        "stage": "prepare_audio_player",
                        "byteCount": String(data.count),
                        "format": outputFormat,
                    ],
                    error: playbackError
                )

                await MainActor.run {
                    errorMessage = "Speech playback failed. Reference ID: \(resolvedReferenceID)"
                    isPlaying = false
                }
            }
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }

    private func saveAudio() {
        guard let data = audioData else { return }

        let panel = NSSavePanel()
        panel.title = "Save Audio"
        panel.nameFieldStringValue = "speech.\(outputFormat)"
        panel.canCreateDirectories = true

        switch outputFormat {
        case "wav":
            panel.allowedContentTypes = [.wav]
        case "flac":
            panel.allowedContentTypes = [UTType(filenameExtension: "flac") ?? .audio]
        default:
            panel.allowedContentTypes = [.mp3]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url)
            errorMessage = ""
        } catch {
            errorMessage = "Failed to save file: \(error.localizedDescription)"
        }
    }

    private func clearAll() {
        stopPlayback()
        inputText = ""
        audioData = nil
        errorMessage = ""
        latestReferenceID = ""
    }

    private func formattedSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - History

    private func loadHistory() {
        Task {
            let records = (try? await HistoryStore.shared.listSpeech()) ?? []
            await MainActor.run { speechHistory = records }
        }
    }

    private func restoreSpeech(_ record: SpeechHistoryRecord) {
        inputText = record.inputText
        selectedVoice = record.voice
        speed = record.speed
        volume = record.volume
        pitch = record.pitch
        outputFormat = record.outputFormat
        errorMessage = ""

        // Try to load audio
        Task {
            if let data = try? await HistoryStore.shared.loadData(category: .speech, fileName: record.audioFileName) {
                await MainActor.run { audioData = data }
            } else {
                await MainActor.run {
                    audioData = nil
                    errorMessage = "Audio file missing — text and parameters restored. Regenerate to create audio."
                }
            }
        }
    }

    private func deleteSpeechRecord(_ record: SpeechHistoryRecord) {
        Task {
            try? await HistoryStore.shared.deleteSpeech(id: record.id)
            let records = (try? await HistoryStore.shared.listSpeech()) ?? []
            await MainActor.run { speechHistory = records }
        }
    }

    private func clearSpeechHistory() {
        Task {
            try? await HistoryStore.shared.clear(category: .speech)
            await MainActor.run { speechHistory = [] }
        }
    }
}

// MARK: - Preview

#if DEBUG
    struct AISpeechView_Previews: PreviewProvider {
        static var previews: some View {
            AISpeechView()
                .frame(width: 900, height: 620)
        }
    }
#endif
