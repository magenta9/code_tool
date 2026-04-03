# Observability Issue Tracking Implementation Plan

## Overview

为 CodeTool 落地一套 Phase 1 可执行的可观测性基础设施：在不打破现有 `AppLogger`、`referenceID`、`HistoryStore` 与测试契约的前提下，统一 app 生命周期、MiniMax 请求链路、Claude CLI 子进程链路、HistoryStore 持久化，以及设置页中的 Diagnostics 消费面。

## Current State Analysis

当前代码已经有一部分可观测性基础，但能力分散且语义不统一。

### Key Discoveries

- `Sources/CodeToolCore/AppLogger.swift:1-257` 已有本地 JSONL 结构化日志、`referenceID` 生成与错误 enrich，但只有 `.info/.error` 两级，且没有 sink 抽象、trace/span 或查询索引。
- `Sources/CodeToolCore/MiniMaxAPIClient.swift:42-85`、`Sources/CodeToolCore/MiniMaxAPIClient.swift:674-1079` 是全仓库最成熟的结构化请求日志边界，已有 request start/finish/failure、redaction 与 `referenceID` 贯穿。
- `Sources/CodeToolCore/ClaudeCLIClient.swift:4-266` 已具备 subprocess 与 NDJSON event 流，但尚未纳入统一日志/trace；`sessionId` 与 `referenceID` 语义也与 MiniMax 路径不一致。
- `Sources/CodeToolCore/ClaudeChatView.swift:831-858` 目前是在保存 history 时才生成 `referenceID`，导致 Claude 的“执行 ID”和“历史 ID”不是同一个语义。
- `Sources/CodeToolCore/HistoryStore.swift:131-175`、`Sources/CodeToolCore/HistoryStore.swift:279-697` 已持久化多种 `referenceID` / `sessionId` 相关记录，并包含 Claude attachment 存储，但没有 diagnostics 专属索引、保留策略或导出能力。
- `Sources/CodeToolCore/ContentView.swift:897-925` 已有双 tab 设置页（MiniMax / Claude CLI），因此按用户决策，Diagnostics 最自然的落点是**设置页中的 Diagnostics Tab**，而不是新增 sidebar tool。
- `Sources/CodeToolCore/HistoryDrawer.swift:6-343` 已有一套成熟的“本地历史浏览”UI 语言，可复用于 Diagnostics 列表、详情与关联 history 展示。
- `Tests/CodeToolTests/CodeToolTests.swift:394-474`、`Tests/CodeToolTests/CodeToolTests.swift:538-547` 已直接断言日志内容与事件名，因此日志事件契约是第一阶段的硬约束。

## Scope

### In Scope

- 建立统一 observability foundation：日志级别、事件模型、统一外显 ID、redaction、retention、sink 抽象
- 在 app 生命周期中初始化 observability bootstrap
- 为 MiniMax 请求链路接入统一上下文和统一日志事件模型
- 为 Claude CLI subprocess / session / stderr / exit code / history save 链路接入统一 observability
- 为 `HistoryStore` 增加 diagnostics 关联索引、查询与导出支撑
- 在现有 SettingsSheet 中新增 Diagnostics Tab
- Diagnostics Tab 支持：
  - recent `.fault/.error`
  - 通过统一外显 ID 搜索
  - 查看 trace/span 摘要
  - 查看关联 `HistoryStore` 记录
  - 导出诊断包
- 本地 retention 裁剪：
  - 日志 14 天 / 200 MB
  - trace/metrics 摘要 7 天 / 500 MB
- 保留现有 `AppLogger.shared.info/error`、事件名与测试模式契约，但不承担旧日志与旧 history 数据兼容

### Out of Scope

- 远端自建后端或第三方 SaaS 真正接入
- 问题分组、去重、告警路由、工单流转
- XPC / Extension 的真实传播实现（只预留 envelope 设计）
- 新增独立 Diagnostics sidebar tool
- 新增复杂图表型观测后台
- 旧日志文件与旧 history 记录的迁移、回填和解码兼容

