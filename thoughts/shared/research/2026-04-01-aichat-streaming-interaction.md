---
date: 2026-04-01T17:05:15Z
researcher: Copilot
git_commit: 662379300f416e60f810d915ebba15d3508dd5d2
branch: main
repository: code_tool
topic: "调研 aichat 工具是否实现流式传输交互"
tags: [research, codebase, aichat, streaming, claude-cli, minimax]
status: complete
last_updated: 2026-04-01
last_updated_by: Copilot
---

# Research: 调研 aichat 工具是否实现流式传输交互

**Date**: 2026-04-01T17:05:15Z
**Git Commit**: `662379300f416e60f810d915ebba15d3508dd5d2`
**Branch**: `main`

## Research Question

调研 `aichat` 工具当前是否实现了流式传输交互，以及当前生效的是哪一条实现链路。

## Summary

当前代码中，`AI Chat` 工具**已经实现流式交互**，而且**当前实际路由到的是 Claude CLI 流式实现**，不是旧的 MiniMax HTTP 聊天视图。

现行链路为：

- `Sources/CodeToolCore/ContentView.swift:495-496` 将 `"AI Chat"` 路由到 `ClaudeChatView()`
- `Sources/CodeToolCore/ClaudeChatView.swift:624-692` 在发送消息时调用 `ClaudeCLIClient.send(...)`
- `Sources/CodeToolCore/ClaudeCLIClient.swift:82-89` 以 `claude -p --output-format stream-json --include-partial-messages` 启动本地 Claude CLI
- `Sources/CodeToolCore/ClaudeCLIClient.swift:145-172` 按行读取 stdout NDJSON
- `Sources/CodeToolCore/ClaudeCLIClient.swift:251-266` 将 `thinking_delta`、`text_delta`、`input_json_delta` 解析为事件
- `Sources/CodeToolCore/ClaudeChatView.swift:717-721` 将增量文本追加到 `streamingThinking` / `streamingText`
- `Sources/CodeToolCore/ClaudeChatView.swift:609-621` 通过 `streamingMessage` 将这些增量内容实时渲染到 UI

因此，从“是否支持流式传输交互”这个问题来看，答案是：**支持，而且当前主路径已经在使用流式交互。**

同时，仓库里还保留着旧的 MiniMax 流式实现：

- `Sources/CodeToolCore/AIChatView.swift:333-342`
- `Sources/CodeToolCore/MiniMaxAPIClient.swift:243-329`

该旧实现同样是流式，但**当前并不是 `AI Chat` 工具的活动路由**。

## Detailed Findings

### 1. 当前生效的 AI Chat 路由

- `Sources/CodeToolCore/ContentView.swift:495-496`：
  - `case "AI Chat": ClaudeChatView()`
- 这说明当前侧边栏中的 `AI Chat` 工具打开后，实际进入的是 `ClaudeChatView`，而不是 `AIChatView`。

相关定位信息也可从代码地图中看到：

- `Sources/CodeToolCore/Tool.swift:62-64` 将 `AI Chat` 注册为工具
- `Sources/CodeToolCore/ContentView.swift:881-882` 为其设置导航 tag

### 2. Claude CLI 路径如何实现流式交互

#### 2.1 启动流式会话

`ClaudeChatView.sendMessage()` 在用户发送消息时启动 Claude 流式交互：

- `Sources/CodeToolCore/ClaudeChatView.swift:624-692`

关键状态初始化：

- `isStreaming = true` — `Sources/CodeToolCore/ClaudeChatView.swift:676`
- `streamingText = ""` — `Sources/CodeToolCore/ClaudeChatView.swift:677`
- `streamingThinking = ""` — `Sources/CodeToolCore/ClaudeChatView.swift:678`

随后调用：

- `Sources/CodeToolCore/ClaudeChatView.swift:684-691`

```swift
await client.send(
    request: ClaudeCLITurnRequest(prompt: prompt, sessionID: outgoingSessionId),
    settings: settings
) { event in
    Task { @MainActor in
        handleEvent(event)
    }
}
```

#### 2.2 Claude CLI 以 stream-json 形式输出

`ClaudeCLIClient.send(...)` 明确要求 Claude CLI 以流式 NDJSON 输出：

- `Sources/CodeToolCore/ClaudeCLIClient.swift:82-89`

```swift
var arguments = [
    "-p",
    "--output-format", "stream-json",
    "--verbose",
    "--include-partial-messages",
    "--model", settings.model,
    "--max-turns", String(settings.maxTurns),
]
```

