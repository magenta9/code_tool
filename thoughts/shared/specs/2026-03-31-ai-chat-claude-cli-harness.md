---
date: 2026-03-31T14:55:00+08:00
researcher: zhang
git_commit: 3cc92808c771abaef20e06d3386e2e36b1e25556
branch: main
topic: "AI Chat Claude CLI Harness"
tags: [research-spec, requirements, claude-cli, ai-chat, refactor]
status: complete
confidence: high
last_updated: 2026-03-31
last_updated_by: zhang
---

# AI Chat → Claude CLI Harness Research Spec

## Summary

将 AI Chat 从基于 MiniMax HTTP API 的实现改为基于本地 Claude CLI (`claude`) 子进程的封装，通过 `Process` 启动 `claude -p --output-format stream-json` 实现流式对话，获得 Claude 的完整 agentic 能力（文件读写、Bash 执行、代码搜索等）。

## Background

### 现状

注：当前产品中的活动 AI Chat 路由已经切到 `ClaudeChatView`。本文中的 `AIChatView` 描述仅作为迁移背景保留，应按 legacy 路径理解。

AI Chat 在该迁移 spec 编写时基于 MiniMax M2.7 模型：
- `AIChatView.swift` → 当时的 UI 层，消息气泡 + 输入框 + system prompt（现已移除）
- `MiniMaxAPIClient.chatCompletionStream()` → SSE 流式请求到 `/chat/completions`
- `MiniMaxProvider.swift` → API Key + 模型配置（UserDefaults 持久化）
- `HistoryStore.swift` → JSON 文件持久化对话历史

### 痛点

1. MiniMax M2.7 能力有限，不如 Claude 系列模型
2. 仅支持纯文本聊天，无 agentic 能力（不能读写文件、执行命令）
3. Token 计数为估算值（字符数÷4），不精确
4. 无花费追踪

### 机遇

Claude CLI v2.1.81 已安装在 `/opt/homebrew/bin/claude`，支持：
- `--output-format stream-json --verbose --include-partial-messages`：token 级别流式 NDJSON 输出
- `--bare`：跳过 hooks/plugins/MCP，快速启动
- `--session-id`：指定会话 ID 实现多轮对话
- `--max-turns`/`--max-budget-usd`：安全限制
- `--append-system-prompt`：追加 system prompt
- `--model`：动态选择模型
- 内置工具：Bash、Read、Edit、Write、Glob、Grep 等
- 认证：支持 ANTHROPIC_API_KEY 环境变量和 OAuth 登录态

## Goals

- 将 AI Chat 后端从 MiniMax API 替换为 Claude CLI 子进程
- 保留 Claude CLI 的完整 agentic 能力（文件读写、命令执行等）
- 实现 token 级别流式渲染（来自 `stream_event` 的 `text_delta`）
- 显示精确的 token 计数和 USD 花费（来自 `result` 消息）
- 显示 Claude 的 thinking 过程（可折叠）
- 显示工具调用过程（文件操作、Bash 执行等的进度指示）
- 支持会话续接（通过 `--session-id` 或 `-c`）

## Non-goals

- 不改动 AI Speech / AI Image / AI Music — 这些继续使用 MiniMax
- 不实现自定义 MCP 服务器配置 UI（用户可在 CLI 层面配置）
- 不实现权限弹窗 UI（使用 `--dangerously-skip-permissions` 或 `--permission-mode plan`）
- 不做 MiniMax 设置的迁移/删除 — MiniMaxSettingsStore 仍服务于其他 AI 工具
- 不自动安装 Claude CLI — 要求用户预先安装

## Requirements

### Functional Requirements

#### FR1: Claude CLI 进程管理（ClaudeCLIClient）

新增 `ClaudeCLIClient.swift`，封装 Claude CLI 子进程交互：

