# Timestamp Converter Rendering Performance Implementation Plan

## Overview

修复 Timestamp Converter 在长时间未访问后再次点击出现加载卡顿的问题，重点优化两类根因：

1. 工具页被 ContentView 长期缓存后仍持续执行每秒刷新。
2. Timestamp 页面及其历史抽屉在渲染热路径里重复创建 formatter、重复计算派生值，并且状态胶囊身份不稳定。

本计划采用已确认的主路径：保留现有工具缓存与切页状态保留能力，但让 Timestamp Converter 仅在可见时刷新，同时压低页面本身的高频渲染成本。

## Current State Analysis

### Key Discoveries

- `Sources/CodeToolCore/Views/ContentView.swift:81-87` 与 `Sources/CodeToolCore/Views/ContentView.swift:95-105`
  - `retainedToolIDs` 采用只增不减的缓存策略，访问过的工具会一直保留在缓存列表中。
- `Sources/CodeToolCore/Views/ContentView.swift:484-498`
  - `ToolDetailCacheView` 使用 `ZStack + opacity + allowsHitTesting` 切换工具页，可见性变化不会销毁已访问页面。
- `Sources/CodeToolCore/Views/DevTools/TimestampConverterView.swift:12-45`
  - TimestampConverterView 在根视图持有每秒一次的主线程 `Timer.publish`，并通过 `.onReceive` 写入 `currentTimestamp`。
- `Sources/CodeToolCore/Views/DevTools/TimestampConverterView.swift:33-38`
  - `TimestampToDateSection` 目前接收 `currentTimestamp` 只是为了 `Now` 按钮，但因此会跟随每秒 tick 一起重渲染。
- `Sources/CodeToolCore/Views/DevTools/TimestampConverterView.swift:294-308`
  - `formatISO8601`、`formatDate`、`formatRelative` 每次调用都会新建 formatter。
- `Sources/CodeToolUI/ToolWorkbench.swift:3-19`
  - `ToolStatusItem` 的 `id` 固定使用新生成的 `UUID()`，导致像 Timestamp 这种每秒变化的 status item 很难被稳定复用。
- `Sources/CodeToolCore/Persistence/HistoryDrawer.swift:201-246` 与 `Sources/CodeToolCore/Persistence/HistoryDrawer.swift:336-340`
  - HistoryDrawer 在列表渲染路径中会重复调用 `relativeTimeString`，而该函数每次都会新建 `RelativeDateTimeFormatter`。
- `Tests/CodeToolTests/CodeToolTests.swift:678-706`
  - 当前已有 `ToolViewCache` 的纯函数测试，可以作为共享缓存行为不被破坏的回归入口。

### Architectural Constraints

- 工具身份与路由已经稳定收敛到 `ToolID` 和 `ToolDestinationRegistry`，不应为单个性能问题引入新的字符串路由或特殊入口分支。
- 现有设计依赖工具视图被缓存后保留本地工作态；本次优化不应默认让 Timestamp 页面切走即丢失 `timestampInput`、`selectedDate`、`showHistory` 等本地状态。
- Timestamp 历史回放契约已经存在，`selectedDateISO8601` 与 `inputValue` 必须继续保持精确恢复能力，不允许为了性能把恢复数据退化成展示摘要。

## Scope

### In Scope

- 为 Timestamp Converter 引入“仅可见时刷新”的生命周期边界。
- 降低 Timestamp 页面渲染热路径中的重复计算与 formatter 分配。
- 稳定 Timestamp 头部状态胶囊的 identity，避免每秒全量重建 status chips。
- 顺手清理 HistoryDrawer 在相对时间格式化上的低成本热点，避免历史面板成为次要放大器。
- 为上述改动补充最小必要的回归测试与手工验证步骤。

### Out of Scope

- 为所有工具引入通用缓存淘汰策略、LRU 或容量上限。
- 重写 `ToolDestinationRegistry` 或调整工具目录/路由体系。
- 新建独立的性能监控中心、Timeline UI 或大范围 observability 改造。
- 修改 Timestamp 历史记录模型、删除历史功能，或以牺牲回放精度换性能。
- 优化除 Timestamp / HistoryDrawer 之外其他工具的持续刷新问题。

