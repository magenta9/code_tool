# Pi Official Agent Integration Plan

## Overview

本方案针对当前 CodeTool 的 Electron + React 架构，规划如何接入 Pi 官方 agent 生态，并把现有已经重构出的 workflow / toolcall UI 真正接到结构化事件流上。

结论先说清楚：

- 推荐路线是 main 进程内嵌 Pi SDK，不是首版直接走 RPC 子进程。
- Pi 应该先作为新的 agent/coding 工具接入，不应该硬替代现有 MiniMax 的图像、语音、音乐任务。
- 第一阶段必须引入明确的 workspace 根目录选择，否则 Pi 的 read / edit / bash / grep 等工具没有可控边界。

## Why SDK First

Pi 官方文档同时支持两条嵌入路线：

- SDK：`createAgentSession()` / `AgentSession` 直接在 Node 进程内工作，支持事件订阅、工具注入、session 管理、settings、auth 和资源加载。
- RPC：`pi --mode rpc` 通过 stdin/stdout JSONL 提供协议，支持完整的 event stream、tool execution、queue、compaction 和 extension UI request/response。

对当前项目，SDK 更合适：

- CodeTool 本身就是 Electron，main 进程已负责外部 provider、密钥、文件系统、历史和日志。Pi SDK 放在 main 进程内最贴合当前边界。
- 现在的 AI 接入是 `packages/main/src/providers/minimax/minimax-task-runner.ts` 驱动统一事件，再经 `packages/main/src/ipc/register.ts` 广播到 renderer。Pi SDK 可以沿用这个模型，不需要先引入子进程和 JSONL 协议层。
- Pi 官方 SDK 明确把“build a custom UI (web, desktop, mobile)”当成目标用例；OpenClaw 也采用直接嵌入 `createAgentSession()`，而不是 RPC 子进程。

RPC 只在以下情况下再引入：

- 需要强进程隔离。
- 需要直接复用 Pi CLI/RPC 的 extension UI 协议。
- 后续要支持非 Node 宿主或语言无关客户端。

## Scope Clarification

Pi 是 coding agent，不是多模态生成 provider。

这意味着：

- `AI Chat` 可以接 Pi。
- `AI Image`、`AI Speech`、`AI Music` 仍然应该保留 MiniMax 路线。
- 如果强行把 Pi 塞进现有 `aiImage` / `aiSpeech` / `aiMusic` 抽象，会把请求模型和 UI 语义搅乱。

推荐做法：

- 新增独立工具 `piAgent`，而不是把现在的 `aiChat` 直接改造成 “MiniMax / Pi 混合工具”。
- 现有 `AI Chat` 继续保留 MiniMax 的通用聊天用途。
- `Pi Agent` 作为新的 coding/agent 工具，专门承载 toolcall、workspace、session、queue、compaction、retry、上下文文件和自定义工具。

这样改动更深但更干净，后续 UI 也更容易做成 LobeHub 风格的真正 agent 工作台。

## Current Code Anchors

当前仓库中与 Pi 接入直接相关的锚点如下：

- `packages/shared/src/types/ai.ts`
  - 现在 `AiTaskRequest` 只支持 `provider: "minimax"`。
  - 现在 `AiTaskEvent` 只有 `started / progress / delta / artifact / completed / cancelled / failed`，不足以表达真实 toolcall 生命周期。
- `packages/main/src/providers/minimax/minimax-task-runner.ts`
  - 当前所有 AI 任务都在 main 进程内由 runner 统一驱动，并向 renderer 发统一事件。
- `packages/main/src/ipc/register.ts`
  - AI provider 的装配点在这里。
- `packages/renderer/src/tools/shared/use-ai-task.ts`
  - renderer 当前已经有 workflow rail，但本质上仍然是把粗粒度 `progress` 事件伪装成 toolcall 风格 UI。
- `packages/renderer/src/components/ai-task-chrome.tsx`
  - 已经具备 workflow / artifact / 状态标签的外观层，等待更丰富的事件模型灌入。