## Implementation Approach

采用**契约优先、集中边界优先、消费面后置**的分期策略：

1. 先建立统一 observability foundation，确保现有 `AppLogger` API、事件名、`referenceID` 与测试不被一次性打断，但不要求兼容旧落盘数据。
2. 再接 app lifecycle + diagnostics storage/backbone，让 observability 成为全局能力而不是仅在请求时存在。
3. 之后分两条最集中的执行边界改造：MiniMax 请求链路、Claude CLI subprocess 链路。
4. 最后把 Diagnostics 作为设置页中的消费面挂出来，并做导出、查询与验证收口。

用户已确认的关键决策如下：

- **Diagnostics 入口**：设置页中的 Diagnostics Tab
- **ID 策略**：`traceID` / `referenceID` 统一为**同一个外显 ID**
- **Retention**：
  - logs: 14 天 / 200 MB
  - trace + metrics 摘要: 7 天 / 500 MB
- **Diagnostics 检索范围**：结构化日志 + trace/span + MetricKit 摘要 + 关联 `HistoryStore` 记录

## Phase 1: Observability Foundation & Contract Layer

### Overview

建立统一 observability 入口层，同时保持现有 `AppLogger` 调用方式和测试契约可继续工作。该阶段不急着重写所有调用点，而是先铺好数据模型、sink 和事件契约；旧日志与旧 history 数据不纳入兼容范围。

### Changes Required

#### 1. Create unified observability primitives
**Files**:
- `Sources/CodeToolCore/AppLogger.swift`
- `Sources/CodeToolCore/` (new files, likely `Observability.swift`, `ObservabilityTypes.swift`, `DiagnosticsStore.swift`, `RedactionPolicy.swift`)

**Changes**:
- 定义统一日志级别：`.fault`, `.error`, `.info`, `.debug`, `.trace`
- 定义统一事件模型：level, subsystem, category, event, message, unified external ID, duration, error fields, metadata
- 定义 redaction policy：
  - 默认不记录正文
  - 记录摘要、长度、哈希
  - Debug 构建下允许显式开启脱敏片段
- 定义 sink 抽象：
  - Unified Logging sink
  - file persistence sink
  - future remote sink protocol
- 保留 `AppLogger.shared.info/error` 兼容入口，让旧调用点先不爆炸
- 让 `AppLogger.makeReferenceID()` 语义升级为统一外显 ID 生成器，避免同时存在第二种用户可见 ID

#### 2. Preserve current test and file contracts
**Files**:
- `Sources/CodeToolCore/AppLogger.swift`
- `Tests/CodeToolTests/CodeToolTests.swift`

**Changes**:
- 保持现有日志目录 override 能力
- 保持按类别枚举日志文件的测试 seam
- 维持现有关键事件名兼容：
  - `request_started`
  - `request_finished`
  - `request_failed`
  - `music_request_failed`
  - `player_prepare_failed`
- 将本地 file sink 继续作为 Phase 1 的主持久化出口，但不要求读取或迁移既有历史日志文件

#### 3. Add retention and failure policy infrastructure
**Files**:
- `Sources/CodeToolCore/` (new observability storage files)

**Changes**:
- 增加 retention config 与裁剪执行器
- 日志保留：14 天 / 200 MB 双上限
- trace + metrics 摘要：7 天 / 500 MB 双上限
- sink 写入失败不得阻塞主流程
- 对 observability 内部错误增加有限递归保护，防止“记录错误本身又报错”

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [x] 现有 `CodeToolTests` 中与日志内容相关的测试继续通过或在同一事件语义下更新通过
- [x] 新增 observability 类型与 redaction 策略的单元测试

