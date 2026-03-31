# AI Chat → Claude CLI Harness Implementation Plan

## Overview

将 AI Chat 后端从 MiniMax HTTP API 替换为本地 Claude CLI 子进程，通过 `Process` 启动 `claude -p --output-format stream-json` 实现流式对话。保留 Claude CLI 完整 agentic 能力（文件读写、Bash 执行），显示精确 token/花费，展示 thinking 和工具调用过程。

## Current State Analysis

### Key Discoveries:
- `AIChatView.swift` (~390 行) 紧耦合 `MiniMaxAPIClient` + `MiniMaxSettingsStore`
- 消息模型为简单元组 `(role: String, content: String)`，无法承载 thinking/tool 信息
- `ContentView.swift:529` 路由 `"AI Chat"` → `AIChatView()`
- `MiniMaxSettingsStore` 使用 `@Observable`（非 `ObservableObject`），新 settings store 需匹配
- `HistoryStore` 是 actor，`ChatHistoryRecord` 字段固定（无 cost/thinking 字段）
- `ToolRegistry.defaults` 当前 10 个工具，测试断言 count=10 且名称集合精确匹配
- Claude CLI v2.1.81 已安装，`--bare` 冷启动 ~1-3 秒
- 实测 NDJSON stream 包含: `system`(init), `stream_event`(deltas), `assistant`(snapshots), `result`(final with cost)

### NDJSON 真实格式（已验证）:
```
{"type":"system","subtype":"init","session_id":"...","model":"...","tools":[...]}
{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"..."}}}
{"type":"stream_event","event":{"type":"content_block_stop","index":0}}
{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"..."}}}
{"type":"stream_event","event":{"type":"content_block_stop","index":1}}
{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{...}}}
{"type":"stream_event","event":{"type":"message_stop"}}
{"type":"result","subtype":"success","total_cost_usd":0.093,"duration_ms":5420,"usage":{"input_tokens":230,"output_tokens":17,...},"session_id":"..."}
```

## Scope

### In Scope
- `ClaudeCLIClient.swift` — Process 封装 + NDJSON 解析
- `ClaudeCLISettingsStore.swift` — Claude CLI 专属配置（UserDefaults 持久化）
- `ClaudeCLISettingsView.swift` — 设置 UI
- `ClaudeChatView.swift` — 全新 Chat UI（thinking 折叠、工具调用指示、精确 cost）
- `HistoryStore.swift` 扩展 — `ClaudeChatHistoryRecord` + `ClaudeChatMessageRecord`
- `ContentView.swift` 路由更新
- `Tool.swift` 描述更新
- `CodeToolTests.swift` 测试更新

### Out of Scope
- AI Speech / AI Image / AI Music 不改动
- MiniMax 设置不删除（仍服务于其他 AI 工具）
- 多 tab 会话、对话导出
- MCP 服务器配置 UI
- 权限弹窗 UI

## Implementation Approach

采用 4 阶段增量推进：先搭核心基础设施（CLI 客户端 + 设置），再建数据模型（扩展 HistoryStore），然后实现 UI（新 ClaudeChatView），最后集成路由和测试。每阶段有独立验证点。

UI 设计方向：**Refined Terminal** — 在现有深色 teal/cyan 主题基础上，打造高级感开发者聊天体验：
- Thinking 区域：`surface` 卡片 + 左侧呼吸灯 cyan 竖线，流式时有脉搏动画，完成后可折叠
- 工具调用卡片：紧凑内联，tool icon + 名称头部，monospaced 输入/输出折叠展开，`surfaceRaised` 背景 + warm orange 左侧指示条
- Stop 按钮：coral 色胶囊按钮替代发送按钮，流式时脉搏动画
- 状态栏：model 名称(accent)、精确 cost(warm orange)、token 分布

---

## Phase 1: Core Infrastructure

### Overview
新建 `ClaudeCLIClient` 和 `ClaudeCLISettingsStore`，封装 CLI 进程管理和配置持久化。

### Changes Required:

#### 1. ClaudeCLISettingsStore.swift (新建)
**File**: `Sources/CodeToolCore/ClaudeCLISettingsStore.swift`
**Purpose**: Claude CLI 配置持久化，模式对齐 `MiniMaxSettingsStore`（`@Observable` 单例）