- **启动进程**：通过 `Process` 启动 `claude` 二进制，传入参数列表
- **标准参数**：`-p --output-format stream-json --verbose --include-partial-messages`
- **可选参数映射**：
  | UI 设置 | CLI 参数 |
  |--------|---------|
  | 模型选择 | `--model <model>` |
  | System Prompt | `--append-system-prompt "<text>"` |
  | 最大轮次 | `--max-turns <N>` |
  | 花费上限 | `--max-budget-usd <N>` |
  | 会话 ID | `--session-id <uuid>` |
  | 快速启动 | `--bare` |
  | 工作目录 | Process.currentDirectoryURL |
- **输出解析**：逐行读取 stdout，JSON 解析 NDJSON 流
- **进程生命周期**：一次 `sendMessage()` 调用 = 一次 CLI 进程的完整生命周期（启动→输出→退出）
- **中断支持**：`cancel()` 方法通过 `process.terminate()` (SIGTERM) 中止当前请求

#### FR2: NDJSON 流解析

解析 Claude CLI 的 stream-json 输出，识别以下消息类型：

| type | subtype/event | 用途 | 需要处理 |
|------|--------------|------|---------|
| `system` | `init` | 会话初始化，含 session_id、model、tools | 提取 session_id 缓存 |
| `stream_event` | `content_block_start` (type=thinking) | thinking 块开始 | 开始累积 thinking 内容 |
| `stream_event` | `content_block_delta` (type=thinking_delta) | thinking 增量 | 更新 thinking 显示 |
| `stream_event` | `content_block_start` (type=text) | 文本块开始 | 开始累积回复文本 |
| `stream_event` | `content_block_delta` (type=text_delta) | **文本增量** | **主要流式渲染来源** |
| `stream_event` | `content_block_start` (type=tool_use) | 工具调用开始 | 显示工具使用指示器 |
| `stream_event` | `content_block_delta` (type=input_json_delta) | 工具参数增量 | 更新工具调用参数显示 |
| `stream_event` | `content_block_stop` | 块结束 | 关闭当前块 |
| `stream_event` | `message_start` | 消息开始 | 清除上一轮内容 |
| `stream_event` | `message_delta` (stop_reason) | 消息结束 | 检查 stop_reason |
| `assistant` | — | 完整助手消息快照 | 可忽略（已从 delta 构建） |
| `result` | `success`/`error` | **最终结果** | **提取 cost、usage、duration** |

#### FR3: UI 改造（AIChatView → ClaudeChatView）

将 `AIChatView` 重构为 `ClaudeChatView`（或原地修改），调整 UI：

**保留不变的部分**：
- ToolWorkbench 外壳（eyebrow/title/statusItems/actions）
- 消息列表（ScrollView + LazyVStack + 气泡布局）
- 输入区域（TextEditor + 发送按钮）
- StyledPanel、StyledButton 等共享组件的使用

**需要修改的部分**：

1. **消息模型扩展**：从 `(role: String, content: String)` 元组改为结构体：
   ```swift
   struct ChatMessage: Identifiable {
       let id: UUID
       let role: MessageRole  // .user, .assistant, .system, .toolUse, .toolResult
       var content: String
       var thinkingContent: String?  // Claude thinking 过程
       var toolName: String?         // 工具名称（如 "Bash", "Read"）
       var toolInput: String?        // 工具输入
       var isStreaming: Bool         // 是否正在流式接收
   }
   ```

2. **Thinking 折叠区域**：assistant 消息内，如果有 thinkingContent，显示一个可折叠的"Thinking..."区块，使用淡灰色背景 + 斜体文字

3. **工具调用指示器**：当 Claude 使用工具时，在消息列表中插入一个紧凑的工具调用条目：
   - 图标 + 工具名称（如 🔧 Bash: `ls -la`）
   - 折叠可查看完整输入/输出
   - 使用 `AppTheme.surface` 背景区分于普通消息

4. **状态栏增强**：
   - 消息计数 badge（保留）
   - 精确 token 计数（来自 `result.usage`，替代估算值）
   - **花费显示**：`$0.26 USD`（来自 `result.total_cost_usd`）
   - **模型名称**：显示实际使用的模型（来自 `init.model`）
   - 流式指示器（保留）

