import AVFoundation
import AudioToolbox
import Foundation

final class StreamingSpeechPlayer: NSObject, AVAudioPlayerDelegate {
    var onPlaybackStateChanged: ((Bool) -> Void)?
    var onPlaybackFinished: (() -> Void)?
    var onError: ((Error) -> Void)?

    private let lock = NSLock()
    private var bufferedData = Data()
    private var format: String = "mp3"
    private var streamComplete = false
    private var playbackRequested = false
    private var isPaused = false
    private var pendingBufferCount = 0
    private var audioFileStream: AudioFileStreamID?
    private var audioQueue: AudioQueueRef?
    private var callbackError: Error?
    private var legacyAudioPlayer: AVAudioPlayer?
    private var isDisposed = false
    private let cleanupLock = NSLock()
    private var callbacksInFlight = 0
    private let callbackBarrier = DispatchQueue(label: "com.codetool.streamspeech.callbacks")

    var currentTime: TimeInterval {
        legacyAudioPlayer?.currentTime ?? 0
    }

    var duration: TimeInterval {
        legacyAudioPlayer?.duration ?? 0
    }

    var canSeek: Bool {
        legacyAudioPlayer != nil
    }

    func seek(to time: TimeInterval) {
        guard let player = legacyAudioPlayer else { return }
        player.currentTime = min(max(0, time), player.duration)
    }

    deinit {
        cleanupLock.lock()
        isDisposed = true
        cleanupLock.unlock()
        callbackBarrier.sync { }
        disposeStreamingObjects()
    }

    func reset(format: String) {
        stop()
        lock.lock()
        self.format = format.lowercased()
        bufferedData.removeAll(keepingCapacity: false)
        streamComplete = false
        callbackError = nil
        lock.unlock()
    }

    func loadCompletedAudio(_ data: Data, format: String) throws {
        let resolvedFormat = format.lowercased()
        guard resolvedFormat == "mp3" || resolvedFormat == "flac" else {
            throw MiniMaxError.unsupportedSpeechFormat(resolvedFormat)
        }
        reset(format: resolvedFormat)
        lock.lock()
        bufferedData = data
        streamComplete = true
        lock.unlock()
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }

        let streamToParse: AudioFileStreamID?
        lock.lock()
        bufferedData.append(chunk)
        streamToParse = audioFileStream
        lock.unlock()

        guard let streamID = streamToParse else { return }