```swift
import Foundation
import Observation

@Observable
public final class ClaudeCLISettingsStore {
    public static let shared = ClaudeCLISettingsStore()

    private enum Keys {
        static let claudePath = "claudeCLI_path"
        static let apiKey = "claudeCLI_api_key"
        static let model = "claudeCLI_model"
        static let systemPrompt = "claudeCLI_system_prompt"
        static let maxTurns = "claudeCLI_max_turns"
        static let maxBudgetUSD = "claudeCLI_max_budget_usd"
        static let useBare = "claudeCLI_use_bare"
        static let workingDirectory = "claudeCLI_working_directory"
    }

    public var claudePath: String {
        didSet { UserDefaults.standard.set(claudePath, forKey: Keys.claudePath) }
    }
    public var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: Keys.apiKey) }
    }
    public var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Keys.model) }
    }
    public var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: Keys.systemPrompt) }
    }
    public var maxTurns: Int {
        didSet { UserDefaults.standard.set(maxTurns, forKey: Keys.maxTurns) }
    }
    public var maxBudgetUSD: Double {
        didSet { UserDefaults.standard.set(maxBudgetUSD, forKey: Keys.maxBudgetUSD) }
    }
    public var useBare: Bool {
        didSet { UserDefaults.standard.set(useBare, forKey: Keys.useBare) }
    }
    public var workingDirectory: String {
        didSet { UserDefaults.standard.set(workingDirectory, forKey: Keys.workingDirectory) }
    }

    /// Whether a valid claude binary has been discovered
    public var isAvailable: Bool { !resolvedClaudePath.isEmpty }

    /// Resolved path after discovery
    public var resolvedClaudePath: String = ""

    public static let availableModels = [
        "claude-sonnet-4-20250514",
        "claude-opus-4-20250514",
        "claude-haiku-3-5-20241022",
    ]

    private init() {
        let defaults = UserDefaults.standard
        self.claudePath = defaults.string(forKey: Keys.claudePath) ?? ""
        self.apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
        self.model = defaults.string(forKey: Keys.model) ?? "claude-sonnet-4-20250514"
        self.systemPrompt = defaults.string(forKey: Keys.systemPrompt) ?? ""
        self.maxTurns = defaults.object(forKey: Keys.maxTurns) as? Int ?? 10
        self.maxBudgetUSD = defaults.object(forKey: Keys.maxBudgetUSD) as? Double ?? 5.0
        self.useBare = defaults.object(forKey: Keys.useBare) as? Bool ?? true
        self.workingDirectory = defaults.string(forKey: Keys.workingDirectory)
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Discover claude binary. Call on app launch or settings change.
    public func discoverCLI() {
        let searchPaths: [String]
        if !claudePath.isEmpty {
            searchPaths = [claudePath]
        } else {
            searchPaths = [
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
                NSHomeDirectory() + "/.local/bin/claude",
                NSHomeDirectory() + "/.claude/local/claude",
            ]
        }

        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                resolvedClaudePath = path
                return
            }
        }

        // Fallback: which claude
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
                    resolvedClaudePath = path
                    return
                }
            }
        } catch {}

        resolvedClaudePath = ""
    }

    public func resetToDefaults() {
        claudePath = ""
        apiKey = ""
        model = "claude-sonnet-4-20250514"
        systemPrompt = ""
        maxTurns = 10
        maxBudgetUSD = 5.0
        useBare = true
        workingDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        discoverCLI()
    }
}
```

#### 2. ClaudeCLIClient.swift (新建)
**File**: `Sources/CodeToolCore/ClaudeCLIClient.swift`
**Purpose**: Claude CLI 子进程封装 + NDJSON 流解析

关键设计决策：
- 一次 `send()` = 一个完整 Process 生命周期
- 回调式 API 而非 AsyncStream（与现有 `chatCompletionStream` onDelta 模式对齐）
- 支持 cancel() 中断（SIGTERM）
- NDJSON 解析使用泛型 JSON 解码（`[String: Any]` 字典而非强类型，因为 CLI 格式可能变化）