## Implementation Approach

采用“两层治理”的方式解决问题：

1. 先缩小 Timestamp 页面自身的热区，让 live clock 的每秒变化不再牵连整个转换结果区和状态条。
2. 再通过共享可见性边界让 Timestamp 页面在隐藏时停止刷新，但仍保留本地交互状态。

这样做的原因是：

- 只做局部微优化，隐藏页面仍会长期驻留刷新，问题只能缓解，不能从根因上解决。
- 只做可见性暂停而不做热路径清理，页面在可见时仍然存在不必要的 formatter 和 item identity 开销。
- 保留全局缓存比“Timestamp 工具不缓存”更符合当前产品的交互预期，风险也更低。

## Phase 1: Timestamp Hot Path Cleanup

### Overview

把 Timestamp 页面里与每秒 tick 无关的工作从刷新链路中剥离，减少可见状态下的无谓重渲染和对象分配。

### Changes Required

#### 1. Stabilize Tool Status Identity
**Files**:
- `Sources/CodeToolUI/ToolWorkbench.swift`
- `Sources/CodeToolCore/Views/DevTools/TimestampConverterView.swift`

**Changes**:
- 将 `ToolStatusItem` 改为支持显式稳定 `id`，避免只能使用每次新建的 `UUID()`。
- 保持现有调用点兼容：大多数工具可以继续使用默认值；Timestamp Converter 明确传入稳定键，例如 `current-time` 与 `time-zone`。
- 不修改 ToolWorkbench 的布局和显示样式，只修正 diff 身份模型。

**Reasoning**:
- 当前 Timestamp header 的时间 chip 每秒变化一次，但 item 身份也跟着变化，SwiftUI 很难复用同一个胶囊节点。

#### 2. Remove Unnecessary Tick Dependency From Conversion Sections
**File**: `Sources/CodeToolCore/Views/DevTools/TimestampConverterView.swift`

**Changes**:
- `TimestampToDateSection` 不再接收 `currentTimestamp`。
- `Now` 按钮改为点击时直接取当前时间，而不是依赖父视图每秒下发 live timestamp。
- 保留 `CurrentTimeSection` 作为唯一需要跟随 live tick 更新的主要内容区。
- `DateToTimestampSection` 继续只依赖 `selectedDate`。

**Reasoning**:
- 现在只要 live clock 更新，`TimestampToDateSection` 也会重新评估 `parseTimestamp(timestampInput)` 和多组格式化输出；这条依赖链没有必要。

#### 3. Reuse Formatters In Timestamp View
**File**: `Sources/CodeToolCore/Views/DevTools/TimestampConverterView.swift`

**Changes**:
- 引入 file-private、主线程使用的 formatter cache，例如 `TimestampFormatterCache`。
- 统一复用以下 formatter：
  - ISO 8601 formatter
  - 当前时区 full date formatter
  - UTC full date formatter
  - relative date formatter
- `saveTimestampHistory`、`restoreTimestamp`、`CurrentTimeSection`、转换结果行统一走同一组格式化帮助函数。

**Reasoning**:
- 当前 formatter 创建都发生在渲染 helper 内部，是低收益但高频的分配热点。

#### 4. Trim HistoryDrawer Relative Time Overhead
**File**: `Sources/CodeToolCore/Persistence/HistoryDrawer.swift`

**Changes**:
- 将 `relativeTimeString` 使用的 `RelativeDateTimeFormatter` 提升为共享静态实例。
- 保持现有 HistoryDrawer 行为和文案不变，不在本阶段调整列表结构或动画。

**Reasoning**:
- 历史抽屉不是首要根因，但它是 Timestamp 页面里最直接的次级放大器，且改动低风险。

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [x] `make test`（若当前机器具备完整 Xcode/XCTest；若环境不满足，明确记录为环境限制）

#### Manual Verification
- [ ] Timestamp 页在可见状态下，输入已有有效 timestamp 时，静置 10 秒不会因为 live clock 导致结果区明显闪动或重排。
- [ ] Current Time 区块仍然每秒更新一次。
- [ ] `Now` 按钮仍能填入当前 Unix 时间。
- [ ] HistoryDrawer 的相对时间显示保持正确，打开与滚动没有新增异常卡顿。

