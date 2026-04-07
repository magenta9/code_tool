# Hermes Agent UI Wrapper Implementation Plan

## Overview

为 CodeTool 新增一个独立的 AI 工具 Hermes Agent，采用本地 Hermes CLI 子进程封装，而不是把 Hermes 塞进现有 AI Chat provider 切换或强行压进 `AIExecutionSession`。该工具需要提供独立会话 UI、任意文件附件输入、New Chat、Stop、Resume 入口，以及基于 `referenceID` 的诊断链路。

本计划基于两类事实收敛实现路径：

1. 仓库内部已经有稳定的工具接入、SettingsSheet、Diagnostics 与 Claude Chat 本地 CLI 壳层模式。
2. 官方 Hermes 文档确认存在本地 CLI、sessions、本地 context references 与 ACP/API Server 等表面，但 plain CLI 没有像 Claude CLI 那样明确承诺稳定的机器流协议。

因此，Hermes V1 的正确落点不是“复刻 Claude Chat 的全部 streaming/tool-use 语义”，而是：

- 用官方文档支持的 CLI surface 建立稳定的发送/停止/恢复闭环。
- 把 timeline 设计成可降级面板：默认至少展示本地阶段进度与最终输出；只有当前 Hermes 版本暴露出可验证的结构化过程信息时才升级为真实 tool cards。
- 不读取私有 SQLite schema，不承诺用户可恢复历史，不把 ACP/API Server 拉进 V1 主范围。

## Current State Analysis

### Key Discoveries

- 工具接入边界已经稳定：`ToolID`、`ToolCatalog`、`ToolRegistry.defaults` 在 `Sources/CodeToolFoundation/Tool.swift`，详情页路由由 `ToolDestinationRegistry` 统一注册在 `Sources/CodeToolCore/Views/ContentView.swift`。
- `ClaudeChatView` 加 `ClaudeCLIClient` 是当前唯一成熟的本地 agent 壳层，负责消息列表、输入区、CLI 子进程、event 解析、history 与 observability 联动，核心文件为 `Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift` 与 `Sources/CodeToolCore/Providers/Claude/ClaudeCLIClient.swift`。
- `AIExecutionSession` 适合统一 `referenceID`、诊断 sink、history sink 与取消语义，但当前 event 模型只覆盖 started/delta/artifact/progress，不足以承载会话型 agent UI、任意文件附件和多态 timeline，见 `Sources/CodeToolCore/Execution/AIExecutionSession.swift`、`Sources/CodeToolCore/Execution/AIExecutionTypes.swift`。
- SettingsSheet 仍然是 `ContentView` 中的手写 segmented picker，而不是 provider registry；Hermes 新增 tab 的成本可控，但必须显式改 `Sources/CodeToolCore/Views/ContentView.swift`。
- `ToolStatusItem` 已经支持 `action`、`help` 与 `accessibilityLabel`，因此 Hermes 头部状态 chip 和可点击动作不需要先改 shared shell，见 `Sources/CodeToolUI/ToolWorkbench.swift`。
- Diagnostics 主路径已经稳定：`AppLogger` 写 unified/file/DiagnosticsStore，`DiagnosticsCaseService` 按 `referenceID` 聚合日志与 `HistoryStore` 匹配结果，见 `Sources/CodeToolCore/Observability/AppLogger.swift`、`Sources/CodeToolCore/Observability/Diagnostics.swift`、`Sources/CodeToolCore/Observability/DiagnosticsCaseService.swift`。
- 当前 `HistoryStore` 与 `HistoryDefinitionRegistry` 已支持“只为 diagnostics 保留最小记录”的扩展方式；Hermes 不必接入 `HistoryDrawer` 也能加入诊断聚合，见 `Sources/CodeToolCore/Persistence/HistoryStore.swift`、`Sources/CodeToolCore/Persistence/HistoryDefinitions.swift`、`Sources/CodeToolCore/Persistence/HistoryEntry.swift`。
- 现成的图片 paste/drop 模式存在于 Claude Chat 和 AI Image，但 Hermes V1 需要的是“任意文件 URL 输入”，因此应复用拖拽、NSOpenPanel、pasteboard URL 读取模式，而不是复用图片二进制导入语义，见 `Sources/CodeToolCore/Views/Shared/ImageImportSupport.swift` 与 `Sources/CodeToolCore/Views/AITools/AIImageView.swift`。