        do {
            try parseData(chunk, streamID: streamID)
        } catch {
            report(error: error)
        }
    }

    private func parseData(_ data: Data, streamID: AudioFileStreamID) throws {
        guard !data.isEmpty else { return }

        let status = data.withUnsafeBytes { rawBuffer -> OSStatus in
            guard let baseAddress = rawBuffer.baseAddress else { return noErr }
            return AudioFileStreamParseBytes(
                streamID,
                UInt32(rawBuffer.count),
                baseAddress,
                AudioFileStreamParseFlags()
            )
        }

        guard status == noErr else {
            throw osStatusError(status, fallback: "Unable to parse streamed audio.")
        }
    }

    func markStreamFinished() {
        lock.lock()
        streamComplete = true
        let shouldFinish = playbackRequested && pendingBufferCount == 0
        lock.unlock()

        if shouldFinish {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.stop()
                self.onPlaybackFinished?()
            }
        }
    }

    private func incrementCallbacksInFlight() {
        callbackBarrier.async { [weak self] in
            guard let self else { return }
            self.cleanupLock.lock()
            self.callbacksInFlight += 1
            self.cleanupLock.unlock()
        }
    }

    private func decrementCallbacksInFlight() {
        callbackBarrier.async { [weak self] in
            guard let self else { return }
            self.cleanupLock.lock()
            self.callbacksInFlight -= 1
            self.cleanupLock.unlock()
        }
    }

    func play() throws {
        lock.lock()
        let isComplete = streamComplete
        lock.unlock()

        if isComplete || format == "wav" {
            try startLegacyPlayback()
            return
        }

        if format == "mp3" || format == "flac" {
            throw NSError(
                domain: "StreamingSpeechPlayer",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Playback becomes available after the full audio finishes generating."
                ]
            )
        }

        lock.lock()
        let existingQueue = audioQueue
        let hasBufferedAudio = !bufferedData.isEmpty
        playbackRequested = true
        isPaused = false
        lock.unlock()

        guard hasBufferedAudio else {
            throw MiniMaxError.invalidResponse
        }

        if let existingQueue {
            let status = AudioQueueStart(existingQueue, nil)
            guard status == noErr else {
                throw osStatusError(status, fallback: "Unable to resume streaming audio playback.")
            }
            DispatchQueue.main.async { [weak self] in self?.onPlaybackStateChanged?(true) }
            return
        }

        try startPlayback()
    }

    func pause() {
        if let legacyAudioPlayer {
            legacyAudioPlayer.pause()
            lock.lock()
            playbackRequested = false
            isPaused = true
            lock.unlock()
            DispatchQueue.main.async { [weak self] in self?.onPlaybackStateChanged?(false) }
            return
        }

        guard let audioQueue else { return }

        let status = AudioQueuePause(audioQueue)
        guard status == noErr else {
            report(error: osStatusError(status, fallback: "Unable to pause streaming audio playback."))
            return
        }

        lock.lock()
        playbackRequested = false
        isPaused = true
        lock.unlock()

        DispatchQueue.main.async { [weak self] in self?.onPlaybackStateChanged?(false) }
    }

    func stop() {
        if let legacyAudioPlayer {
            legacyAudioPlayer.delegate = nil
            legacyAudioPlayer.stop()
            self.legacyAudioPlayer = nil
        }

        lock.lock()
        playbackRequested = false
        isPaused = false
        pendingBufferCount = 0
        callbackError = nil
        lock.unlock()

        disposeStreamingObjects()
        DispatchQueue.main.async { [weak self] in self?.onPlaybackStateChanged?(false) }
    }

    private func startLegacyPlayback() throws {
        lock.lock()
        let data = bufferedData
        let isComplete = streamComplete
        lock.unlock()

        guard !data.isEmpty else {
            throw MiniMaxError.invalidResponse
        }
        guard isComplete else {
            throw NSError(
                domain: "StreamingSpeechPlayer",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "WAV playback is only available after the complete audio has finished loading."
                ]
            )
        }

        if let legacyAudioPlayer {
            guard legacyAudioPlayer.play() else {
                throw NSError(
                    domain: "StreamingSpeechPlayer",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to resume audio playback."]
                )
            }
            DispatchQueue.main.async { [weak self] in self?.onPlaybackStateChanged?(true) }
            return
        }

        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.prepareToPlay()
        guard player.play() else {
            throw NSError(
                domain: "StreamingSpeechPlayer",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to start audio playback."]
            )
        }

        legacyAudioPlayer = player
        DispatchQueue.main.async { [weak self] in self?.onPlaybackStateChanged?(true) }
    }

    private func startPlayback() throws {
        let fileTypeHint = try streamFileTypeHint()
        let streamID = try openAudioFileStream(fileTypeHint: fileTypeHint)

        lock.lock()
        audioFileStream = streamID
        let initialData = bufferedData
        callbackError = nil
        lock.unlock()

        do {
            try parse(initialData, streamID: streamID)
            if let callbackError = takeCallbackError() {
                throw callbackError
            }
            guard let audioQueue else {
                throw NSError(
                    domain: "StreamingSpeechPlayer",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Audio is still buffering. Wait for a little more audio before pressing Play."
                    ]
                )
            }

            let status = AudioQueueStart(audioQueue, nil)
            guard status == noErr else {
                throw osStatusError(status, fallback: "Unable to start streaming audio playback.")
            }

            DispatchQueue.main.async { [weak self] in self?.onPlaybackStateChanged?(true) }
        } catch {
            disposeStreamingObjects()
            throw error
        }
    }

    private func parse(_ data: Data, streamID: AudioFileStreamID) throws {
        guard !data.isEmpty else { return }

        let status = data.withUnsafeBytes { rawBuffer -> OSStatus in
            guard let baseAddress = rawBuffer.baseAddress else { return noErr }
            return AudioFileStreamParseBytes(
                streamID,
                UInt32(rawBuffer.count),
                baseAddress,
                AudioFileStreamParseFlags()
            )
        }

        guard status == noErr else {
            throw osStatusError(status, fallback: "Unable to parse streamed audio.")
        }
    }

    private func streamFileTypeHint() throws -> AudioFileTypeID {
        switch format {
        case "mp3":
            return AudioFileTypeID(kAudioFileMP3Type)
        case "flac":
            return AudioFileTypeID(kAudioFileFLACType)
        default:
            throw MiniMaxError.unsupportedSpeechFormat(format)
        }
    }

    private func openAudioFileStream(fileTypeHint: AudioFileTypeID) throws -> AudioFileStreamID {
        var streamID: AudioFileStreamID?
        let status = AudioFileStreamOpen(
            Unmanaged.passUnretained(self).toOpaque(),
            Self.propertyListener,
            Self.packetsListener,
            fileTypeHint,
            &streamID
        )

        guard status == noErr, let streamID else {
            throw osStatusError(status, fallback: "Unable to open streamed audio parser.")
        }

        return streamID
    }

    private func createAudioQueueIfNeeded(streamID: AudioFileStreamID) {
        guard audioQueue == nil else { return }

        var formatDescription = AudioStreamBasicDescription()
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let dataFormatStatus = AudioFileStreamGetProperty(
            streamID,
            kAudioFileStreamProperty_DataFormat,
            &propertySize,
            &formatDescription
        )
        guard dataFormatStatus == noErr else {
            reportCallbackError(
                osStatusError(dataFormatStatus, fallback: "Unable to read streamed audio format.")
            )
            return
        }

        var queue: AudioQueueRef?
        let queueStatus = AudioQueueNewOutput(
            &formatDescription,
            Self.outputCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            nil,
            0,
            &queue
        )
        guard queueStatus == noErr, let queue else {
            reportCallbackError(
                osStatusError(queueStatus, fallback: "Unable to create streaming audio output queue.")
            )
            return
        }

        audioQueue = queue
        applyMagicCookieIfNeeded(streamID: streamID, queue: queue)
    }

    private func applyMagicCookieIfNeeded(streamID: AudioFileStreamID, queue: AudioQueueRef) {
        var propertySize: UInt32 = 0
        var writable = DarwinBoolean(false)
        let infoStatus = AudioFileStreamGetPropertyInfo(
            streamID,
            kAudioFileStreamProperty_MagicCookieData,
            &propertySize,
            &writable
        )
        guard infoStatus == noErr, propertySize > 0 else { return }

        var cookieData = Data(count: Int(propertySize))
        let cookieStatus = cookieData.withUnsafeMutableBytes { rawBuffer -> OSStatus in
            guard let baseAddress = rawBuffer.baseAddress else { return noErr }
            return AudioFileStreamGetProperty(
                streamID,
                kAudioFileStreamProperty_MagicCookieData,
                &propertySize,
                baseAddress
            )
        }
        guard cookieStatus == noErr else {
            reportCallbackError(
                osStatusError(cookieStatus, fallback: "Unable to configure streaming audio decoder.")
            )
            return
        }

        let setCookieStatus = cookieData.withUnsafeBytes { rawBuffer -> OSStatus in
            guard let baseAddress = rawBuffer.baseAddress else { return noErr }
            return AudioQueueSetProperty(
                queue,
                kAudioQueueProperty_MagicCookie,
                baseAddress,
                UInt32(rawBuffer.count)
            )
        }
        guard setCookieStatus == noErr else {
            reportCallbackError(
                osStatusError(setCookieStatus, fallback: "Unable to apply streamed audio decoder state.")
            )
            return
        }
    }

    private func enqueuePackets(
        numberBytes: UInt32,
        numberPackets: UInt32,
        inputData: UnsafeRawPointer,
        packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?
    ) {
        guard let audioQueue else { return }

        var audioBuffer: AudioQueueBufferRef?
        let allocateStatus = AudioQueueAllocateBuffer(audioQueue, numberBytes, &audioBuffer)
        guard allocateStatus == noErr, let audioBuffer else {
            reportCallbackError(
                osStatusError(allocateStatus, fallback: "Unable to allocate a streaming audio buffer.")
            )
            return
        }

        memcpy(audioBuffer.pointee.mAudioData, inputData, Int(numberBytes))
        audioBuffer.pointee.mAudioDataByteSize = numberBytes

        let enqueueStatus: OSStatus
        if numberPackets > 0, let packetDescriptions {
            var descriptions = Array(
                UnsafeBufferPointer(start: packetDescriptions, count: Int(numberPackets))
            )
            enqueueStatus = descriptions.withUnsafeMutableBufferPointer { descriptionBuffer in
                AudioQueueEnqueueBuffer(audioQueue, audioBuffer, numberPackets, descriptionBuffer.baseAddress)
            }
        } else {
            enqueueStatus = AudioQueueEnqueueBuffer(audioQueue, audioBuffer, 0, nil)
        }

        guard enqueueStatus == noErr else {
            AudioQueueFreeBuffer(audioQueue, audioBuffer)
            reportCallbackError(
                osStatusError(enqueueStatus, fallback: "Unable to queue streamed audio for playback.")
            )
            return
        }

        lock.lock()
        pendingBufferCount += 1
        let shouldStartQueue = playbackRequested && !isPaused
        lock.unlock()

        guard shouldStartQueue else { return }

        let startStatus = AudioQueueStart(audioQueue, nil)
        if startStatus != noErr {
            reportCallbackError(
                osStatusError(startStatus, fallback: "Unable to continue streaming audio playback.")
            )
        }
    }

    private func bufferDidFinishPlaying(queue: AudioQueueRef, buffer: AudioQueueBufferRef) {
        AudioQueueFreeBuffer(queue, buffer)

        lock.lock()
        pendingBufferCount = max(0, pendingBufferCount - 1)
        let shouldFinish = playbackRequested && streamComplete && pendingBufferCount == 0
        lock.unlock()

        guard shouldFinish else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stop()
            self.onPlaybackFinished?()
        }
    }

    private func takeCallbackError() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        let error = callbackError
        callbackError = nil
        return error
    }

    private func reportCallbackError(_ error: Error) {
        lock.lock()
        let shouldReport = callbackError == nil
        if shouldReport {
            callbackError = error
        }
        lock.unlock()
        if shouldReport {
            report(error: error)
        }
    }

    private func report(error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error)
        }
    }

    private func disposeStreamingObjects() {
        if let audioQueue {
            AudioQueueStop(audioQueue, true)
            AudioQueueDispose(audioQueue, true)
            self.audioQueue = nil
        }

        if let audioFileStream {
            AudioFileStreamClose(audioFileStream)
            self.audioFileStream = nil
        }
    }

    private func osStatusError(_ status: OSStatus, fallback: String) -> NSError {
        NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: fallback]
        )
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        lock.lock()
        playbackRequested = false
        isPaused = false
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.legacyAudioPlayer = nil
            self.onPlaybackStateChanged?(false)
            self.onPlaybackFinished?()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard let error else { return }
        report(error: error)
    }

    private static let propertyListener: AudioFileStream_PropertyListenerProc = {
        userData, streamID, propertyID, _ in
        let player = Unmanaged<StreamingSpeechPlayer>.fromOpaque(userData).takeUnretainedValue()
        player.incrementCallbacksInFlight()
        defer { player.decrementCallbacksInFlight() }

        guard !player.isDisposed else { return }

        switch propertyID {
        case kAudioFileStreamProperty_DataFormat, kAudioFileStreamProperty_ReadyToProducePackets:
            player.createAudioQueueIfNeeded(streamID: streamID)
        default:
            break
        }
    }

    private static let packetsListener: AudioFileStream_PacketsProc = {
        userData, numberBytes, numberPackets, inputData, packetDescriptions in
        let player = Unmanaged<StreamingSpeechPlayer>.fromOpaque(userData).takeUnretainedValue()
        player.incrementCallbacksInFlight()
        defer { player.decrementCallbacksInFlight() }

        guard !player.isDisposed else { return }

        player.enqueuePackets(
            numberBytes: numberBytes,
            numberPackets: numberPackets,
            inputData: inputData,
            packetDescriptions: packetDescriptions
        )
    }

    private static let outputCallback: AudioQueueOutputCallback = {
        userData, queue, buffer in
        guard let userData else { return }
        let player = Unmanaged<StreamingSpeechPlayer>.fromOpaque(userData).takeUnretainedValue()
        player.incrementCallbacksInFlight()
        defer { player.decrementCallbacksInFlight() }

        guard !player.isDisposed else { return }

        player.bufferDidFinishPlaying(queue: queue, buffer: buffer)
    }
}
