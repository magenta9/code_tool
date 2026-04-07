---
date: 2026-04-07T14:10:00+08:00
researcher: zhang
git_commit: f6a70f1c72f4f035dd03961f67752a2ad8136994
branch: main
topic: "Hermes Agent UI Wrapper"
tags: [research-spec, requirements, hermes, ai-tools, agent-ui]
status: complete
confidence: medium
last_updated: 2026-04-07
last_updated_by: zhang
---

# Hermes Agent UI Wrapper Research Spec

## Summary

新增一个独立 AI 工具 Hermes Agent，以本地 Hermes CLI / 子进程方式封装 Hermes agent，提供会话式聊天 UI、任意文件附件输入、新建 chat、工具执行时间线，以及基于 Hermes 本地 session 存储的 resume 入口；首版不做工作目录绑定、不做用户可恢复历史、不接 ACP / MCP / gateway 作为主交互面，也不追求完整复刻 Claude Chat 的全部能力。

## Background

当前仓库里已经有两类可复用模式，但没有现成的 Hermes 实现：

- 工具接入模式已经稳定：工具目录由 `ToolCatalog` / `ToolRegistry.defaults` 提供，详情页路由由 `ToolDestinationRegistry` 负责。
- Claude Chat 是最接近“agent UI 封装”的现有实现：它具备本地 CLI 子进程、流式事件解析、消息区、工具调用展示、附件输入、历史恢复等完整链路。
- `AIExecutionSession` 已经抽出了统一执行生命周期，但当前更适合“单次执行内核”，而不是完整的 agent 会话 UI 容器；Claude Chat 仍然主要走专用链路。

结合最新外部 research，可确认 Hermes 官方同时提供 CLI、ACP、MCP、gateway 四类入口，但对当前 CodeTool 而言，CLI 是唯一与现有本地子进程聊天壳直接同构的接入面。ACP 更适合编辑器代理集成，MCP 是 Hermes 的工具增强层，gateway 是跨消息平台入口，这三者都不应进入 Hermes V1 主范围。

这意味着 Hermes 的关键设计不是“能不能做”，而是“要做成 Claude 风格的独立 agent 工具，还是塞进通用 execution 抽象里”。基于现有代码和用户选择，本次明确采用前者。

## Current Behavior

### Existing Tool Integration Boundary

- 新增工具时，必须从 `ToolID`、`ToolCatalog`、`ToolDestinationRegistry` 三个点完成接入。
- README 和测试对工具数量、目录和路由有一致性要求，不能只改 UI 不改 catalog/tests/docs。

### Existing Agent-like UI Boundary

- `ClaudeChatView` 是当前唯一成熟的 agent 会话型 UI：本地进程驱动、消息流式渲染、工具调用条目、附件输入、历史抽屉、会话继续。
- 但它把会话、专用事件模型、历史记录和部分产品行为耦合在 Claude 专线里，不能直接当作通用 AgentWorkbench 复用。

### Existing Execution Boundary

- `AIExecutionSession`、`AIExecutionProvider`、`AIExecutionHistorySink` 已经能承载单轮执行生命周期、诊断和历史 side effects。
- 当前这套抽象还不覆盖 Hermes 这类“多消息会话 + 文件附件 + 工具过程时间线”的完整交互语义。

### Existing Settings And Diagnostics Boundary

- 设置面板当前是 `ContentView` 内部的手写 tab 分发，不是注册式 provider 扩展；Hermes 新增设置页是低风险改动，但必须显式加 tab。
- Diagnostics 链路与 HistoryDrawer 解耦。Hermes V1 可以只接诊断和最小持久化记录，而不暴露恢复旧 chat 的 UI。

## Goals

- 新增一个独立的侧边栏 AI 工具 Hermes Agent，而不是修改现有 AI Chat。
- Hermes 通过本地 CLI / 子进程运行，并由 app 负责启动、取消、事件解析与 UI 映射。
- 提供会话式消息界面，支持连续对话和“New Chat”清空当前上下文。
- 提供 resume 入口，优先复用 Hermes 自带的本地 session 存储，而不是由 CodeTool 自己维护一套完整恢复历史。
- 支持任意文件作为附件输入，入口至少包括拖拽、文件选择，以及 Finder 文件复制后的粘贴。
- 在 UI 中展示工具执行时间线和最终输出，帮助用户理解 agent 做了什么。
- 保持与现有产品外壳一致：复用 `ToolWorkbench`、共享主题和基础组件。

## Non-goals

