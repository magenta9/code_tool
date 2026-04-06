---
date: 2026-04-06T15:31:33+08:00
researcher: zhang
git_commit: a310c816b38bc3c4a9bf8b9baf188f9205492816
branch: main
topic: "前端渲染性能深度研究"
tags: [research-spec, performance, swiftui, rendering]
status: complete
confidence: medium
last_updated: 2026-04-06
last_updated_by: zhang
---

# CodeTool 前端渲染性能研究规范

## Summary

围绕 CodeTool 的 SwiftUI 前端，建立一套可落地的渲染性能研究与治理规范，优先解决“隐藏工具页缓存保活 + 高频状态源 + 重型子树重复构建”叠加导致的输入卡顿、流式渲染抖动、历史抽屉/恢复卡顿与重型媒体页面掉帧问题。

## Background

### 现状

当前渲染性能问题不是单一控件热点，而是系统性叠加：

1. `ContentView` 会把访问过的工具页长期保留在缓存 `ZStack` 中，未选中页面仅通过 `opacity` 和 `allowsHitTesting` 隐藏，而不是移出视图树。
2. AI 工具页自己持有大块本地状态，并直接驱动高频更新：
   - `ClaudeChatView` / `AIChatView`：流式 text/thinking/tool-call 增量、自动滚动、Markdown 渲染
   - `AISpeechView` / `AIMusicView`：100ms tick 的播放状态更新
   - `AIImageView`：大图 hero + thumbnail/contact sheet 双重渲染
3. 若干重型子树在主线程渲染路径中做重复工作：
   - `ClaudeMarkdownView` 每次构建时重新解析 markdown
   - `ClaudeChatView` 在视图路径中同步解码附件缩略图
   - `ScrollingLyricsView` 在父视图更新时重建逐行模型
   - `HistoryDrawer` 打开时 eager load 全量记录，restore 时 eager decode 二进制资源

### 当前行为总结

- **全局壳层**：`ContentView` 的工具缓存策略保留工作态，但也让隐藏页面继续存在于视图树中。
- **高频更新源**：聊天流式 delta、自动滚动、播放 timer、hover/动画状态会持续触发 UI 更新。
- **重型渲染面**：Markdown、附件缩略图、图片工作台、历史抽屉、媒体恢复流程是当前最明显的主线程成本放大器。
- **已有先例**：`TimestampConverterView` 已经开始引入“仅可见时刷新”的治理思路，说明仓库可以接受 visibility-aware 的优化路线。

## Goals

- 建立覆盖全局壳层、聊天、历史、图像、音频播放四条主路径的性能研究范围。
- 明确代表性负载、量化采集方案与平衡档性能目标。
- 输出两条治理路线：
  - **低风险优化线**：尽量不改变交互语义，优先止血。
  - **架构治理线**：为后续深层重构提供边界和触发条件。
- 约束未来实现：默认保留页面缓存/状态语义，但允许在证据充分时引入“卸载隐藏页面”作为兜底策略。

## Non-goals

- 本文档不直接实施代码修改。
- 不以一次性重写全部 SwiftUI 页面或彻底替换 UI 架构为前提。
- 不要求第一阶段引入完整性能监控平台或常驻 profiling 系统。
- 不为非关键路径的视觉细节做无证据优化。

## Requirements

### Functional Requirements

#### FR1: 研究范围必须覆盖 4 类代表性负载

1. **长 Claude Chat**
   - 长 markdown 回复
   - thinking 区块
   - tool use / tool result
   - 图片附件
   - 自动滚动
2. **大 HistoryDrawer / restore**
   - 大量历史记录
   - 聊天附件
   - 图片/音频 restore
3. **AI Image 重型图像视图**
   - reference hero
   - reference strip
   - output hero
   - contact sheet
4. **AI Music / AI Speech 定时播放视图**
   - 播放 timer
   - seek / play pause
   - lyrics scroll / highlight

#### FR2: 研究结论必须把问题拆成“共享根因”和“页面特定热点”