5. **输入区域增强**：
   - 移除 System Prompt 折叠区域 → 改为设置面板中的选项
   - 新增"Stop"按钮：流式中显示，点击调用 `ClaudeCLIClient.cancel()`

#### FR4: 设置面板（ClaudeCLISettingsView）

新增 Claude CLI 专属设置视图，或在 MiniMaxSettingsView 中新增 "Claude CLI" tab：

| 设置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| Claude 路径 | String | 自动发现 | `/opt/homebrew/bin/claude` 等 |
| API Key (可选) | String | 空 | 覆盖系统认证，传为 env var |
| 模型 | Picker | `claude-sonnet-4-6` | 可选 opus/sonnet/haiku |
| System Prompt | TextEditor | 空 | 全局 append system prompt |
| 最大轮次 | Stepper | 10 | `--max-turns` |
| 花费上限 (USD) | TextField | 5.0 | `--max-budget-usd` |
| 快速启动 | Toggle | true | `--bare` 跳过 hooks/plugins |
| 工作目录 | 目录选择器 | `~` | Process cwd |

设置通过 `UserDefaults` 持久化（key prefix: `claudeCLI_`），新建 `ClaudeCLISettingsStore` 单例。

#### FR5: Claude CLI 二进制发现

启动时自动搜索 `claude` 可执行文件：

搜索顺序：
1. 用户在设置中指定的路径
2. `/opt/homebrew/bin/claude`（Apple Silicon Homebrew）
3. `/usr/local/bin/claude`（Intel Homebrew）
4. `~/.local/bin/claude`（npm global）
5. `~/.claude/local/claude`
6. 通过 `Process("/usr/bin/which", ["claude"])` 动态查找

如果未找到，在 UI 中显示 `ToolMessageBanner` 警告："Claude CLI not found. Install with: `npm install -g @anthropic-ai/claude-code`"

#### FR6: 会话管理

- 每次 `clearChat()` 生成新的 UUID 作为 `sessionId`
- 后续消息发送时都传 `--session-id <sessionId>` 实现多轮对话上下文续接
- Claude CLI 自己管理会话历史（`~/.claude/projects/` 下），app 不需要手动拼接消息数组
- 这意味着**不再需要**将全部消息历史传入每次请求（Claude CLI 自己维护上下文）

#### FR7: 历史记录适配

调整 `ChatHistoryRecord` 以适配 Claude CLI 输出：

```swift
struct ChatHistoryRecord: Codable {
    let id: UUID
    let createdAt: Date
    let systemPrompt: String?
    let messages: [ChatMessageRecord]
    let model: String          // 从 init 消息获取
    let totalCostUSD: Double?  // 从 result 消息获取
    let inputTokens: Int?      // 精确值
    let outputTokens: Int?     // 精确值
    let durationMs: Int?       // 从 result.duration_ms 获取
    let sessionId: String?     // Claude session ID
    let referenceID: String
}
```

**ChatMessageRecord 扩展**：
```swift
struct ChatMessageRecord: Codable {
    let role: String
    let content: String
    let thinkingContent: String?  // 新增
    let toolName: String?         // 新增
    let toolInput: String?        // 新增
}
```

#### FR8: ToolRegistry 和 ContentView 路由更新

- `ToolRegistry.defaults` 中 "AI Chat" 条目保持名称不变，更新描述
- `ContentView.swift` 中 `case "AI Chat"` 路由到新的 view（`ClaudeChatView()`）
- 侧边栏中展示名称不变为 "AI Chat"

### Non-functional Requirements

- **性能**：Claude CLI 冷启动含 `--bare` 约 1-3 秒，可接受。后续请求使用 `--session-id` 续接，Claude CLI 自行管理缓存
- **安全**：
  - 不在日志中记录 API Key
  - `--dangerously-skip-permissions` 仅在用户显式开启时使用
  - 默认使用 `--permission-mode plan`（只读 + 规划，不执行）
  - 子进程环境变量最小化传递