```swift
import Foundation

/// Events emitted by the Claude CLI NDJSON stream.
public enum ClaudeCLIEvent {
    /// Session initialized with session ID and model name
    case initialized(sessionId: String, model: String)
    /// Thinking content delta
    case thinkingDelta(text: String)
    /// Text content delta (main streaming source)
    case textDelta(text: String)
    /// Tool use started
    case toolUseStart(id: String, name: String)
    /// Tool input JSON delta
    case toolInputDelta(text: String)
    /// Tool result received
    case toolResult(toolUseId: String, content: String)
    /// Content block completed
    case blockStop(index: Int)
    /// Final result with cost/usage
    case result(
        isError: Bool,
        totalCostUSD: Double,
        inputTokens: Int,
        outputTokens: Int,
        durationMs: Int,
        sessionId: String
    )
    /// Process exited
    case completed(exitCode: Int32)
    /// Error from stderr or process failure
    case error(message: String)
}

public final class ClaudeCLIClient {
    private var process: Process?
    private var isCancelled = false

    public init() {}

    /// Send a message to Claude CLI and receive streaming events via callback.
    /// This method blocks until the CLI process exits.
    public func send(
        message: String,
        settings: ClaudeCLISettingsStore,
        sessionId: String?,
        onEvent: @escaping @Sendable (ClaudeCLIEvent) -> Void
    ) async {
        isCancelled = false

        let claudePath = settings.resolvedClaudePath
        guard !claudePath.isEmpty else {
            onEvent(.error(message: "Claude CLI not found"))
            onEvent(.completed(exitCode: -1))
            return
        }

        var arguments = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--model", settings.model,
            "--max-turns", String(settings.maxTurns),
        ]

        if settings.maxBudgetUSD > 0 {
            arguments += ["--max-budget-usd", String(settings.maxBudgetUSD)]
        }

        if settings.useBare {
            arguments.append("--bare")
        }

        if let sessionId, !sessionId.isEmpty {
            arguments += ["--session-id", sessionId]
        }

        let trimmedSystemPrompt = settings.systemPrompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSystemPrompt.isEmpty {
            arguments += ["--append-system-prompt", trimmedSystemPrompt]
        }

        // User message is the last positional argument
        arguments.append(message)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claudePath)
        proc.arguments = arguments

        // Working directory
        let cwd = settings.workingDirectory
        if FileManager.default.fileExists(atPath: cwd) {
            proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        // Environment: only pass API key if set
        var env = ProcessInfo.processInfo.environment
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            env["ANTHROPIC_API_KEY"] = apiKey
        }
        proc.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        self.process = proc

        do {
            try proc.run()
        } catch {
            onEvent(.error(message: "Failed to launch Claude CLI: \(error.localizedDescription)"))
            onEvent(.completed(exitCode: -1))
            return
        }

        // Read stdout line by line on a background thread
        let fileHandle = stdoutPipe.fileHandleForReading

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let bufferSize = 65536
                var leftover = Data()

                while true {
                    let data = fileHandle.availableData
                    if data.isEmpty { break } // EOF

                    leftover.append(data)

                    // Split by newlines
                    while let newlineIndex = leftover.firstIndex(of: UInt8(ascii: "\n")) {
                        let lineData = leftover[leftover.startIndex..<newlineIndex]
                        leftover = Data(leftover[leftover.index(after: newlineIndex)...])

                        guard !lineData.isEmpty else { continue }

                        self?.parseLine(lineData, onEvent: onEvent)
                    }
                }

                // Process remaining data
                if !leftover.isEmpty {
                    self?.parseLine(leftover, onEvent: onEvent)
                }

                proc.waitUntilExit()

                // Read stderr
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if !stderrData.isEmpty,
                   let stderrText = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !stderrText.isEmpty {
                    onEvent(.error(message: stderrText))
                }

                onEvent(.completed(exitCode: proc.terminationStatus))
                continuation.resume()
            }
        }

        self.process = nil
    }

    /// Cancel the current Claude CLI process.
    public func cancel() {
        isCancelled = true
        process?.terminate()
    }

    // MARK: - NDJSON Parsing

    private func parseLine(_ data: Data, onEvent: @escaping (ClaudeCLIEvent) -> Void) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "system":
            if let subtype = json["subtype"] as? String, subtype == "init" {
                let sessionId = json["session_id"] as? String ?? ""
                let model = json["model"] as? String ?? ""
                onEvent(.initialized(sessionId: sessionId, model: model))
            }

        case "stream_event":
            guard let event = json["event"] as? [String: Any],
                  let eventType = event["type"] as? String else { return }

            switch eventType {
            case "content_block_start":
                if let block = event["content_block"] as? [String: Any],
                   let blockType = block["type"] as? String {
                    if blockType == "tool_use" {
                        let id = block["id"] as? String ?? ""
                        let name = block["name"] as? String ?? ""
                        onEvent(.toolUseStart(id: id, name: name))
                    }
                }

            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any],
                   let deltaType = delta["type"] as? String {
                    switch deltaType {
                    case "thinking_delta":
                        if let text = delta["thinking"] as? String {
                            onEvent(.thinkingDelta(text: text))
                        }
                    case "text_delta":
                        if let text = delta["text"] as? String {
                            onEvent(.textDelta(text: text))
                        }
                    case "input_json_delta":
                        if let text = delta["partial_json"] as? String {
                            onEvent(.toolInputDelta(text: text))
                        }
                    default:
                        break
                    }
                }

            case "content_block_stop":
                let index = event["index"] as? Int ?? -1
                onEvent(.blockStop(index: index))

            default:
                break
            }

        case "result":
            let isError = json["is_error"] as? Bool ?? false
            let cost = json["total_cost_usd"] as? Double ?? 0.0
            let durationMs = json["duration_ms"] as? Int ?? 0
            let sessionId = json["session_id"] as? String ?? ""

            var inputTokens = 0
            var outputTokens = 0
            if let usage = json["usage"] as? [String: Any] {
                inputTokens = usage["input_tokens"] as? Int ?? 0
                outputTokens = usage["output_tokens"] as? Int ?? 0
            }

            onEvent(.result(
                isError: isError,
                totalCostUSD: cost,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                durationMs: durationMs,
                sessionId: sessionId
            ))

        default:
            break // Ignore "assistant" snapshot messages etc.
        }
    }
}
```

### Success Criteria:

#### Automated Verification:
- [x] `swift build` 编译通过（新增 2 个文件不破坏现有代码）
- [ ] `swift test --filter CodeToolTests/testRegistryContainsTenTools` 仍然通过（尚未改动 registry）

