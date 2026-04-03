---
date: 2026-04-02T23:50:19+08:00
researcher: zhang
git_commit: 76b9593663a5abe794f6270dbdbc53d167ff1648
branch: main
topic: "macOS App 可观测性与问题追踪基础设施"
tags: [research-spec, observability, logging, tracing, metrickit, crash-reporting]
status: complete
confidence: high
last_updated: 2026-04-02
last_updated_by: zhang
---

# macOS App 可观测性与问题追踪基础设施 Research Spec

## Summary

为 CodeTool 构建一套分层的可观测性基础设施，统一覆盖 crash/fatal、结构化日志、trace/span、MetricKit 与本地诊断导出能力，使开发者能基于 `referenceID` / `traceID` 在几分钟内定位用户问题，同时为后续接入远端采集平台预留稳定接口。

## Background

当前代码库已经有一套局部可用的诊断能力，但距离“良好的问题追踪系统”还有明显缺口：

- 已存在 `AppLogger`，以 JSON Lines 形式写入 `Application Support/CodeTool/logs`，并在 MiniMax 相关链路记录 `info` / `error` 日志。
- `MiniMaxAPIClient` 已经在请求开始、结束、失败时写入结构化字段，并向上层返回 `referenceID`。
- `HistoryStore` 会持久化 AI Chat / Speech / Image / Music / Claude Chat 的历史记录，其中保存了 `referenceID`，Claude 路径还保存了 `sessionId`。
- 但当前没有：
  - 系统级 `OSLog` / Unified Logging 接入
  - crash / fatal 采集与统一出口
  - 跨模块统一 trace/span 模型
  - MetricKit / `os_signpost` / hang 与性能诊断采集
  - Claude CLI 路径与 MiniMax 路径一致的观测模型
  - 内置 Diagnostics 查看与导出入口

结果是：MiniMax 相关问题可以看到一些局部日志，但 App 生命周期、Claude CLI 子进程、持久化失败、系统性能退化、用户设备级 crash/hang 仍然缺乏统一追踪。

## Goals

- 建立四层可观测性体系：Crash & Fatal、Structured Logging、Tracing、Metrics & Health。
- 用统一上下文模型串联主 App 生命周期、MiniMax 网络请求、Claude CLI 子进程、HistoryStore 持久化和调试工具页面。
- 在 Phase 1 内提供本地 Diagnostics 查看与导出能力，而不依赖远端控制台。
- 默认采用隐私优先策略：日志不落用户正文，只落摘要、长度、哈希与关键结构化字段。
- 架构上预留可插拔 sink，后续可接自建后端或第三方 SaaS。

## Non-goals

- 本期不设计问题分组、去重、告警路由、工单流转与归因平台。
- 本期不强制接入第三方 crash/telemetry SaaS。
- 本期不实现 XPC / Extension 专用传播协议，仅要求为未来预留上下文传播接口。
- 本期不构建复杂可视化分析后台。
- 本期不以完整用户行为埋点替代业务分析平台。

## Requirements

### Functional Requirements

- 提供统一的 `Observability` 入口层，至少包含：
  - `Logger` 抽象
  - `TraceContext` / `Span` 抽象
  - `MetricsSink` / `DiagnosticSink` 抽象
  - 可插拔 `sink` 注册机制
- Crash / Fatal 层必须覆盖：
  - App 生命周期启动、前后台切换、退出
  - 未恢复的 fatal 类错误
  - 子进程异常退出（Claude CLI 非零退出、stderr 异常）
  - MetricKit 交付的 crash/hang 诊断 payload 接收与落盘
- Structured Logging 层必须：
  - 优先写入 `OSLog` / Unified Logging
  - 本地持久化 `.fault` / `.error` / `.info` 级别日志
  - 对 `.debug` / `.trace` 实施按构建配置与开关控制
  - 支持事件名、类别、级别、时间戳、模块、线程/任务上下文、`referenceID`、`traceID`、`spanID`、错误域/错误码、耗时、状态码等结构化字段
- Tracing 层必须：
  - 对每个用户操作创建 `traceID`
  - 对关键模块步骤创建 `span`
  - 支持父子 span 关系与耗时计算
  - 在主 App -> MiniMax 请求 -> Claude CLI 子进程 -> HistoryStore 落盘的边界上传播上下文
  - 为未来 XPC / Extension 传播定义可序列化上下文格式
- Metrics & Health 层必须：
  - 接入 `MetricKit`
  - 采集 crash-free / hang 相关诊断输入
  - 采集启动时间、关键请求耗时、子进程执行耗时、历史落盘失败率等核心指标
  - 支持使用 `os_signpost` 标记关键性能区间
