# Claude CLI Optimization Implementation Plan

## Overview

优化现有 Claude CLI 聊天能力，聚焦三个明确目标：

1. 历史记录按整段对话保存，而不是按单次 assistant 返回生成多条记录。
2. 聊天输入支持图像附件。
3. 输入区支持常见快捷键，并参考 t3code 的交互取舍，但保持当前 macOS 原生应用的实现复杂度可控。

本计划以现有 Claude CLI 实现为基础增量演进，不重做整个聊天栈。

## Current State Analysis

### Key Discoveries

- 现有 Claude CLI UI、客户端和历史模型已经存在，不是从零开始：
  - `Sources/CodeToolCore/ClaudeChatView.swift:77` 已经接入 HistoryDrawer。
  - `Sources/CodeToolCore/ClaudeCLIClient.swift:57` 已经使用 `claude -p --output-format stream-json`。
  - `Sources/CodeToolCore/HistoryStore.swift:105` 已经定义 `ClaudeChatHistoryRecord`。
- 历史记录之所以按“消息/turn”而不是按“会话”累积，是因为：
  - `Sources/CodeToolCore/ClaudeChatView.swift:591` 在每次 `.result(...)` 事件后都会调用 `saveHistory()`。
  - `Sources/CodeToolCore/ClaudeChatView.swift:656` 的 `saveHistory()` 每次都会新建一个 `ClaudeChatHistoryRecord`，默认生成新的 `UUID()`。
  - `Sources/CodeToolCore/HistoryStore.swift:339` 的 `save(_:)` 以 record id 作为 JSON 文件名，因此每次新 UUID 都会落成一条新记录，而不是更新原会话。
- Claude CLI 发送链路目前只支持纯文本：
  - `Sources/CodeToolCore/ClaudeCLIClient.swift:85` 直接把 `message` 作为最后一个 positional argument 追加给 CLI。
  - `Sources/CodeToolCore/ClaudeChatView.swift:441` 当前输入区仍然是普通 `TextEditor`，没有附件状态、图片预览、粘贴截获或快捷键分发。
- 当前历史抽屉本身已经适配 Claude chat，不需要重写：
  - `Sources/CodeToolCore/HistoryDrawer.swift:29` 和 `Sources/CodeToolCore/HistoryDrawer.swift:33` 已经根据 Claude chat record 计算标题和副标题。
  - `Sources/CodeToolCore/HistoryDrawer.swift:148` 的 HistoryDrawer 是通用组件，可继续复用。