#### Manual Verification:
- [ ] `ClaudeCLISettingsStore.shared.discoverCLI()` 后 `resolvedClaudePath` 非空（前提: claude 已安装）
- [ ] 在 playground 或临时测试中调用 `ClaudeCLIClient().send(...)` 能收到 `.initialized` 和 `.textDelta` 事件

---

## Phase 2: Data Models & History

### Overview
扩展 `HistoryStore` 以支持 Claude Chat 的丰富数据模型（thinking、tool calls、cost）。为避免破坏现有 `ChatHistoryRecord` 的 JSON 兼容性，新建独立的 `ClaudeChatHistoryRecord`。

### Changes Required:

#### 1. HistoryStore.swift — 新增模型和存储方法
**File**: `Sources/CodeToolCore/HistoryStore.swift`

在文件顶部（`ChatMessageRecord` 之后）新增：

```swift
// MARK: - Claude Chat History Models

/// Role for Claude chat messages.
public enum ClaudeMessageRole: String, Codable {
    case user
    case assistant
    case toolUse
    case toolResult
}

/// A single message in a Claude chat conversation.
public struct ClaudeChatMessageRecord: Codable {
    public let role: String
    public let content: String
    public let thinkingContent: String?
    public let toolName: String?
    public let toolInput: String?

    public init(
        role: String,
        content: String,
        thinkingContent: String? = nil,
        toolName: String? = nil,
        toolInput: String? = nil
    ) {
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.toolName = toolName
        self.toolInput = toolInput
    }
}

/// History record for a Claude CLI chat session.
public struct ClaudeChatHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let systemPrompt: String?
    public let messages: [ClaudeChatMessageRecord]
    public let model: String
    public let totalCostUSD: Double?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let durationMs: Int?
    public let sessionId: String?
    public let referenceID: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        systemPrompt: String? = nil,
        messages: [ClaudeChatMessageRecord],
        model: String,
        totalCostUSD: Double? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        durationMs: Int? = nil,
        sessionId: String? = nil,
        referenceID: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.model = model
        self.totalCostUSD = totalCostUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.durationMs = durationMs
        self.sessionId = sessionId
        self.referenceID = referenceID
    }
}

extension ClaudeChatHistoryRecord: HistoryRecord {}
```

在 `HistoryCategory` enum 中新增 `claudeChat` case:

```swift
public enum HistoryCategory: String, CaseIterable {
    case chat
    case claudeChat = "claude-chat"
    case speech
    case image
    case music
}
```

在 `HistoryStore` actor 中新增存储方法:

```swift
public func save(_ record: ClaudeChatHistoryRecord) throws {
    let dir = try categoryURL(.claudeChat)
    let data = try encoder.encode(record)
    try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
}

public func listClaudeChat() throws -> [ClaudeChatHistoryRecord] {
    try loadRecords(category: .claudeChat)
}

public func deleteClaudeChat(id: UUID) throws {
    let dir = try categoryURL(.claudeChat)
    let jsonURL = dir.appendingPathComponent("\(id.uuidString).json")
    try? fileManager.removeItem(at: jsonURL)
}
```

#### 2. AppLogger.swift — 新增 category (可选但推荐)
**File**: `Sources/CodeToolCore/AppLogger.swift`

如果想区分 Claude Chat 日志可新增 `.claudeChat` case，但也可以复用 `.aichat`。推荐新增以保持日志清晰:

```swift
public enum AppLogCategory: String, Codable {
    case aimusic
    case aispeech
    case aiimage
    case aichat
    case claudechat  // 新增
}
```

### Success Criteria:

#### Automated Verification:
- [x] `swift build` 编译通过
- [ ] 现有测试全部通过（`ChatHistoryRecord` 不受影响）

#### Manual Verification:
- [ ] 创建 `ClaudeChatHistoryRecord` 实例并通过 `HistoryStore.shared.save()` 持久化，然后 `listClaudeChat()` 能取回

---

## Phase 3: Chat UI (ClaudeChatView)

### Overview
新建 `ClaudeChatView.swift`，实现完整的 Claude Chat 界面。这是本计划最大的文件，包含消息模型、流式渲染、thinking 折叠、工具调用指示器、精确 cost 显示。

### UI Design Specification

**美学方向: Refined Terminal**

延续现有深色 teal/cyan 主题：
- **背景**: 使用 `AppTheme.background` / `AppTheme.surface`
- **用户消息气泡**: `accent.opacity(0.12)` 背景 + `accent.opacity(0.22)` 描边（现有风格）
- **助手消息气泡**: `surface` 背景 + `border` 描边（现有风格）
- **Thinking 区域**: 嵌在助手消息内部，`surfaceRaised` 背景，左侧 3px cyan 竖线（流式时有呼吸动画），斜体文字 `textMuted` 色，可折叠 DisclosureGroup
- **工具调用卡片**: 独立于消息气泡的紧凑条目，`surface` 背景 + 左侧 3px warm orange 竖线，图标 + 工具名 + 折叠式参数/结果
- **Stop 按钮**: 替代发送按钮位置，`error` (coral) 色胶囊，流式时显示
- **状态栏**: model 名称标签(accent), 精确 `$X.XX`(accentWarm), `↑N ↓N tokens`(textMuted)
- **空状态**: "Chat with Claude" 标题 + "Send a message to start a conversation with Claude CLI" 副标题