- 不把 Hermes 做成 AI Chat 的一个 provider 切换项。
- 不替换现有 AI Chat / Claude Chat。
- 首版不做工作目录选择或工程目录绑定。
- 首版不做用户可恢复历史，不接 `HistoryDrawer` 作为产品功能。
- 首版不要求展示完整 thinking 过程；默认重点是工具时间线和最终输出。
- 首版不要求接入远端 HTTP / WebSocket Hermes 服务。
- 首版不把 ACP 作为客户端协议接入，不把 MCP 作为主交互层，不把 gateway 作为桌面内嵌交互方案。
- 首版不追求与 Claude Chat 完整功能对齐，例如成本统计、附件持久化恢复、session resume 等。

## Requirements

### Functional Requirements

#### FR1: 新增独立 Hermes 工具入口

- 新增稳定 `ToolID`，建议命名为 `hermesAgent`。
- 在 `ToolCatalog` 中新增一个 AI Tools 条目，显示名称建议为 `Hermes Agent`。
- 在 `ToolDestinationRegistry` 中为该 `ToolID` 注册独立 detail view。
- README、工具数量测试、catalog 完整性测试必须同步更新。

#### FR2: 本地 Hermes CLI 客户端封装

- 新增 Hermes 专属 client / provider 层，建议命名：
  - `HermesCLIClient.swift`
  - `HermesSettingsStore.swift`
  - `HermesSettingsView.swift`
- 该 client 负责：
  - 启动 Hermes 本地子进程
  - 传入 prompt 与附件上下文
  - 消费 stdout/stderr
  - 将 Hermes 输出解析为 UI 可消费事件
  - 支持取消当前请求
- 具体 CLI 参数、事件协议、认证方式依赖 Hermes 实际接口；在实现前必须先验证 Hermes CLI contract，尤其是：
  - stdin / stdout / stderr 形状
  - 流式输出协议
  - 退出码语义
  - 附件引用方式
  - 本地 session 发现与 resume 入口

#### FR3: Hermes 会话 UI

- 新增 `HermesAgentView` 作为独立工具主界面。
- 页面骨架复用 `ToolWorkbench`，并保留现有 AI 工具一致的 header、status chip 和 action 样式。
- 主体由三部分构成：
  - 消息列表
  - 工具执行时间线 / 过程卡片
  - 底部 composer
- 顶部 action 至少包含：
  - `New Chat`
  - `Stop`（仅请求进行中显示）
  - `Resume`（见 FR5）
  - `Settings` 入口可继续复用全局设置面板

#### FR4: 文件输入能力

- 支持任意文件附件输入，不限制为图片。
- 文件输入入口至少覆盖：
  - 拖拽文件到 composer
  - 通过文件选择器添加文件
  - 从 macOS pasteboard 粘贴文件 URL
- UI 需要展示附件 chip / 列表，支持单个移除和清空。
- 首版不做目录级挂载；附件语义限定为“当前请求的附加输入”。
- 如果 Hermes CLI 本身不支持二进制直传，则 app 需要将附件转化为本地文件路径或 Hermes 支持的引用形式。

#### FR5: 新建 Chat、Resume 与会话边界

- `New Chat` 明确表示重置当前内存态对话。
- 首版只要求单窗口内的当前 chat 上下文，不要求由 CodeTool 提供通用落盘恢复。
- 用户关闭 app 或切换工具后，Hermes 当前对话可视为易失状态。
- V1 暴露 `Resume` 入口，但其数据来源限定为 Hermes 自己的本地 session 存储或官方 continue 机制。
- CodeTool 不在 V1 自己维护“可恢复会话列表”或完整 session 映射。
- 如果目标 Hermes 版本缺少稳定的本地 session 读取协议，`Resume` 按钮允许保留，但必须显示明确的“不支持 / 当前版本不可用”提示，而不是伪装成功。
- `Resume` 不能反向扩大 V1 范围为“完整历史恢复产品”。

#### FR6: 工具过程展示

- UI 默认展示工具时间线和最终回答。
- 过程展示至少应覆盖：
  - 某个工具开始执行
  - 工具名称
  - 运行中状态
  - 结果或摘要
- 默认不要求完整展示 thinking；若 Hermes 协议提供 thinking，可保留为隐藏字段或二期扩展。
- 若 Hermes 无法提供结构化工具事件，至少要有请求阶段进度和最终输出的占位表现，不能让用户误以为请求卡死。

#### FR7: Hermes 设置与二进制发现

- 新增 Hermes 设置存储，至少包含：
  - Hermes 可执行文件路径
  - 可选模型 / profile 标识（若 Hermes 支持）
  - 可选附加参数或模式开关（若 Hermes 支持）
  - 可选认证信息来源说明，不在 UI 中泄露敏感值