### External Findings That Change The Plan

- 官方已证实本地命令名为 `hermes`，支持 `hermes chat -q ...` 形式的 one-shot 查询，以及 `--resume` / `--continue` 对话续接。
- 官方已证实 session 数据位于 `~/.hermes/state.db`，但同时提供 `hermes sessions list`、`browse`、`export` 等 CLI 命令；V1 应优先依赖 CLI 暴露的 session surface，而不是直接耦合 SQLite 私有 schema。
- 官方已证实 Context References 是文件输入的正式能力，适合作为“任意文件附件”的实现落点。
- 官方未证实 plain CLI 提供稳定的 JSON/NDJSON/stream-json 机器协议；结构化事件主要在 ACP 和 API Server。
- 官方已证实 ACP 和 API Server 是结构化协议面，但它们属于编辑器协议或后台服务层，不适合当前桌面工具的 V1 主接入面。

这些外部事实决定了 V1 必须先做 CLI capability probe，再决定哪些高级能力启用，不能像 Claude CLI 那样直接假设稳定的 streaming event contract。

## Scope

### In Scope

- 新增独立 `ToolID.hermesAgent` 与侧边栏入口 `Hermes Agent`。
- 新增 Hermes 设置存储与设置页，支持二进制发现、能力探测结果展示和基础启动参数配置。
- 新增 `HermesAgentView`，包含：消息列表、过程 timeline、底部 composer、New Chat、Stop、Resume、Settings 动作。
- 通过本地 Hermes CLI 子进程完成发送、取消、错误展示与最终输出回显。
- 支持任意文件附件输入，入口覆盖：拖拽、文件选择、Finder 复制后的文件 URL 粘贴。
- `Resume` 基于 Hermes 官方 CLI session surface；若当前版本没有稳定可消费的 session 列表能力，则明确提示不可用。
- 为 Hermes 引入最小诊断持久化记录，使 Diagnostics 能按 `referenceID` 聚合 Hermes 相关问题。
- README、测试、工具数量与路由覆盖保持一致。

### Out of Scope

- 不把 Hermes 做成 `AI Chat` 的 provider 切换项。
- 不用 ACP 作为 V1 的主客户端协议。
- 不用 API Server / gateway 作为 V1 的主传输层。
- 不直接读取 `~/.hermes/state.db` 私有 schema。
- 不接 `HistoryDrawer`，不提供用户可恢复历史。
- 不引入工作目录选择或工程目录绑定。
- 不承诺展示完整 thinking 过程。
- 不依赖未文档化的 plain CLI TUI 输出做 fragile 的 tool parser。

## Resolved Decisions

### 1. V1 主接入面固定为 CLI

Hermes Agent V1 只走本地 `hermes` CLI。ACP 和 API Server 只作为未来演进面保留，不进入本轮实现。

### 2. Timeline 默认采用“本地阶段 + 可选结构化增强”

Hermes V1 的 timeline 基线不是 CLI tool event，而是 app 自己可证明的阶段事件：

- capability probe
- preparing attachments
- launching process
- waiting for response
- resolving session metadata
- completed / cancelled / failed

如果当前 Hermes 版本在 probe 后暴露出稳定且可解析的结构化过程信息，再在同一 timeline 面板中追加 tool entries；否则不做脆弱的 stdout 启发式解析。

### 3. Resume 只依赖官方 CLI session surface

V1 只在以下条件满足时实现可选 session picker：

- `hermes sessions list` 或等价命令存在。
- 输出格式在当前版本上可稳定解析。

如果不满足，`Resume` 入口保留，但只展示“当前 Hermes 版本不可用”的明确说明。V1 不直接读 `~/.hermes/state.db`。

### 4. 文件附件采用“文件引用”而不是“文件上传”

Hermes V1 只支持文件 URL / 绝对路径类输入：

- 拖拽文件
- 选择文件
- Finder 文件复制后的 pasteboard URL

不做原始剪贴板二进制注入，不做目录挂载，不做 multipart 上传。发送时统一由 `HermesPromptComposer` 转为 Hermes 官方支持的 context reference 语法。