### Changes Required:

#### 1. ClaudeChatView.swift (新建)
**File**: `Sources/CodeToolCore/ClaudeChatView.swift`

View Model 状态:

```swift
/// A single chat message for the Claude chat UI.
struct ClaudeChatMessage: Identifiable {
    let id = UUID()
    let role: ClaudeMessageRole
    var content: String
    var thinkingContent: String?
    var toolName: String?
    var toolInput: String?
    var isStreaming: Bool

    enum ClaudeMessageRole {
        case user
        case assistant
        case toolUse
        case toolResult
    }
}
```

ClaudeChatView 主要 @State:

```swift
@State private var messages: [ClaudeChatMessage] = []
@State private var inputText: String = ""
@State private var isStreaming: Bool = false
@State private var streamingText: String = ""
@State private var streamingThinking: String = ""
@State private var currentToolName: String = ""
@State private var currentToolInput: String = ""
@State private var errorMessage: String = ""
@State private var sessionId: String = UUID().uuidString
@State private var currentModel: String = ""
@State private var totalCostUSD: Double = 0.0
@State private var inputTokens: Int = 0
@State private var outputTokens: Int = 0
@State private var showThinking: Set<UUID> = []  // IDs of messages with expanded thinking
```

核心结构布局（与 AIChatView 一致的 ToolWorkbench 外壳）:

```swift
ToolWorkbench(
    eyebrow: "Claude CLI",
    title: "AI Chat",
    description: "Chat with Claude — full agentic capabilities",
    systemImage: "bubble.left.and.bubble.right",
    statusItems: statusItems
) {
    // Actions
    StyledButton("Clear Chat", systemImage: "trash", variant: .ghost) { clearChat() }
    CopyButton("Copy Last", text: lastAssistantReply)
} content: {
    VStack(spacing: 0) {
        // CLI not found warning
        if !settings.isAvailable { notInstalledBanner }

        // Error banner
        if !errorMessage.isEmpty { errorBanner }

        // Message list
        messageListView

        // Input area
        inputArea
    }
}
```

消息气泡 — 用户消息（复用现有风格）:

```swift
@ViewBuilder
private func userBubble(_ message: ClaudeChatMessage) -> some View {
    HStack {
        Spacer(minLength: 60)
        VStack(alignment: .trailing, spacing: AppTheme.Spacing.xxs) {
            Text("You")
                .font(.caption2).fontWeight(.semibold).textCase(.uppercase)
                .foregroundColor(AppTheme.accent)
            Text(message.content)
                .font(.body)
                .foregroundColor(AppTheme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .fill(AppTheme.accent.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .strokeBorder(AppTheme.accent.opacity(0.22), lineWidth: 1)
                )
        }
    }
}
```

消息气泡 — 助手消息（含 thinking 折叠）:

```swift
@ViewBuilder
private func assistantBubble(_ message: ClaudeChatMessage) -> some View {
    HStack {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            Text("Claude")
                .font(.caption2).fontWeight(.semibold).textCase(.uppercase)
                .foregroundColor(AppTheme.accentWarm)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                // Thinking section (collapsible)
                if let thinking = message.thinkingContent, !thinking.isEmpty {
                    thinkingBlock(thinking, messageId: message.id, isStreaming: message.isStreaming)
                }

                // Main text content
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.body)
                        .foregroundColor(AppTheme.textPrimary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )
        }
        Spacer(minLength: 60)
    }
}
```

Thinking 折叠区域（核心 UI 创新点）:

```swift
@ViewBuilder
private func thinkingBlock(_ text: String, messageId: UUID, isStreaming: Bool) -> some View {
    let isExpanded = showThinking.contains(messageId) || isStreaming

    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
        Button {
            withAnimation(AppTheme.Anim.normal) {
                if showThinking.contains(messageId) {
                    showThinking.remove(messageId)
                } else {
                    showThinking.insert(messageId)
                }
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                Text(isStreaming ? "Thinking…" : "Thinking")
                    .font(.caption2).fontWeight(.semibold)
                if isStreaming {
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 6, height: 6)
                        .opacity(0.8)
                        .modifier(PulseModifier())
                }
            }
            .foregroundColor(AppTheme.textMuted)
        }
        .buttonStyle(.plain)

        if isExpanded {
            HStack(spacing: 0) {
                // Left accent bar
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isStreaming ? AppTheme.accent : AppTheme.accent.opacity(0.4))
                    .frame(width: 3)
                    .modifier(isStreaming ? AnyViewModifier(BreathingModifier()) : AnyViewModifier(StaticModifier()))

                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .italic()
                    .foregroundColor(AppTheme.textMuted)
                    .textSelection(.enabled)
                    .padding(.leading, AppTheme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(AppTheme.surfaceRaised.opacity(0.6))
            )
        }
    }
}
```