- 当前代码库已经有两个可复用的快捷键挂点：
  - `Sources/CodeToolCore/ContentView.swift:42` 已用隐藏按钮方式注册 `⌘\`。
  - `Sources/CodeToolApp/CodeToolApp.swift:14` 已有 `.commands` 注入点，可在需要时加 app 级菜单命令。
- 现有测试已经覆盖 Claude CLI 的关键约束之一：
  - `Tests/CodeToolTests/CodeToolTests.swift:227` 已验证续接必须使用 `--resume`。
  - `Tests/CodeToolTests/CodeToolTests.swift:189` 和 `Tests/CodeToolTests/CodeToolTests.swift:199` 已覆盖 Claude CLI settings 默认值与 Claude chat history codable。

### External Constraints Verified

- Claude Code 官方文档明确说明图像可以通过三种方式进入会话：拖拽、CLI 中 `Ctrl+V` 粘贴、或直接在提示词里提供图像路径。
- Claude CLI print mode 支持 `--input-format stream-json`，但官方文档未给出稳定的图像附件 payload 契约；对当前 app 来说，首版采用“持久化图片文件 + 将图片路径注入 prompt”的方式最稳妥。
- t3code 的交互模式值得参考，但它是可配置的 web keybinding 系统；本仓库更适合实现一组固定、原生、低复杂度的快捷键，而不是复制其完整 keybinding engine。

## Scope

### In Scope

- 将 Claude chat 历史从“每个 turn 一条记录”改为“一个会话一条记录，持续覆盖更新”。
- 为 Claude chat 增加图像附件模型、预览和恢复能力。
- 支持常用快捷键：
  - `Enter` 发送
  - `Shift+Enter` 换行
  - `Cmd+Shift+O` 新建对话，参考 t3code 的 `chat.new`
  - `Cmd+L` 清空当前对话
  - `Esc` 停止当前流式输出
  - `Cmd+V` 有图片时优先附加图片，否则保留普通文本粘贴
- 保留现有 HistoryDrawer、ClaudeCLISettingsStore、ClaudeCLIClient 的主体结构。

### Out of Scope

- 不实现类似 t3code 的可配置 keybinding 系统。
- 不切换到未验证 schema 的 `--input-format stream-json` 多模态协议。
- 不做历史数据迁移脚本去合并过去已经生成的重复 JSON 记录。
- 不扩展到 AI Chat 之外的其他工具。
- 首版不做图片拖拽上传；优先完成粘贴和选择文件两条主路径。

## Implementation Approach

### Core Decisions

#### 1. 会话历史采用稳定 record id 覆盖写入，而不是新增 HistoryStore API

这是最小改动且最符合现有存储实现的方案。

- `HistoryStore.shared.save(record)` 已经会用同一个 id 覆盖同一个 JSON 文件。
- 因此无需新增 `updateClaudeChat(...)` 之类的 actor API。
- 真正要修的是 `ClaudeChatView` 的会话状态，让同一个聊天会话始终复用同一个 history record id 和 createdAt。

#### 2. 图像输入首版采用“持久化附件文件 + prompt 路径注入”

实现方式：

- 将粘贴或选择的图像保存到本地持久化目录。
- 在发送给 Claude CLI 前，把图片路径附加到 prompt 中。
- 在 UI 层保留附件缩略图和 message-level attachment metadata，保证历史恢复与会话继续都可用。

原因：

- 兼容现有 `ClaudeCLIClient.send(message:...)` 的参数模型。
- 与官方文档中“提供图像路径给 Claude”一致。
- 避免把实现建立在当前仓库尚未验证的 stream-json 输入 schema 上。

#### 3. 快捷键采用“本地 composer 快捷键 + 少量 view 级命令”

- 输入框内部行为用 AppKit-backed composer 统一处理：`Enter`、`Shift+Enter`、`Cmd+V`。
- 对话级命令用 view 级快捷键或 menu commands 处理：`Cmd+Shift+O`、`Cmd+L`、`Esc`。
- 不复制 t3code 的全局 shortcut resolver，只借鉴其行为选择。

## Phase 1: Conversation-Scoped History

### Overview

把 Claude chat 的持久化语义改成“一段会话一条历史记录”。

### Changes Required

#### 1. ClaudeChatView.swift

**File**: `Sources/CodeToolCore/ClaudeChatView.swift`

新增会话级状态：

- `activeConversationRecordID: UUID?`
- `activeConversationCreatedAt: Date?`
- `hasPersistedConversation: Bool` 或等价状态，避免无 assistant 结果时提前写空会话

改动点：

- `saveHistory()` 改为：
  - 第一次保存时生成稳定的 conversation record id。
  - 后续 turn 使用同一 id 重写 JSON。
  - `createdAt` 保持会话初次落盘时间不变。
- `clearChat()` 重置上述会话状态。
- `restoreChat(_:)` 恢复时同步设置 `activeConversationRecordID = record.id` 与 `activeConversationCreatedAt = record.createdAt`，保证从历史恢复后继续聊天时仍然覆盖原记录，而不是再裂变出新记录。

建议提炼纯函数，降低 view 内状态耦合：

```swift
private func makeConversationRecord() -> ClaudeChatHistoryRecord
private func ensureConversationRecordIdentity()
```

#### 2. HistoryDrawer.swift

**File**: `Sources/CodeToolCore/HistoryDrawer.swift`

无需重写组件，但建议微调 Claude chat 副标题，让会话粒度更清晰：

- 保留消息数。
- 如有附件则追加图片数量。
- 保留 cost / token 信息。

### Success Criteria

#### Automated Verification

- [x] `make build`
- [ ] 如环境支持 XCTest，执行 `swift test --filter CodeToolTests/testClaudeChatHistoryRecordCodable`

#### Manual Verification

- [ ] 一次包含多轮问答的 Claude chat 在历史抽屉中只出现一条记录。
- [ ] 同一会话继续聊天后，历史抽屉中的该记录消息数会增长，而不是新增第二条。
- [ ] 从历史恢复后继续聊天，仍然只更新原记录。
- [ ] 清空聊天后开启新会话，会产生新的历史记录。

---

## Phase 2: Image Attachment Pipeline

### Overview

给 Claude chat 引入图片附件的完整链路：选择/粘贴、预览、发送、历史恢复。

### Changes Required

#### 1. HistoryStore.swift

**File**: `Sources/CodeToolCore/HistoryStore.swift`

扩展 Claude chat message record，支持附件元数据：

```swift
public struct ClaudeChatAttachmentRecord: Codable, Identifiable {
    public let id: UUID
    public let type: String   // 首版固定为 "image"
    public let fileName: String
    public let mimeType: String
    public let sizeBytes: Int
}
```

在 `ClaudeChatMessageRecord` 中新增：

```swift
public let attachments: [ClaudeChatAttachmentRecord]
```

同时为 Claude chat 增加附件文件目录约定。建议不要新增 HistoryCategory，而是复用 `claude-chat` 目录旁的子目录，例如：

```text
Application Support/CodeTool/history/claude-chat/
Application Support/CodeTool/history/claude-chat-attachments/
```

并补充两个帮助方法：

- `saveClaudeChatAttachment(data:fileName:)`
- `loadClaudeChatAttachment(fileName:)`

删除 Claude chat record 时，同时清理该 record 被引用的附件文件。

#### 2. ClaudeChatView.swift

**File**: `Sources/CodeToolCore/ClaudeChatView.swift`

新增 UI 状态：

- `composerImages: [ClaudeComposerImage]`
- `attachmentWarning: String`

新增发送前 prompt 组装逻辑：

```swift
private func buildOutgoingPrompt(text: String, attachments: [ClaudeComposerImage]) -> String
```

推荐的 prompt 形态：

```text
Attached images:
- /absolute/path/to/image-1.png
- /absolute/path/to/image-2.jpg