### 5. Hermes 只写最小诊断记录，不落完整 transcript

由于 V1 不做用户历史恢复，Hermes 的持久化记录应只保留 diagnostics 需要的信息，例如：

- `referenceID`
- `sessionID`（若可得）
- model/profile 摘要
- 请求摘要与附件数量
- 最终输出摘要
- 状态与耗时

不要为 V1 新建完整会话 transcript 存储。

## Implementation Approach

### Why Not Reuse AIExecutionSession Directly

`AIExecutionSession` 可以继续作为设计参考，但不应成为 Hermes V1 的主要集成面：

- Hermes UI 需要会话态消息列表、附件暂存、Resume 入口与 timeline 面板。
- 当前 `AIExecutionEvent` 不足以表达这类产品边界。
- 把 Hermes 强塞进 execution 抽象，只会把 transport、timeline 与 composer 状态重新搬回 view 层，无法真正减少复杂度。

本轮应采用“独立 Hermes UI + 局部复用 observability/history pattern”的方案。

### Recommended Internal Shape

建议新增目录：

```text
Sources/CodeToolCore/Providers/Hermes/
  HermesCLIContractProbe.swift
  HermesCapabilityMatrix.swift
  HermesCLIClient.swift
  HermesPromptComposer.swift
  HermesSessionDiscovery.swift
  HermesSettingsStore.swift
  HermesSettingsView.swift

Sources/CodeToolCore/Views/AITools/
  HermesAgentView.swift

Sources/CodeToolCore/Views/Shared/
  FileReferenceImportSupport.swift
  HermesComposer.swift
```

其中：

- `HermesCLIContractProbe` 负责能力探测与版本矩阵。
- `HermesCLIClient` 只负责命令构建、子进程生命周期、stdout/stderr 收集、取消与标准化事件。
- `HermesPromptComposer` 统一把文本与附件转换为最终 query 文本，避免 UI 分散拼接协议细节。
- `HermesSessionDiscovery` 只消费官方 sessions 命令输出，不读 SQLite。
- `HermesAgentView` 负责会话态 UI、timeline、banner、resume sheet 与 composer 状态。

### Capability-Driven Design

建议引入单独的 capability 模型，禁止在 view 层直接猜 CLI 能力：

```swift
struct HermesCapabilityMatrix: Sendable, Codable {
    let binaryPath: String
    let versionString: String?
    let supportsChatQuery: Bool
    let supportsQuietOutput: Bool
    let supportsResumeFlag: Bool
    let supportsContinueFlag: Bool
    let supportsSessionsList: Bool
    let supportsModelFlag: Bool
    let supportsProfileFlag: Bool
    let supportsContextReferences: Bool
    let outputMode: HermesOutputMode
}

enum HermesOutputMode: String, Codable, Sendable {
    case finalTextOnly
    case humanStreaming
    case structured
}
```

这样 Phase 0 之后所有实现都只消费 `HermesCapabilityMatrix`，避免后续逻辑继续散落在 Settings 与 View 里。

### Settings Strategy

Hermes 设置页至少包含：

- Hermes binary path
- capability probe result / detected version
- optional model/profile field（仅当 probe 证实相关 flag 时显示）
- optional raw extra args（高级字段，用于未来兼容未建模的 CLI flag）
- auth / install guidance

不要在 capability 未确认前硬编码 `--model` 或 `--profile` 之类参数。

### Resume Strategy

Resume 流程固定为：

1. 通过 `HermesSessionDiscovery` 运行官方 session 命令。
2. 若输出可解析，则展示会话列表 sheet。
3. 用户选择后，将 session ID 写入当前 chat state。
4. 后续请求在 `HermesCLIClient` 中带上 capability-confirmed 的 `--resume` 或 `--continue` 语义。
5. 若 discovery 不可用，则只展示不可用原因，不回退到私有 SQLite 读取。

### Attachment Strategy

Hermes V1 附件对象应是文件引用而不是内存 blob：

```swift
struct HermesAttachmentReference: Identifiable, Equatable, Sendable {
    let id: UUID
    let fileURL: URL
    let displayName: String
    let kindDescription: String
    let sizeBytes: Int64?
}
```

发送前只做：