**共享根因**
- 隐藏工具页仍挂载在视图树中
- 高频状态更新直接驱动大树重算
- 重型派生数据在 `body` 或构造路径中重复计算
- restore / history 打开路径是 eager 的，而不是渐进或惰性的

**页面特定热点**
- `ClaudeChatView` / `AIChatView`：streaming + markdown + auto-scroll
- `ClaudeChatView`：附件缩略图同步解码
- `AIImageView`：多处图像重复渲染与 restore 后的全量解码
- `AISpeechView` / `AIMusicView`：timer 驱动下的父视图刷新与歌词重建
- `HistoryDrawer`：全量 list/decode/sort 与行级摘要计算

#### FR3: 研究规范必须明确量化采集方案

应采用 **debug-only、轻量、可关闭** 的方式，优先复用现有 `Observability` / `Diagnostics` / `AppLogger` 能力，不要求先搭完整性能平台。

建议采集点如下：

| 采集点 | 采集内容 | 用途 |
| --- | --- | --- |
| `ContentView` 工具切换 | 选中工具 ID、切换开始/结束时间、是否命中缓存 | 评估切换卡顿与缓存副作用 |
| 工具可见性变化 | `isToolVisible` true/false、隐藏期间是否仍有 tick/streaming 更新 | 验证 offscreen work |
| Claude Chat 流式更新 | delta 数量、批次大小、UI 提交频率、auto-scroll 次数 | 识别 streaming 抖动与过度更新 |
| Markdown 渲染 | parse 耗时、消息长度、是否命中缓存 | 判断 markdown 是否为主热点 |
| HistoryDrawer 打开 | 目录扫描耗时、JSON decode 数量、首屏内容可见时间 | 评估 drawer latency |
| restore 流程 | 资源数量、首个可见预览时间、总恢复时间 | 评估 eager load 成本 |
| Playback tick | 可见/不可见状态下 tick 次数、UI 提交次数 | 验证隐藏页面是否仍在刷新 |

#### FR4: 规范必须输出两条治理路线

##### A. 低风险优化线（优先落地）

1. **Visibility gating**
   - 让高频刷新逻辑仅在页面可见时运行
   - 对 timer、streaming、auto-scroll、hover-heavy 子树做显式 gating
2. **Batching / throttling**
   - 限制聊天流式 UI 提交频率
   - 限制 auto-scroll 触发频率
3. **Render-path caching**
   - 缓存 markdown parse 结果或引入更稳定的 render model
   - 避免在 `body` 中同步解码图片和重建歌词模型
4. **Lazy hydration**
   - HistoryDrawer 首屏优先摘要
   - restore 先给首个可见结果，再补全剩余资源
5. **Stable identity**
   - 避免高频更新时列表、status chip、消息行因 identity 不稳定而全量重建

##### B. 架构治理线（第二阶段）

1. 引入统一的 **render/update policy**
   - 明确哪些页面可以缓存保活
   - 哪些页面需要隐藏即暂停
   - 哪些页面允许隐藏即卸载
2. 将重型派生逻辑从 View 中下沉到更稳定的 render model / view model / execution domain
3. 统一聊天、历史、restore 的增量更新契约
4. 为大资源（图片、附件、音频）引入更清晰的预解码/缩略图/渐进加载边界

#### FR5: 默认语义与兜底策略必须明确

- **默认语义**：优先保留工具页缓存保活和页面状态。
- **允许的兜底**：若证据显示某类隐藏页面仍长期制造显著 offscreen cost，可对该类页面引入“隐藏即卸载”或更细粒度 cache eviction。
- **不允许**：在没有负载和指标证据前，直接全局取消缓存。

### Non-functional Requirements

#### 性能

采用 **平衡档**，基线环境为 **Apple Silicon 开发机**。

##### 代表性负载定义

1. **长 Claude Chat**
   - 150-200 条消息
   - 含长 markdown、thinking、tool result
   - 至少 4-6 个图片附件
2. **大 HistoryDrawer / restore**
   - 300-500 条记录
   - 含附件型记录与媒体型记录
3. **AI Image**
   - 4 张 reference + 4 张 output
   - hero + thumbnails + grid 同时存在