工具调用指示器:

```swift
@ViewBuilder
private func toolUseCard(_ message: ClaudeChatMessage) -> some View {
    HStack(spacing: 0) {
        // Left warm orange indicator
        RoundedRectangle(cornerRadius: 1.5)
            .fill(AppTheme.accentWarm)
            .frame(width: 3, height: nil)

        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: toolIcon(for: message.toolName ?? ""))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.accentWarm)
                Text(message.toolName ?? "Tool")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                if message.isStreaming {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }
            }

            if let input = message.toolInput, !input.isEmpty {
                Text(input)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AppTheme.textMuted)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
    }
    .background(
        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
            .fill(AppTheme.surface.opacity(0.8))
    )
    .overlay(
        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
            .strokeBorder(AppTheme.border, lineWidth: 1)
    )
}

private func toolIcon(for name: String) -> String {
    switch name.lowercased() {
    case "bash": return "terminal"
    case "read": return "doc.text"
    case "write", "edit": return "pencil.line"
    case "glob": return "folder.badge.gearshape"
    case "grep": return "magnifyingglass"
    default: return "wrench"
    }
}
```

输入区域（含 Stop 按钮）:

```swift
private var inputArea: some View {
    HStack(alignment: .bottom, spacing: AppTheme.Spacing.sm) {
        // Text input (same as existing AIChatView)
        ZStack(alignment: .topLeading) {
            if inputText.isEmpty {
                Text("Type a message…")
                    .font(.body)
                    .foregroundColor(AppTheme.textMuted)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
            TextEditor(text: $inputText)
                .font(.body)
                .foregroundColor(AppTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, AppTheme.Spacing.xs)
                .padding(.vertical, AppTheme.Spacing.xs)
        }
        .frame(minHeight: 36, maxHeight: 120)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                .fill(AppTheme.background.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )

        if isStreaming {
            // Stop button
            StyledButton("Stop", systemImage: "stop.fill", variant: .destructive) {
                client.cancel()
            }
        } else {
            // Send button
            StyledIconButton("paperplane.fill", help: "Send message") {
                sendMessage()
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
        }
    }
    .padding(.horizontal, AppTheme.Spacing.xxl)
    .padding(.top, AppTheme.Spacing.md)
    .padding(.bottom, AppTheme.Spacing.xxl)
}
```

sendMessage() 核心逻辑:

```swift
private func sendMessage() {
    let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !isStreaming else { return }

    messages.append(ClaudeChatMessage(role: .user, content: trimmed, isStreaming: false))
    inputText = ""
    errorMessage = ""
    isStreaming = true
    streamingText = ""
    streamingThinking = ""

    Task {
        await client.send(
            message: trimmed,
            settings: settings,
            sessionId: sessionId
        ) { event in
            Task { @MainActor in
                handleEvent(event)
            }
        }
    }
}

@MainActor
private func handleEvent(_ event: ClaudeCLIEvent) {
    switch event {
    case .initialized(let sid, let model):
        if sessionId.isEmpty || sessionId != sid {
            sessionId = sid
        }
        currentModel = model

    case .thinkingDelta(let text):
        streamingThinking += text

    case .textDelta(let text):
        streamingText += text

    case .toolUseStart(let id, let name):
        // Finalize any pending streaming text as assistant message
        finalizeStreamingAssistantIfNeeded()
        currentToolName = name
        currentToolInput = ""
        messages.append(ClaudeChatMessage(
            role: .toolUse, content: "", toolName: name,
            toolInput: "", isStreaming: true
        ))

    case .toolInputDelta(let text):
        currentToolInput += text
        if var last = messages.last, last.role == .toolUse {
            messages[messages.count - 1].toolInput = currentToolInput
        }

    case .blockStop:
        // Mark tool use as done
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == .toolUse,
           messages[lastIndex].isStreaming {
            messages[lastIndex].isStreaming = false
        }

    case .result(let isError, let cost, let inTok, let outTok, let duration, let sid):
        finalizeStreamingAssistantIfNeeded()
        totalCostUSD += cost
        inputTokens += inTok
        outputTokens += outTok
        isStreaming = false

        if isError {
            errorMessage = "Claude returned an error."
        }

        // Save history
        saveHistory()

    case .completed(let exitCode):
        if exitCode != 0 && !isCancelled(exitCode) {
            finalizeStreamingAssistantIfNeeded()
            isStreaming = false
        }

    case .error(let message):
        if isStreaming {
            finalizeStreamingAssistantIfNeeded()
            isStreaming = false
        }
        errorMessage = message
    }
}

private func finalizeStreamingAssistantIfNeeded() {
    guard !streamingText.isEmpty || !streamingThinking.isEmpty else { return }
    messages.append(ClaudeChatMessage(
        role: .assistant,
        content: streamingText,
        thinkingContent: streamingThinking.isEmpty ? nil : streamingThinking,
        isStreaming: false
    ))
    streamingText = ""
    streamingThinking = ""
}
```