- existence check
- readability check
- duplication removal
- current capability 下的 context reference 渲染

这能保持操作即时、不阻塞主线程，也避免引入额外文件 staging。

### Diagnostics Persistence Strategy

建议新增 Hermes 专属最小 record，而不是复用 Claude transcript：

```swift
public struct HermesAgentDiagnosticsRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let sessionID: String?
    public let modelOrProfile: String?
    public let requestSummary: String
    public let outputSummary: String
    public let attachmentCount: Int
    public let durationMs: Int?
    public let status: String
    public let referenceID: String
}
```

它只用于 Diagnostics 聚合，不用于 UI 恢复。

## Phase 0: CLI Contract Probe

### Overview

在任何 Hermes UI 或 transport 代码落地前，先建立一个可测试、可缓存的 capability probe。没有这个 phase，后续每个实现点都会在“这个 flag 到底支不支持”上重复猜测。

### Changes Required

#### 1. 新增 Hermes capability 探测器
**Files**:
- `Sources/CodeToolCore/Providers/Hermes/HermesCLIContractProbe.swift`
- `Sources/CodeToolCore/Providers/Hermes/HermesCapabilityMatrix.swift`

**Changes**:
- 通过 `Process` 运行以下命令采集帮助输出与版本信息：
  - `hermes --help`
  - `hermes chat --help`
  - `hermes sessions --help`
  - 必要时 `hermes sessions list --help`
- 解析能力矩阵：query flag、quiet 模式、resume/continue、sessions list、model/profile flag、context references 是否在当前版本文档中可见。
- 结果缓存到 `HermesSettingsStore`，避免每次打开页面都重复跑探测。

#### 2. 定义输出模式决策
**Files**:
- `Sources/CodeToolCore/Providers/Hermes/HermesCapabilityMatrix.swift`

**Changes**:
- 若 probe 只证实 final-only 输出，则 `outputMode = .finalTextOnly`。
- 若当前版本能安全提供逐步 stdout 且不会污染结果解析，可升级为 `.humanStreaming`。
- V1 默认不要把 plain CLI 假设成 `.structured`；只有本机 probe 与 fixture 测试都证明存在稳定结构化协议时才允许。

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [ ] `make test`
- [x] 新增 probe fixture 测试，验证帮助输出能正确映射到 capability matrix

#### Manual Verification
- [ ] 在已安装 Hermes 的机器上，Settings 打开后能显示检测到的 binary path 与版本。
- [ ] 未安装 Hermes 时，probe 不崩溃且能返回清晰错误状态。
- [ ] 当 sessions list 或 model/profile 不可用时，对应 capability 会被明确关闭。

---

## Phase 1: Tool Wiring and Hermes Settings

### Overview

先把 Hermes 接入工具目录、路由、设置面板和日志分类。这个 phase 不碰会话 UI，只建立稳定的产品入口与配置宿主。

### Changes Required

#### 1. 新增工具 ID 与目录元数据
**File**: `Sources/CodeToolFoundation/Tool.swift`

**Changes**:
- 新增 `ToolID.hermesAgent`。
- 为 AI Tools 新增 `ToolCatalogEntry`：标题 `Hermes Agent`，描述聚焦本地 Hermes CLI agent wrapper。
- 为新工具定义稳定 route slug，例如 `Agent`。

#### 2. 新增路由与文案同步
**File**: `Sources/CodeToolCore/Views/ContentView.swift`

**Changes**:
- 在 `ToolDestinationRegistry` 中注册 `HermesAgentView()`。
- 在 landing page 的 AI Tools 文案中把 Hermes 纳入描述。
- 在 footer 的 provider copy 中加入 Hermes。
- `onAppear` 时增加 `HermesSettingsStore.shared.discoverCLI()` 或等价 probe 入口。

#### 3. 新增 Settings tab
**Files**:
- `Sources/CodeToolCore/Views/ContentView.swift`
- `Sources/CodeToolCore/Providers/Hermes/HermesSettingsStore.swift`
- `Sources/CodeToolCore/Providers/Hermes/HermesSettingsView.swift`

**Changes**:
- SettingsSheet 新增 `Hermes` segmented tab。
- `HermesSettingsStore` 持久化 binary path、capability cache、可选 model/profile、可选 extra args。
- `HermesSettingsView` 显示安装状态、版本、capability 摘要、探测与重置动作。