User request:
<原始文本，若为空则使用 image-only bootstrap 文案>
```

首版支持两种添加方式：

- 剪贴板粘贴图片
- 通过按钮打开 `NSOpenPanel` 选择图片

UI 变化：

- composer 上方显示附件缩略图条。
- user bubble 显示该消息附带的图片预览或文件名 chips。
- 历史恢复时加载预览图。

#### 3. ClaudeCLIClient.swift

**File**: `Sources/CodeToolCore/ClaudeCLIClient.swift`

保持 CLI 协议最小改动，但接口从单纯 `message: String` 升级为请求模型更合理：

```swift
public struct ClaudeCLITurnRequest {
    public let prompt: String
    public let sessionID: String?
}
```

即使首版内部仍然只把拼好的 prompt 作为 positional argument 传给 CLI，也要先把接口改成 request model，避免第二轮再为了附件/元数据重改公共 API。

### Success Criteria

#### Automated Verification

- [x] `make build`
- [ ] 如环境支持 XCTest，新增并执行附件 record 的 codable roundtrip 测试

#### Manual Verification

- [ ] `Cmd+V` 粘贴图片后，composer 出现缩略图。
- [ ] 通过选择文件添加图片后，composer 出现缩略图。
- [ ] 仅发送图片不输入文字时，Claude 仍能收到可理解的请求。
- [ ] 历史恢复后，用户消息中的图片预览仍能显示。
- [ ] 删除 Claude chat 历史记录后，其关联附件文件也被清理。

---

## Phase 3: Shortcut and Composer Interaction

### Overview

把当前 `TextEditor` 升级为适合聊天输入的 composer，补齐常用快捷键和图片粘贴行为。

### Changes Required

#### 1. 新建 ClaudeChatComposer.swift

**File**: `Sources/CodeToolCore/ClaudeChatComposer.swift`

不建议继续在 `ClaudeChatView` 中直接使用 `TextEditor`。应新增一个专用的 `NSViewRepresentable` 包装 `NSTextView`，原因：

- 需要精确区分 `Enter` 和 `Shift+Enter`
- 需要拦截 `Cmd+V`
- 需要保留普通文本编辑体验

建议能力：

- `Enter` 触发发送
- `Shift+Enter` 插入换行
- `Cmd+V` 如果 pasteboard 中有 `NSImage`，走 `onPasteImages([NSImage])`；否则 fallback 到默认文本粘贴
- 暴露 `onEscape` 回调

对外接口建议为：

```swift
public struct ClaudeChatComposer: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSubmit: () -> Void
    let onPasteImages: ([NSImage]) -> Void
    let onEscape: () -> Void
}
```

#### 2. ClaudeChatView.swift

**File**: `Sources/CodeToolCore/ClaudeChatView.swift`

将当前 input area 中的 `TextEditor` 替换为 `ClaudeChatComposer`。

新增本地快捷键行为：

- `Cmd+Shift+O`: 新建对话
- `Cmd+L`: 清空当前对话
- `Esc`: 若正在 streaming，则 stop；否则不劫持系统行为

这里建议优先使用与现有 `ContentView.swift:42` 一致的简单模式：

- view 内隐藏按钮注册 `keyboardShortcut`
- 仅当 Claude chat view 存在时生效

如果发现 `Cmd+Shift+O` / `Cmd+L` 与 menu 焦点行为冲突，再升级到 app 级 `Commands`。

#### 3. CodeToolApp.swift

**File**: `Sources/CodeToolApp/CodeToolApp.swift`

作为兜底扩展点，保留后续追加 menu command 的路径，但首版不强制改动。只有在 view 内 `keyboardShortcut` 无法稳定覆盖时，再把 `New Chat` / `Clear Chat` 升级到 `.commands`。

### Shortcut Set

最终首版固定支持：

- `Enter`: 发送
- `Shift+Enter`: 换行
- `Cmd+Shift+O`: 新建对话
- `Cmd+L`: 清空当前会话
- `Esc`: 停止流式输出
- `Cmd+V`: 粘贴图片或文本

说明：

- 这里故意选 `Cmd+Shift+O` 而不是 `Cmd+N`，因为它更接近 t3code 的 `chat.new`，同时避免与 macOS 多窗口默认行为冲突。

### Success Criteria

#### Automated Verification

- [x] `make build`

#### Manual Verification

- [ ] `Enter` 发送消息，`Shift+Enter` 插入换行。
- [ ] `Cmd+Shift+O` 创建全新空白会话。
- [ ] `Cmd+L` 清空当前对话并重置统计与附件状态。
- [ ] Claude 正在流式输出时按 `Esc` 能停止当前请求。
- [ ] 剪贴板是文本时 `Cmd+V` 仍然是正常粘贴文本。
- [ ] 剪贴板是图片时 `Cmd+V` 会附加图片而不是把不可读内容写进输入框。

---

## Phase 4: Tests and Verification

### Overview

补齐最关键的回归测试，并按仓库实际环境安排验证步骤。

### Changes Required

#### 1. CodeToolTests.swift

**File**: `Tests/CodeToolTests/CodeToolTests.swift`

新增测试建议：

- `testClaudeChatConversationRecordReusesStableID`
  - 验证同一个 conversation record id 多次保存时，只会覆盖同一条记录。
- `testClaudeChatAttachmentRecordCodable`
  - 验证附件 metadata 的 JSON roundtrip。
- `testClaudeCLIClientStillUsesResumeForExistingSession`
  - 复用现有测试，确保附件/请求模型改造后不回退到 `--session-id`。
- `testBuildOutgoingPromptIncludesImagePaths`
  - 纯函数测试，验证图片路径注入 prompt 的格式正确。

如果为了测试需要，优先把以下逻辑从 view 中抽成纯 helper：

- prompt 组装
- 会话 record identity 选择
- 附件文件名生成

### Verification Strategy

#### Automated Verification

- [x] `make build`
- [ ] 如本机具备可用 XCTest 环境，执行：
  - `swift test --filter CodeToolTests/testClaudeChatHistoryRecordCodable`
  - `swift test --filter CodeToolTests/testClaudeCLIClientUsesResumeForExistingSession`
  - `swift test --filter CodeToolTests/testClaudeChatAttachmentRecordCodable`
  - `swift test --filter CodeToolTests/testBuildOutgoingPromptIncludesImagePaths`

#### Manual Verification

1. 新建 Claude chat，会话内连续发 3 轮消息，确认历史抽屉只出现 1 条记录。
2. 给消息附加 1 张图片并发送，确认 Claude 能读取图片上下文。
3. 关闭并从历史恢复该会话，确认图片预览、消息列表、session 继续聊天都正常。
4. 在流式输出中按 `Esc`，确认部分输出保留且 UI 状态回到可继续输入。
5. 使用 `Cmd+Shift+O` 开启新会话，确认旧会话历史不被覆盖。

## Migration Notes

- 旧的重复历史记录不做自动合并。
- 新逻辑上线后，新产生的会话将自动符合“一会话一记录”。
- 如后续需要整理旧数据，可单独增加一次性清理工具，但不应阻塞本轮交付。

## Risks and Mitigations

- 风险：图片路径注入对极端权限模式或工具可见性敏感。
  - 缓解：首版保持默认工具集，不在 `--bare` 之外再做工具裁剪；手工验证 image-only prompt。
- 风险：composer 自定义 `NSTextView` 可能破坏现有输入体验。
  - 缓解：把图片粘贴、快捷键和文本编辑分离成清晰的 coordinator 逻辑，并保留普通文本粘贴 fallback。
- 风险：删除历史记录时遗漏附件文件，产生孤儿文件。
  - 缓解：附件文件名包含 record id 前缀，并在删除逻辑中从 record metadata 精确清理。

## References

- Current Claude chat view: `Sources/CodeToolCore/ClaudeChatView.swift:77`, `Sources/CodeToolCore/ClaudeChatView.swift:441`, `Sources/CodeToolCore/ClaudeChatView.swift:591`, `Sources/CodeToolCore/ClaudeChatView.swift:656`
- Current CLI client: `Sources/CodeToolCore/ClaudeCLIClient.swift:57`, `Sources/CodeToolCore/ClaudeCLIClient.swift:75`, `Sources/CodeToolCore/ClaudeCLIClient.swift:85`, `Sources/CodeToolCore/ClaudeCLIClient.swift:199`
- Claude chat history store: `Sources/CodeToolCore/HistoryStore.swift:105`, `Sources/CodeToolCore/HistoryStore.swift:339`, `Sources/CodeToolCore/HistoryStore.swift:405`, `Sources/CodeToolCore/HistoryStore.swift:485`
- Existing history drawer: `Sources/CodeToolCore/HistoryDrawer.swift:29`, `Sources/CodeToolCore/HistoryDrawer.swift:33`, `Sources/CodeToolCore/HistoryDrawer.swift:148`
- Existing keyboard shortcut pattern: `Sources/CodeToolCore/ContentView.swift:42`
- Existing app command hook: `Sources/CodeToolApp/CodeToolApp.swift:14`
- Existing Claude CLI tests: `Tests/CodeToolTests/CodeToolTests.swift:189`, `Tests/CodeToolTests/CodeToolTests.swift:199`, `Tests/CodeToolTests/CodeToolTests.swift:227`
- Prior Claude CLI baseline plan: `thoughts/shared/plans/2026-03-31-ai-chat-claude-cli.md`
- Prior history UI plan: `thoughts/shared/plans/2026-03-31-tool-history-ui.md`
- Official Claude Code docs: image workflows and CLI reference for `--resume`, `--print`, `--input-format`, and image path usage