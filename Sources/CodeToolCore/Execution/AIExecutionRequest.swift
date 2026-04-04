import Foundation

/// Typed payload for each AI tool's execution request.
public enum AIExecutionPayload: Sendable {
    case chat(ChatExecutionPayload)
    case speech(SpeechExecutionPayload)
    case image(ImageExecutionPayload)
    case music(MusicExecutionPayload)
    case claudeChat(ClaudeChatExecutionPayload)
}

/// Payload for MiniMax chat completions.
public struct ChatExecutionPayload: Sendable {
    public let messages: [(role: String, content: String)]
    public let systemPrompt: String?
    public let temperature: Double
    public let maxTokens: Int

    public init(
        messages: [(role: String, content: String)],
        systemPrompt: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 2048
    ) {
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

/// Payload for MiniMax speech generation.
public struct SpeechExecutionPayload: Sendable {
    public let text: String
    public let voiceId: String
    public let speed: Double
    public let volume: Double
    public let pitch: Int
    public let format: String

    public init(
        text: String,
        voiceId: String,
        speed: Double = 1.0,
        volume: Double = 1.0,
        pitch: Int = 0,
        format: String = "mp3"
    ) {
        self.text = text
        self.voiceId = voiceId
        self.speed = speed
        self.volume = volume
        self.pitch = pitch
        self.format = format
    }
}

/// Payload for MiniMax image generation.
public struct ImageExecutionPayload: Sendable {
    public let prompt: String
    public let aspectRatio: String?
    public let width: Int?
    public let height: Int?
    public let imageCount: Int
    public let seed: Int?
    public let promptOptimizer: Bool
    public let referenceImageData: [Data]

    public init(
        prompt: String,
        aspectRatio: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        imageCount: Int = 1,
        seed: Int? = nil,
        promptOptimizer: Bool = false,
        referenceImageData: [Data] = []
    ) {
        self.prompt = prompt
        self.aspectRatio = aspectRatio
        self.width = width
        self.height = height
        self.imageCount = imageCount
        self.seed = seed
        self.promptOptimizer = promptOptimizer
        self.referenceImageData = referenceImageData
    }
}

/// Payload for MiniMax music generation.
public struct MusicExecutionPayload: Sendable {
    public let prompt: String
    public let lyrics: String?
    public let isInstrumental: Bool
    public let format: String
    public let sampleRate: Int
    public let bitrate: Int

    public init(
        prompt: String,
        lyrics: String? = nil,
        isInstrumental: Bool = false,
        format: String = "mp3",
        sampleRate: Int = 44100,
        bitrate: Int = 256000
    ) {
        self.prompt = prompt
        self.lyrics = lyrics
        self.isInstrumental = isInstrumental
        self.format = format
        self.sampleRate = sampleRate
        self.bitrate = bitrate
    }
}

/// Payload for Claude CLI chat.
public struct ClaudeChatExecutionPayload: Sendable {
    public let prompt: String
    public let sessionID: String?
    public let workingDirectory: String

    public init(
        prompt: String,
        sessionID: String? = nil,
        workingDirectory: String
    ) {
        self.prompt = prompt
        self.sessionID = sessionID
        self.workingDirectory = workingDirectory
    }
}

/// Normalized input for one AI operation.
public struct AIExecutionRequest: Sendable {
    public let tool: AIExecutionTool
    public let payload: AIExecutionPayload
    public let referenceID: String

    public init(
        tool: AIExecutionTool,
        payload: AIExecutionPayload,
        referenceID: String? = nil
    ) {
        self.tool = tool
        self.payload = payload
        self.referenceID = referenceID ?? UUID().uuidString.lowercased()
    }
}