这些锚点说明：Pi 最自然的落点是“并列新增一个 Pi provider + Pi tool runner”，而不是在 renderer 里临时拼一个前端 agent。

## Recommended Target Architecture

### 1. Tool and Routing

新增独立工具 `piAgent`。

涉及文件：

- `packages/shared/src/tool-catalog.ts`
- `packages/renderer/src/App.tsx`
- `packages/renderer/src/components/workbench.tsx`
- `README.md`

理由：

- Pi 的 session、toolcall、workspace、queue、compaction 明显超出 MiniMax Chat 的职责。
- 单独路由后可以把 UI 和状态机做深，不需要兼容 MiniMax 的简化模型。

### 2. Main-Process Provider Package

新增：

```text
packages/main/src/providers/pi/
  pi-agent-runner.ts
  pi-session-factory.ts
  pi-settings.ts
  pi-tool-adapter.ts
  pi-event-mapper.ts
```

职责拆分建议：

- `pi-session-factory.ts`
  - 创建 `createAgentSession()` / `createAgentSessionRuntime()` 所需依赖。
  - 组装 `AuthStorage`、`ModelRegistry`、`SettingsManager`、`SessionManager`、`DefaultResourceLoader`。
- `pi-agent-runner.ts`
  - 仿照 `MiniMaxTaskRunner` 暴露 `createTask()`、`cancelTask()`、`onTaskEvent()`。
  - 负责 prompt、abort、session 生命周期和 cleanup。
- `pi-tool-adapter.ts`
  - 组织 Pi 内建 tools 与 CodeTool 自定义 tools。
  - 第一版建议只暴露只读或低风险工具，再逐步放开 edit/write/bash。
- `pi-event-mapper.ts`
  - 把 Pi SDK 事件映射成 CodeTool 的共享事件模型。
- `pi-settings.ts`
  - 封装 Pi 相关目录、模型、provider、thinking level、workspace 根目录、是否允许写工具等设置。

### 3. Storage and Runtime Location

Pi 不应直接污染用户全局 `~/.pi/agent`。

推荐目录：

- `agentDir`: `path.join(app.getPath("userData"), "pi-agent")`
- `sessions`: `path.join(app.getPath("userData"), "pi-agent", "sessions")`
- `settings/models`: 跟随 `agentDir`

好处：

- CodeTool 的 Pi 状态与用户系统级 Pi 配置隔离。
- 打包应用时更可控。
- 迁移、诊断、导出都可落在当前产品数据目录下。

### 4. Auth Strategy

第一版不要依赖 Pi 默认的 `auth.json` 作为唯一真相。

推荐策略：

- 继续保持 “密钥只在 main 进程” 的现有原则。
- 用现有 secrets / settings 机制保存 provider 相关凭据。
- 创建 Pi session 前，用 `AuthStorage.setRuntimeApiKey()` 注入运行时密钥。
- 如果后续需要 OAuth 或多 provider profile，再扩展 Pi 专用 auth 管理层。

这能保持与现有 MiniMax 接入相同的安全边界。

### 5. Workspace Boundary

这是首版必须先解决的问题。

Pi 的核心价值在工具调用，但当前 CodeTool 并没有严肃的 workspace 根目录概念。打包后的 Electron 应用如果直接使用 `process.cwd()`，路径边界会不稳定，甚至可能指向错误目录。

所以第一版必须补：

- Pi tool 页中的 workspace 选择器。
- main 进程中的 `workspaceRoot` 校验与白名单边界。
- tool factory 基于显式 `cwd` 创建，如 `createCodingTools(cwd)` 或 `createReadOnlyTools(cwd)`。

在没有 workspace 选择和校验前，不建议放开 edit/write/bash。

## Shared Event Model Changes

当前 `AiTaskEvent` 太浅，无法承接 Pi 的真实事件面。

建议把共享事件模型拆成两层：

