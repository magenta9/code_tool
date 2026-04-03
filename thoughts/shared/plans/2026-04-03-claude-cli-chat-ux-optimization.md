# Claude CLI Chat UX Optimization Implementation Plan

## Overview

优化 Claude CLI Chat 的本地交互体验，聚焦五个明确目标：

1. 每个 chat 独立选择工作目录，而不是通过全局 Settings 配置。
2. 读取 ~/.claude/settings.json 中的模型配置，替代当前硬编码模型列表。
3. Thinking 默认收起，仅在流式生成时展开。
4. 修复中文输入法与图片粘贴场景下的输入卡顿。
5. 简化图片交互，移除文件选择入口，仅保留粘贴图片，并增强可发现性。

本计划基于当前 Claude CLI 聊天实现做增量演进，不重做聊天架构或 Claude CLI 协议层。

## Current State Analysis

### Key Discoveries

- 当前 Claude CLI Chat 的主状态全部集中在 [Sources/CodeToolCore/ClaudeChatView.swift](Sources/CodeToolCore/ClaudeChatView.swift) 中：
  - [Sources/CodeToolCore/ClaudeChatView.swift#L7](Sources/CodeToolCore/ClaudeChatView.swift#L7) 到 [Sources/CodeToolCore/ClaudeChatView.swift#L30](Sources/CodeToolCore/ClaudeChatView.swift#L30) 定义了消息、流式输出、模型、token、thinking 展开状态、附件和历史等全部视图状态。
  - [Sources/CodeToolCore/ClaudeChatView.swift#L109](Sources/CodeToolCore/ClaudeChatView.swift#L109) 的 statusItems 只展示 model、cost、token、message count 和 streaming 状态，目前不支持交互。
- 工作目录仍然是全局配置，不是对话级配置：
  - [Sources/CodeToolCore/ClaudeCLISettingsStore.swift](Sources/CodeToolCore/ClaudeCLISettingsStore.swift) 的 `workingDirectory` 持久化在 UserDefaults。
  - [Sources/CodeToolCore/ClaudeCLISettingsView.swift#L212](Sources/CodeToolCore/ClaudeCLISettingsView.swift#L212) 到 [Sources/CodeToolCore/ClaudeCLISettingsView.swift#L260](Sources/CodeToolCore/ClaudeCLISettingsView.swift#L260) 提供了 Working Directory 设置 UI。
  - [Sources/CodeToolCore/ClaudeCLIClient.swift#L127](Sources/CodeToolCore/ClaudeCLIClient.swift#L127) 到 [Sources/CodeToolCore/ClaudeCLIClient.swift#L134](Sources/CodeToolCore/ClaudeCLIClient.swift#L134) 直接读取 `settings.workingDirectory` 设置 `Process.currentDirectoryURL`。
- Thinking 当前并非默认收起：
  - [Sources/CodeToolCore/ClaudeChatView.swift#L345](Sources/CodeToolCore/ClaudeChatView.swift#L345) 的 `thinkingBlock` 在流式期间会自动展开。
  - [Sources/CodeToolCore/ClaudeChatView.swift#L828](Sources/CodeToolCore/ClaudeChatView.swift#L828) 到 [Sources/CodeToolCore/ClaudeChatView.swift#L845](Sources/CodeToolCore/ClaudeChatView.swift#L845) 的 `finalizeStreamingAssistantIfNeeded()` 会把有 thinking 的消息 ID 写入 `showThinking`，导致最终消息默认展开。
  - [Sources/CodeToolCore/ClaudeChatView.swift#L974](Sources/CodeToolCore/ClaudeChatView.swift#L974) 到 [Sources/CodeToolCore/ClaudeChatView.swift#L989](Sources/CodeToolCore/ClaudeChatView.swift#L989) 的 `restoreChat()` 会恢复所有 thinking 消息为展开状态。
- 中文输入卡顿的根因更可能在 IME 组合输入与 SwiftUI 状态同步，而不是消息列表副作用：
  - [Sources/CodeToolCore/ClaudeChatComposer.swift#L61](Sources/CodeToolCore/ClaudeChatComposer.swift#L61) 到 [Sources/CodeToolCore/ClaudeChatComposer.swift#L79](Sources/CodeToolCore/ClaudeChatComposer.swift#L79) 的 `textDidChange` 每次击键都立即写回 `@Binding text`。
  - 当前没有 debounce 或 marked text 特殊处理；输入法组合过程中也会持续触发 SwiftUI 更新。
  - [Sources/CodeToolCore/ClaudeChatView.swift](Sources/CodeToolCore/ClaudeChatView.swift) 中没有 `inputText` 的 `.onChange` 副作用，因此主要风险是高频状态同步和输入区整体重算，而不是额外逻辑。
- 图片粘贴功能实际上已经存在，但入口设计和文案不明显：
  - [Sources/CodeToolCore/ClaudeChatComposer.swift#L121](Sources/CodeToolCore/ClaudeChatComposer.swift#L121) 到 [Sources/CodeToolCore/ClaudeChatComposer.swift#L165](Sources/CodeToolCore/ClaudeChatComposer.swift#L165) 已实现粘贴板图片与图片文件 URL 识别。
  - [Sources/CodeToolCore/ClaudeChatView.swift#L923](Sources/CodeToolCore/ClaudeChatView.swift#L923) 到 [Sources/CodeToolCore/ClaudeChatView.swift#L943](Sources/CodeToolCore/ClaudeChatView.swift#L943) 仍保留 Finder 选图入口。
  - 用户已明确要求删除输入框左侧图片按钮，只保留粘贴图片。
- 模型列表当前是硬编码的，和实际 ~/.claude 配置不一致：
  - [Sources/CodeToolCore/ClaudeCLISettingsStore.swift#L53](Sources/CodeToolCore/ClaudeCLISettingsStore.swift#L53) 到 [Sources/CodeToolCore/ClaudeCLISettingsStore.swift#L57](Sources/CodeToolCore/ClaudeCLISettingsStore.swift#L57) 定义了固定的 `availableModels`。
  - 本机 ~/.claude/settings.json 已包含 `env.ANTHROPIC_MODEL`、`ANTHROPIC_SMALL_FAST_MODEL`、`ANTHROPIC_DEFAULT_SONNET_MODEL`、`ANTHROPIC_DEFAULT_OPUS_MODEL`、`ANTHROPIC_DEFAULT_HAIKU_MODEL`，具备作为动态模型来源的条件。
- 当前历史记录尚未保存对话级工作目录：
  - [Sources/CodeToolCore/HistoryStore.swift#L131](Sources/CodeToolCore/HistoryStore.swift#L131) 到 [Sources/CodeToolCore/HistoryStore.swift#L157](Sources/CodeToolCore/HistoryStore.swift#L157) 的 `ClaudeChatHistoryRecord` 不包含 workingDirectory。
  - [Sources/CodeToolCore/ClaudeChatView.swift#L853](Sources/CodeToolCore/ClaudeChatView.swift#L853) 到 [Sources/CodeToolCore/ClaudeChatView.swift#L876](Sources/CodeToolCore/ClaudeChatView.swift#L876) 的 `makeConversationRecord()` 也没有写入目录信息。
- 当前通用头部状态 chip 不支持点击交互：
  - [Sources/CodeToolCore/ToolWorkbench.swift#L3](Sources/CodeToolCore/ToolWorkbench.swift#L3) 到 [Sources/CodeToolCore/ToolWorkbench.swift#L12](Sources/CodeToolCore/ToolWorkbench.swift#L12) 的 `ToolStatusItem` 只有 title、icon、tint。
  - [Sources/CodeToolCore/ToolWorkbench.swift#L89](Sources/CodeToolCore/ToolWorkbench.swift#L89) 到 [Sources/CodeToolCore/ToolWorkbench.swift#L106](Sources/CodeToolCore/ToolWorkbench.swift#L106) 将 statusItems 渲染为纯展示胶囊。

### Key Constraints

- 该仓库要求新 UI 继续复用现有共享壳层和风格系统，不能引入独立页面结构：[Sources/CodeToolCore/ToolWorkbench.swift](Sources/CodeToolCore/ToolWorkbench.swift)、[Sources/CodeToolCore/StyledComponents.swift](Sources/CodeToolCore/StyledComponents.swift)、[Sources/CodeToolCore/Theme.swift](Sources/CodeToolCore/Theme.swift)。
- `swift build` 是最低验证标准；`swift test` 在当前环境可能因 XCTest 模块问题失败，不能默认把测试写成必过前提。
- Claude CLI 仍通过本地 `Process` 调用，不应在这次改动中引入新的桥接协议或重新设计 streaming 解析层。

## Scope

### In Scope

- 让每个 Claude Chat 会话持有独立工作目录，并可从聊天页直接切换。
- 从 ~/.claude/settings.json 动态提取可用模型列表，并在 Settings 中展示。
- 把 Thinking 的默认状态改为收起，保留用户手动展开能力。
- 优化中文 IME 和图片粘贴下的输入体验，减少卡顿。
- 删除输入框左侧选图按钮，只保留粘贴图片，并强化提示文案。
- 将工作目录纳入 Claude Chat 历史记录，保证恢复对话时目录一致。

### Out of Scope

- 不改 Claude CLI 的协议格式、stream-json 事件解析或工具调用展示结构。
- 不引入图片上传到 CLI 的新 payload 协议，继续沿用“本地落盘 + prompt 注入图片路径”。
- 不实现多目录 profile、最近目录列表或 workspace 自动推断目录。
- 不在这次改动中增加拖拽图片，除非实现过程中发现几乎零成本；当前用户明确需求仅为粘贴图片。
- 不展示 ~/.claude/settings.json 的全部配置上下文，首期只用于模型来源。

## Implementation Approach

采用最小侵入式方案，沿着现有状态流做增量修改：

1. 把“工作目录”从全局设置下沉为会话状态，由 ClaudeChatView 明确持有并传给 ClaudeCLIClient。
2. 为避免 IME 组合输入阶段频繁同步 SwiftUI 状态，在 NSTextView 层识别 marked text，仅在组合确认后再更新绑定。
3. 新增轻量配置读取器解析 ~/.claude/settings.json，将模型发现和 CLI 路径发现保持为同等级配置能力。
4. 对 ToolWorkbench 做小幅扩展，让状态区支持可点击 chip，而不是在 ClaudeChatView 私自复制头部 UI。
5. 历史模型做向后兼容扩展，新增可选字段保存 workingDirectory，避免破坏旧记录解码。

## Phase 1: Thinking 默认收起

### Overview

修正 thinking block 的默认展开逻辑，使流式阶段继续自动展开，但消息完成后默认收起；从历史恢复时也保持收起。

### Changes Required

#### 1. ClaudeChatView thinking 状态逻辑
**File**: `Sources/CodeToolCore/ClaudeChatView.swift`
**Changes**:
- 保留 `thinkingBlock(_:messageId:isStreaming:)` 中 `isStreaming` 时自动展开的逻辑。
- 删除 `finalizeStreamingAssistantIfNeeded()` 中自动 `showThinking.insert(message.id)` 的行为。
- 删除 `restoreChat()` 中对所有 thinking 消息预填 `showThinking` 的逻辑。
- 确认 `clearChat()` 和新建会话时 `showThinking` 仍会被清空。

### Success Criteria

#### Automated Verification:
- [x] `swift build`
- [x] 搜索代码确认 `finalizeStreamingAssistantIfNeeded()` 不再自动把 finalized assistant thinking 加入 `showThinking`

#### Manual Verification:
- [x] 发送一条会触发 thinking 的消息，流式期间 thinking 自动展开。
- [x] 响应结束后同一条 thinking 自动收起，点击后可再次展开。
- [x] 从 History 恢复旧对话时，thinking 默认收起。

---

## Phase 2: 输入性能优化

### Overview

减少中文输入法组合输入和粘贴图片场景下的卡顿，重点优化 NSTextView 到 SwiftUI 的状态同步频率，而不是引入复杂 debounce 机制。

### Changes Required

#### 1. ComposerTextView IME 组合输入处理
**File**: `Sources/CodeToolCore/ClaudeChatComposer.swift`
**Changes**:
- 在 `Coordinator.textDidChange` 中识别 `textView.markedRange()` 或等价 API，若当前存在 marked text，则暂不更新 `parent.text`。
- 在组合输入确认后同步完整文本，避免拼音输入过程中每次候选变化都触发 SwiftUI 状态更新。
- 如有必要，在 `Coordinator` 增加一个轻量的 `lastCommittedText` 缓冲，避免重复写入相同文本。

#### 2. Composer 更新路径去抖式短路
**File**: `Sources/CodeToolCore/ClaudeChatComposer.swift`
**Changes**:
- 保留 `updateNSView` 的 `if textView.string != text` 守卫。
- 检查是否需要在 `updateNSView` 中额外避免覆盖当前 marked text 状态，防止输入法组合被打断。

#### 3. 输入区文案与粘贴交互协同优化
**File**: `Sources/CodeToolCore/ClaudeChatView.swift`
**Changes**:
- 更新 placeholder 文案，明确提示“可直接粘贴图片”。
- 检查 `handlePastedImages(_:)` 在多张图片场景下是否有多次状态追加导致明显卡顿；必要时先批量组装数组再一次性 append。

### Success Criteria

#### Automated Verification:
- [x] `swift build`
- [x] 代码检查确认输入法组合期间不会在每次 `textDidChange` 都写回 SwiftUI `@State`

#### Manual Verification:
- [x] 使用中文输入法连续输入长句，不出现明显卡顿或候选中断。
- [x] 粘贴单张截图时输入框无明显冻结。
- [x] 粘贴多张图片时预览能稳定出现，文本输入不被打断。

---

## Phase 3: ~/.claude 模型配置读取

### Overview

新增对 ~/.claude/settings.json 的读取能力，从 CLI 自有配置中提取模型列表，替代目前硬编码的 `availableModels`，同时保持 fallback 逻辑，避免用户本地缺少配置时失效。

### Changes Required

#### 1. 新增 Claude 配置读取器
**File**: `Sources/CodeToolCore/ClaudeConfigReader.swift`
**Changes**:
- 新增一个轻量 reader/decoder，用于读取 `~/.claude/settings.json`。
- 定义最小解码模型，只解析需要的字段：`env.ANTHROPIC_MODEL`、`ANTHROPIC_SMALL_FAST_MODEL`、`ANTHROPIC_DEFAULT_SONNET_MODEL`、`ANTHROPIC_DEFAULT_OPUS_MODEL`、`ANTHROPIC_DEFAULT_HAIKU_MODEL`。
- 做好文件不存在、JSON 非法和字段缺失时的容错。
- 输出去重后的 `[String]` 模型列表，并保留当前硬编码数组作为 fallback。

#### 2. ClaudeCLISettingsStore 模型来源重构
**File**: `Sources/CodeToolCore/ClaudeCLISettingsStore.swift`
**Changes**:
- 将 `availableModels` 从静态常量改为动态来源，支持从 `ClaudeConfigReader` 加载。
- 为 UI 提供稳定访问接口，例如 `availableModels` 计算属性或在初始化时缓存。
- 保证 `resetToDefaults()` 与默认 model 的兼容性；若当前 model 不在动态列表里，仍允许保留已有值。

#### 3. ClaudeCLISettingsView 模型展示更新
**File**: `Sources/CodeToolCore/ClaudeCLISettingsView.swift`
**Changes**:
- Picker 改为消费 store 的动态模型列表。
- 如读取失败且只能 fallback，可考虑用现有 status 或说明文案提示来源为默认列表，但不额外增加复杂错误 UI。

### Success Criteria

#### Automated Verification:
- [x] `swift build`
- [x] 代码检查确认 Settings 不再只依赖硬编码模型列表

#### Manual Verification:
- [x] 当 ~/.claude/settings.json 存在模型字段时，Settings 的 model picker 能展示对应模型。
- [x] 当 ~/.claude/settings.json 缺失或字段为空时，Settings 仍回退到内置默认模型列表。
- [x] 当前已保存 model 值不会因列表刷新被意外清空。

---

## Phase 4: Per-chat 工作目录

### Overview

把工作目录从全局设置迁移到每个 chat 会话自身的状态中，并在 Claude Chat 页头部状态区通过可点击 chip 完成切换。

### Changes Required

#### 1. ClaudeChatView 对话级工作目录状态
**File**: `Sources/CodeToolCore/ClaudeChatView.swift`
**Changes**:
- 新增 `@State private var workingDirectory`，对新 chat 初始化为用户 Home 目录或合理默认值。
- `clearChat()` 时重置为默认目录。
- `sendMessage()` 调用 client 时显式传入本次会话的 working directory。
- 在状态区新增当前目录展示，文案建议使用最后一级目录名，tooltip/secondary text 展示全路径。
- 新增目录选择动作，使用 `NSOpenPanel` 选择目录。

#### 2. ToolWorkbench 状态 chip 可点击能力
**File**: `Sources/CodeToolCore/ToolWorkbench.swift`
**Changes**:
- 扩展 `ToolStatusItem` 支持可选 action、help 或 accessibility 文案。
- 状态区在 item 可点击时渲染为 Button，否则继续保持纯展示 Label。
- 改动保持对其它工具页向后兼容。

#### 3. ClaudeCLIClient 显式接收 workingDirectory
**File**: `Sources/CodeToolCore/ClaudeCLIClient.swift`
**Changes**:
- 在 `send(request:settings:onEvent:)` 与底层 `send(message:settings:sessionId:referenceID:onEvent:)` 之间增加 working directory 参数。
- 去掉对 `settings.workingDirectory` 的直接依赖，改为优先使用请求显式传入的目录。
- 日志里的 `workingDirectory` 元数据同步改为记录本次 chat 实际目录。

#### 4. 历史记录保存/恢复 workingDirectory
**File**: `Sources/CodeToolCore/HistoryStore.swift`
**Changes**:
- 给 `ClaudeChatHistoryRecord` 新增 `workingDirectory: String?` 可选字段。
- 保持 Codable 向后兼容，旧记录不受影响。

**File**: `Sources/CodeToolCore/ClaudeChatView.swift`
**Changes**:
- `makeConversationRecord()` 写入当前会话 workingDirectory。
- `restoreChat()` 恢复该字段；旧记录缺失时回退到默认目录。

#### 5. Settings 中移除工作目录
**File**: `Sources/CodeToolCore/ClaudeCLISettingsStore.swift`
**Changes**:
- 删除 `workingDirectory` 的持久化 key、属性和 reset 逻辑。

**File**: `Sources/CodeToolCore/ClaudeCLISettingsView.swift`
**Changes**:
- 删除 Working Directory section 和 `chooseWorkingDirectory()`。
- 保留 CLI path、API key、model、limits、system prompt 等全局配置。

#### 6. 测试更新
**File**: `Tests/CodeToolTests/CodeToolTests.swift`
**Changes**:
- 更新 `ClaudeChatHistoryRecord` Codable 测试，覆盖新字段的编码/解码兼容。
- 如现有 CLI client 测试能方便扩展，新增一个 working directory 相关单测，验证 send 链路不再依赖 settings 中的目录字段。

### Success Criteria

#### Automated Verification:
- [x] `swift build`
- [ ] 如测试可运行，执行 `swift test --filter CodeToolTests/testClaudeChatHistoryRecordCodable`
- [x] 代码检查确认 `ClaudeCLISettingsStore` 不再持有 `workingDirectory`

#### Manual Verification:
- [x] Claude Chat 顶部状态区显示当前工作目录 chip，点击后可切换目录。
- [x] 在不同 chat 会话中可使用不同目录，互不影响。
- [x] 恢复历史对话后，目录 chip 恢复为当时的工作目录。
- [x] Settings 页面不再出现 Working Directory 配置项。

---

## Phase 5: 图片交互简化

### Overview

删除输入框左侧图片按钮，只保留粘贴图片的工作流，并通过文案和附件预览保持交互可理解。

### Changes Required

#### 1. 移除 Finder 选图入口
**File**: `Sources/CodeToolCore/ClaudeChatView.swift`
**Changes**:
- 删除输入区左侧 `photo.badge.plus` 按钮。
- 删除 `pickImageFile()` 及其调用路径。
- 保留 `composerImages` 缩略图预览和删除能力，因为它是当前唯一附件确认与回退手段。

#### 2. 强化粘贴提示
**File**: `Sources/CodeToolCore/ClaudeChatView.swift`
**Changes**:
- placeholder 文案改为显式提示输入文字、Enter 发送、Shift+Enter 换行、Cmd+V 粘贴图片。
- 如空间允许，可在附件 warning 区域或预览区补充一条低干扰提示，但优先避免视觉噪音。

#### 3. Composer 注释与行为说明同步
**File**: `Sources/CodeToolCore/ClaudeChatComposer.swift`
**Changes**:
- 确认头部注释与真实交互一致，明确“支持粘贴图片”。
- 如粘贴图片时需要更稳妥地处理多类型 pasteboard 数据，可把现有识别逻辑整理得更可维护，但不扩大功能范围。

### Success Criteria

#### Automated Verification:
- [x] `swift build`
- [x] 搜索代码确认 Claude Chat 输入区不再保留文件选择图片按钮与 `pickImageFile()` 调用

#### Manual Verification:
- [x] 输入区左侧不再显示图片选择按钮。
- [x] 用户复制截图后按 Cmd+V，图片能进入附件预览区。
- [x] 附件预览仍可单独删除，发送后图片路径仍能随 prompt 发给 Claude CLI。
- [x] 未读代码的用户也能从 placeholder 文案理解“可以直接粘贴图片”。

---

## Testing Strategy

### Build Verification
- `swift build`

### Targeted Tests
- `swift test --filter CodeToolTests/testClaudeChatHistoryRecordCodable`
- 如环境允许，可增加并运行一个 Claude CLI client working directory 的定向测试。

### Manual Testing Steps
1. 打开 Claude Chat，确认状态区新增工作目录 chip，且可点击切换。
2. 新建一个 chat，切换目录后发送消息，确认 Claude CLI 在目标目录执行。
3. 发送带 thinking 的请求，确认流式期间展开、完成后收起。
4. 使用中文输入法连续输入一段较长文字，确认无明显卡顿或候选闪断。
5. 复制截图并在输入框按 Cmd+V，确认图片进入预览区并可删除。
6. 发送含图片的消息，确认生成后的用户消息仍保留附件记录。
7. 通过 History 恢复对话，确认 working directory 与 thinking 默认收起状态都正确恢复。
8. 打开 Settings，确认模型列表来自 ~/.claude/settings.json，且 Working Directory 配置已移除。

## Performance Considerations

- IME 优化重点是减少组合输入阶段的无效 SwiftUI 状态同步，而不是增加通用 debounce。通用 debounce 容易引入光标、撤销栈和提交时机问题，不适合 NSTextView 聊天输入。
- status chip 交互扩展应保持轻量，避免为了一个可点击目录 chip 重构整个 ToolWorkbench header。
- 图片仍然按当前方案在发送前落盘，不在这次优化中改为内存直传，以避免协议与历史层联动风险。

## Migration Notes

- `ClaudeChatHistoryRecord` 新增 `workingDirectory` 时必须保持可选字段，确保旧历史 JSON 可继续解码。
- 从 Settings 移除 Working Directory 后，旧的 UserDefaults 键即使残留也不应影响运行；无需额外 migration UI。
- 如果用户当前本地 ~/.claude/settings.json 的模型值与 app 中已保存的 `settings.model` 不一致，UI 应允许继续保留旧值，避免自动覆盖用户已有选择。

## References

- Related code: `Sources/CodeToolCore/ClaudeChatView.swift`
- Related code: `Sources/CodeToolCore/ClaudeChatComposer.swift`
- Related code: `Sources/CodeToolCore/ClaudeCLIClient.swift`
- Related code: `Sources/CodeToolCore/ClaudeCLISettingsStore.swift`
- Related code: `Sources/CodeToolCore/ClaudeCLISettingsView.swift`
- Related code: `Sources/CodeToolCore/ToolWorkbench.swift`
- Related code: `Sources/CodeToolCore/HistoryStore.swift`
- Related tests: `Tests/CodeToolTests/CodeToolTests.swift`
- Existing related plan: `thoughts/shared/plans/2026-03-31-claude-cli-optimization.md`