#### 4. 日志分类扩展
**File**: `Sources/CodeToolFoundation/LogTypes.swift`

**Changes**:
- 新增 `AppLogCategory.hermesagent`。
- 后续 Hermes client、view、session discovery 与 diagnostics record 全部统一使用该 category。

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [ ] `make test`
- [x] 工具 catalog 覆盖测试与 destination coverage 测试更新后通过

#### Manual Verification
- [ ] 侧边栏出现独立 `Hermes Agent` 入口。
- [ ] SettingsSheet 中出现 `Hermes` tab。
- [ ] Hermes 未安装时，设置页和工具页都能展示可理解的不可用状态。

---

## Phase 2: Hermes CLI Client and Session Discovery

### Overview

建立 Hermes transport 层和 session discovery 层，但先不做复杂 UI。这个 phase 的目标是可靠地“发送、停止、解析最终输出、拿到 session 元数据、处理 resume”。

### Changes Required

#### 1. 新增 Hermes 请求与事件模型
**Files**:
- `Sources/CodeToolCore/Providers/Hermes/HermesCLIClient.swift`

**Changes**:
- 定义 `HermesTurnRequest`，字段至少包括：
  - `prompt: String`
  - `resumeSessionID: String?`
  - `referenceID: String`
  - `modelOrProfile: String?`
  - `extraArguments: [String]`
- 定义 `HermesAgentEvent`，不要直接暴露 raw stdout/stderr 到 view：

```swift
enum HermesAgentEvent: Sendable {
    case phaseChanged(HermesPhase)
    case outputDelta(String)
    case completed(HermesTurnResult)
    case warning(String)
    case failed(String)
}
```

#### 2. 建立 capability-aware 命令构建
**File**: `Sources/CodeToolCore/Providers/Hermes/HermesCLIClient.swift`

**Changes**:
- 命令构建严格依赖 `HermesCapabilityMatrix`。
- query 输入优先使用 probe 证实的 `-q` / `--query`。
- 只有 capability 明确存在时才追加 model/profile 参数。
- 只有 capability 明确存在时才追加 `--resume` / `--continue`。
- stdout/stderr 统一收集并打结构化日志。

#### 3. 定义结果解析与取消语义
**File**: `Sources/CodeToolCore/Providers/Hermes/HermesCLIClient.swift`

**Changes**:
- 对 `.finalTextOnly` 模式：把 stdout 视为最终输出源，并通过本地 phase events 驱动 timeline。
- 对 `.humanStreaming` 模式：允许低频批量推送 `outputDelta`，但不依赖它生成结构化 tool timeline。
- `cancel()` 通过 `process.terminate()` 或等价方式终止当前请求。
- 非零退出、stderr 非空、解析失败都归一到 `failed` 或 `warning` 事件，并携带 `referenceID` 日志。

#### 4. 新增 session discovery
**Files**:
- `Sources/CodeToolCore/Providers/Hermes/HermesSessionDiscovery.swift`

**Changes**:
- 仅在 `supportsSessionsList == true` 时运行会话枚举命令。
- 解析结果为 `HermesSessionSummary` 列表：session ID、title/summary、updatedAt。
- 若命令不可用或解析不稳定，返回显式 unavailable 状态，不回退到 SQLite。

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [ ] `make test`
- [ ] 新增 client fixture 测试，覆盖：命令构建、stderr 失败、取消、final-text 解析、session list 解析

#### Manual Verification
- [ ] 使用 one-shot query 能在 UI 外部验证 Hermes CLI 确实返回可消费文本。
- [ ] Stop 能终止 Hermes 子进程并回到可继续输入状态。
- [ ] 当前 Hermes 版本支持 session list 时，能够列出 resume 候选。
- [ ] 当前 Hermes 版本不支持时，Resume 明确显示不可用说明。

---

## Phase 3: File Attachment Intake and Prompt Composition

### Overview

为 Hermes V1 建立“任意文件引用”的输入链路。重点不是文件内容处理，而是稳定、安全地把用户选择的本地文件引用映射成 Hermes 官方支持的上下文引用形式。

### Changes Required