- 保留当前通用层，继续服务 MiniMax。
- 为 agent 类 provider 增加 richer event union。

推荐新增事件：

```ts
type AiTaskEvent =
  | ExistingMiniMaxEvents
  | { type: "agent_start"; taskId: string; provider: "pi"; sessionId: string }
  | { type: "agent_end"; taskId: string; provider: "pi"; messageIds: string[] }
  | { type: "message_start"; taskId: string; messageId: string; role: "assistant" | "user" }
  | { type: "message_delta"; taskId: string; messageId: string; deltaType: "text" | "thinking"; text: string }
  | { type: "toolcall_start"; taskId: string; toolCallId: string; toolName: string; args: unknown }
  | { type: "toolcall_delta"; taskId: string; toolCallId: string; partialResult: unknown }
  | { type: "toolcall_end"; taskId: string; toolCallId: string; result: unknown; isError: boolean }
  | { type: "queue_update"; taskId: string; steering: string[]; followUp: string[] }
  | { type: "compaction_start"; taskId: string; reason: string }
  | { type: "compaction_end"; taskId: string; reason: string; summary?: string; errorMessage?: string }
  | { type: "auto_retry_start"; taskId: string; attempt: number; maxAttempts: number; delayMs: number; errorMessage: string }
  | { type: "auto_retry_end"; taskId: string; success: boolean; attempt: number; finalError?: string }
```

关键点：

- `toolCallId` 必须成为一等标识，renderer 才能真正做 toolcall 卡片与流式进度替换。
- `message_delta` 需要区分 `text` 与 `thinking`，否则 UI 只能继续假装。
- `queue_update`、`compaction_*`、`auto_retry_*` 应该进入侧栏状态区，而不是丢弃。

## Renderer Integration

### 1. New Tool Page

新增：

```text
packages/renderer/src/tools/pi-agent/
  pi-agent.tsx
```

页面结构建议：

- 左侧：对话区 + composer + workspace/context controls
- 右侧：toolcall rail + queue + compaction/retry 状态 + session metadata

这页应直接复用现有：

- `packages/renderer/src/components/ai-task-chrome.tsx`
- `packages/renderer/src/components/tool-layout.tsx`

但要扩展新的渲染能力：

- Thinking block
- Tool call argument block
- Tool execution partial output
- Queue badges
- Compaction banner
- Retry banner

### 2. Hook Strategy

不要继续让 `use-ai-task.ts` 只服务 MiniMax 的浅事件。

建议拆分为：

- `use-ai-task.ts`
  - 保留给 MiniMax 这类轻任务。
- `use-agent-task.ts`
  - 专门处理 Pi 的 message/toolcall/session/queue/compaction/retry 事件。

这样不会把两个完全不同的任务模型硬塞进同一个 hook。

### 3. UX Rules

Pi 页第一版建议：

- 明确显示当前 workspace 根目录。
- 明确显示当前模型 / provider / thinking level。
- 明确显示当前工具权限级别：只读、读写、可执行命令。
- 明确显示 session 状态：streaming、idle、compacting、retrying。

这几项比继续堆视觉细节更重要，因为它们决定 agent 是否可控。

## Suggested Implementation Order

### Phase 1: Provider Spike in Main Only

目标：先证明 Pi SDK 能在 main 进程跑起来，并能把事件映射出来。

实施：

- 新增 `packages/main/src/providers/pi/` 最小 runner。
- 用 `SessionManager.inMemory()`。
- 用显式 `cwd` 和只读工具集。
- 在 `AiHandlers` 上挂新的 create/cancel task 通道。
- 暂时只记录事件到日志，不改 renderer。

验证：

- `pnpm build`
- 一个最小集成测试：发 prompt，收到 `message_update` 文本和至少一个 `tool_execution_*` 事件。

### Phase 2: Shared Contract Expansion

目标：把 Pi 的结构化事件落进共享类型和 IPC 合同。

实施：