- 设置页需要支持二进制路径发现或校验。
- 设置页以新增独立 tab 的方式接入现有 SettingsSheet，而不是改造为 provider registry。
- 当 Hermes CLI 不可用时，UI 应展示清晰错误 banner，并禁用发送。

#### FR8: 观测与错误处理

- 每次 Hermes 请求都要生成 `referenceID`，并贯穿：
  - Hermes client 日志
  - 子进程异常退出
  - 视图层错误展示
- 非零退出、stderr 输出、解析失败、附件转换失败都需要结构化日志。
- sink 失败不能阻塞主业务流。
- Hermes 首版即便不做会话恢复，也不能缺失诊断链路。
- Hermes V1 允许写入最小持久化诊断记录，用于 Diagnostics 导出和 `referenceID` 关联，但这不等同于对用户暴露 HistoryDrawer 或恢复 UI。

#### FR9: 首版不接入用户可恢复历史

- Hermes V1 不接 `HistoryDrawer` 作为产品功能。
- 不新增 Hermes 专属“恢复旧 chat”入口。
- 允许为诊断或未来扩展保留最小持久化记录；但不能在 V1 UI 中承诺“可恢复历史”。
- `Resume` 属于 Hermes 自有 session 能力映射，不等同于 CodeTool 历史恢复能力。

### Non-functional Requirements

- **性能**:
  - 流式输出应在主观上连续，UI 不应因时间线更新明显卡顿。
  - 附件加入和移除应为本地即时操作，不阻塞主线程。
- **安全**:
  - 默认不记录完整用户正文、附件原文、敏感 token。
  - 日志保留摘要、长度、错误码、参考 ID 等结构化字段。
- **兼容性**:
  - 保持现有 AI Chat / MiniMax 工具行为不变。
  - 继续遵守当前工具目录、路由、设置面板和 shared UI 约定。
- **可用性**:
  - Hermes CLI 缺失、参数无效、认证失败、文件不支持时，都要显示可理解的错误。
  - 如果 `Resume` 不可用，按钮或入口状态必须明确解释原因。

### Constraints

- 当前仓库没有 Hermes 相关代码，也没有 Hermes CLI 协议文档落在仓库中。
- 现有最接近模式是 Claude Chat 专线，而不是通用 agent workbench。
- 现有 `AIExecutionSession` 不足以直接承载“会话型 agent UI + 任意文件附件 + 工具时间线”这一整组产品行为。
- 工具接入必须遵守现有 catalog-routing 规则，不能仅靠 display name 临时路由。
- 设置面板是手写 tab 分发；Hermes 需要显式加入设置页，而不是自动出现。
- 首版范围已被明确收窄：不做工作目录、不做用户可恢复历史。
- Hermes V1 的 `Resume` 能力受制于 Hermes 自身是否暴露稳定的本地 session 存储读取协议。
- 当前 external research 没有证明 Hermes CLI 的附件 contract 和 session discovery contract 已稳定到可直接编码。

### Assumptions

- Hermes 有可调用的本地 CLI 或等价子进程入口。
- Hermes 至少能接收文本 prompt，并以 stdout/stderr 或流式协议返回结果。
- Hermes 附件能力可以通过文件路径或 Hermes 支持的 attachment schema 表达。
- Hermes 的 continue / resume 语义可以通过官方本地 session 存储或 CLI 提供的稳定入口访问。
- Finder 文件复制后的 pasteboard 输入是首版“copy/粘贴文件”的主要实现路径，而不是任意原始剪贴板二进制注入。

## Recommended Architecture

### Why Not Reuse AIExecutionSession Directly

直接把 Hermes 放到现有 `AIExecutionSession` 下，只能较好复用“开始执行、取消、记录失败”这一层；但用户需要的核心是一个 agent 工具壳：

- 多消息会话 UI
- 文件附件管理
- 过程时间线
- New Chat

这些能力当前都更接近 `ClaudeChatView` 的产品边界，而不是 `AIExecutionSession` 的执行边界。

### Recommended Shape

- 产品层：新增独立 `HermesAgentView`
- 传输层：新增 `HermesCLIClient`
- 设置层：新增 `HermesSettingsStore` / `HermesSettingsView`
- 目录与路由层：接入 `ToolCatalog` 与 `ToolDestinationRegistry`
- 观测层：沿用现有 `referenceID` + `AppLogger` / Diagnostics 约定，并允许写最小 HistoryStore 记录供诊断聚合使用

### Official Hermes Surface Mapping

- V1 主接入面：CLI
- V1 明确排除：ACP 作为主客户端协议
- V1 后续增强候选：MCP
- V1 明确排除：gateway 作为桌面交互主入口

### Optional Internal Reuse