#### 1. 新增通用文件引用导入 helper
**Files**:
- `Sources/CodeToolCore/Views/Shared/FileReferenceImportSupport.swift`

**Changes**:
- 提供以下能力：
  - 从 `[URL]` 构造 `HermesAttachmentReference`
  - 从 pasteboard 的 `NSURL` / file URL 读取文件
  - 从 drag-and-drop 的 `NSItemProvider` 读取文件 URL
  - 基础校验：存在、可读、非目录
- 不做图片解码，不做 raw binary pasteboard fallback。

#### 2. 新增附件状态与 prompt composer
**Files**:
- `Sources/CodeToolCore/Providers/Hermes/HermesPromptComposer.swift`

**Changes**:
- 统一把文本和附件转为最终 query。
- 附件引用语法必须集中在一个 helper 中，不能散落在 view。
- 空文本 + 有附件时，自动注入最小 bootstrap 语句，例如“Please inspect the attached files.” 的 Hermes 版本文案。
- 发送前去重并校验所有文件存在；任一文件无效则阻止请求并给出具体错误。

#### 3. 明确 drag / pick / paste 三条入口
**Files**:
- `Sources/CodeToolCore/Views/AITools/HermesAgentView.swift`
- 视情况新增 `Sources/CodeToolCore/Views/Shared/HermesComposer.swift`

**Changes**:
- 拖拽：接受 `UTType.fileURL`。
- 选择文件：通过 `NSOpenPanel`，允许多选任意文件。
- 粘贴：只处理 Finder 文件复制后的 file URLs。
- UI 中展示 attachment chips，支持单个移除与 clear all。

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [ ] `make test`
- [ ] 新增 helper 测试，覆盖 file URL import、invalid file rejection、prompt composition 与 empty-text attachment send

#### Manual Verification
- [ ] 拖拽文件到 composer 后附件 chip 即时出现。
- [ ] 使用文件选择器添加多个文件后 UI 顺序稳定。
- [ ] 在 Finder 复制文件后粘贴，附件能进入当前请求。
- [ ] 不存在或不可读文件会在发送前阻止请求并给出明确错误。

---

## Phase 4: Hermes Agent View and Adaptive Timeline UI

### Overview

实现 Hermes 的独立会话 UI，复用 `ToolWorkbench` 与现有 shared components，但不复刻 Claude Chat 的完整 transcript/history 语义。

### Changes Required

#### 1. 新增 Settings 打开动作桥
**Files**:
- `Sources/CodeToolCore/Views/ContentView.swift`
- 如需要，新增轻量 environment key 到 shared UI 层

**Changes**:
- 由于 Hermes 顶部 action 需要 `Settings`，需要从 `ContentView` 向工具页注入“打开 SettingsSheet 并切到 Hermes tab”的闭包。
- 这个桥只暴露意图，不暴露 SettingsSheet 实现细节。

#### 2. 新增 HermesAgentView
**Files**:
- `Sources/CodeToolCore/Views/AITools/HermesAgentView.swift`

**Changes**:
- 使用 `ToolWorkbench`。
- 顶部 actions 包含：
  - `New Chat`
  - `Stop`（仅请求进行中显示）
  - `Resume`
  - `Settings`
- 主体布局包含：
  - 消息列表
  - timeline / process cards
  - composer
- 消息渲染可复用 `ClaudeMarkdownView`，减少新增 markdown renderer。

#### 3. 定义会话内状态模型
**File**: `Sources/CodeToolCore/Views/AITools/HermesAgentView.swift`

**Changes**:
- 状态至少包括：
  - `messages`
  - `timelineEntries`
  - `attachments`
  - `draftText`
  - `isRunning`
  - `activeReferenceID`
  - `activeSessionID`
  - `resumeAvailability`
  - `errorBanner`
- `New Chat` 若有活动请求，先 cancel，再重置所有内存态。

#### 4. 设计可降级 timeline 模型
**Files**:
- `Sources/CodeToolCore/Views/AITools/HermesAgentView.swift`

**Changes**:
- timeline entry 建议至少包含：
  - phase label
  - status
  - detail summary
  - timestamp