- Diagnostics 消费面必须：
  - 内置一个 Diagnostics 入口
  - 能查看最近 `.fault` / `.error`
  - 能按 `referenceID` / `traceID` 搜索
  - 能导出诊断包（日志片段、trace 摘要、最近 MetricKit payload 元数据、版本信息、设备信息、相关 history 元数据）
- 数据策略必须：
  - 默认不记录用户正文、Prompt、Lyrics、Claude 完整工具输入
  - 只记录摘要、长度、哈希、模型、状态码、耗时与必要上下文字段
  - Debug 构建支持可配置的脱敏片段记录
  - 敏感值必须显式标记并统一经过 redaction 策略
- 失败策略必须：
  - 所有 sink 的失败都不得阻塞主业务流程
  - 允许低优先级日志丢弃
  - sink 自身错误必须以内部 fault/error 记录，但要防止递归写爆

### Non-functional Requirements

- **性能**:
  - 普通日志写入不应显著增加主线程延迟。
  - trace/span 创建必须足够轻量，可安全用于高频交互边界。
  - Diagnostics 导出应在后台执行。
- **安全**:
  - 默认采用最小化数据采集。
  - 不记录 API Key、完整正文、完整附件内容、完整工具输入。
  - 支持按字段级 redaction。
- **兼容性**:
  - 应兼容现有 `AppLogger` / `referenceID` / `HistoryStore` 语义，避免一次性推翻现有诊断入口。
  - 新系统需能逐步接管 MiniMax 与 Claude CLI 路径。
- **可用性**:
  - 即使远端 sink 不存在或失败，本地诊断依然可用。
  - 开发者应能通过系统 Console 与应用内 Diagnostics 双路径排障。

### Constraints

- 当前仓库只有两个 SwiftPM target：`CodeToolApp` 与 `CodeToolCore`，且依赖较轻，不适合在 Phase 1 强依赖重量级遥测栈。
- 当前生产级日志主要集中于 `MiniMaxAPIClient`，Claude CLI 与 App 生命周期观测能力薄弱，改造必须考虑渐进接入。
- 当前历史与日志都落在 `Application Support/CodeTool/` 下，本期应优先沿用该存储模型。
- 第一阶段范围限定为：
  - 主 App 生命周期
  - MiniMax 网络请求
  - Claude CLI 子进程
  - HistoryStore 持久化
  - 调试工具类页面
  - 未来 XPC/Extension 预留设计

### Assumptions

- 目标运行环境为 macOS 14+，可使用现代 Swift Concurrency、`OSLog` 与 `MetricKit` 能力。
- Phase 1 以“先把本地排障闭环打通”为优先级，高于远端聚合。
- 当前已有 `referenceID` 是重要兼容资产，后续应将其视为 `traceID` 的外显或桥接字段之一，而不是直接废弃。
- 现有 JSON 文件日志可以保留为兼容/导出层，但系统级事实源应转向 Unified Logging。

## Current Behavior Summary

### What exists today

- `AppLogger`:
  - 提供 `info` / `error`
  - 写入 JSONL 本地文件
  - 支持 `referenceID`
  - 自动附加错误域、错误码、基础 stack trace
- `MiniMaxAPIClient`:
  - 在请求开始/结束/失败处集中打点
  - 为 Chat / Speech / Image / Music 分配 `referenceID`
  - 在部分路径记录耗时、状态码、响应摘要
- `HistoryStore`:
  - 持久化多个功能的历史记录
  - 保存 `referenceID`
- Claude CLI:
  - 具备 `sessionId`
  - 通过 `Process` + NDJSON event 工作
  - 尚未纳入统一日志与 trace 体系

### What is missing today

- App 级 crash / fatal / hang 观测
- `OSLog` / Unified Logging
- 统一 trace/span 上下文
- MetricKit 集成
- `os_signpost`
- Diagnostics UI / 导出能力
- 统一 redaction / 数据分级
- sink 插件机制

## Proposed Design

### 1. Layered Observability Architecture

定义一个统一架构：

1. `ObservabilitySystem`
   - 负责启动、配置、sink 注册、全局策略、构建模式开关
2. `AppEventLogger`
   - 面向业务代码的统一结构化日志 API
3. `TraceManager`
   - 负责创建 `TraceContext`、`SpanContext`、传播与结束
4. `MetricsManager`
   - 负责 `MetricKit` payload 接收、关键指标聚合、`os_signpost` 包装
5. `DiagnosticsStore`
   - 负责本地索引、留存裁剪、导出诊断包

### 2. Log Model

建议日志级别与持久化策略：