如果 Hermes CLI 的事件模型足够简单，可以局部复用 `AIExecutionSession` 的诊断或 sink 思路；但不建议为了复用而把首版产品边界强行压扁成“单轮执行器”。

## Edge Cases

| 场景 | 预期行为 |
| --- | --- |
| Hermes CLI 未安装或路径错误 | 显示错误 banner，禁用发送按钮，引导用户到设置页修正 |
| 发送时没有文本但有附件 | 允许发送，视为“请处理这些附件”类请求 |
| 发送时既无文本也无附件 | 禁止发送 |
| 请求进行中再次发送 | 禁止再次发送，直到当前请求结束或被停止 |
| 用户点击 Stop | 终止子进程，保留已展示的部分结果，并标记本轮已中断 |
| 附件文件不存在或读取失败 | 在发送前阻止请求，并给出具体错误 |
| 附件类型 Hermes 不支持 | 在 UI 侧明确报错，而不是静默忽略 |
| Hermes 只返回最终文本，没有结构化工具事件 | UI 降级为“请求进行中 + 最终输出”模式 |
| Hermes 输出事件格式异常 | 记录 referenceID 和解析错误，显示用户可理解错误 |
| Hermes 本地 session 列表不可读 | `Resume` 入口显示不支持或不可用，而不是伪造空状态 |
| Hermes 支持 continue 但当前会话来源无效 | 明确提示恢复失败，并允许用户回到 New Chat |
| New Chat 时仍有请求在执行 | 先取消当前请求，再重置当前内存态 |
| app 关闭后重新打开 | 不承诺恢复到上次 Hermes 对话 |

## Dependencies

- 本地 Hermes CLI / agent 可执行文件
- Hermes 本地 session 存储或 continue/resume 入口
- 现有工具接入边界：`ToolCatalog`、`ToolRegistry`、`ToolDestinationRegistry`
- 现有共享 UI 壳：`ToolWorkbench`、`StyledComponents`、`AppTheme`
- 现有可观测性边界：`AppLogger`、Diagnostics、`referenceID`
- 现有设置面板宿主：`ContentView` 中的 SettingsSheet

## Acceptance Criteria

- [ ] 侧边栏中出现独立的 `Hermes Agent` 工具入口。
- [ ] 工具点击后进入独立的 Hermes 会话界面，而不是复用 AI Chat。
- [ ] Hermes 通过本地 CLI / 子进程成功启动并返回结果。
- [ ] 用户可以通过拖拽、文件选择、粘贴文件 URL 三种方式向当前请求添加附件。
- [ ] 附件支持在发送前可视化查看和移除。
- [ ] 用户可以启动新的 chat，并清空当前内存态上下文。
- [ ] 在 Hermes 提供稳定本地 session 协议的前提下，用户可以通过 `Resume` 入口继续旧会话；若不支持，UI 会明确提示不可用。
- [ ] 请求进行中可停止当前 Hermes 执行。
- [ ] UI 能展示工具时间线和最终输出；若 Hermes 不提供结构化事件，也有明确降级体验。
- [ ] Hermes CLI 缺失、解析失败、附件失败、非零退出等错误都会展示给用户并写入诊断日志。
- [ ] 首版没有由 CodeTool 提供的“恢复旧 chat”历史抽屉能力。
- [ ] Hermes 会写入最小诊断持久化记录，供 Diagnostics 导出和 `referenceID` 关联使用。
- [ ] `swift build` 通过。
- [ ] 工具 catalog、路由、README、测试在新增 Hermes 后保持一致。

## Success Metrics

- 用户能够在 app 内直接打开独立的 Hermes Agent 工具并完成一次带附件的请求。
- Hermes 工具的产品边界与 AI Chat 清晰分离，不引入 provider 混合复杂度。
- 即使 Hermes 协议能力不完整，V1 仍能提供稳定的发送、停止、附件输入和结果展示闭环。
- 即使 Hermes 目标版本不支持稳定 session discovery，V1 仍然可以交付主聊天能力，并对 `Resume` 不可用给出明确反馈。
- 诊断侧能基于 `referenceID` 定位 Hermes 子进程失败和解析失败。

## Open Questions

- [ ] Hermes CLI 的精确调用协议是什么：参数、stdin/stdout 形状、流式事件格式、退出码语义。
- [ ] Hermes 的认证方式是什么：环境变量、配置文件、系统登录态，还是完全不需要 app 参与。
- [ ] Hermes 是否支持结构化工具事件输出；若支持，字段名称和层级是什么。
- [ ] Hermes 对“任意文件附件”的支持方式是什么：文件路径引用、上传、还是专用多模态 schema。
- [ ] Hermes 本地 session 存储是否有稳定、可枚举、适合桌面 app 消费的读取协议。