- 当 `HermesCLIClient` 将来能提供结构化 tool event 时，同一 timeline model 允许承载 `toolStart/toolResult`。
- 当前 phase 基线必须覆盖：launch / waiting / completed / cancelled / failed。

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [ ] `make test`
- [ ] 视图层纯 helper 和 render state 测试覆盖 New Chat、send disabled、timeline fallback 逻辑

#### Manual Verification
- [ ] 打开 Hermes Agent 后能看到独立于 AI Chat 的页面。
- [ ] 发送一条普通文本请求后，timeline 至少显示本地阶段进度与最终输出。
- [ ] Stop 中断后，保留已有输出并把当前 turn 标记为中断。
- [ ] New Chat 会清空当前消息、附件与 timeline，并取消任何在途请求。
- [ ] Resume 可用时能继续旧 session；不可用时能给出明确说明。

---

## Phase 5: Minimal Diagnostics Persistence and Diagnostics Integration

### Overview

把 Hermes 请求写进现有 diagnostics 聚合链路，但不对用户暴露 HistoryDrawer。这个 phase 的目标是让 `referenceID` 能完整串起日志、最小 history match 和导出包。

### Changes Required

#### 1. 新增 Hermes diagnostics history record
**Files**:
- `Sources/CodeToolCore/Persistence/HistoryStore.swift`
- `Sources/CodeToolCore/Persistence/HistoryDefinitions.swift`
- `Sources/CodeToolCore/Persistence/HistoryEntry.swift`

**Changes**:
- 新增 `HistoryCategory.hermesAgent` 与 `HistoryToolID.hermesAgent`。
- 新增 `HermesAgentDiagnosticsRecord` 与对应 codec。
- `diagnosticsInfo` 输出标题 `Hermes Agent` 和最小 detail 文案。
- 只保存 summary，不保存完整正文或附件内容。

#### 2. 在 Hermes 完成/失败路径写记录
**Files**:
- `Sources/CodeToolCore/Views/AITools/HermesAgentView.swift`
- 或 `Sources/CodeToolCore/Providers/Hermes/HermesCLIClient.swift` 旁的专用 saver helper

**Changes**:
- 请求结束后写入最小 record。
- `referenceID`、session ID、状态、duration、attachment count 必须齐全。
- sink 失败不能影响主 UI 流程。

#### 3. 日志链路补齐 Hermes 事件
**Files**:
- `Sources/CodeToolCore/Providers/Hermes/HermesCLIClient.swift`
- `Sources/CodeToolCore/Views/AITools/HermesAgentView.swift`

**Changes**:
- 记录能力探测、发送开始、进程启动、stderr、完成、失败、取消等关键事件。
- metadata 中只保留 summary / counts / flags，不记录完整文本。

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [ ] `make test`
- [x] 新增 diagnostics match 测试，验证 `referenceID` 能把 Hermes log 与 Hermes minimal record 聚合到同一个 case snapshot

#### Manual Verification
- [ ] Hermes 失败请求可在 Diagnostics 中通过 `referenceID` 查到。
- [ ] 导出的 diagnostics package 含 Hermes 相关 logs 与 minimal history match。
- [ ] Hermes 不会出现在用户可见的 HistoryDrawer 恢复入口中。

---

## Phase 6: Documentation, Polish, and Full Verification

### Overview

同步 README、测试与收尾文案，确保 Hermes 加入后 catalog-routing-tests-docs 仍然一致。

### Changes Required

#### 1. README 更新
**File**: `README.md`

**Changes**:
- 在 Features 中加入 `Hermes Agent`。
- 在架构说明中补 Hermes 本地 CLI wrapper 的位置。
- 若 README 继续声明 provider surfaces，也要把 Hermes 单独列出来。

#### 2. 测试补齐
**File**: `Tests/CodeToolTests/CodeToolTests.swift`

**Changes**:
- 更新 `ToolID` / `ToolCatalog` / destination coverage 断言。
- 新增 `HermesSettingsStore` 默认值或 capability mapping 测试。
- 新增 contract probe、prompt composer、session list parser、minimal diagnostics record codec 测试。

#### 3. 最终验证
**Commands**:
- `swift build`
- `make test`

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [ ] `make test`

