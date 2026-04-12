# AI Chat Back To MiniMax Implementation Plan

## Overview

将 AI Chat 从当前的 Claude CLI 产品链路切回最小可用的 MiniMax 文本聊天，并彻底删除 Claude Chat 全栈实现、历史类型、诊断分类、设置入口、测试和文档痕迹。

这份计划以当前仓库现实为准：仓库里已经没有可直接切回的用户态 MiniMax Chat 视图，只保留了 MiniMax 文本聊天的 provider / execution / history 基础设施。因此，本次不是简单改路由，而是“补一个新的最小 MiniMax Chat UI + 收缩 Claude 栈”。

这份计划有意覆盖今天的 MiniMax CLI 迁移 spec 中“AI Chat 仍保持 Claude CLI”的边界；本计划不包含 MiniMax CLI 迁移，只基于现有 MiniMax HTTP 聊天链路恢复 AI Chat。

> Implementation status: completed in branch `feat-aichat-back-to-minimax`; automated verification is green (`swift build`, `make test`).

## Current State Analysis

当前 AI Chat 运行时固定走 Claude，而不是 MiniMax：

- `Sources/CodeToolFoundation/Tool.swift` 将 AI Chat 描述为 “Chat with Claude — full agentic capabilities via CLI.”
- `Sources/CodeToolCore/Views/ContentView.swift` 将 `.aiChat` 路由到 `ClaudeChatView()`，并在启动时执行 `ClaudeCLISettingsStore.shared.discoverCLI()`。
- `Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift` 直接驱动 `ClaudeCLIClient`，没有经过通用 `AIExecutionSession`。

Claude Chat 已经发展成独立栈，而非单纯视图替换：

- `Sources/CodeToolCore/Providers/Claude/` 下有完整的 CLI client、settings store、settings view、config reader。
- `Sources/CodeToolCore/Persistence/HistoryStore.swift`、`HistoryDefinitions.swift`、`HistoryEntry.swift` 中存在 `claude-chat` 专属 history model、codec、category 和附件目录。
- `Sources/CodeToolFoundation/LogTypes.swift` 与 `Sources/CodeToolCore/Execution/AppLoggerDiagnosticsSink.swift` 中有 `claudechat` 专属诊断分类。
- `Tests/CodeToolTests/CodeToolTests+Claude.swift`、`CodeToolTests+History.swift`、`CodeToolTests+Diagnostics.swift`、`AIExecutionSessionTests.swift` 已编码了 Claude chat 的存在。

MiniMax 文本聊天基础设施仍然存在，但只剩基础层：

- `Sources/CodeToolCore/Execution/MiniMaxChatExecutionProvider.swift` 仍可把 chat payload 转成 MiniMax 流式调用。
- `Sources/CodeToolCore/Providers/MiniMax/MiniMaxAPIClient.swift` 仍提供 `chatCompletionStream(...)`。
- `Sources/CodeToolCore/Persistence/HistoryStore.swift` 仍保留 `ChatHistoryRecord` / `ChatMessageRecord` / `listChat()` / `save(_ record: ChatHistoryRecord)`。
- 当前工作树中没有用户可见的 MiniMax Chat 视图文件，因此必须新增一个最小文本聊天页。

### Key Discoveries

- `Sources/CodeToolCore/Providers/MiniMax/MiniMaxProvider.swift` 文件名虽然是 `MiniMaxProvider.swift`，但实际定义的是 `MiniMaxSettingsStore`；计划中的 MiniMax 配置落点要以类型名为准。
- Claude Chat 的历史不只是 JSON 记录，还包含 `claude-chat-attachments` 附件目录；如果删除 Claude 历史类型，删除逻辑和清理逻辑都要一起收掉。
- 现有最完整的聊天 UI 样板在 `ClaudeChatView`，但其中的 thinking、tool-use、图片附件、working directory、Claude markdown 和 Claude composer 都属于本次明确的删除范围。
- 最接近“最小 MiniMax 文本聊天”的现成组合是：`MiniMaxChatExecutionProvider` + `MiniMaxAPIClient.chatCompletionStream(...)` + `ChatHistoryRecord` + `HistoryDrawer`。

## Scope

### In Scope

- 新增一个最小 MiniMax 文本聊天视图，重新接回 AI Chat 路由。
- 更新 AI Chat tool catalog、欢迎页文案、Provider Settings 结构，使其不再暴露 Claude。
- 删除 Claude Chat 专属 provider、settings、view、shared UI、history、diagnostics、tests、README 文案和 thoughts 文档。
- 将统一 execution / history / diagnostics 模型收缩回只有 MiniMax chat 主路径。
- 更新测试和文档，使仓库不再假设 Claude Chat 存在。

### Out of Scope