这里可以直接确认：

- 当前实现不是一次性等待完整回复
- 而是要求 Claude CLI 输出 `stream-json`
- 并包含 partial messages

#### 2.3 客户端按行读取增量输出

`ClaudeCLIClient` 使用 `Process` + `Pipe` 读取子进程 stdout，并按换行切分 NDJSON：

- `Sources/CodeToolCore/ClaudeCLIClient.swift:130-147`
- `Sources/CodeToolCore/ClaudeCLIClient.swift:148-172`

核心流程：

- 启动 `Process`
- 从 `stdoutPipe.fileHandleForReading.availableData` 读数据
- 追加到 `leftover`
- 遇到换行就切出一条 JSON 记录
- 交给 `parseLine(...)`

这是一种典型的“逐条增量消费流式事件”的实现。

#### 2.4 解析为文本 / thinking / 工具输入增量事件

`ClaudeCLIClient.parseLine(...)` 将 NDJSON 解析为 `ClaudeCLIEvent`：

- `Sources/CodeToolCore/ClaudeCLIClient.swift:224-305`

已实现的增量事件包括：

- `thinking_delta` → `.thinkingDelta(text:)` — `Sources/CodeToolCore/ClaudeCLIClient.swift:255-258`
- `text_delta` → `.textDelta(text:)` — `Sources/CodeToolCore/ClaudeCLIClient.swift:259-262`
- `input_json_delta` → `.toolInputDelta(text:)` — `Sources/CodeToolCore/ClaudeCLIClient.swift:263-266`
- `content_block_start` 中的 `tool_use` → `.toolUseStart(...)` — `Sources/CodeToolCore/ClaudeCLIClient.swift:241-247`
- 最终 `result` → `.result(...)` — `Sources/CodeToolCore/ClaudeCLIClient.swift:280-300`

事件模型定义位于：

- `Sources/CodeToolCore/ClaudeCLIClient.swift:4-32`

其中明确包含：

- `.thinkingDelta`
- `.textDelta`
- `.toolUseStart`
- `.toolInputDelta`
- `.result`
- `.completed`
- `.error`

这些都说明当前实现是围绕“流事件”设计的，而不是单次响应模型。

### 3. ClaudeChatView 如何把流式事件转成实时 UI

#### 3.1 增量更新内存态

`ClaudeChatView.handleEvent(_:)` 对流事件做 UI 状态更新：

- `Sources/CodeToolCore/ClaudeChatView.swift:710-808`

关键逻辑：

- `.thinkingDelta` 时：
  - `streamingThinking += text` — `Sources/CodeToolCore/ClaudeChatView.swift:717-718`
- `.textDelta` 时：
  - `streamingText += text` — `Sources/CodeToolCore/ClaudeChatView.swift:720-721`
- `.toolUseStart` 时：
  - 插入 `role: .toolUse` 的消息卡片 — `Sources/CodeToolCore/ClaudeChatView.swift:723-733`
- `.toolInputDelta` 时：
  - 持续追加 `toolInput` — `Sources/CodeToolCore/ClaudeChatView.swift:735-743`
- `.result` 时：
  - 汇总 token / cost / duration，并将 `isStreaming = false` — `Sources/CodeToolCore/ClaudeChatView.swift:765-780`

#### 3.2 流式内容在完成前就会显示

`ClaudeChatView` 定义了一个计算属性 `streamingMessage`：

- `Sources/CodeToolCore/ClaudeChatView.swift:609-621`

只要：

- `streamingText` 非空，或
- `streamingThinking` 非空

就会构造一个 `isStreaming: true` 的临时 assistant message。

该临时消息会被插入渲染列表：

- `Sources/CodeToolCore/ClaudeChatView.swift:170-206`

其中：

- 已提交消息来自 `messages`
- 流中的临时消息来自 `streamingMessage` — `Sources/CodeToolCore/ClaudeChatView.swift:183-185`

这就是“边收边显示”的直接证据。

#### 3.3 界面对流式变化自动滚动

消息视图会在以下变化时滚到底部：

- `messages.count` 改变 — `Sources/CodeToolCore/ClaudeChatView.swift:193-197`
- `streamingText` 改变 — `Sources/CodeToolCore/ClaudeChatView.swift:198-200`
- `streamingThinking` 改变 — `Sources/CodeToolCore/ClaudeChatView.swift:201-202`