#### Manual Verification
- [ ] 旧 `AppLogger.shared.info/error` 调用点无需立即改写也能继续产生日志
- [ ] 本地日志仍可在 `Application Support/CodeTool/logs` 下看到
- [ ] 在容量和天数限制下裁剪行为符合双上限策略
- [ ] sink 失败不会让用户主流程报错或卡死

---

## Phase 2: App Lifecycle & Diagnostics Storage Backbone

### Overview

把 observability 变成 app 启动即存在的全局能力，而不是“请求时顺手写点日志”。同时建立 Diagnostics 查询、索引、MetricKit payload 落盘和 HistoryStore 关联所需的存储骨架。

### Changes Required

#### 1. Bootstrap observability at app startup
**Files**:
- `Sources/CodeToolApp/CodeToolApp.swift`
- `Sources/CodeToolApp/AppDelegate.swift`
- `Package.swift`
- `Sources/CodeToolApp/Resources/` (new app info resource if needed)
- `Sources/CodeToolCore/ContentView.swift`

**Changes**:
- 在 app 启动阶段初始化 observability system
- 记录 app lifecycle 关键边界事件：
  - app launch started / finished
  - root view ready
  - app terminate
- 注册 MetricKit listener / payload receiver
- 初始化本地 diagnostics store 与 retention cleanup
- 明确版本元数据来源：把固定产品版本写入 app info，并把短 git hash 写入 app info 的 build/version 字段，Diagnostics 只从 `Bundle.main.infoDictionary` 读取

#### 2. Introduce diagnostics storage and query model
**Files**:
- `Sources/CodeToolCore/` (new store/index/query files)
- `Sources/CodeToolCore/HistoryStore.swift`

**Changes**:
- 增加 diagnostics store：
  - recent fault/error 索引
  - unified external ID → related events 索引
  - trace/span 摘要索引
  - MetricKit payload 摘要持久化
- 为 `HistoryStore` 提供 diagnostics 关联查询桥梁，而不是重写其主存储模型
- 为新的 diagnostics 关联字段定义清晰 schema；旧 history 文件可直接删除，不做 additive decode 兼容
- 支持导出诊断包所需的元数据聚合

#### 3. Define export package composition
**Files**:
- `Sources/CodeToolCore/` (new export utility files)

**Changes**:
- 诊断包至少包含：
  - app version / build hash / build type
  - recent fault/error/info 摘要
  - 指定统一外显 ID 对应日志与 trace 摘要
  - 相关 `HistoryStore` 记录元数据
  - 最近 MetricKit payload 摘要
  - 系统版本与设备环境白名单字段
- 版本号与构建哈希只从 app info 读取，不额外依赖运行时 git commit / git branch 查询

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [x] Diagnostics store/index CRUD tests
- [x] `HistoryStore` 新 schema 与 diagnostics association tests
- [x] export package composition tests

#### Manual Verification
- [ ] app 启动后不需要触发 AI 请求，也会有 lifecycle 观测记录
- [ ] MetricKit payload 到达时可被持久化摘要
- [ ] 给定统一外显 ID，可以查到相关 diagnostics 条目与 history 记录
- [ ] 导出诊断包包含预期元数据且不含敏感正文/密钥

---

## Phase 3: MiniMax Transport Instrumentation

### Overview

先改造最集中的请求边界：`MiniMaxAPIClient`。目标是最小化视图层分散打点，把统一 observability 主要落在 transport 层和少量视图边界错误点。

### Changes Required

#### 1. Upgrade MiniMax diagnostics context to unified observability context
**File**: `Sources/CodeToolCore/MiniMaxAPIClient.swift`

**Changes**:
- 把现有 `DiagnosticsContext` / `MusicDiagnosticsContext` 演进为统一 context
- 在请求开始、结束、失败时写入统一 observability event
- 继续保留当前 redaction/summary 逻辑，但把 hash/长度字段纳入统一策略
- 把 `referenceID` 语义升级为统一外显 ID，确保 chat/speech/image/music 一致
- 为未来 trace/span 预留 parent-child 关系