| Level | 用途 | Unified Logging | 本地持久化 |
| --- | --- | --- | --- |
| `.fault` | 不可恢复错误、严重观测系统异常 | 是 | 是 |
| `.error` | 可恢复但异常、用户请求失败 | 是 | 是 |
| `.info` | 关键业务流转、边界事件 | 是 | 是 |
| `.debug` | 开发诊断 | 是 | 按开关 |
| `.trace` | 高频时序/性能细节 | 优先 signpost / 可选日志 | 默认否 |

建议统一日志字段：

| 字段 | 说明 |
| --- | --- |
| `timestamp` | 事件发生时间 |
| `level` | 日志级别 |
| `subsystem` | 如 `com.codetool.app` |
| `category` | 如 `aichat` / `claudechat` / `history` |
| `event` | 机器可聚合事件名 |
| `message` | 人类可读简述 |
| `referenceID` | 与现有系统兼容 |
| `traceID` | 一次用户操作全链路 ID |
| `spanID` / `parentSpanID` | trace 层级关系 |
| `module` | 例如 `MiniMaxAPIClient` |
| `durationMs` | 耗时 |
| `status` / `httpStatus` / `exitCode` | 结果码 |
| `errorDomain` / `errorCode` | 错误结构化字段 |
| `payloadSummary` | 摘要而非正文 |
| `payloadLength` / `payloadHash` | 用于比对与去敏排查 |

### 3. Trace Model

建议核心模型：

```swift
struct TraceContext: Codable, Sendable {
    let traceID: UUID
    let rootReferenceID: String
    let startedAt: ContinuousClock.Instant
    let source: TraceSource
    let attributes: [String: String]
}

struct SpanContext: Codable, Sendable {
    let traceID: UUID
    let spanID: UUID
    let parentSpanID: UUID?
    let name: String
    let startedAt: ContinuousClock.Instant
    let attributes: [String: String]
}
```

传播策略：

- 用户点击“发送/生成/保存”等动作时创建 root trace。
- `MiniMaxAPIClient` 请求创建网络 span。
- `ClaudeCLIClient` 启动子进程时创建 process span，并将 `traceID` / `referenceID` 作为环境变量或启动参数的附加上下文。
- `HistoryStore` 保存记录时创建 persistence span。
- 未来 XPC/Extension 通过序列化后的 `TraceContextEnvelope` 传播。

### 4. Crash & Fatal Strategy

Phase 1 采用“Apple 原生优先 + 可插拔远端 sink”：

- 本地事实源：
  - Unified Logging
  - 本地 DiagnosticsStore
  - MetricKit payload
- 远端策略：
  - 通过 `RemoteDiagnosticsSink` 协议预留
  - 默认不启用具体供应商
- 需要覆盖的故障源：
  - App 生命周期异常退出
  - 致命断言/前置条件失败
  - Claude CLI 非零退出与 stderr 异常
  - 关键持久化失败
  - MetricKit 的 crash / hang 诊断

说明：Swift 的 `fatalError`/崩溃并不能都靠应用层可靠捕获，因此设计目标不是“拦截所有 crash”，而是通过系统日志、MetricKit、崩溃前关键 breadcrumb 与退出前边界事件最大化恢复现场。

### 5. Metrics & Health Strategy

指标分四类：

| 指标类型 | 指标 | 实现建议 |
| --- | --- | --- |
| 稳定性 | crash-free rate, hang diagnostics count, Claude 进程异常退出率 | MetricKit + 本地聚合 |
| 性能 | 启动时间、请求耗时、子进程耗时、导出耗时 | `os_signpost` + 结构化日志 |
| 业务/产品 | 功能使用量、生成成功率、失败分布 | 事件聚合，默认本地 |
| 资源/健康 | 内存压力、CPU 异常、磁盘写入失败率 | MetricKit + 本地 health counters |

Phase 1 至少应产出以下可消费指标：

- `app.launch.duration`
- `minimax.request.duration`
- `minimax.request.failure_rate`
- `claude.process.duration`
- `claude.process.nonzero_exit_rate`
- `history.save.failure_rate`
- `diagnostics.export.duration`
- `diagnostics.log.dropped_count`

### 6. Diagnostics Center

第一阶段需要内置 Diagnostics 入口，至少包含：

- 最近 fault/error 列表
- 按时间、类别、级别过滤
- 按 `referenceID` / `traceID` 搜索
- 查看单次 trace 的 span 摘要
- 导出诊断包

诊断包建议包含：

- App 版本、commit、branch、构建类型
- 最近 fault/error/info 摘要
- 指定 `referenceID` / `traceID` 的相关日志
- 相关 history 元数据（不含敏感正文）
- 最近 MetricKit payload 摘要
- 设备与系统版本信息

