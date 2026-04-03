import AppKit
import CodeToolUI
import SwiftUI
import UniformTypeIdentifiers

public struct AISpeechView: View {
    private enum SpeechStreamPhase: Equatable {
        case idle
        case buffering
        case playable
        case ready
        case cancelled
        case failed
    }

    private var settings = MiniMaxSettingsStore.shared

    @State private var inputText: String = ""
    @State private var streamPhase: SpeechStreamPhase = .idle
    @State private var audioData = Data()
    @State private var completedAudioData: Data? = nil
    @State private var playbackController = StreamingSpeechPlayer()
    @State private var isPlaying: Bool = false
    @State private var errorMessage: String = ""
    @State private var selectedVoice: String = "male-qn-qingse"
    @State private var speed: Double = 1.0
    @State private var volume: Double = 1.0
    @State private var pitch: Double = 0
    @State private var outputFormat: String = "mp3"
    @State private var loadedAudioFormat: String? = nil
    @State private var latestReferenceID: String = ""
    @State private var activeGenerationReferenceID: String? = nil
    @State private var showHistory = false
    @State private var speechHistory: [SpeechHistoryRecord] = []
    @State private var generationTask: Task<Void, Never>? = nil
    @State private var didConfigurePlaybackController = false

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

    private let outputFormats = ["mp3", "flac"]
    private let minimumPlaybackBufferBytes = 32 * 1024

    public init() {}

    private var isGenerating: Bool {
        switch streamPhase {
        case .buffering, .playable:
            return true
        default:
            return false
        }
    }

    private var hasBufferedAudio: Bool {
        !audioData.isEmpty
    }

    private var canStartPlayback: Bool {
        guard hasBufferedAudio else { return false }
        if isPlaying || completedAudioData != nil { return true }

        switch streamPhase {
        case .playable, .ready, .cancelled, .failed:
            return true
        case .buffering:
            return audioData.count >= minimumPlaybackBufferBytes
        case .idle:
            return false
        }
    }