#### 2. Keep current MiniMax response contracts stable while enriching metadata
**File**: `Sources/CodeToolCore/MiniMaxAPIClient.swift`

**Changes**:
- 保持现有 response structs 暴露统一外显 ID
- 不破坏现有视图层依赖 `referenceID` 的方式
- 扩展 request/response metadata，但保持原有错误文案与用户可见 ID 契约

#### 3. Trim view-level logging to true edge cases only
**Files**:
- `Sources/CodeToolCore/AIChatView.swift`
- `Sources/CodeToolCore/AISpeechView.swift`
- `Sources/CodeToolCore/AIImageView.swift`
- `Sources/CodeToolCore/AIMusicView.swift`

**Changes**:
- 视图层保留真正属于 UI 边界的日志：
  - playback prepare failure
  - image decode failure after successful transport
- 避免在 view 中重复记录 transport 层已覆盖的请求事件
- 确保保存 history 时继续写入统一外显 ID

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [x] 现有 MiniMax 相关日志测试继续通过或按兼容方式更新：
  - speech timeout log
  - image API error log
  - chat stream API error log
  - music timeout log
- [x] redaction/hash/summary unit tests

#### Manual Verification
- [ ] MiniMax chat/speech/image/music 各路径都能产出统一 observability 事件
- [ ] 错误文案继续向用户暴露可搜索的统一外显 ID
- [ ] Diagnostics 中可按该 ID 找到请求日志链路与关联 history

---

## Phase 4: Claude CLI Subprocess & Session Instrumentation

### Overview

补齐当前最不一致的链路：Claude CLI。目标是让 subprocess 执行、stderr、exit code、session continuation、history save 和统一外显 ID 成为同一条 observability 链。

### Changes Required

#### 1. Add unified observability to subprocess lifecycle
**File**: `Sources/CodeToolCore/ClaudeCLIClient.swift`

**Changes**:
- 在 subprocess 启动、stdout event、stderr 收集、非零退出、取消、完成等边界写统一 observability event
- 为 `ClaudeCLITurnRequest` / send flow 增加统一外显 ID 传播
- 让 `sessionId` 保持为会话续接语义，不再承担用户可见问题定位语义
- 为 trace/span 模型预留 process span
- 保持现有 `--resume` CLI 合约与对应测试兼容

#### 2. Make Claude history use the same external ID semantics as execution
**File**: `Sources/CodeToolCore/ClaudeChatView.swift`

**Changes**:
- 不再在 `makeConversationRecord()` 时临时生成另一个“历史 ID”
- 将 subprocess 执行链路的统一外显 ID 传到 history record
- 在 `.result`、`.completed`、`.error` 等状态收口时保证 UI、history 与 diagnostics 共享同一个 ID
- 为 attachment save failure / history save failure 增加结构化边界事件

#### 3. Preserve conversation persistence behavior
**Files**:
- `Sources/CodeToolCore/ClaudeChatView.swift`
- `Sources/CodeToolCore/HistoryStore.swift`
- `Tests/CodeToolTests/CodeToolTests.swift`

**Changes**:
- 保持当前 stable conversation record ID 覆盖写模式
- 保持 `sessionId` 在 history 中可选，用于续接语义和 diagnostics 关联
- Claude history schema 可直接演进；若落盘格式调整，可清理旧记录而不做 backward compatibility

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [x] Claude CLI fake executable tests继续通过，尤其是 `--resume` 行为
- [x] Claude history Codable round-trip tests
- [x] Claude history overwrite semantics tests

#### Manual Verification
- [ ] Claude CLI 启动失败、stderr 报错、非零退出都能在 Diagnostics 中被检索
- [ ] Claude 一次对话从发起到保存 history 使用同一个外显 ID
- [ ] 通过该 ID 能看到 subprocess 事件、session 关联信息和 history 记录

---

## Phase 5: Diagnostics Tab in Settings

### Overview