这说明 UI 不只是支持流式数据接收，也对实时显示做了配套交互处理。

#### 3.4 流结束后再固化为正式消息

流式阶段使用临时缓冲：

- `streamingText`
- `streamingThinking`

完成后通过 `finalizeStreamingAssistantIfNeeded()` 写入正式消息：

- `Sources/CodeToolCore/ClaudeChatView.swift:811-827`

该函数会：

- 构造 `role: .assistant`
- 把 `streamingText` 作为正文
- 把 `streamingThinking` 作为 `thinkingContent`
- append 到 `messages`
- 清空缓冲区

这表明当前实现采用的是“实时缓冲 + 完成后落入正式消息列表”的流式 UI 模式。

### 4. 当前流式交互不只是文本，还覆盖 thinking / tool use / result

当前 Claude 路径的流式交互不局限于纯文本 token：

#### Thinking

- 事件来源：`thinking_delta`
- 累积状态：`streamingThinking`
- UI 渲染：`thinkingBlock(...)`
  - `Sources/CodeToolCore/ClaudeChatView.swift:352-399`

当消息仍在流式中，thinking 区域会自动展开：

- `let isExpanded = showThinking.contains(messageId) || isStreaming`
  - `Sources/CodeToolCore/ClaudeChatView.swift:353`

#### Tool Use

- 启动事件：`.toolUseStart`
- 输入增量：`.toolInputDelta`
- UI：`toolCard(...)`
  - `Sources/CodeToolCore/ClaudeChatView.swift:403-476`

在工具卡片里，如果消息仍在 streaming，会显示进度状态：

- `ProgressView()` — `Sources/CodeToolCore/ClaudeChatView.swift:436-440`

#### Result / Usage

最终结果不是消息气泡，而是状态栏汇总：

- 成本：`totalCostUSD`
- token：`inputTokens` / `outputTokens`
- 时长：`totalDurationMs`

状态栏渲染位于：

- `Sources/CodeToolCore/ClaudeChatView.swift:118-165`

其中流式中还会显示：

- `Streaming…` badge — `Sources/CodeToolCore/ClaudeChatView.swift:158-165`

### 5. 仓库中仍然保留旧的 MiniMax 流式实现

旧版 `AIChatView` 在研究时仍然存在，且它本身也是流式实现；当前仓库已删除该 UI 文件，这里仅保留历史分析背景：

- `Sources/CodeToolCore/AIChatView.swift:307-386`

它调用：

- `MiniMaxAPIClient.shared.chatCompletionStream(...)`
  - `Sources/CodeToolCore/AIChatView.swift:333-338`

而 `MiniMaxAPIClient.chatCompletionStream(...)` 会：

- 在请求 body 中发送 `"stream": true` — `Sources/CodeToolCore/MiniMaxAPIClient.swift:263-269`
- 用 `session.bytes(for:)` 读取流 — `Sources/CodeToolCore/MiniMaxAPIClient.swift:292`
- 用 `for try await line in bytes.lines` 逐行消费 SSE 数据 — `Sources/CodeToolCore/MiniMaxAPIClient.swift:317`
- 解析 `data: ...` 和 `[DONE]` — `Sources/CodeToolCore/MiniMaxAPIClient.swift:318-325`
- 将 `content` 增量回调给 `onDelta` — `Sources/CodeToolCore/MiniMaxAPIClient.swift:326-329`

`AIChatView` 侧对应的 UI 缓冲为：

- `isStreaming`
- `streamingContent`

并在回调中追加：

- `streamingContent += delta` — `Sources/CodeToolCore/AIChatView.swift:338-341`

所以仓库层面存在两套流式实现：

1. MiniMax SSE 流式实现（旧）
2. Claude CLI NDJSON 流式实现（当前路由）

### 6. thoughts/ 中的历史文档也说明了演进过程

#### 6.1 迁移前：AI Chat 基于 MiniMax SSE

`thoughts/shared/specs/2026-03-31-ai-chat-claude-cli-harness.md` 明确写到：

- 当时的 AI Chat 当前实现为 `MiniMaxAPIClient.chatCompletionStream()`
- 通过 SSE 调用 `/chat/completions`
- `AIChatView.swift` 是旧 UI

参考：

- `thoughts/shared/specs/2026-03-31-ai-chat-claude-cli-harness.md:24-28`

#### 6.2 迁移目标：切换到 Claude CLI stream-json