#### Manual Verification
- [ ] 侧边栏、Landing、README、测试与实际工具列表完全一致。
- [ ] Hermes CLI 缺失、session discovery 不可用、附件无效、非零退出四类主要失败都能被清晰展示。
- [ ] 现有 Claude Chat / MiniMax 三个 AI 工具行为没有回归。

## Testing Strategy

### Unit Tests

- `HermesCLIContractProbe` 帮助输出解析测试。
- `HermesCLIClient` 命令构建、stderr 失败、取消与 final-output 解析测试。
- `HermesSessionDiscovery` parse / unavailable 测试。
- `HermesPromptComposer` 附件引用和空文本 bootstrap 测试。
- `HermesAgentDiagnosticsRecord` codec 与 diagnostics match 测试。
- tool catalog 与 destination coverage 测试更新。

### Manual Testing Steps

1. 在 Hermes 已安装机器上打开 `Hermes Agent`，确认 settings probe 正常显示版本与能力。
2. 发起一次纯文本请求，确认最终输出显示且 timeline 至少展示 launch/wait/complete。
3. 在请求进行中点击 `Stop`，确认子进程被终止且部分输出保留。
4. 通过拖拽、选择文件、Finder 复制粘贴三种方式分别添加附件并发送。
5. 若当前版本支持 session list，执行一次 resume；若不支持，确认 UI 明确显示 unavailable。
6. 制造一个错误场景（错误 binary path 或无效附件），确认 banner 与 Diagnostics 都能定位到同一 `referenceID`。
7. 运行 `swift build` 与 `make test`，确认 catalog/tests/README 同步后通过。

## Performance Considerations

- 默认不要做逐 token UI 更新；plain CLI 无稳定机器流协议时，优先走 final-text 模式以保持 UI 与解析稳定。
- 如果探测到 `.humanStreaming`，也应采用批量 flush，而不是每一小段 stdout 都触发 SwiftUI 重绘，可参考 `ClaudeChatView` 的 pending buffer 策略。
- 附件加入与移除只处理本地 metadata，不读大文件内容到内存。
- Diagnostics record 只存 summary，避免引入大 transcript 写盘。

## Migration Notes

- Hermes 是新增工具，不涉及现有数据迁移。
- 新增 `HistoryCategory.hermesAgent` 后，不需要给旧数据做 backfill。
- 如果未来 Hermes 官方提供稳定 JSON/ACP-like CLI surface，应优先复用当前 capability matrix 与 event abstraction，而不是重写 HermesAgentView。
- V1 明确不读 `~/.hermes/state.db`，这样后续 Hermes 本地 schema 变化不会直接打破 app。

## References

- Original requirements: `thoughts/shared/specs/2026-04-07-hermes-agent-ui-wrapper.md`
- Tool catalog and route boundary: `Sources/CodeToolFoundation/Tool.swift`, `Sources/CodeToolCore/Views/ContentView.swift`
- Existing agent UI pattern: `Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift`
- Existing local CLI client pattern: `Sources/CodeToolCore/Providers/Claude/ClaudeCLIClient.swift`
- Settings host and tab model: `Sources/CodeToolCore/Views/ContentView.swift`
- Shared header/action shell: `Sources/CodeToolUI/ToolWorkbench.swift`
- Diagnostics and referenceID chain: `Sources/CodeToolCore/Observability/AppLogger.swift`, `Sources/CodeToolCore/Observability/Diagnostics.swift`, `Sources/CodeToolCore/Observability/DiagnosticsCaseService.swift`
- Minimal history / diagnostics registry pattern: `Sources/CodeToolCore/Persistence/HistoryStore.swift`, `Sources/CodeToolCore/Persistence/HistoryDefinitions.swift`, `Sources/CodeToolCore/Persistence/HistoryEntry.swift`
- Relevant prior plans: `thoughts/shared/plans/refactor-tool-catalog-routing.md`, `thoughts/shared/plans/refactor-ai-execution-session.md`, `thoughts/shared/plans/2026-03-31-claude-cli-optimization.md`, `thoughts/shared/plans/2026-04-03-claude-cli-chat-ux-optimization.md`, `thoughts/shared/plans/2026-04-03-ai-image-reference-workbench.md`
- Hermes official references used in planning: installation docs, CLI docs, sessions docs, context references docs, ACP docs, API Server docs