在现有 `SettingsSheet` 里新增 Diagnostics Tab，复用现有设置页与 `HistoryDrawer` 风格，提供 Phase 1 必需的本地诊断消费面。

### Changes Required

#### 1. Extend settings shell with Diagnostics tab
**Files**:
- `Sources/CodeToolCore/ContentView.swift`
- `Sources/CodeToolCore/MiniMaxSettingsView.swift`
- `Sources/CodeToolCore/ClaudeCLISettingsView.swift`
- `Sources/CodeToolCore/ToolWorkbench.swift`

**Changes**:
- 在现有 SettingsSheet segmented control 中新增 Diagnostics tab
- 维持 MiniMax / Claude CLI tab 行为不变
- 确保 Diagnostics 使用与现有设置页一致的 ToolWorkbench shell

#### 2. Build Diagnostics view using existing local UI language
**Files**:
- `Sources/CodeToolCore/` (new `DiagnosticsView.swift`, maybe supporting subviews)
- `Sources/CodeToolCore/HistoryDrawer.swift`

**Changes**:
- 展示 recent fault/error 列表
- 支持按统一外显 ID 搜索
- 展示 trace/span 摘要
- 关联显示 `HistoryStore` 记录
- 支持导出诊断包
- 优先复用 `HistoryDrawer` 的时间线/本地记录浏览模式，而不是重造完全不同的 UI 语言

#### 3. Make Diagnostics search bridge logs + trace summaries + HistoryStore
**Files**:
- `Sources/CodeToolCore/` (diagnostics query files)
- `Sources/CodeToolCore/HistoryStore.swift`

**Changes**:
- 给定统一外显 ID，Diagnostics 页面能聚合：
  - structured log events
  - subprocess/request trace 摘要
  - MetricKit 摘要
  - relevant history records

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [ ] Diagnostics view model/search/export tests
- [ ] settings routing tests where practical

#### Manual Verification
- [ ] 打开 settings 可看到 Diagnostics tab
- [ ] recent fault/error 可浏览
- [ ] 输入统一外显 ID 可检索到日志、trace 摘要与相关 history
- [ ] 导出诊断包成功且结果符合隐私策略

---

## Phase 6: Hardening, Migration, and Verification

### Overview

收口留存裁剪、失败降级、坏数据清理、测试扩充与手工验证，确保 observability 系统不会反过来成为稳定性风险。

### Changes Required

#### 1. Storage cleanup and bad-data hardening
**Files**:
- `Sources/CodeToolCore/AppLogger.swift`
- `Sources/CodeToolCore/HistoryStore.swift`
- `Tests/CodeToolTests/CodeToolTests.swift`

**Changes**:
- 明确升级时可清理旧 JSONL 日志与旧 history 目录，不做迁移
- 明确 Diagnostics 遇到坏记录/坏日志时的跳过、删除或重建策略
- 验证坏数据不会阻断 app 启动、Diagnostics 查询或新数据落盘

#### 2. Failure-mode hardening
**Files**:
- observability storage/query/export files
- affected view/client files

**Changes**:
- 本地磁盘不足
- sink 写入失败
- diagnostics export 失败
- MetricKit payload 延迟或不可用
- history 记录与日志不完全一致时的 UI 降级

#### 3. Final verification matrix
**Files**:
- `Tests/CodeToolTests/CodeToolTests.swift`
- plan execution notes only through code/test updates, no extra repo docs

**Changes**:
- 按现有测试模式扩展：
  - logger override + raw content assertions
  - MiniMax mock URLProtocol
  - Claude fake executable
  - HistoryStore temp directory
- 手工验证设置页 Diagnostics 流程与典型错误路径

### Success Criteria

#### Automated Verification
- [ ] `swift build`
- [ ] 针对 observability foundation、MiniMax、Claude、HistoryStore、Diagnostics 的新增测试
- [ ] 现有受影响测试继续通过或在同一事件语义下更新通过