同一份 spec 中还明确写到：

- 通过 `Process` 启动 `claude -p --output-format stream-json`
- 使用 `text_delta` 作为主要流式渲染来源
- thinking/tool/result 都基于流事件驱动

参考：

- `thoughts/shared/specs/2026-03-31-ai-chat-claude-cli-harness.md:18`
- `thoughts/shared/specs/2026-03-31-ai-chat-claude-cli-harness.md:40`
- `thoughts/shared/specs/2026-03-31-ai-chat-claude-cli-harness.md:51-57`
- `thoughts/shared/specs/2026-03-31-ai-chat-claude-cli-harness.md:93-109`

#### 6.3 后续计划文档表明 Claude CLI 流式栈已落地

`thoughts/shared/plans/2026-03-31-claude-cli-optimization.md` 摘要显示：

- `ClaudeChatView.swift` 已存在
- `ClaudeCLIClient.swift` 已经使用 `claude -p --output-format stream-json`
- `HistoryStore.swift` 已有 `ClaudeChatHistoryRecord`

这与当前代码实况一致。

## Code References

- `Sources/CodeToolCore/ContentView.swift:495-496` - `AI Chat` 当前路由到 `ClaudeChatView()`
- `Sources/CodeToolCore/ClaudeChatView.swift:624-692` - 发送消息并启动 Claude 流式请求
- `Sources/CodeToolCore/ClaudeChatView.swift:609-621` - `streamingMessage` 临时流式消息
- `Sources/CodeToolCore/ClaudeChatView.swift:710-808` - 处理流式事件并更新 UI 状态
- `Sources/CodeToolCore/ClaudeChatView.swift:811-827` - 将流式缓冲固化为正式 assistant 消息
- `Sources/CodeToolCore/ClaudeCLIClient.swift:52-190` - Claude CLI 流式子进程启动与 stdout 消费
- `Sources/CodeToolCore/ClaudeCLIClient.swift:224-305` - NDJSON 事件解析
- `Sources/CodeToolCore/AIChatView.swift:307-386` - 旧 MiniMax 聊天视图的流式逻辑
- `Sources/CodeToolCore/MiniMaxAPIClient.swift:243-329` - MiniMax SSE 流式解析
- `Tests/CodeToolTests/CodeToolTests.swift:405-442` - MiniMax `chatCompletionStream` 相关测试

## Architecture Documentation

当前 `AI Chat` 的活动实现路径为：

`ToolRegistry` / `ContentView` → `ClaudeChatView` → `ClaudeCLIClient`

其中：

- 路由层决定当前 AI Chat 用 Claude 实现
- `ClaudeCLIClient` 负责本地 CLI 子进程及 NDJSON 流事件解析
- `ClaudeChatView` 负责将这些事件转化为：
  - assistant 文本增量
  - thinking 折叠块
  - tool use 卡片
  - token/cost 状态栏

旧的 MiniMax 架构仍保留在仓库中：

历史路径：`AIChatView` → `MiniMaxAPIClient.chatCompletionStream()`

但目前不在主路由上。

## Historical Context (from thoughts/)

- `thoughts/shared/specs/2026-03-31-ai-chat-claude-cli-harness.md` 记录了从 MiniMax SSE 迁移到 Claude CLI `stream-json` 的设计背景与目标。
- `thoughts/shared/plans/2026-03-31-ai-chat-claude-cli.md` 记录了把 `"AI Chat"` 从 `AIChatView()` 切到 `ClaudeChatView()` 的计划。
- `thoughts/shared/plans/2026-03-31-claude-cli-optimization.md` 表示 Claude CLI 聊天 UI / client / history model 已经存在，并基于 `stream-json` 工作。

## Related Research

- `thoughts/shared/specs/2026-03-31-ai-chat-claude-cli-harness.md`
- `thoughts/shared/plans/2026-03-31-ai-chat-claude-cli.md`
- `thoughts/shared/plans/2026-03-31-claude-cli-optimization.md`
- `thoughts/shared/plans/2026-03-31-tool-history-ui.md`

## Open Questions

- `ClaudeCLIEvent.toolResult` 在事件模型和 UI 层都有定义，但在当前 `ClaudeCLIClient.parseLine(...)` 可见实现中，没有直接看到将某类 NDJSON 记录映射为 `.toolResult(...)` 的分支；当前可确认的活动流式链路仍然包含 text/thinking/tool input/result 等核心交互。