---

## Phase 2: Visibility-Aware Live Refresh

### Overview

让 Timestamp Converter 在被缓存保活时仍保留草稿状态，但隐藏期间停止 live tick，从根因上消除长期后台刷新。

### Changes Required

#### 1. Add Shared Tool Visibility Context
**Files**:
- `Sources/CodeToolCore/Views/Shared/ToolVisibility.swift`（新文件）
- `Sources/CodeToolCore/Views/ContentView.swift`

**Changes**:
- 新增一个共享 environment value，例如 `isToolVisible`。
- 在 `ToolDetailCacheView` 渲染每个缓存工具时，根据 `selectedTool` 将可见性状态注入对应页面。
- 保持 `ToolDestinationRegistry` 的无参工厂接口不变，避免把本次性能需求扩散成路由层签名调整。

**Reasoning**:
- 仓库当前没有现成的工具可见性抽象；environment 注入是最小改动、最符合现有架构边界的做法。

#### 2. Replace Root Timer Publisher With Visibility-Scoped Refresh
**File**: `Sources/CodeToolCore/Views/DevTools/TimestampConverterView.swift`

**Changes**:
- 移除根视图常驻的 `Timer.publish(...).autoconnect()` + `.onReceive` 组合。
- 改成基于 `isToolVisible` 的可取消刷新任务，例如 `.task(id: isToolVisible)` 或等价的可见性绑定机制：
  - 进入可见状态时立刻刷新一次 `currentTimestamp`
  - 仅在可见期间按 1 秒节奏更新
  - 隐藏后自动停止，不再继续驱动状态写入

**Reasoning**:
- 这一步才是修复“长时间切走后再点回来卡顿”的根因。只要隐藏页不再被定时写状态，缓存本身就不再持续放大成本。

#### 3. Preserve Existing Working State Semantics
**File**: `Sources/CodeToolCore/Views/DevTools/TimestampConverterView.swift`

**Changes**:
- 明确保持以下状态在切页后继续保留：
  - `timestampInput`
  - `selectedDate`
  - `showHistory`
  - `timestampHistory`
- 不引入“切走即重置”的行为变化。

**Reasoning**:
- 本次方案的价值就在于同时保住当前交互语义和性能收益；否则直接禁用缓存会更简单，但不符合已选路径。

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [x] `make test`（若当前机器具备完整 Xcode/XCTest；若环境不满足，明确记录为环境限制）
- [x] `Tests/CodeToolTests/CodeToolTests.swift` 中现有 `ToolViewCache` 相关测试继续通过

#### Manual Verification
- [ ] 打开 Timestamp Converter，输入一个有效 timestamp，然后切到其他工具并停留至少 2 分钟，再切回时没有明显加载卡顿。
- [ ] 切走再切回后，`timestampInput` 和 `selectedDate` 仍保留原值。
- [ ] 切回后 current time status chip 会立即刷新到当前时间，而不是停留在旧值。
- [ ] Timestamp 页隐藏期间不会继续造成可感知的后台刷新负担。

---

## Phase 3: Regression Coverage And Lightweight Diagnostics

### Overview

补上能为这次优化兜底的自动化与手工验证，确保后续不会因为工具缓存或状态胶囊实现回退到旧问题。

### Changes Required

#### 1. Add Focused Regression Tests Where Pure Boundaries Exist
**Files**:
- `Tests/CodeToolTests/CodeToolTests.swift`
- 如有必要，少量配套辅助类型所在文件

**Changes**:
- 为 `ToolStatusItem` 的稳定身份支持补最小单元测试。
- 如果 Phase 2 抽出纯粹的可见性辅助逻辑或可测试 helper，为其补纯函数测试。
- 不为 SwiftUI 视图结构本身引入沉重 snapshot 测试。

**Reasoning**:
- 当前渲染问题的核心在身份和生命周期边界，优先测试这些稳定、可纯函数化的接口。

#### 2. Use Existing Diagnostics Surfaces For Manual Confirmation
**Files**:
- `Sources/CodeToolCore/Views/ContentView.swift`
- `Sources/CodeToolCore/Observability/DiagnosticsView.swift`