动画 modifier（呼吸灯效果）:

```swift
private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

private struct BreathingModifier: ViewModifier {
    @State private var isBreathing = false

    func body(content: Content) -> some View {
        content
            .opacity(isBreathing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: isBreathing
            )
            .onAppear { isBreathing = true }
    }
}
```

#### 2. ClaudeCLISettingsView.swift (新建)
**File**: `Sources/CodeToolCore/ClaudeCLISettingsView.swift`

结构与 `MiniMaxSettingsView` 对齐（ToolWorkbench 外壳 + StyledPanel 分区）:

```swift
public struct ClaudeCLISettingsView: View {
    @Bindable private var settings = ClaudeCLISettingsStore.shared

    public init() {}

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Configuration",
            title: "Claude CLI Settings",
            description: "Configure Claude CLI for AI Chat.",
            systemImage: "terminal",
            statusItems: [
                ToolStatusItem(
                    title: settings.isAvailable ? "CLI Found" : "CLI Not Found",
                    systemImage: settings.isAvailable ? "checkmark.circle" : "xmark.circle",
                    tint: settings.isAvailable ? AppTheme.success : AppTheme.error
                )
            ]
        ) {
            StyledButton("Reset Defaults", systemImage: "arrow.counterclockwise", variant: .ghost) {
                settings.resetToDefaults()
            }
            StyledButton("Detect CLI", systemImage: "magnifyingglass", variant: .primary) {
                settings.discoverCLI()
            }
        } content: {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    cliPathSection
                    apiKeySection
                    modelSection
                    limitsSection
                    systemPromptSection
                    workingDirectorySection
                }
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.top, AppTheme.Spacing.xl)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
    }
}
```

各分区内容:

- **CLI Path**: TextField `settings.claudePath`, 下方显示 resolved path 状态
- **API Key**: SecureField + eye toggle（与 MiniMaxSettingsView 相同模式）
- **Model**: Picker 从 `ClaudeCLISettingsStore.availableModels` 选择
- **Limits**: maxTurns (Stepper), maxBudgetUSD (TextField), useBare (Toggle)
- **System Prompt**: 多行 StyledTextEditor
- **Working Directory**: TextField + 目录选择按钮（NSOpenPanel）

### Success Criteria:

#### Automated Verification:
- [x] `swift build` 编译通过

#### Manual Verification:
- [ ] ClaudeChatView 独立渲染正常（可在 Preview 中验证空状态）
- [ ] Thinking 折叠展开交互流畅
- [ ] 工具调用卡片以正确图标和 warm orange 左侧条显示
- [ ] Stop 按钮在流式中可见，点击后流式中断
- [ ] 状态栏显示 model, cost, token 分布

---

## Phase 4: Integration & Tests

### Overview
路由更新、ToolRegistry 描述修改、ContentView 导航、测试更新。

### Changes Required:

#### 1. Tool.swift — 更新 AI Chat 描述
**File**: `Sources/CodeToolCore/Tool.swift`

```swift
// Before:
Tool(
    name: "AI Chat", description: "Chat with MiniMax M2.7-highspeed AI model.",
    systemImage: "bubble.left.and.bubble.right", category: .aiTools),

// After:
Tool(
    name: "AI Chat", description: "Chat with Claude — full agentic capabilities via CLI.",
    systemImage: "bubble.left.and.bubble.right", category: .aiTools),
```

#### 2. ContentView.swift — 路由更新
**File**: `Sources/CodeToolCore/ContentView.swift`

在 `ToolDetailView` 的 switch 中修改:

```swift
// Before:
case "AI Chat":
    AIChatView()

// After:
case "AI Chat":
    ClaudeChatView()
```

在 `MiniMaxSettingsSheet` 体中新增 Claude CLI 设置入口（或独立 sheet）。推荐在 sidebar 底部 gear 按钮的 `.sheet` 中提供两个 tab:

```swift
private struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = "minimax"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $selectedTab) {
                    Text("MiniMax").tag("minimax")
                    Text("Claude CLI").tag("claude")
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(AppTheme.Spacing.md)

            if selectedTab == "minimax" {
                MiniMaxSettingsView()
            } else {
                ClaudeCLISettingsView()
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(AppTheme.background)
    }
}
```

将 sidebar 中引用 `MiniMaxSettingsSheet()` 替换为 `SettingsSheet()`。

#### 3. ContentView.swift — 在 app 启动时 discover CLI

在 `ContentView.onAppear` 中添加:

```swift
.onAppear {
    ClaudeCLISettingsStore.shared.discoverCLI()
    // ...existing code
}
```

#### 4. CodeToolTests.swift — 更新测试

**File**: `Tests/CodeToolTests/CodeToolTests.swift`

工具数量不变（仍为 10），但需更新描述相关测试（如果有的话）。当前测试只检查 count 和名称集合，所以主要确认不需要改 count。