4. **AI Music / AI Speech**
   - 持续播放 3-5 分钟
   - 有歌词或较长文本

##### 平衡档目标

- **工具切换**
  - 已打开的重型工具页切回，首个可交互帧目标 `p95 <= 300ms`
- **Claude Chat**
  - 中文输入法组合输入无明显候选中断或卡顿
  - 流式渲染 UI 提交频率应被批处理到可控范围，建议 `<= 20 commits/sec`
  - 主线程单次更新尖峰目标 `p95 <= 33ms`
- **HistoryDrawer**
  - 打开抽屉首屏可见目标 `<= 400ms`
  - 大数据量下允许剩余内容懒加载，但不能阻塞首屏摘要出现
- **AI Image restore**
  - 首个可见预览目标 `<= 600ms`
  - 全量恢复目标 `<= 1500ms`
- **AI Music / AI Speech**
  - 隐藏页面时不应继续产生可观察的 UI 提交
  - 可见时播放更新维持功能正确，且不因每次 tick 重建整块歌词/布局

#### 安全

- debug-only 观测不得记录敏感正文、完整附件路径或密钥。
- 聊天内容、文件内容、路径等仍需遵守现有 redaction/logging 规则。

#### 兼容性

- 保持 macOS SwiftUI 架构，不引入破坏现有模块边界的强制性依赖。
- 默认复用现有 `ToolWorkbench`、`StyledComponents`、`HistoryStore`、`Observability` 体系。

#### 可用性

- 优化不能破坏历史恢复、输入保留、附件展示、播放控制等现有核心行为。
- 若引入惰性化或卸载策略，必须保证用户可感知状态不会无提示丢失。

### Constraints

- 代码库当前采用缓存保活的工具页路由结构，变更需谨慎。
- 仓库已有的性能先例主要是定点优化，不是全局 runtime 管理器。
- Markdown、图片、历史、音频都与现有持久化/restore 行为耦合，不能只改 View 而忽略数据恢复链路。
- 指标采集方案应以轻量埋点和 debug-only 开关为主，避免观测本身制造新的主线程负担。

### Assumptions

- 当前最值得优先研究的是系统性渲染与状态传播问题，而非 GPU 绘制层面的极端瓶颈。
- Apple Silicon 开发机可作为首个真实基线。
- 用户接受“两条线都写，但先落低风险线”的策略。
- 若后续实测表明缓存保活是主导问题，允许把隐藏页面卸载纳入实现备选。

## Edge Cases

| 场景 | 预期行为 |
| --- | --- |
| 隐藏的 Claude Chat 仍在 streaming | 默认应停止或显著削弱无意义 UI 更新，不影响恢复时的最终内容一致性 |
| 隐藏的 Speech/Music 页面仍在播放 | 隐藏期间不应持续触发整页 SwiftUI 重算；必要时只保留底层播放状态，不保留频繁 UI 刷新 |
| 长 markdown 回复持续增长 | 渲染与滚动应批处理，避免每个 delta 都全树重建 |
| HistoryDrawer 记录量很大 | 首屏先展示摘要，剩余内容可惰性加载，不能整包 decode 后才出现 UI |
| restore 的图片/音频资源部分缺失 | 先恢复文本和参数，缺失资源给非阻塞提示，不让页面卡死或崩溃 |
| 引入隐藏页卸载策略 | 必须限定在高证据、高收益页面，且不能默默丢失用户编辑态 |
| IME 组合输入与 streaming 同时发生 | 输入优先级高于流式刷新，不能打断候选或造成明显输入延迟 |

## Dependencies

- `ContentView.swift`
- `ToolVisibility.swift`
- `ClaudeChatView.swift`
- `AIChatView.swift`
- `AIImageView.swift`
- `AISpeechView.swift`
- `AIMusicView.swift`
- `ClaudeMarkdownView.swift`
- `ClaudeChatComposer.swift`
- `HistoryDrawer.swift`
- `HistoryStore.swift`
- `ToolWorkbench.swift`
- `ScrollingLyricsView.swift`
- `ClaudeCLIClient.swift`
- `Observability` / `Diagnostics` / `AppLogger`

