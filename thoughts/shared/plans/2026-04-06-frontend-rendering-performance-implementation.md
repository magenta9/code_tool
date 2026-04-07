# Frontend Rendering Performance Implementation Plan

## Overview

基于当前研究规范与源码核查，本计划把 CodeTool 的前端渲染性能治理拆成两条同步推进的主线：

1. 先建立 debug-only、轻量、可关闭的量化采集与共享可见性策略，确保每次优化都有基线和回归证据。
2. 再按热点优先级逐步治理 Claude Chat、AI Image、AI Speech、AI Music、History/restore 这几条真实主路径。

本计划遵守当前已确认的产品语义：默认保留工具页缓存保活与本地状态，不做全局取消缓存；“隐藏即卸载”只作为证据驱动的兜底策略，而不是第一阶段默认动作。

另外，当前主路由已明确由 ClaudeChatView 承担 AI Chat；旧的 AIChatView 不再是活动页面。本计划把 AIChatView 视为待清理的 legacy 代码，而不是第一阶段继续优化的目标。

## Current State Analysis

### Key Discoveries

- [Sources/CodeToolCore/Views/ContentView.swift#L36-L90](Sources/CodeToolCore/Views/ContentView.swift#L36-L90)
  - 工具页缓存采用只增不减的 retainedToolIDs，访问过的页面会持续挂在缓存集合中。
- [Sources/CodeToolCore/Views/ContentView.swift#L484-L503](Sources/CodeToolCore/Views/ContentView.swift#L484-L503)
  - ToolDetailCacheView 通过 ZStack、opacity、allowsHitTesting 隐藏页面，而不是移出视图树。
- [Sources/CodeToolCore/Views/Shared/ToolVisibility.swift#L4-L23](Sources/CodeToolCore/Views/Shared/ToolVisibility.swift#L4-L23)
  - 仓库已经有可见性环境值，但当前重型 AI 页面没有消费它；现有明确使用样例主要是 TimestampConverterView。
- [Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift#L13-L31](Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift#L13-L31)
  - ClaudeChatView 持有大量本地状态，且消息、streaming、thinking、附件、历史、工作目录都直接驱动视图更新。
- [Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift#L194-L203](Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift#L194-L203)
  - messages.count、streamingText、streamingThinking 的变化都会直接触发自动滚动。
- [Sources/CodeToolCore/Views/Shared/ClaudeMarkdownView.swift#L174-L185](Sources/CodeToolCore/Views/Shared/ClaudeMarkdownView.swift#L174-L185)
  - ClaudeMarkdownView 初始化时会同步解析 markdown；当前没有跨消息或跨增量的 render model 缓存边界。
- [Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift#L341-L378](Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift#L341-L378)
  - 历史消息附件缩略图在视图构建路径里同步读取文件并解码 NSImage。
- [Sources/CodeToolCore/Views/AITools/AIImageView.swift#L1070-L1153](Sources/CodeToolCore/Views/AITools/AIImageView.swift#L1070-L1153)
  - AIImageView 生成后立即把所有结果图解码为 NSImage 并回填页面状态。
- [Sources/CodeToolCore/Views/AITools/AIImageView.swift#L1280-L1343](Sources/CodeToolCore/Views/AITools/AIImageView.swift#L1280-L1343)
  - AIImage restore 会遍历全部参考图和输出图逐个读盘、逐个解码，然后一次性回填。
- [Sources/CodeToolCore/Views/AITools/AISpeechView.swift#L333-L363](Sources/CodeToolCore/Views/AITools/AISpeechView.swift#L333-L363)
  - AISpeechView 有常驻 100ms playback tick；当前并未按页面可见性暂停 UI 刷新。
- [Sources/CodeToolCore/Views/AITools/AIMusicView.swift#L267-L300](Sources/CodeToolCore/Views/AITools/AIMusicView.swift#L267-L300)
  - AIMusicView 同样有常驻 100ms playback tick；隐藏状态下也会保留这条刷新链。
- [Sources/CodeToolUI/ScrollingLyricsView.swift#L14-L19](Sources/CodeToolUI/ScrollingLyricsView.swift#L14-L19)
  - 歌词组件每次 body 都把整段文本拆成 LyricLine 数组，属于典型的 view-path 派生计算。
- [Sources/CodeToolCore/Persistence/HistoryStore.swift#L681-L737](Sources/CodeToolCore/Persistence/HistoryStore.swift#L681-L737)
  - 统一历史 list(query) 路径是目录扫描、全量读 JSON、全量解码、再排序。
- [Sources/CodeToolCore/Persistence/HistoryStore.swift#L800-L869](Sources/CodeToolCore/Persistence/HistoryStore.swift#L800-L869)
  - 传统 listSpeech/listImage/listMusic/listClaudeChat 与 loadData 也都偏 eager；HistoryDrawer 打开前数据已基本准备完毕。
- [Sources/CodeToolCore/Observability/AppLogger.swift#L181-L279](Sources/CodeToolCore/Observability/AppLogger.swift#L181-L279)
  - AppLogger 已支持结构化 metadata 与 durationMs，可作为 debug-only 性能埋点出口。
- [Sources/CodeToolCore/Observability/Diagnostics.swift#L74-L141](Sources/CodeToolCore/Observability/Diagnostics.swift#L74-L141)
  - DiagnosticsStore 具备本地 JSONL 存储与查询能力，但当前没有面向渲染性能的专用轻量事件模型。
- [Sources/CodeToolCore/Views/AITools/AIChatView.swift](Sources/CodeToolCore/Views/AITools/AIChatView.swift)
  - 该页面仍在仓库中，但 [Sources/CodeToolCore/Views/ContentView.swift#L8-L18](Sources/CodeToolCore/Views/ContentView.swift#L8-L18) 已明确把 aiChat 路由到了 ClaudeChatView。

### Corrections To The Research Spec

- 活动的 AI Chat 主路径是 ClaudeChatView，不是 AIChatView。
- ToolStatusItem 已经使用稳定字符串 id，见 [Sources/CodeToolUI/ToolWorkbench.swift#L3-L25](Sources/CodeToolUI/ToolWorkbench.swift#L3-L25)，因此“修复 status chip identity”不再是第一阶段热点。
- HistoryDrawer 的相对时间 formatter 已缓存，见 [Sources/CodeToolCore/Persistence/HistoryDrawer.swift#L5-L10](Sources/CodeToolCore/Persistence/HistoryDrawer.swift#L5-L10)，不应再作为主要收益点。

### Architectural Constraints

- 现有产品语义依赖缓存保活；不能在没有指标证据的前提下全局取消 retainedToolIDs。
- 现有可见性环境值已经存在，优先沿用 ToolVisibility 而不是重做路由签名。
- 观测方案必须复用现有 AppLogger 和 DiagnosticsStore，且默认只在 debug-only 范围开启，防止观测本身变成新负担。
- AIImage、AISpeech、AIMusic、ClaudeChat 的历史恢复都与 HistoryStore 耦合，优化不能只停留在视图层。
- 旧 AIChatView 虽然不在主路由，但其删除会牵涉到 legacy 文档、测试和可能的 execution-session 辅助代码边界，需要显式规划而不是顺手删文件。

## Scope

### In Scope

- 建立 debug-only 的渲染性能基线采集：工具切换、可见性变化、streaming 提交频率、markdown 渲染耗时、drawer 首屏时间、restore 首屏时间、隐藏页 tick 活动。
- 让重型 AI 页面真正消费 isToolVisible，并统一纳入共享 visibility policy。
- 优化 Claude Chat 的 streaming、markdown、auto-scroll、附件缩略图路径。
- 优化 AI Speech 和 AI Music 的播放 tick 与歌词派生计算。
- 优化 HistoryDrawer / HistoryStore / AIImage restore 的首屏策略和渐进加载边界。
- 删除旧 AIChatView 及其活动路径外的 stale 引用，确保后续性能治理不再围绕错误主路径展开。
- 为后续第二阶段架构治理定义统一的 render/update policy 边界。

### Out of Scope

- 不做全局缓存淘汰、LRU、统一卸载隐藏页面的激进改造。
- 不重写 MiniMaxAPIClient、ClaudeCLIClient 或整体 SwiftUI 架构。
- 不在第一阶段引入完整性能平台、常驻 profiler 或第三方 telemetry。
- 不删除 AIExecutionSession 及其支撑抽象，除非在完整引用清扫后确认它们完全脱离当前和后续计划；本计划默认先清理 AIChatView 本身和其 UI/路由层残留。
- 不为非关键路径做无证据视觉优化。

## Implementation Approach

实施顺序采用“先测量、再止血、后收口”的方式：

1. 先补统一的 debug-only 采集和 visibility policy，把 offscreen work 变成可观测事实。
2. 针对当前真实用户路径优先修 Claude Chat，再处理 Media，再处理 History 与 AI Image restore。
3. 最后做 legacy 清理和统一 render/update policy 收口，避免问题再次回流到页面级 patch。

选择这个顺序的原因是：

- 当前最重的交互问题集中在 ClaudeChatView，而不是旧的 AIChatView。
- 没有基线的情况下直接做“隐藏即卸载”风险过高，也违背当前缓存语义。
- History/restore 的收益需要与 drawer 首屏和首个可见预览指标一起验证，不能仅凭体感调整。

## Phase 1: Baseline Instrumentation And Visibility Policy

### Overview

建立最小可用的性能观测面，并把共享的页面可见性策略真正接到重型工具页，为后续优化提供统一边界。

### Changes Required

#### 1. Add Debug-only Performance Probe Surface
**Files**:
- `Sources/CodeToolCore/Observability/AppLogger.swift`
- `Sources/CodeToolCore/Observability/Diagnostics.swift`
- `Sources/CodeToolCore/Views/ContentView.swift`
- 如有必要，新增 `Sources/CodeToolCore/Observability/RenderingPerformance.swift`

**Changes**:
- 新增一组 debug-only 的性能事件帮助方法，复用 AppLogger 的 metadata 和 durationMs。
- 约定统一事件名，至少包含：
  - `tool_switch_started` / `tool_switch_finished`
  - `tool_visibility_changed`
  - `claude_stream_batch_committed`
  - `claude_markdown_rendered`
  - `history_drawer_opened`
  - `image_restore_first_preview_ready`
  - `image_restore_completed`
  - `playback_tick_observed`
- 观测内容只落工具 id、referenceID、长度、数量、耗时、是否命中缓存等脱敏字段，不记录正文或完整路径。

#### 2. Introduce Shared Visibility Policy Registry
**Files**:
- `Sources/CodeToolCore/Views/Shared/ToolVisibility.swift`
- `Sources/CodeToolCore/Views/ContentView.swift`

**Changes**:
- 在现有 isToolVisible 基础上，新增统一的 visibility policy 抽象，例如 `keepAliveOnHide`、`pauseOnHide`、`unloadOnHide` 三档。
- 第一阶段默认对重型页面只启用 `pauseOnHide`，不启用卸载。
- ContentView 在缓存页注入时不仅下发布尔可见性，也下发 policy 信息，避免各页面自定义一套 hide behavior。

#### 3. Wire Heavy Pages To Visibility State
**Files**:
- `Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift`
- `Sources/CodeToolCore/Views/AITools/AIImageView.swift`
- `Sources/CodeToolCore/Views/AITools/AISpeechView.swift`
- `Sources/CodeToolCore/Views/AITools/AIMusicView.swift`

**Changes**:
- 让上述页面开始消费 isToolVisible 与共享 policy。
- 第一阶段先不改变用户可见状态，仅为后续 gating 做条件分支和调试埋点。

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [x] `make test`
- [x] 搜索代码确认所有重型 AI 页面都开始消费 `isToolVisible` 或对应 policy 抽象

#### Manual Verification
- [ ] Debug 构建下可以看到工具切换、可见性变化和关键热点事件的脱敏性能日志。
- [ ] 非 Debug 构建不产生这批新增渲染性能事件。
- [ ] 页面切换行为与当前缓存语义保持一致，没有状态丢失。

---

## Phase 2: Claude Chat Hot-path Remediation

### Overview

优先治理当前真实主路径 ClaudeChatView，目标是降低 IME 输入干扰、streaming 抖动、markdown 重算和附件缩略图同步解码带来的主线程尖峰。

### Changes Required

#### 1. Batch Streaming UI Commits
**File**: `Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift`

**Changes**:
- 将 `handleEvent(_:)` 中对 `streamingText` 和 `streamingThinking` 的逐 delta 直接写入，改为批处理缓冲。
- 为 UI 提交增加节流目标，默认控制在不高于 20 commits/sec。
- 对 auto-scroll 使用同一节流窗口，避免每个 delta 都触发滚动。

#### 2. Move Markdown Work Off The View Path
**Files**:
- `Sources/CodeToolCore/Views/Shared/ClaudeMarkdownView.swift`
- 如有必要，新增 `Sources/CodeToolCore/Views/Shared/MarkdownRenderModel.swift`

**Changes**:
- 按 spec 已确认方向，优先引入更稳定的预计算 render model，而不是只做 parse cache。
- 至少把 Document 解析与 attributed inline 生成从直接 view init 路径中移开。
- 允许阶段性先做消息级缓存，但最终边界要能支持增量更新和跨消息复用。

#### 3. Defer Attachment Thumbnail Decode
**Files**:
- `Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift`
- 视需要新增 `Sources/CodeToolCore/Views/Shared/ClaudeAttachmentThumbnailView.swift`

**Changes**:
- 把 attachmentChip 里的同步 `NSImage(contentsOf:)` 读盘与解码移出 body 路径。
- 为历史附件缩略图提供异步加载与缓存边界，优先显示文件名占位。

#### 4. Respect Visibility During Streaming
**File**: `Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift`

**Changes**:
- 隐藏期间显著削弱无意义的 UI 提交、滚动与动画更新。
- 需要保证恢复可见时内容一致，不丢失最终消息结果。

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [x] `make test`
- [x] Debug 日志显示 streaming UI commit 频率已被批处理控制

#### Manual Verification
- [ ] 长对话下中文输入法组合输入不出现明显候选中断或卡顿。
- [ ] 流式响应期间滚动仍正确，但不再每个 delta 抖动。
- [ ] 历史消息中的图片附件缩略图不再因为同步读盘导致明显卡顿。
- [ ] 切走 Claude Chat 后，隐藏页面不再持续产生高频 UI 提交。

---

## Phase 3: Media Tick Containment And Lyrics Model Stabilization

### Overview

治理 AISpeechView 与 AIMusicView 的常驻 playback tick，并将歌词行模型从 view body 中抽离，避免隐藏页面继续 100ms 刷新和可见页面重复构建。

### Changes Required

#### 1. Gate Playback Tick By Visibility
**Files**:
- `Sources/CodeToolCore/Views/AITools/AISpeechView.swift`
- `Sources/CodeToolCore/Views/AITools/AIMusicView.swift`

**Changes**:
- 将常驻 `Timer.publish(every: 0.1, ...)` 改为仅在页面可见且确实需要 UI 刷新时生效。
- 隐藏期间允许底层播放状态继续存在，但页面层 currentTime 与相关绑定不再频繁写入。
- 增加 tick 观测事件，区分 visible 与 hidden 场景。

#### 2. Extract Lyrics Line Model
**File**: `Sources/CodeToolUI/ScrollingLyricsView.swift`

**Changes**:
- 将 `lines` 从计算属性改为更稳定的输入模型或缓存模型。
- 避免每次 currentTime 或 hover 变化都重新对全文做 split 和映射。

#### 3. Keep Playback UX Correct Under Gating
**Files**:
- `Sources/CodeToolCore/Views/AITools/AISpeechView.swift`
- `Sources/CodeToolCore/Views/AITools/AIMusicView.swift`

**Changes**:
- 确保重新可见时 currentTime、播放状态、seek 和 stop 仍正确。
- Speech 的 stream/playbackController 回调继续保持功能正确，但不推动整页无意义刷新。

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [x] `make test`
- [x] Debug 日志能区分可见与隐藏状态下的 tick 数量

#### Manual Verification
- [ ] Speech 和 Music 页面可见时播放控制仍然正确。
- [ ] 切走页面后，不再观察到隐藏页持续刷新 UI。
- [ ] 歌词滚动和高亮逻辑保持正确，且长文本下滚动更平稳。

---

## Phase 4: History Drawer And AI Image Progressive Restore

### Overview

把 History 与 restore 路径从“整包准备完再显示”改为“首屏优先、其余渐进”，优先保证抽屉首屏和图像首个可见预览时间。

### Changes Required

#### 1. Add Summary-first History Loading
**Files**:
- `Sources/CodeToolCore/Persistence/HistoryStore.swift`
- `Sources/CodeToolCore/Persistence/HistoryDrawer.swift`
- 如有必要，新增 `Sources/CodeToolCore/Persistence/HistoryIndex.swift`

**Changes**:
- 第一阶段先把 HistoryDrawer 所需的首屏摘要与完整 payload 解耦。
- 采用固定 page size 的分页或摘要索引读取，至少满足 20 条首屏快速可见。
- 保留旧 JSON 数据兼容，不要求一次性完成完整磁盘索引化，但接口要向第二阶段索引演进留口。

#### 2. Make AIImage Restore Progressive
**File**: `Sources/CodeToolCore/Views/AITools/AIImageView.swift`

**Changes**:
- restore 先恢复 prompt、参数与首个可见参考图或输出图。
- 其余图片资源继续后台补齐，不再等待全部图像解码完成后一次性回填。
- 对缺失资源保持现有非阻塞 warning 语义。

#### 3. Measure Drawer And Restore Milestones
**Files**:
- `Sources/CodeToolCore/Persistence/HistoryDrawer.swift`
- `Sources/CodeToolCore/Views/AITools/AIImageView.swift`

**Changes**:
- 记录 drawer open 首屏耗时、restore first preview 耗时、restore full completion 耗时。

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [x] `make test`
- [x] Debug 日志包含 drawer 首屏和 image restore 首预览两个关键里程碑

#### Manual Verification
- [ ] 大量历史记录下，HistoryDrawer 首屏摘要在 400ms 目标内可见。
- [ ] AIImage restore 在 600ms 目标内出现首个可见预览，剩余资源随后补齐。
- [ ] 资源缺失时仍能恢复文本与参数，不会卡死或崩溃。

---

## Phase 5: Legacy Cleanup And Unified Render Policy

### Overview

在低风险优化完成并验证后，收口错误主路径与统一策略边界，避免性能问题继续围绕 legacy 页面和分散页面逻辑反复出现。

### Changes Required

#### 1. Remove Legacy AIChatView UI Surface
**Files**:
- `Sources/CodeToolCore/Views/AITools/AIChatView.swift`
- 任何仍引用该页面的测试、文档或注释位置

**Changes**:
- 删除旧 AIChatView 文件与其直接引用。
- 清理当前文档、spec、research 中把 AIChatView 写成活动主路径的误导性描述；历史性文档可保留背景，但要明确标注 legacy。
- 不在本阶段强制删除 AIExecutionSession、MiniMaxChatExecutionProvider、ChatHistoryExecutionSink 等 execution 抽象，除非完整引用分析后确认其不再服务任何当前或既定后续计划。

#### 2. Formalize Render/Update Policy
**Files**:
- `Sources/CodeToolCore/Views/Shared/ToolVisibility.swift`
- `Sources/CodeToolCore/Views/ContentView.swift`
- 必要时新增策略注册表文件

**Changes**:
- 固化页面分类：keepAliveOnHide、pauseOnHide、unloadOnHide。
- 把 Claude Chat、Speech、Music、Image、History 等典型页面归类，形成统一策略而不是页面各写一套判断。
- 只有在前四个阶段完成后仍未达标时，才对个别页面启用 unloadOnHide 试点。

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [x] `make test`
- [x] 搜索代码确认不存在旧 AIChatView 活动路由或 UI 引用

#### Manual Verification
- [ ] 产品中的 AI Chat 只剩 ClaudeChatView 一条主路径。
- [ ] 页面可见性策略有统一定义，不再依赖零散页面级 patch。
- [ ] 若未启用 unloadOnHide，当前缓存保活与状态保留语义保持不变。

---

## Testing Strategy

### Automated Verification

- `swift build`
- `make test`
- 如需要针对性回归，可在完整 Xcode toolchain 下补充筛选执行：
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AIExecutionSessionTests`
  - 针对新增性能 helper 或 history/index helper 的定向测试

### Manual Verification

1. 使用代表性长 Claude Chat 负载验证输入、streaming、thinking、tool card、图片附件和自动滚动。
2. 使用 300 到 500 条历史记录验证 HistoryDrawer 首屏、滚动、恢复与删除。
3. 在 AI Image 页面验证 4 张参考图和 4 张输出图同时存在的生成与恢复路径。
4. 在 AI Speech 和 AI Music 页面持续播放 3 到 5 分钟，验证隐藏页不再持续触发可观察 UI 提交。
5. 重复切换多个重型工具页，确认状态保留不丢失、切回时首个可交互帧接近平衡档目标。

## Performance Considerations

- 观测埋点必须保持 debug-only、轻量、可关闭，避免把 DiagnosticsStore 的 eager 读取路径引入实时热点。
- Markdown render model 优先走消息级稳定缓存和后台预计算，不在 body 中重复创建 Document(parsing:)。
- 对隐藏页面优先使用 pauseOnHide，而不是直接 destroy view tree；只有证据充分时才考虑卸载。
- AIImage restore 与 HistoryDrawer 应优先解决首屏和首个可见预览，再解决全量补齐时间。

## Migration Notes

- 现有历史 JSON 与附件目录结构必须保持兼容。
- 旧 AIChatView 删除后，历史性文档可以保留，但需要标注其为 legacy/archived path，避免后续计划继续误判当前主路径。
- 若后续决定进一步删除 execution-session 抽象，应单独立项并验证不会与既有 refactor-ai-execution-session 规划冲突。

## References

- Original requirements: `thoughts/shared/specs/2026-04-06-frontend-rendering-performance.md`
- Related code: `Sources/CodeToolCore/Views/ContentView.swift#L36-L90`
- Related code: `Sources/CodeToolCore/Views/Shared/ToolVisibility.swift#L4-L23`
- Related code: `Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift#L13-L31`
- Related code: `Sources/CodeToolCore/Views/Shared/ClaudeMarkdownView.swift#L174-L185`
- Related code: `Sources/CodeToolCore/Views/AITools/AIImageView.swift#L1070-L1153`
- Related code: `Sources/CodeToolCore/Views/AITools/AIImageView.swift#L1280-L1343`
- Related code: `Sources/CodeToolCore/Views/AITools/AISpeechView.swift#L333-L363`
- Related code: `Sources/CodeToolCore/Views/AITools/AIMusicView.swift#L267-L300`
- Related code: `Sources/CodeToolCore/Persistence/HistoryStore.swift#L681-L869`
- Related code: `Sources/CodeToolCore/Observability/AppLogger.swift#L181-L279`
- Related code: `Sources/CodeToolCore/Observability/Diagnostics.swift#L74-L141`
- Similar implementation: `thoughts/shared/plans/2026-04-05-timestamp-converter-rendering-performance.md`
- Related plan: `thoughts/shared/plans/2026-04-03-claude-cli-chat-ux-optimization.md`
- Related plan: `thoughts/shared/plans/2026-04-03-ai-image-reference-workbench.md`
- Related spec: `thoughts/shared/specs/2026-04-02-observability-issue-tracking.md`