需新增测试:
```swift
func testClaudeCLISettingsStoreDefaults() {
    let store = ClaudeCLISettingsStore.shared
    XCTAssertEqual(store.model, "claude-sonnet-4-20250514")
    XCTAssertEqual(store.maxTurns, 10)
    XCTAssertEqual(store.maxBudgetUSD, 5.0)
    XCTAssertTrue(store.useBare)
}

func testClaudeChatHistoryRecordCodable() throws {
    let record = ClaudeChatHistoryRecord(
        messages: [
            ClaudeChatMessageRecord(role: "user", content: "Hello"),
            ClaudeChatMessageRecord(role: "assistant", content: "Hi",
                                    thinkingContent: "User says hello")
        ],
        model: "claude-sonnet-4-20250514",
        totalCostUSD: 0.05,
        inputTokens: 100,
        outputTokens: 10,
        referenceID: "test-ref"
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(record)
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(ClaudeChatHistoryRecord.self, from: data)

    XCTAssertEqual(decoded.id, record.id)
    XCTAssertEqual(decoded.messages.count, 2)
    XCTAssertEqual(decoded.messages[1].thinkingContent, "User says hello")
    XCTAssertEqual(decoded.totalCostUSD, 0.05)
}
```

### Success Criteria:

#### Automated Verification:
- [x] `swift build` 编译通过
- [ ] `swift test --filter CodeToolTests/testRegistryContainsTenTools` 通过
- [ ] `swift test --filter CodeToolTests/testRegistryContainsExpectedTools` 通过
- [ ] `swift test --filter CodeToolTests/testClaudeCLISettingsStoreDefaults` 通过
- [ ] `swift test --filter CodeToolTests/testClaudeChatHistoryRecordCodable` 通过

#### Manual Verification:
- [ ] 侧边栏 "AI Chat" → 显示新的 ClaudeChatView（eyebrow 显示 "Claude CLI"）
- [ ] Claude CLI 未安装时显示 ToolMessageBanner 安装引导
- [ ] 发送消息 → 流式渲染文字 → thinking 折叠 → token/cost 显示
- [ ] 工具调用（如 Bash/Read）在消息中以折叠卡片显示
- [ ] Stop 按钮中断流式，已接收内容保留
- [ ] Settings gear → 显示 MiniMax / Claude CLI 两个 tab
- [ ] AI Speech / AI Image / AI Music 功能不受影响

---

## File Summary

### New Files (4):
| File | LOC (est.) | Purpose |
|------|-----------|---------|
| `ClaudeCLISettingsStore.swift` | ~130 | 配置持久化 |
| `ClaudeCLIClient.swift` | ~250 | CLI 进程封装 + NDJSON 解析 |
| `ClaudeChatView.swift` | ~550 | 完整 Chat UI |
| `ClaudeCLISettingsView.swift` | ~200 | 设置 UI |

### Modified Files (5):
| File | Change | Scope |
|------|--------|-------|
| `HistoryStore.swift` | 新增 models + save/list/delete 方法 | ~80 行新增 |
| `AppLogger.swift` | 新增 `.claudechat` category | 1 行 |
| `Tool.swift` | 更新 "AI Chat" 描述 | 1 行 |
| `ContentView.swift` | 路由更新 + Settings sheet 改造 + onAppear | ~40 行修改 |
| `CodeToolTests.swift` | 新增 2 个测试 | ~40 行新增 |

### Untouched (existing AI tools):
- `AIChatView.swift` — 保留作为 legacy/备份，不再被路由引用
- `MiniMaxAPIClient.swift` — 不修改
- `MiniMaxProvider.swift` — 不修改
- `MiniMaxSettingsView.swift` — 不修改
- `AISpeechView.swift`, `AIImageView.swift`, `AIMusicView.swift` — 不修改

## Testing Strategy

### Unit Tests
- `ClaudeCLISettingsStore` 默认值
- `ClaudeChatHistoryRecord` Codable roundtrip
- `ToolRegistry` count 和名称集合（不变）

### Manual Testing Steps:
1. 启动 app → 侧边栏 "AI Chat" → 确认 eyebrow 显示 "Claude CLI"
2. 发送 "hello" → 验证 thinking 折叠出现 → 文本流式渲染 → cost 显示
3. 发送 "list files in current directory" → 验证 Bash 工具调用卡片出现
4. 点击 Stop → 验证流式中断 + 部分内容保留
5. Settings → Claude CLI tab → 修改模型 → 新对话使用新模型
6. 切换到 AI Speech/Image/Music → 验证功能正常

## References

- Spec: `thoughts/shared/specs/2026-03-31-ai-chat-claude-cli-harness.md`
- Existing chat UI: `Sources/CodeToolCore/AIChatView.swift`
- Settings pattern: `Sources/CodeToolCore/MiniMaxProvider.swift`
- History store: `Sources/CodeToolCore/HistoryStore.swift`
- Theme tokens: `Sources/CodeToolCore/Theme.swift`
- Shared components: `Sources/CodeToolCore/StyledComponents.swift`
- Workbench shell: `Sources/CodeToolCore/ToolWorkbench.swift`