**Changes**:
- 本阶段默认不新增用户可见的 observability 功能。
- 若实现过程中定位仍不够清晰，可在 debug-only 范围内增加极轻量的 timing/signpost，边界限定在：
  - Timestamp 页面进入可见状态
  - HistoryDrawer 打开与历史列表加载
- 不把 Timestamp dev tool history 接入 diagnostics referenceID 聚合链路。

**Reasoning**:
- 现有 observability spec 明确要求观测本身不能成为新的主线程负担；本任务以修复性能为主，不扩大诊断系统范围。

### Success Criteria

#### Automated Verification
- [x] `swift build`
- [x] `make test`（若当前机器具备完整 Xcode/XCTest；若环境不满足，明确记录为环境限制）
- [x] 新增的纯函数级测试通过，且不破坏现有 cache/history/diagnostics 相关测试

#### Manual Verification
- [ ] 使用预览或运行态进入 Timestamp 页，重复切换 10 次以上，没有明显越来越慢的趋势。
- [ ] 历史抽屉的打开、删除、清空、恢复流程仍然正常。
- [ ] Timestamp 页与 ContentView 的既有行为一致，没有引入新的路由、缓存或状态丢失问题。
- [ ] 若增加 debug-only timing/signpost，可用 Instruments 或诊断视图确认“隐藏期间无持续 tick 写状态”。

---

## Testing Strategy

### Unit Tests

- `ToolStatusItem` 显式稳定 identity 的构造与回归测试。
- 如 Phase 2 抽出可测试的可见性 helper，则补一组纯函数测试，覆盖：
  - 可见 -> 隐藏时停止刷新
  - 隐藏 -> 可见时立即补一帧
  - 不影响现有 `ToolViewCache` 的缓存保留语义

### Manual Testing Steps

1. 启动应用，进入 Timestamp Converter，记录首次打开状态。
2. 输入一个合法的秒级或毫秒级 timestamp，确认结果正常显示。
3. 保持 Timestamp 页可见并静置，确认只有 Current Time 区块持续更新，结果区没有无意义抖动。
4. 切换到其他工具并停留至少 2 分钟，再切回 Timestamp 页，确认没有明显卡顿，且输入状态仍在。
5. 打开 HistoryDrawer，执行恢复、删除、清空操作，确认没有功能回退。
6. 重复在 Timestamp、JSON Tool、JWT Tool 之间切换，确认缓存行为与用户感知保持稳定。

### CLI Verification

- 最低要求：`swift build`
- 完整验证：`make test`
- 若 `make test` 或等效 Xcode toolchain 测试无法执行，必须在实施结果里明确说明是环境限制，而不是跳过不报。

## Performance Considerations

- `DateFormatter` 与 `RelativeDateTimeFormatter` 不是线程安全类型；本计划中的共享 formatter 仅用于主线程/SwiftUI 渲染路径，不把它们扩散到跨 actor 并发使用。
- 优化目标是减少隐藏页面的持续状态写入与可见页面的重复计算，不追求把 Timestamp 转换逻辑抽成新的跨模块服务。
- 只对 Timestamp 及 HistoryDrawer 做定点优化，避免因为一次性能修复触碰所有 ToolWorkbench 使用方。
- 如果后续发现其他工具也有类似“缓存保活 + 持续刷新”问题，再单独立项做通用缓存策略改造，而不是在本任务中顺手扩大范围。

## Migration Notes

- 无数据迁移。
- 不修改 TimestampHistoryRecord 结构，不新增持久化字段。
- 不改变工具目录、ToolID、路由 slug 或 HistoryStore 目录结构。

## References

- `Sources/CodeToolCore/Views/ContentView.swift`
- `Sources/CodeToolCore/Views/DevTools/TimestampConverterView.swift`
- `Sources/CodeToolCore/Persistence/HistoryDrawer.swift`
- `Sources/CodeToolUI/ToolWorkbench.swift`
- `Tests/CodeToolTests/CodeToolTests.swift`
- `thoughts/shared/plans/2026-03-31-tool-history-ui.md`
- `thoughts/shared/plans/refactor-tool-catalog-routing.md`
- `thoughts/shared/specs/2026-04-02-observability-issue-tracking.md`