## Edge Cases

| 场景 | 预期行为 |
| -------- | ---------- |
| `OSLog` 可写但本地文件 sink 失败 | 主流程继续，记录内部 sink fault，允许文件持久化缺失 |
| 本地磁盘空间不足 | 丢弃低优先级日志，保留 fault/error，Diagnostics 明确标记数据不完整 |
| Claude CLI 非零退出但 stderr 为空 | 仍记录 process fault，写入 exit code、命令摘要、trace/reference ID |
| 同一用户操作触发多个并发请求 | 共用同一 `traceID`，为每个请求创建独立 span |
| `HistoryStore` 成功但业务请求失败 | 按实际边界分别记录 span 结果，不能伪装为成功链路 |
| Debug 开关打开时包含敏感片段 | 必须经过 redaction，并在 Diagnostics 中标记该日志包含调试级敏感片段 |
| MetricKit payload 延迟到达 | 作为异步补充事实写入，不要求实时阻塞主流程 |
| 观测系统自身抛错 | 仅允许有限递归保护下的内部 fault 记录，不得无限重试 |
| 旧记录只有 `referenceID` 没有 `traceID` | 查询层支持桥接，把 `referenceID` 视作旧链路主键 |
| 未来增加 XPC / Extension | 使用预留的 `TraceContextEnvelope`，而不是重做 trace 模型 |

## Dependencies

- Apple Unified Logging (`OSLog`, `Logger`)
- Apple `MetricKit`
- `os_signpost` / Instruments 兼容的性能标记能力
- 现有 `AppLogger`
- 现有 `MiniMaxAPIClient`
- 现有 `ClaudeCLIClient`
- 现有 `HistoryStore`

## Acceptance Criteria

- [ ] 主 App 生命周期、MiniMax、Claude CLI、HistoryStore、调试工具页面全部接入统一 observability API。
- [ ] 每次用户主操作都生成 `traceID`，并可在至少 3 个跨模块边界上继续传播。
- [ ] 所有请求失败场景都能从 Diagnostics 中通过 `referenceID` 或 `traceID` 找到对应日志链路。
- [ ] Claude CLI 非零退出、stderr 异常、启动失败均被记录为结构化事件。
- [ ] MiniMax 网络请求统一记录请求开始、结束、失败、耗时、状态码与脱敏摘要。
- [ ] HistoryStore 的保存/加载失败具备结构化日志与 span 记录。
- [ ] `OSLog` 成为主日志出口；本地持久化作为诊断与导出层保留。
- [ ] `MetricKit` payload 能被接收、落盘并在 Diagnostics 中查看摘要。
- [ ] Diagnostics 页面支持 fault/error 浏览、`referenceID`/`traceID` 搜索和诊断包导出。
- [ ] 默认构建下日志不含用户正文、Prompt、Lyrics、完整工具输入和密钥。
- [ ] Debug 构建允许显式开启脱敏片段记录，且有统一开关与标识。
- [ ] sink 失败不会阻塞主流程，且可观测系统不会成为新的 crash 根因。
- [ ] 本地留存执行“双上限”裁剪：按时间 + 容量共同管理。

## Success Metrics

- 开发者针对单个用户问题，能在 **5 分钟内** 基于 `referenceID` / `traceID` 找到相关失败链路。
- `Claude CLI` 异常退出场景的现场恢复率显著提升：每次异常退出都有结构化记录和关联 ID。
- MiniMax 请求失败中，绝大多数都能看到明确的 stage、错误码、耗时、模型和摘要。
- Diagnostics 导出成功率达到高可用水平，且导出过程不阻塞用户交互。
- 低优先级日志丢弃在容量压力下可控，fault/error 保留率接近完整。

## Rollout Notes

- 先兼容现有 `AppLogger` 与 `referenceID`，再逐步迁移到统一 `ObservabilitySystem`。
- 优先改造集中边界层，而非在视图层分散打点：
  - `MiniMaxAPIClient`
  - `ClaudeCLIClient`
  - `HistoryStore`
  - `AppDelegate` / App 启动路径
- 对现有 JSONL 日志文件可保留读取能力，用于 Diagnostics 兼容历史数据。

## Open Questions

- [ ] 是否在 Phase 2 接入自建远端聚合后端，还是直接接第三方 SaaS。
- [ ] `traceID` 是否直接复用现有 `referenceID` 外显给用户，还是仅保留 `referenceID` 作为用户可见别名。
- [ ] Diagnostics 导出包是否需要加入更细粒度的设备/环境信息白名单配置。