## Acceptance Criteria

- [ ] 研究范围明确覆盖长聊天、历史抽屉/恢复、AI Image、AI Music/Speech 四类负载
- [ ] 规范明确区分共享根因与页面特定热点
- [ ] 规范提供可执行的量化采集方案，而非仅停留在主观体感描述
- [ ] 规范同时给出低风险优化线与架构治理线
- [ ] 规范默认保留缓存保活语义，并明确“卸载隐藏页面”仅为证据驱动的兜底策略
- [ ] 规范给出 Apple Silicon 基线下的平衡档目标
- [ ] 规范覆盖 IME、streaming、history、restore、timer、offscreen work 等关键边界场景

## Success Metrics

- **交互体感**：用户在长聊天、重型 restore、媒体播放和切换工具时不再稳定复现明显卡顿。
- **量化证据**：关键链路具备可重复采集的耗时和更新频率指标。
- **架构收益**：后续性能修复不再只靠页面局部 patch，而能沿“可见性、批处理、惰性化、卸载策略”统一推进。
- **风险可控**：第一阶段优化不以牺牲页面状态保留为代价。

## Measurement Plan

### Phase A: Baseline Capture

1. 对四类代表性负载建立固定复现脚本或手工步骤。
2. 在 debug-only 模式采集：
   - tool switch latency
   - streaming update frequency
   - markdown parse cost
   - drawer open latency
   - restore first-preview / full-restore latency
   - hidden-page timer/streaming activity

### Phase B: Low-risk Remediation Validation

逐项验证以下策略能否带来稳定收益：

1. visibility gating
2. streaming batching / scroll throttling
3. markdown render cache
4. attachment/image lazy decode
5. history/restore incrementalization
6. stable identity cleanup

### Phase C: Architecture Decision Gate

只有在以下任一条件成立时，才建议进入架构治理线：

1. 低风险优化后关键指标仍无法达标
2. 同类问题在多个工具页反复出现且需要重复 patch
3. offscreen work 无法仅靠 visibility gating 彻底约束

## Open Questions

- [x] 隐藏页面卸载策略应做成全局统一策略，还是仅先对 AI/高频页面试点？
- [x] Markdown 优化应优先做解析缓存，还是直接引入更稳定的预计算 render model？
- [x] HistoryDrawer 应维持全量 JSON 扫描 + 摘要缓存，还是进一步演进到分页/索引化读取？

### Resolved Decisions

**Q1: 隐藏页面卸载策略**
- **决策**：采用**全局统一策略**，但在实现层面按页面类型区分行为。
- **理由**：分散的 page-specific 逻辑会快速累积技术债务，且难以统一治理。统一策略 + 差异化配置（`ToolWorkbench` 的 visibility policy registry）可兼顾一致性与灵活性。
- **粒度建议**：通过 `ToolVisibilityPolicy` 协议，允许按工具类型（chat/media/image）配置 `unloadOnHide`、`pauseOnHide`、`keepAliveOnHide` 三档。

**Q2: Markdown 优化**
- **决策**：**优先引入预计算 render model**，解析缓存作为渐进增强。
- **理由**：纯缓存方案仍会在首次解析时阻塞主线程，且无法解决大文档增量更新问题。预计算 model 将 markdown AST 与 attributedString 的构造移出 view body，支持后台预排版、增量 diff 与跨消息共享。
- **路径**：先构建 `MarkdownRenderModel`（持有 parsed AST + cached attributedString），再在 `ClaudeMarkdownView` 中桥接使用。

**Q3: HistoryDrawer 分页/索引化**
- **决策**：**演进到分页 + 摘要索引化读取**。
- **理由**：全量 JSON 扫描在 300-500 条记录时已出现明显首屏阻塞，分页可将首屏延迟从 O(n) 降到 O(1)（固定 page size）。长期看，历史记录随使用量线性增长，索引化是必经之路。
- **阶段规划**：第一阶段实现固定 page size（如 20 条）懒加载 + 内存缓存；第二阶段引入磁盘索引文件（`HistoryIndex`）支持随机访问和过滤。