- 不实施 MiniMax CLI 迁移。
- 不保留 Claude Chat 历史兼容读取，也不在 UI 中暴露旧的 `claude-chat` 数据。
- 不把 Claude Chat 的 thinking、工具调用、图片附件、工作目录、Markdown 扩展迁移到 MiniMax。
- 不做新的多模型选择器、system prompt 折叠区、图片输入、工具调用展示。
- 不自动迁移用户本地 `Application Support/CodeTool/history/claude-chat*` 目录中的旧文件。

## Implementation Approach

采用“先恢复 AI Chat 可用，再整体删除 Claude 栈，最后收缩基础设施与测试”的顺序，避免仓库在中间状态出现“AI Chat 不可用但 Claude 仍残留”的半完成状态。

MiniMax Chat 侧坚持最小可用原则：

- 仅支持用户文本输入、assistant 流式文本输出、多轮上下文、清空会话、查看历史、恢复历史。
- 继续使用 `ToolWorkbench`、`ToolMessageBanner`、`HistoryDrawer` 和现有 `ChatHistoryRecord`。
- 不引入 Claude 专属 message role，也不让 UI 依赖 `claudeChat` history / diagnostics / settings。

Claude 删除侧坚持“整块拔除”原则：

- 优先删除整文件，其次删除共享文件中的 Claude case / type / category。
- 所有 `claudeChat`、`ClaudeCLI*`、`ClaudeChat*`、`claude-chat`、`claudechat` 相关路径都要收口到 0。
- README、thoughts 文档和测试必须在同一轮内同步收缩，避免仓库继续保留过时契约。

## Phase 1: Restore Minimal MiniMax AI Chat

### Overview

新增最小 MiniMax 文本聊天视图并接回 AI Chat 路由，保证用户侧 AI Chat 恢复可用。

### Changes Required

#### 1. New MiniMax chat view
**File**: `Sources/CodeToolCore/Views/AITools/MiniMaxChatView.swift`
**Changes**:

- 新建用户可见的最小文本聊天页。
- 使用 `ToolWorkbench` 构建页面外壳。
- 维持最小状态：`messages`、`inputText`、`isStreaming`、`streamingText`、`errorMessage`。
- 发送链路调用 `MiniMaxAPIClient.chatCompletionStream(...)` 或通过 `MiniMaxChatExecutionProvider` 统一接入。
- 支持 `HistoryDrawer`、`Clear Chat`、流式中禁用再次发送。

建议视图状态模型保持接近旧 `ChatHistoryRecord`，避免再引入 Claude 风格的 message role：

```swift
struct MiniMaxChatMessage: Identifiable {
    let id: UUID
    let role: String
    var content: String
    var isStreaming: Bool
}
```

#### 2. Route AI Chat back to MiniMax
**File**: `Sources/CodeToolCore/Views/ContentView.swift`
**Changes**:

- 将 `.aiChat` 的 destination 从 `ClaudeChatView()` 改为新的 `MiniMaxChatView()`。
- 删除 `onAppear` 中的 `ClaudeCLISettingsStore.shared.discoverCLI()`。
- 移除设置页中 Claude tab 的分支渲染。
- 保持 AI Chat 在欢迎页与侧边栏仍然可见，但文案改为 MiniMax 文本聊天。

#### 3. Update tool catalog copy
**File**: `Sources/CodeToolFoundation/Tool.swift`
**Changes**:

- 将 AI Chat 描述从 Claude CLI agent chat 改回 MiniMax 文本聊天。
- 保持 `ToolID.aiChat` 不变，避免扩大路由身份变更。

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [x] `make test`

#### Manual Verification
- [ ] 打开 AI Chat 时进入新的 MiniMax 文本聊天页，而不是 Claude 页面。
- [ ] 发送一条消息后能看到 MiniMax 流式文本回复。
- [ ] Clear Chat 能清空本轮消息和流式状态。
- [ ] 历史抽屉能展示并恢复 `ChatHistoryRecord`。

---

## Phase 2: Delete Claude Chat Product And Provider Stack

### Overview

整块删除 Claude Chat 的可见页面、provider、settings 和专属共享 UI，确保产品和源码层都不再暴露 Claude Chat。

### Changes Required

#### 1. Remove Claude-specific source files
**Files**:

- `Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift`
- `Sources/CodeToolCore/Views/Shared/ClaudeChatComposer.swift`
- `Sources/CodeToolCore/Views/Shared/ClaudeMarkdownView.swift`
- `Sources/CodeToolCore/Views/Shared/ClaudeAttachmentThumbnailView.swift`
- `Sources/CodeToolCore/Providers/Claude/ClaudeCLIClient.swift`
- `Sources/CodeToolCore/Providers/Claude/ClaudeCLISettingsStore.swift`
- `Sources/CodeToolCore/Providers/Claude/ClaudeCLISettingsView.swift`
- `Sources/CodeToolCore/Providers/Claude/ClaudeConfigReader.swift`