#### Manual Verification
- [ ] sink 失败不影响主业务流程
- [ ] 升级后即使删除旧历史记录和旧日志，app 与 Diagnostics 仍可正常工作
- [ ] Phase 1 范围内所有链路都可通过同一个外显 ID 在 Diagnostics 中检索

## Testing Strategy

### Unit / Automated Tests

- `AppLogger` contract tests
- redaction/hash/summary tests
- retention pruning tests
- diagnostics store/index tests
- export package tests
- MiniMax logging path tests using `MockURLProtocol`
- Claude subprocess tests using fake executable scripts
- HistoryStore schema rewrite / query association tests
- Diagnostics search aggregation tests

### Manual Verification Steps

1. 启动 app，打开 Settings，确认新增 Diagnostics tab。
2. 触发一次 MiniMax 失败请求，记录用户可见 ID。
3. 在 Diagnostics 中搜索该 ID，确认可看到日志链路与相关 history。
4. 触发一次 Claude CLI 启动失败或非零退出，确认 Diagnostics 能检索到 subprocess 边界事件。
5. 触发一次 speech/image/music 的 UI 边界错误，确认保留的 view-level observability 事件可被检索。
6. 导出诊断包，确认包含 app version / build hash / app info / diagnostics 摘要 / history metadata，且不包含敏感正文或密钥。
7. 人工制造 retention 压力，确认双上限裁剪生效且 fault/error 优先保留。

## Performance Considerations

- 高集中度打点优先落在 `MiniMaxAPIClient`、`ClaudeCLIClient`、`HistoryStore`、app lifecycle，而不是在每个视图里无差别加日志。
- Diagnostics 查询层需要避免扫描所有原始日志文件作为常态路径，Phase 1 应通过本地索引/摘要层提升查询效率。
- export 和 retention cleanup 必须后台执行，不阻塞主线程。

## Migration Notes

- `referenceID` / `traceID` 不采取双轨对外策略，Phase 1 统一为同一个外显 ID；但在代码迁移期可通过兼容 API 保持旧命名不立即大规模重构。
- Claude 路径需要从“保存 history 时才生成 `referenceID`”迁移到“执行开始即拥有统一外显 ID”，这是最关键的语义修正之一。
- 旧日志与旧 history 不做迁移；升级时可直接清理 `Application Support/CodeTool/logs` 与相关 history 目录。
- `HistoryStore` schema 可以直接演进；若遇到旧格式残留，策略是删除或忽略，而不是兼容混读。

## References

- Research spec: `thoughts/shared/specs/2026-04-02-observability-issue-tracking.md`
- Claude CLI harness spec: `thoughts/shared/specs/2026-03-31-ai-chat-claude-cli-harness.md`
- Claude CLI plan: `thoughts/shared/plans/2026-03-31-ai-chat-claude-cli.md`
- History UI plan: `thoughts/shared/plans/2026-03-31-tool-history-ui.md`
- Streaming interaction research: `thoughts/shared/research/2026-04-01-aichat-streaming-interaction.md`
- App entry points: `Sources/CodeToolApp/CodeToolApp.swift`, `Sources/CodeToolApp/AppDelegate.swift`
- Logging core: `Sources/CodeToolCore/AppLogger.swift`
- MiniMax boundary: `Sources/CodeToolCore/MiniMaxAPIClient.swift`
- Claude boundary: `Sources/CodeToolCore/ClaudeCLIClient.swift`, `Sources/CodeToolCore/ClaudeChatView.swift`
- Persistence boundary: `Sources/CodeToolCore/HistoryStore.swift`
- Settings / diagnostics landing zone: `Sources/CodeToolCore/ContentView.swift`, `Sources/CodeToolCore/ClaudeCLISettingsView.swift`, `Sources/CodeToolCore/MiniMaxSettingsView.swift`
- Existing tests: `Tests/CodeToolTests/CodeToolTests.swift`
