import Foundation

private actor ChatExecutionTranscriptBuffer {
    private var value = ""

    func append(_ delta: String) {
        value.append(delta)
    }

    func content() -> String {
        value
    }
}

public struct MiniMaxChatExecutionProvider: AIExecutionProviding {
    public typealias StreamChat = @Sendable (
        _ messages: [(role: String, content: String)],
        _ temperature: Double,
        _ maxTokens: Int,
        _ referenceID: String,
        _ onDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> Void

    public typealias ModelProvider = @Sendable () -> String

    private let streamChat: StreamChat
    private let modelProvider: ModelProvider

    public init(
        streamChat: @escaping StreamChat = { messages, temperature, maxTokens, referenceID, onDelta in
            let apiMessages = messages.map {
                MiniMaxAPIClient.ChatMessage(role: $0.role, content: $0.content)
            }

            try await MiniMaxAPIClient.shared.chatCompletionStream(
                messages: apiMessages,
                temperature: temperature,
                maxTokens: maxTokens,
                referenceID: referenceID
            ) { delta in
                Task {
                    await onDelta(delta)
                }
            }
        },
        modelProvider: @escaping ModelProvider = {
            MiniMaxSettingsStore.shared.chatModel
        }
    ) {
        self.streamChat = streamChat
        self.modelProvider = modelProvider
    }

    public func execute(
        request: AIExecutionRequest,
        emit: @escaping @Sendable (AIExecutionEvent) async -> Void
    ) async throws -> AIExecutionResult {
        guard case let .chat(payload) = request.payload else {
            throw AIExecutionFailure(
                message: "MiniMaxChatExecutionProvider only supports chat payloads.",
                domain: "MiniMaxChatExecutionProvider"
            )
        }

        var requestMessages: [(role: String, content: String)] = []
        let trimmedPrompt = payload.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedPrompt.isEmpty {
            requestMessages.append((role: "system", content: trimmedPrompt))
        }
        requestMessages.append(contentsOf: payload.messages)

        let startedAt = Date()
        let transcriptBuffer = ChatExecutionTranscriptBuffer()

        try await streamChat(
            requestMessages,
            payload.temperature,
            payload.maxTokens,
            request.referenceID
        ) { delta in
            await transcriptBuffer.append(delta)
            await emit(.delta(delta))
        }

        let assistantContent = await transcriptBuffer.content()

        let promptTokens = requestMessages.reduce(0) { $0 + ($1.content.count / 4) }
        let completionTokens = assistantContent.count / 4

        return AIExecutionResult(
            referenceID: request.referenceID,
            tool: .chat,
            startedAt: startedAt,
            completedAt: Date(),
            metadata: [
                "assistantContent": assistantContent,
                "promptTokens": String(promptTokens),
                "completionTokens": String(completionTokens),
                "totalTokens": String(promptTokens + completionTokens),
                "model": modelProvider(),
            ]
        )
    }
}