**Changes**:

- 删除上述整文件。
- 如果删除后有共享 UI 空洞，优先让 MiniMax chat view 使用更通用的现有组件，而不是保留 Claude 组件壳子。

#### 2. Remove Claude settings tab and settings assumptions
**Files**:

- `Sources/CodeToolCore/Views/Shared/ToolSettingsTab.swift`
- `Sources/CodeToolCore/Views/ContentView.swift`

**Changes**:

- 删除 `claude` tab。
- Provider Settings 只保留 MiniMax 与 Diagnostics。
- 删除所有 Claude provider 文案、默认 tab 行为和入口按钮依赖。

#### 3. Remove Claude-specific thoughts/docs
**Files**:

- `thoughts/shared/specs/2026-03-31-ai-chat-claude-cli-harness.md`
- `thoughts/shared/plans/2026-03-31-ai-chat-claude-cli.md`
- `thoughts/shared/plans/2026-03-31-claude-cli-optimization.md`
- `thoughts/shared/plans/2026-04-03-claude-cli-chat-ux-optimization.md`

**Changes**:

- 从仓库中删除 Claude Chat 专属 spec / plan 文档。
- 保留与 MiniMax、observability、layout 等无关 Claude Chat 的文档。

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [x] `make test`
- [x] 源码搜索不再返回 `ClaudeCLIClient`、`ClaudeCLISettingsStore`、`ClaudeChatView`

#### Manual Verification
- [ ] Provider Settings 中不再出现 Claude tab。
- [ ] 应用内不再有 Claude Chat 入口或 Claude CLI 配置 UI。
- [ ] AI Chat 页面不再展示 Claude 专属状态、附件或工具调用 UI。

---

## Phase 3: Collapse History, Diagnostics, Execution, And Tests

### Overview

删除 Claude Chat 对共享基础设施的侵入，让统一 history / diagnostics / execution 模型重新回到只有 MiniMax chat 主路径。

### Changes Required

#### 1. Remove Claude execution payloads and diagnostics categories
**Files**:

- `Sources/CodeToolCore/Execution/AIExecutionRequest.swift`
- `Sources/CodeToolCore/Execution/AIExecutionTypes.swift`
- `Sources/CodeToolCore/Execution/AppLoggerDiagnosticsSink.swift`
- `Sources/CodeToolFoundation/LogTypes.swift`
- `Sources/CodeToolCore/Observability/RenderingPerformance.swift`

**Changes**:

- 删除 `ClaudeChatExecutionPayload`、`.claudeChat` tool case 和对应 sink 映射。
- 删除 `claudechat` 日志分类。
- 删除 Claude markdown / streaming 批处理等专属性能事件。

#### 2. Remove Claude history category and attachment storage
**Files**:

- `Sources/CodeToolCore/Persistence/HistoryStore.swift`
- `Sources/CodeToolCore/Persistence/HistoryDefinitions.swift`
- `Sources/CodeToolCore/Persistence/HistoryEntry.swift`
- `Sources/CodeToolCore/Persistence/HistoryDrawer.swift`

**Changes**:

- 删除 `ClaudeChatHistoryRecord`、`ClaudeChatMessageRecord`、`ClaudeChatAttachmentRecord`。
- 删除 `claude-chat` category / toolID / codec / drawer 适配。
- 删除 `claude-chat-attachments` 的同步与 actor 存储 API。
- 统一历史抽屉只保留 `ChatHistoryRecord` 作为 AI Chat 主路径。

#### 3. Update test suite to MiniMax-only AI Chat assumptions
**Files**:

- `Tests/CodeToolTests/CodeToolTests+Claude.swift`
- `Tests/CodeToolTests/CodeToolTests+History.swift`
- `Tests/CodeToolTests/CodeToolTests+Diagnostics.swift`
- `Tests/CodeToolTests/AIExecutionSessionTests.swift`
- `Tests/CodeToolTests/CodeToolTests+ToolCatalog.swift`
- `Tests/CodeToolTests/CodeToolTests.swift`

**Changes**:

- 删除 Claude 专属测试文件和断言。
- 更新 catalog / settings / diagnostics / history / execution 相关测试，使其不再引用 `claudeChat`、Claude settings、Claude history codec。
- 新增 MiniMax 最小聊天页的 targeted tests，至少覆盖：
  - AI Chat route 指向 MiniMax view
  - `MiniMaxChatExecutionProvider` 的主路径仍可聚合 delta
  - `ChatHistoryRecord` 仍能保存与恢复最小文本聊天历史

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [x] `make test`
- [x] 源码搜索不再返回 `claudeChat`、`claude-chat`、`claudechat`