- 扩展 `packages/shared/src/types/ai.ts`
- 更新 `packages/shared/src/ipc-contract.ts`
- 为 Pi 和 MiniMax 保持兼容的事件订阅机制

验证：

- shared 类型测试通过
- main -> renderer 事件链路 smoke test 通过

### Phase 3: Pi Agent Renderer Page

目标：把现在的 LobeHub 风格壳子接上真实 toolcall。

实施：

- 新增 `pi-agent.tsx`
- 新增 `use-agent-task.ts`
- 扩展 `ai-task-chrome.tsx` 以渲染 thinking / toolcall / execution output / queue / compaction / retry

验证：

- 页面能显示真实 toolcall 卡片
- streaming text、tool output replace、失败态均可视化

### Phase 4: Workspace + Session Persistence

目标：让 Pi 从 demo 变成可用工具。

实施：

- 引入 workspace 选择器
- `SessionManager.create(workspaceRoot)` 或自定义 session file 管理
- 支持 `newSession`、`switchSession`、`get_state` 等会话能力
- 历史记录中保存 Pi session 摘要与 session file 引用

验证：

- 切换 session 后 renderer 能重新订阅新 session
- workspace 边界正确生效

### Phase 5: Settings, Auth, Tool Policy

目标：把 Pi 变成受控的产品功能，而不是实验入口。

实施：

- 新增 Pi 设置区：provider、model、thinking、tool policy、agentDir/session root
- 从 Keychain/runtime key 注入 Pi auth
- 工具白名单 / 风险级别控制
- 必要时再评估是否补 RPC 模式

验证：

- 配置可持久化
- 未配置认证时有明确错误
- 工具权限切换能真实影响 runtime tools

## File Change Map

如果按推荐路线落地，预计主要改这些文件：

- `packages/shared/src/tool-catalog.ts`
- `packages/shared/src/types/ai.ts`
- `packages/shared/src/ipc-contract.ts`
- `packages/main/src/ipc/register.ts`
- `packages/main/src/ipc/ai.ts`
- `packages/main/src/providers/pi/*`
- `packages/renderer/src/App.tsx`
- `packages/renderer/src/components/workbench.tsx`
- `packages/renderer/src/components/ai-task-chrome.tsx`
- `packages/renderer/src/tools/shared/use-ai-task.ts`
- `packages/renderer/src/tools/shared/use-agent-task.ts`
- `packages/renderer/src/tools/pi-agent/pi-agent.tsx`
- `packages/renderer/src/routes/settings.tsx`
- `README.md`

## Risks and Constraints

### 1. Tool Safety

不解决 workspace 和 tool policy，就不要开放写文件和 bash。

### 2. Event Volume

Pi 的 `message_update`、`tool_execution_update`、`queue_update` 事件量明显高于当前 MiniMax。renderer 侧需要做增量归并，不然 UI 会抖动。

### 3. Session Semantics

Pi session 是树结构和可 fork 的，不是当前 `HistoryRepository` 这种单条记录模型。第一版不要试图把整个 session 树硬塞进当前历史 schema。

### 4. Extension UI

如果后续转向 RPC 或加载依赖 UI 交互的扩展，会碰到 extension UI request/response 子协议。第一版 SDK 路线最好避免依赖这类扩展。

## Final Recommendation

对当前仓库，最稳且价值最高的路径是：

1. 新增独立 `piAgent` 工具，而不是改造现有 MiniMax 多模态工具。
2. 在 main 进程内嵌 Pi SDK，先做只读 workspace agent。
3. 扩展共享事件模型，让现有 LobeHub 风格 UI 吃到真正的 toolcall / queue / compaction / retry 事件。
4. 等 workspace、session、权限和 auth 边界稳定后，再评估是否需要 RPC 模式或更复杂的 Pi 扩展能力。

这是当前代码库里技术风险最低、UI 收益最高、且能最快把“伪 toolcall”变成“真 toolcall”的路线。