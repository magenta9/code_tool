import Foundation

public struct ChatHistoryExecutionSink: AIExecutionHistorySink {
    public typealias ModelProvider = @Sendable () -> String
    public typealias RecordSaver = @Sendable (ChatHistoryRecord) async -> Void

    private let modelProvider: ModelProvider
    private let recordSaver: RecordSaver

    private static func persistRecord(_ record: ChatHistoryRecord) async {
        try? await HistoryStore.shared.upsert(record, using: ChatHistoryCodec())
    }

    init(
        modelProvider: @escaping ModelProvider = {
            MiniMaxSettingsStore.shared.chatModel
        },
        recordSaver: @escaping RecordSaver = { record in
            await ChatHistoryExecutionSink.persistRecord(record)
        }
    ) {
        self.modelProvider = modelProvider
        self.recordSaver = recordSaver
    }

    public func record(result: AIExecutionResult, request: AIExecutionRequest) async {
        guard request.tool == .chat, case let .chat(payload) = request.payload else {
            return
        }

        let assistantContent = result.metadata["assistantContent"] ?? ""
        let promptTokens = Int(result.metadata["promptTokens"] ?? "") ?? 0
        let completionTokens = Int(result.metadata["completionTokens"] ?? "") ?? 0
        let totalTokens = Int(result.metadata["totalTokens"] ?? "") ?? 0
        let model = result.metadata["model"] ?? modelProvider()

        let messageRecords =
            payload.messages.map { ChatMessageRecord(role: $0.role, content: $0.content) }
            + [ChatMessageRecord(role: "assistant", content: assistantContent)]

        let record = ChatHistoryRecord(
            id: UUID(),
            createdAt: result.completedAt,
            systemPrompt: payload.systemPrompt ?? "",
            messages: messageRecords,
            model: model,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens,
            referenceID: result.referenceID
        )

        await recordSaver(record)
    }
}