#### Manual Verification
- [ ] Diagnostics 页面不再出现 Claude Chat 分类或样本。
- [ ] AI Chat 历史只显示 MiniMax `chat` 记录。
- [ ] 删除 Claude 相关源码后，应用仍能启动并正常打开 AI Chat。

---

## Phase 4: Documentation And Final Cleanup

### Overview

同步 README、仓库说明和残余样本，确保仓库叙述与实际实现完全一致。

### Changes Required

#### 1. Update README
**File**: `README.md`
**Changes**:

- 将 AI Chat 功能描述改回 MiniMax 文本聊天。
- 删除 Claude provider 目录、Claude CLI 集成说明和相关文案。
- 保持 MiniMax Speech / Image / Music 的现有描述不变。

#### 2. Remove stale repository artifacts
**Files**:

- `CodeTool-Diagnostics-recent-issues-0503B6DA-9389-408C-B866-E03815241A31.json`

**Changes**:

- 如果仓库保留诊断样本文件，需要删除或更新其中的 Claude 事件样本，避免仓库继续保留已删除能力的示例数据。

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [x] `make test`
- [x] 源码与文档搜索不再返回 “Chat with Claude” 或 Claude Chat 相关仓库说明

#### Manual Verification
- [ ] README 对 AI Chat 的描述与应用实际行为一致。
- [ ] 仓库结构说明不再声明 `Providers/Claude/` 为活跃模块。

---

## Testing Strategy

### Unit Tests

- 保留并更新 `MiniMaxChatExecutionProvider` 相关测试，验证流式 delta 聚合与 metadata 仍正确。
- 保留并更新 `ChatHistoryExecutionSink` / `ChatHistoryRecord` 相关测试，验证最小聊天记录仍能保存、列出和恢复。
- 更新 tool catalog / route registry 测试，确保 `.aiChat` 仍存在且路由不再指向 Claude。
- 更新 diagnostics / history registry 测试，确保 `claude-chat` 与 `claudechat` 不再出现在注册表中。

### Manual Testing Steps

1. 打开 AI Chat，确认进入新的 MiniMax 文本聊天页。
2. 配置 MiniMax API Key 后发送一条消息，确认流式回复正常显示。
3. 触发错误场景（如未配置 API Key），确认只出现 MiniMax 相关错误提示，没有 Claude 文案。
4. 打开 AI Chat 历史，确认能看到新的 MiniMax 聊天记录并恢复。
5. 打开 Provider Settings，确认只剩 MiniMax 与 Diagnostics。
6. 搜索仓库与应用 UI，确认没有 Claude Chat、Claude CLI、claude-chat 历史、Claude 附件相关入口。

## Performance Considerations

- 最小 MiniMax chat 视图优先复用现有流式文本缓冲策略，避免每个 delta 都直接触发整棵消息列表重绘。
- 由于本次删除 Claude markdown、thinking、tool-use 和附件链路，AI Chat 渲染复杂度应明显下降，不需要额外保留 Claude 专属的性能埋点。
- 不在这次回切中重建复杂 composer；优先使用更简单的文本输入模型，减少输入性能和维护成本。

## Migration Notes

- 本计划不保留 Claude Chat 历史兼容读取；代码删除后，已有 `claude-chat` JSON 与附件目录会成为未使用的本地残留数据。
- 本计划不自动删除用户本地 `Application Support/CodeTool/history/claude-chat` 和 `claude-chat-attachments` 目录；如需清理，可作为单独运维步骤执行，而不是混入本次产品回切。
- `ToolID.aiChat` 保持不变，因此侧边栏 identity、缓存和选择状态无需迁移，只切换 destination 与实现。

## References

- Original requirements: `thoughts/shared/specs/2026-04-12-minimax-cli-migration.md`
- Related code: `Sources/CodeToolFoundation/Tool.swift`
- Related code: `Sources/CodeToolCore/Views/ContentView.swift`
- Related code: `Sources/CodeToolCore/Execution/MiniMaxChatExecutionProvider.swift`
- Related code: `Sources/CodeToolCore/Providers/MiniMax/MiniMaxAPIClient.swift`
- Related code: `Sources/CodeToolCore/Providers/MiniMax/MiniMaxProvider.swift`
- Related code: `Sources/CodeToolCore/Persistence/HistoryStore.swift`
- Related code: `Sources/CodeToolCore/Persistence/HistoryDefinitions.swift`
- Related code: `Sources/CodeToolCore/Persistence/HistoryEntry.swift`
- Related tests: `Tests/CodeToolTests/AIExecutionSessionTests.swift`
- Related tests: `Tests/CodeToolTests/CodeToolTests+History.swift`
- Related tests: `Tests/CodeToolTests/CodeToolTests+ToolCatalog.swift`