- **兼容性**：Mac 专属（已有项 — CodeTool 是 macOS app）
- **可用性**：CLI 未安装时降级为清晰的安装引导，不崩溃

### Constraints

- 依赖 Claude CLI 已安装（v2.0.0+）
- 依赖系统认证（OAuth 登录或 ANTHROPIC_API_KEY）
- Mac only（`Process` 是 Foundation 的 `NSTask` 封装）
- Claude CLI 的 `stream-json` 格式是非官方契约，可能在升级中变化
- 每次消息发送启动新进程（非长驻 daemon），有冷启动开销

### Assumptions

- 用户已安装 Claude CLI v2.0.0+ 并完成认证
- Claude CLI 的 stream-json NDJSON 格式在主要版本内保持向后兼容
- 用户可接受每次请求的 1-3 秒冷启动延迟
- `--session-id` 可实现跨进程调用的上下文续接

## Architecture

### 新增文件

```
Sources/CodeToolCore/
├── ClaudeCLIClient.swift         # 核心：Process 封装 + NDJSON 解析
├── ClaudeCLISettingsStore.swift   # 设置持久化（UserDefaults）
├── ClaudeCLISettingsView.swift    # 设置 UI（可能合入 MiniMaxSettingsView 作为 tab）
└── ClaudeChatView.swift           # 新 Chat UI
```

### 修改文件

```
Sources/CodeToolCore/
├── ContentView.swift      # 路由更新："AI Chat" → ClaudeChatView
├── AIChatView.swift       # 迁移阶段的旧路径说明；当前仓库已移除该 UI 文件
├── HistoryStore.swift     # ChatHistoryRecord/ChatMessageRecord 扩展
├── Tool.swift             # "AI Chat" 描述更新
Tests/CodeToolTests/
├── CodeToolTests.swift    # 测试更新
```

### 数据流

```
用户输入 → ClaudeChatView.sendMessage()
  ├─ 构建 claude 参数列表
  │   [-p, --output-format, stream-json, --verbose,
  │    --include-partial-messages, --model, <model>,
  │    --session-id, <uuid>, --max-turns, <N>, --bare,
  │    --append-system-prompt, <text>, <user_message>]
  │
  ├─ ClaudeCLIClient.send(arguments:)
  │   ├─ Process(executableURL: claudePath, arguments: args)
  │   ├─ 可选 env: [ANTHROPIC_API_KEY: <key>]
  │   ├─ process.standardOutput → Pipe → FileHandle
  │   └─ readLine loop (逐行 NDJSON)
  │       ├─ type:"system" subtype:"init" → 提取 session_id, model
  │       ├─ type:"stream_event" event.type:"content_block_delta"
  │       │   ├─ delta.type:"thinking_delta" → onThinking(text)
  │       │   └─ delta.type:"text_delta" → onTextDelta(text)  ← 主要流式渲染
  │       ├─ type:"stream_event" event.type:"content_block_start" (tool_use)
  │       │   → onToolUseStart(name, id)
  │       ├─ type:"result" → onResult(cost, usage, duration)
  │       └─ process exit → onComplete()
  │
  ├─ UI 更新（MainActor）
  │   ├─ streamingContent += delta → 气泡实时渲染
  │   ├─ thinkingContent += delta → thinking 区域实时渲染
  │   └─ 工具调用 → 插入工具调用指示器
  │
  ├─ 完成后
  │   ├─ 将完整消息追加到 messages[]
  │   ├─ 更新 token 计数、花费（精确值）
  │   └─ HistoryStore.save()
  │
  └─ 错误处理
      ├─ process exit code != 0 → 显示错误
      ├─ stderr 输出 → 解析错误信息
      └─ SIGTERM (cancel) → 显示"已中断"
```

## Edge Cases