    private var currentAudioFormat: String {
        loadedAudioFormat ?? outputFormat
    }

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Text to Speech",
            title: "AI Speech",
            description: "Stream MiniMax Speech 2.8 audio, buffer it live, and start playback when you're ready.",
            systemImage: "waveform",
            statusItems: statusItems
        ) {
            StyledButton("Generate Speech", systemImage: "waveform.path", variant: .primary) {
                generateSpeech()
            }
            .disabled(
                inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating
                    || !settings.isConfigured)

            if isGenerating {
                StyledButton("Stop Generation", systemImage: "stop.circle", variant: .secondary) {
                    cancelGeneration()
                }
            }

            if completedAudioData != nil {
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
            .disabled(inputText.isEmpty && !hasBufferedAudio)
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
        .onAppear {
            configurePlaybackControllerIfNeeded()
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
                    title: streamPhase == .playable ? "Streaming" : "Buffering…",
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: AppTheme.accentWarm
                ))
        }

        if hasBufferedAudio {
            let title: String
            let tint: Color

            if isPlaying {
                title = "Playing"
                tint = AppTheme.accentWarm
            } else if completedAudioData != nil {
                title = "Audio ready"
                tint = AppTheme.success
            } else if canStartPlayback {
                title = "Buffered"
                tint = AppTheme.success
            } else {
                title = "Buffering"
                tint = AppTheme.accent
            }

            items.append(
                ToolStatusItem(
                    title: title,
                    systemImage: isPlaying ? "speaker.wave.3.fill" : "waveform.circle.fill",
                    tint: tint
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
                    if hasBufferedAudio {
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

            Text("WAV is unavailable in streaming mode.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
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
                .disabled(!isPlaying && !canStartPlayback)

                StyledIconButton("stop.fill", help: "Stop") {
                    stopPlayback()
                }
                .disabled(!isPlaying)

                Spacer()

                Text(formattedSize(audioData.count))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textMuted)
            }

            if isGenerating && !canStartPlayback {
                Text("Buffering live audio. Play unlocks automatically once enough audio is queued.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textMuted)
            } else if isGenerating && !isPlaying {
                Text("Streaming is in progress. Click Play whenever you want to start playback.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textMuted)
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
        } else if !errorMessage.isEmpty {
            ToolMessageBanner(
                systemImage: "exclamationmark.triangle.fill",
                message: errorMessage,
                tint: AppTheme.error
            )
        } else if isGenerating && isPlaying {
            ToolMessageBanner(
                systemImage: "speaker.wave.3.fill",
                message: "Streaming speech and playing buffered audio…",
                tint: AppTheme.accent
            )
        } else if isGenerating && canStartPlayback {
            ToolMessageBanner(
                systemImage: "waveform.circle.fill",
                message: "Speech is still streaming. Buffered audio is ready, and playback remains manual.",
                tint: AppTheme.accent
            )
        } else if isGenerating {
            ToolMessageBanner(
                systemImage: "arrow.triangle.2.circlepath",
                message: "Streaming speech and buffering audio…",
                tint: AppTheme.accent
            )
        } else if completedAudioData != nil {
            ToolMessageBanner(
                systemImage: "checkmark.circle.fill",
                message: "Speech streamed successfully. Use playback controls or save the final audio.",
                tint: AppTheme.success
            )
        } else if streamPhase == .cancelled && hasBufferedAudio {
            ToolMessageBanner(
                systemImage: "stop.circle.fill",
                message: "Generation stopped. The buffered audio remains available for preview.",
                tint: AppTheme.warning
            )
        } else if streamPhase == .failed && hasBufferedAudio {
            ToolMessageBanner(
                systemImage: "exclamationmark.triangle.fill",
                message: "Streaming stopped early, but the buffered audio is still available.",
                tint: AppTheme.warning
            )
        } else {
            ToolMessageBanner(
                systemImage: "sparkles",
                message: "Enter text and stream speech with MiniMax Speech 2.8, then press Play when enough audio is buffered.",
                tint: AppTheme.accentWarm
            )
        }
    }

    // MARK: - Actions

    private func generateSpeech() {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        configurePlaybackControllerIfNeeded()
        generationTask?.cancel()
        playbackController.reset(format: outputFormat)

        let referenceID = AppLogger.makeReferenceID()
        let selectedVoice = selectedVoice
        let speed = speed
        let volume = volume
        let pitchValue = Int(pitch)
        let format = outputFormat
        let pitchRecordValue = pitch

        audioData.removeAll(keepingCapacity: false)
        completedAudioData = nil
        loadedAudioFormat = format
        errorMessage = ""
        latestReferenceID = referenceID
        activeGenerationReferenceID = referenceID
        streamPhase = .buffering

        generationTask = Task {
            do {
                let response = try await MiniMaxAPIClient.shared.textToSpeechStream(
                    text: trimmedInput,
                    voiceId: selectedVoice,
                    speed: speed,
                    vol: volume,
                    pitch: pitchValue,
                    format: format,
                    referenceID: referenceID
                ) { chunk in
                    Task { @MainActor in
                        receiveAudioChunk(chunk, referenceID: referenceID)
                    }
                }

                await MainActor.run {
                    completeStreaming(response, referenceID: referenceID)
                }

                let recordID = UUID()
                let audioFileName = "\(recordID.uuidString).\(format)"
                let record = SpeechHistoryRecord(
                    id: recordID,
                    createdAt: Date(),
                    inputText: trimmedInput,
                    voice: selectedVoice,
                    speed: speed,
                    volume: volume,
                    pitch: pitchRecordValue,
                    outputFormat: format,
                    model: MiniMaxSettingsStore.shared.speechModel,
                    durationMs: response.durationMs,
                    audioFileName: audioFileName,
                    referenceID: response.referenceID
                )
                try? await HistoryStore.shared.save(record, audioData: response.audioData)
            } catch is CancellationError {
                await MainActor.run {
                    handleCancelledGeneration(referenceID: referenceID)
                }
            } catch {
                await MainActor.run {
                    handleStreamingFailure(error, referenceID: referenceID)
                }
            }

            await MainActor.run {
                if activeGenerationReferenceID == referenceID {
                    generationTask = nil
                    activeGenerationReferenceID = nil
                }
            }
        }
    }

    private func receiveAudioChunk(_ chunk: Data, referenceID: String) {
        guard activeGenerationReferenceID == referenceID else { return }
        guard !chunk.isEmpty else { return }

        audioData.append(chunk)
        playbackController.append(chunk)

        if streamPhase == .buffering && audioData.count >= minimumPlaybackBufferBytes {
            streamPhase = .playable
        }
    }

    private func completeStreaming(
        _ response: MiniMaxAPIClient.TTSResponse,
        referenceID: String
    ) {
        guard activeGenerationReferenceID == referenceID else { return }
        audioData = response.audioData
        completedAudioData = response.audioData
        loadedAudioFormat = response.format
        latestReferenceID = response.referenceID
        playbackController.markStreamFinished()

        if !isPlaying {
            streamPhase = .ready
        }
    }

    private func handleCancelledGeneration(referenceID: String) {
        guard activeGenerationReferenceID == referenceID else { return }
        playbackController.markStreamFinished()
        streamPhase = hasBufferedAudio ? .cancelled : .idle
    }

    private func handleStreamingFailure(_ error: Error, referenceID: String) {
        guard activeGenerationReferenceID == referenceID else { return }
        playbackController.markStreamFinished()
        errorMessage = error.localizedDescription
        streamPhase = hasBufferedAudio ? .failed : .idle
    }

    private func cancelGeneration() {
        generationTask?.cancel()
    }

    private func togglePlayback() {
        if isPlaying {
            playbackController.pause()
        } else {
            do {
                try playbackController.play()
                errorMessage = ""
            } catch {
                handlePlaybackFailure(error)
            }
        }
    }

    private func stopPlayback() {
        playbackController.stop()
    }

    private func handlePlaybackFailure(_ error: Error) {
        let playbackError = error
        let referenceID = latestReferenceID

        Task {
            let resolvedReferenceID = await AppLogger.shared.error(
                category: .aispeech,
                event: "player_prepare_failed",
                referenceID: referenceID.isEmpty ? nil : referenceID,
                message: "Failed to prepare streamed speech for playback.",
                metadata: [
                    "stage": "prepare_streaming_audio_player",
                    "byteCount": String(audioData.count),
                    "format": currentAudioFormat,
                ],
                error: playbackError
            )

            await MainActor.run {
                errorMessage = "Speech playback failed. Reference ID: \(resolvedReferenceID)"
                isPlaying = false
            }
        }
    }

    private func saveAudio() {
        guard let data = completedAudioData else { return }
        let format = currentAudioFormat

        let panel = NSSavePanel()
        panel.title = "Save Audio"
        panel.nameFieldStringValue = "speech.\(format)"
        panel.canCreateDirectories = true

        switch format {
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
        generationTask?.cancel()
        generationTask = nil
        activeGenerationReferenceID = nil
        stopPlayback()
        playbackController.reset(format: outputFormat)
        inputText = ""
        audioData.removeAll(keepingCapacity: false)
        completedAudioData = nil
        loadedAudioFormat = nil
        errorMessage = ""
        latestReferenceID = ""
        streamPhase = .idle
    }

    private func formattedSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func configurePlaybackControllerIfNeeded() {
        guard !didConfigurePlaybackController else { return }
        didConfigurePlaybackController = true

        playbackController.onPlaybackStateChanged = { playing in
            Task { @MainActor in
                isPlaying = playing
            }
        }

        playbackController.onPlaybackFinished = {
            Task { @MainActor in
                isPlaying = false
                if completedAudioData != nil {
                    streamPhase = .ready
                } else if isGenerating {
                    streamPhase = canStartPlayback ? .playable : .buffering
                }
            }
        }

        playbackController.onError = { error in
            Task { @MainActor in
                handlePlaybackFailure(error)
            }
        }
    }

    // MARK: - History

    private func loadHistory() {
        Task {
            let records = (try? await HistoryStore.shared.listSpeech()) ?? []
            await MainActor.run { speechHistory = records }
        }
    }

    private func restoreSpeech(_ record: SpeechHistoryRecord) {
        generationTask?.cancel()
        generationTask = nil
        activeGenerationReferenceID = nil
        stopPlayback()
        configurePlaybackControllerIfNeeded()

        inputText = record.inputText
        selectedVoice = record.voice
        speed = record.speed
        volume = record.volume
        pitch = record.pitch
        outputFormat = outputFormats.contains(record.outputFormat) ? record.outputFormat : outputFormats[0]
        errorMessage = ""
        latestReferenceID = record.referenceID

        Task {
            if let data = try? await HistoryStore.shared.loadData(category: .speech, fileName: record.audioFileName) {
                await MainActor.run {
                    if !outputFormats.contains(record.outputFormat) {
                        audioData = data
                        completedAudioData = data
                        loadedAudioFormat = record.outputFormat
                        streamPhase = .ready
                        errorMessage =
                            "\(record.outputFormat.uppercased()) history can still be exported, but new streaming generations use MP3 or FLAC."
                    } else {
                        do {
                            try playbackController.loadCompletedAudio(data, format: record.outputFormat)
                            audioData = data
                            completedAudioData = data
                            loadedAudioFormat = record.outputFormat
                            streamPhase = .ready
                        } catch {
                            audioData.removeAll(keepingCapacity: false)
                            completedAudioData = nil
                            loadedAudioFormat = nil
                            streamPhase = .idle
                            errorMessage = "Failed to load audio: \(error.localizedDescription)"
                        }
                    }
                }
            } else {
                await MainActor.run {
                    audioData.removeAll(keepingCapacity: false)
                    completedAudioData = nil
                    loadedAudioFormat = nil
                    streamPhase = .idle
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