| 场景 | 预期行为 |
| --- | --- |
| Claude CLI 未安装 | ToolMessageBanner 显示安装指引，禁用发送按钮 |
| Claude CLI 版本过低（不支持 stream-json） | 解析失败时 fallback 到 text 模式，显示版本升级提示 |
| 认证失败/过期 | 解析 stderr 或 exit code，显示 "Please run `claude` in terminal to authenticate" |
| 请求超时（进程长时间无输出） | 120 秒无新输出时自动 terminate，显示超时错误 |
| 用户在流式中发送新消息 | 禁用发送按钮直到当前流完成（与现行为一致） |
| 用户点击 Stop 中断流式 | SIGTERM 终止进程，将已接收的内容作为部分回复显示 |
| Claude 使用工具但进程被中断 | 工具调用条目显示"已中断"状态 |
| 多轮对话中 session 数据损坏 | 捕获错误，自动生成新 session ID 重试 |
| claude 进程 crash（SIGABRT 等） | 捕获非零 exit code，显示 stderr 内容 |
| rate limit 被触发 | 解析 result 消息中的 rate limit 信息，显示等待时间 |
| API Key 配置了无效值 | 传为 env var 后 Claude CLI 会在 stderr 报错，解析显示 |
| `--bare` 模式下无 MCP 工具 | 预期行为 — 快速启动模式下不加载 MCP |
| 并发请求 | 一次只允许一个 Process 实例，发送按钮在流式中禁用 |
| 工作目录不存在 | fallback 到 `~`，显示警告 |

## Dependencies

- **Claude CLI** (`claude` v2.0.0+)：核心依赖，必须预装
- **Foundation/Process**：macOS 子进程 API
- **SwiftUI**：UI 框架（已有）
- **HistoryStore**：历史持久化（已有，需扩展）
- **MiniMaxSettingsStore**：仍服务于 Speech/Image/Music（不修改）
- **ToolWorkbench / StyledComponents / AppTheme**：UI 共享组件（不修改）

## Acceptance Criteria

- [ ] `ClaudeCLIClient` 能启动 claude 进程并解析 stream-json NDJSON 输出
- [ ] 文本增量（text_delta）在 UI 中实时流式渲染，延迟 < 100ms
- [ ] Thinking 内容在可折叠区域显示
- [ ] 工具调用（Bash、Read 等）在消息列表中有可视指示
- [ ] 精确的 token 计数和 USD 花费在状态栏显示（来自 result 消息）
- [ ] 会话续接工作正常（使用 --session-id，多轮对话有上下文）
- [ ] Stop 按钮能中断流式并显示已接收的部分内容
- [ ] Claude CLI 未安装时显示清晰的安装指引
- [ ] 认证失败时显示有意义的错误信息
- [ ] 设置面板支持模型选择、最大轮次、花费上限等配置
- [ ] 对话完成后 HistoryStore 持久化记录含 cost 和精确 token
- [ ] AI Speech / AI Image / AI Music 功能不受影响
- [ ] `swift build` 编译通过
- [ ] 现有测试（tool count 等）更新后通过

## Success Metrics

- 用户可在 app 内直接使用 Claude 的全部能力（聊天 + 工具使用）
- 流式渲染体验与 Claude CLI 终端交互一致
- 精确的花费追踪帮助用户控制成本
- 零额外安装步骤（对已有 claude CLI 的用户）

## Open Questions

- [x] 是否保留 AI Chat 名称？→ **是，保持 "AI Chat"，但 eyebrow 改为 "Claude CLI"**
- [x] 是否在 app 内展示 Claude 的 tool_result？→ **是，折叠显示**
- [x] `--bare` 是否应为默认？→ **是，冷启动更快；用户可在设置中关闭以加载 MCP**
- [x] 权限模式默认值？→ **`plan` — 只读 + 规划，用户可升级到 `acceptEdits`**
- [ ] 是否需要支持多会话（tab 式多对话）？→ 建议后续迭代，本次实现单会话
- [ ] 是否支持对话导出（Markdown/JSON）？→ 建议后续迭代
