# Kanban UI Alignment Implementation Plan

> 状态：Draft v0.1  
> 日期：2026-05-10  
> 输入：`thoughts/shared/research/2026-05-10-kanban-ui-alignment.md` + 本轮确认决策  
> 目标：以 Kanban 当前 UI 语言为基准，分阶段统一 CodeTool 的按钮、控件、色板、Panel、ToolLayout、Workbench 与重点工具页风格。

## 1. Goal

把 Kanban 已经形成的低噪音、紧凑、状态清楚的 UI 语言沉淀为 renderer 共享组件和 design token，并逐步迁移其他页面。

这次对齐的重点是 **shared UI grammar**，不是强制所有工具使用同一种页面结构。不同工具仍然可以根据自身任务模型决定布局，但基础控件、交互反馈、色板、阴影、边框、信息密度要向同一套标准收敛。

## 2. Confirmed Decisions

- 不强制统一所有工具的布局结构。
- 不要求所有工具都有 Kanban 式二级侧栏、顶栏或右侧详情抽屉。
- 不为了适配布局而给轻工具硬加功能。
- 可以给工具补“真实有用”的辅助能力，但功能新增不能和本轮视觉迁移混在同一阶段。
- 先新增统一 token 和新按钮体系，再迁移旧页面。
- 新 token 要视觉上统一到 Kanban 风格，但落地时先用中性 `--ui-*` 承接，避免一次性硬改所有旧 `--app-*` 调用。
- `PrimaryButton` / `SecondaryButton` 不保留长期兼容 wrapper；迁移完成后删除旧组件。
- 按钮迁移一次性覆盖所有 `packages/renderer/src` 调用点。
- 工具操作按钮优先使用 lucide icon + 短文字；dialog footer、简单确认动作允许纯文字。
- 新按钮体系要有尺寸分级，但默认使用 compact。
- 危险按钮默认不使用红底，只用 danger 文字/icon 和轻边框；二次确认弹窗的最终破坏性动作可用更强的 danger soft 样式。
- Kanban 自己必须回迁共享基础控件，避免形成“Kanban 私有一套、其他页面仿一套”的第三种风格。
- 按钮迁移和 Kanban 基础控件回迁分成两个阶段。
- 每个阶段都要做截图验收，不能只跑 typecheck/test。
- 实施计划按可独立提交的小阶段拆分，每阶段明确文件范围和验收标准。

## 3. Non-Goals

- 不把 Kanban 的布局强制套到所有工具页。
- 不为了填充布局而给 JSON、JWT、Image Converter 等轻工具硬加侧栏、详情栏或多视图。
- 不把 `.kanban-*` 私有 class 直接复制到其他页面。
- 不在第一阶段重构 Kanban 的 column、card、details drawer 等业务布局。
- 不把视觉迁移和业务功能新增放在同一阶段。
- 不长期保留 `PrimaryButton` / `SecondaryButton` 两套旧 API。
- 不一次性重写所有 `--app-*` token；先通过新 `--ui-*` token 收敛新组件。
- 不只靠测试通过来判断 UI 对齐完成，截图验收是硬要求。

## 4. Design Direction

### 4.1 Shared UI Grammar

后续页面不必长得像 Kanban，但这些基础规则要统一：

- 常规工具按钮默认 32px 高，12px 字号，650 字重，7px 左右圆角。
- 主操作使用 soft tint，不使用高饱和实心色。
- 危险操作默认只强调文字/icon，不大面积铺红。
- hover 主要增强 border/background，不制造额外重阴影。
- focus ring 使用统一 primary soft tint。
- icon button 默认透明或低背景，hover 才显示边框和 surface。
- 搜索、分段控件、输入框、选择器、dialog 控件使用共享组件。
- Panel 和卡片默认降低阴影，让层级来自 surface、border、section 和 row，而不是到处投影。

### 4.2 Layout Policy

工具布局由工具自身任务模型决定：

| 工具类型 | 布局原则 |
|---|---|
| 工作流型工具，如 Kanban、Pi Agent | 可以使用 app-shell、内部导航、详情栏、任务流 |
| 单输入单输出工具，如 JSON、JWT、Timestamp | 保持轻量，不强行增加侧栏；通过控件语言和 Panel 收敛保持一致 |
| AI workflow 工具，如 AI Chat、AI Image、AI Music | 可以保留 prompt / execution / artifact 三段式，但按钮、状态、Panel、任务卡片要收敛 |
| Settings / Diagnostics | 保持设置和日志语义，但用 compact controls、row/list、低阴影 section 靠齐 |
| Home / Workbench | 保持总导航职责，但降低侧边栏、卡片和胶囊标签的视觉噪音 |

## 5. Target Components

新增或重构共享 UI 组件，建议放在 `packages/renderer/src/components/ui.tsx`，或者拆分为 `components/ui/`。如果保持文件少，第一阶段可先放在 `tool-layout.tsx`，后续再拆。

### 5.1 Token

在 `packages/renderer/src/styles/index.css` 中新增中性 token：

- `--ui-primary`
- `--ui-primary-soft`
- `--ui-primary-soft-strong`
- `--ui-danger`
- `--ui-danger-soft`
- `--ui-bg`
- `--ui-surface`
- `--ui-surface-soft`
- `--ui-surface-quiet`
- `--ui-border`
- `--ui-border-strong`
- `--ui-text`
- `--ui-text-muted`
- `--ui-text-faint`
- `--ui-focus-ring`

初始取值应接近 Kanban：

- primary: `#756858`
- primary soft: `rgba(117, 104, 88, 0.12)`
- primary soft strong: `rgba(117, 104, 88, 0.22)`
- border: `rgba(25, 25, 22, 0.1)`
- border strong: `rgba(25, 25, 22, 0.18)`
- text muted: `#686861`
- surface soft: `#f1f1ee`

### 5.2 Button Components

新按钮体系：

- `ActionButton`
  - `variant="neutral" | "primary" | "danger" | "dangerStrong"`
  - `size="sm" | "md"`
  - 默认 `variant="neutral"`、`size="sm"`
  - 工具操作优先传 icon
- `IconButton`
  - `variant="neutral" | "primary" | "danger"`
  - `size="icon-sm" | "icon-md"`
  - 必须有 `aria-label`
- `ButtonGroup` 或轻量 wrapper，可选

尺寸建议：

| size | 用途 | 高度 |
|---|---|---|
| `sm` | 常规工具操作 | 32px |
| `md` | 空状态主操作、较重要表单提交 | 34-36px |
| `icon-sm` | 卡片、列表、列头小操作 | 24px |
| `icon-md` | toolbar、dialog header | 30-32px |

危险操作规则：

- toolbar/list/details 中的危险动作使用 `variant="danger"`。
- 二次确认弹窗中的最终删除动作使用 `variant="dangerStrong"`。
- 禁止普通危险按钮使用高饱和红底。

### 5.3 Input and Control Components

后续阶段抽出：

- `SearchField`
- `SegmentedControl`
- `CompactInput`
- `CompactSelect`
- `CompactTextArea` 或调整现有 `TextArea`
- `Dialog`
- `SectionPanel`
- `ListRow`

第一阶段只要求按钮和 token；其余按阶段推进。

## 6. Phase Plan

### Phase 1: Tokens and Button System

目标：建立新 token 与新按钮 API，并一次性替换旧 `PrimaryButton` / `SecondaryButton`。

文件范围：

- `packages/renderer/src/styles/index.css`
- `packages/renderer/src/components/tool-layout.tsx` 或新建 `packages/renderer/src/components/ui.tsx`
- 所有使用 `PrimaryButton` / `SecondaryButton` 的 renderer 文件

主要改动：

- 新增 `--ui-*` token。
- 新增 `ActionButton` 和 `IconButton`。
- 一次性替换 `PrimaryButton` / `SecondaryButton` 调用。
- 给主要工具操作补 lucide icon。
- 删除 `PrimaryButton` / `SecondaryButton` 组件导出。
- 更新所有 import。

硬性验收：

- `rg "PrimaryButton|SecondaryButton" packages/renderer/src` 无结果。
- 旧按钮组件已从源码中删除。
- 所有工具操作按钮尺寸、圆角、hover、active 基本一致。
- 工具操作优先 icon + 短文字；纯文字仅保留在合理表单语义处。

验证：

- `pnpm --filter @codetool/renderer typecheck`
- `pnpm test` 或至少跑受影响 renderer 测试

截图验收：

- Kanban
- Settings
- JSON Tool
- AI Chat 或 Pi Agent
- Workbench 侧边栏

检查点：

- 按钮高度是否明显统一。
- primary 是否是 soft tint。
- danger 是否没有普通红底。
- icon 与文字间距是否统一。
- disabled / hover / active 是否可见但不吵。

### Phase 2: Kanban Basic Controls Back-Migration

目标：让 Kanban 自己使用共享基础控件，验证新组件真的能承载 Kanban 风格。

文件范围：

- `packages/renderer/src/tools/kanban/kanban.tsx`
- `packages/renderer/src/styles/index.css`
- 共享 UI 组件文件

主要改动：

- 用 `ActionButton` 替换 `.kanban-command` 用途。
- 用 `IconButton` 替换 `.kanban-icon-button`、列头小按钮、卡片 action 小按钮中适合回迁的部分。
- 抽 `SearchField` 并替换 `.kanban-search`。
- 抽 `SegmentedControl` 并替换 `.kanban-segmented`。
- 抽 `CompactInput` / `CompactSelect` 的首版，如果能清晰替换 Kanban detail metadata 控件则替换；复杂 custom select 可保留到 Phase 3。
- 清理不再使用的 `.kanban-command`、`.kanban-icon-button`、`.kanban-search`、`.kanban-segmented` 样式。

暂不改：

- `.kanban-column`
- `.kanban-card`
- `.kanban-details`
- drag preview / dnd 布局
- rich text editor 业务结构

硬性验收：

- Kanban 基础按钮、搜索、segmented 不再依赖对应私有 `.kanban-*` 控件样式。
- Kanban 视觉不能明显退化，仍然保持当前紧凑感。
- shared controls 放回 Kanban 后不需要大量 one-off class 才能工作。

验证：

- `pnpm --filter @codetool/renderer typecheck`
- Kanban 相关测试，如有

截图验收：

- Kanban board view
- Kanban list view
- Kanban archive view
- Card details drawer
- Text/confirm dialog

检查点：

- 顶栏按钮、搜索、segmented 和 Phase 1 其他页面按钮是否一致。
- card/column 业务布局是否未被误伤。
- hover/focus/active 是否仍清楚。

### Phase 3: Settings and Simple Tool Pages

目标：迁移 Settings 与单输入单输出类工具，让它们保留轻量任务模型，但视觉语言靠齐。

文件范围：

- `packages/renderer/src/routes/settings.tsx`
- `packages/renderer/src/tools/json-tool/json-tool.tsx`
- `packages/renderer/src/tools/jwt-tool/jwt-tool.tsx`
- `packages/renderer/src/tools/json-diff/json-diff.tsx`
- `packages/renderer/src/tools/timestamp-converter/timestamp-converter.tsx`
- `packages/renderer/src/tools/image-converter/image-converter.tsx`
- `packages/renderer/src/tools/word-cloud/word-cloud.tsx`
- 共享 input/select/search/control 组件

主要改动：

- Settings 的 input/select/button 使用 compact 控件。
- Settings 的 `Kanban data` 不再看起来像普通旧 Panel，控件密度向 Kanban 靠近。
- 普通工具页 Panel actions 使用 `ActionButton`。
- 输入区和结果区 focus ring 统一到 `--ui-focus-ring`。
- 不为了布局添加侧栏或详情栏。
- 只在确实有价值时记录 future enhancement，例如 JSON snippets/history/schema validation，但不在本阶段实现。

硬性验收：

- 轻工具仍然轻，不因 UI 对齐增加无意义结构。
- Settings 与 Kanban data 的视觉割裂明显减少。
- 输入框、选择器、按钮的高度和 focus 样式与共享组件一致。

验证：

- `pnpm --filter @codetool/renderer typecheck`
- 相关工具页测试，如有

截图验收：

- Settings
- JSON Tool
- JWT Tool
- Image Converter
- Timestamp Converter

### Phase 4: Panel, ToolLayout, and Section Density

目标：降低旧工作台卡片感，统一 Panel 和 ToolLayout 的信息密度。

文件范围：

- `packages/renderer/src/components/tool-layout.tsx`
- 使用 `Panel`、`StatusStrip`、`PillTag`、`CodeBlock` 的页面
- `packages/renderer/src/components/ai-task-chrome.tsx`

主要改动：

- `ToolLayout` 标题从强页面标题向工具标题收敛，减少首屏重量。
- `Panel` 默认降低阴影，必要时用 border/surface 区分层级。
- Panel header 的 accent dot 只在有状态含义时保留；普通 section header 采用更轻样式。
- `StatusStrip` 使用 `--ui-*` token。
- 结果列表、日志列表优先使用 row/list，而不是多层卡片。

硬性验收：

- 没有明显“卡片套卡片”的旧视觉。
- Panel 在简单工具、AI workflow 和 Settings 中都不显得过重。
- 视觉层级仍然清楚，不能因为去阴影而变成一整片平面。

验证：

- `pnpm --filter @codetool/renderer typecheck`

截图验收：

- JSON Tool input/result
- AI Chat workflow/artifact
- Pi Agent config/session
- Diagnostics recent events

### Phase 5: Workbench, Home, and AI Workflow Refinement

目标：处理第一印象和复杂工具页，让全局框架不再和 Kanban 风格冲突。

文件范围：

- `packages/renderer/src/components/workbench.tsx`
- `packages/renderer/src/routes/home.tsx`
- `packages/renderer/src/components/ai-task-chrome.tsx`
- AI 工具页：
  - `ai-chat`
  - `ai-image`
  - `ai-music`
  - `ai-speech`
  - `pi-agent`

主要改动：

- Workbench 搜索框改用共享 `SearchField` 或同源样式。
- nav active 状态减少棕色左线权重，靠近 Kanban 的低噪音 active/hover。
- icon container 弱化，避免每个 nav item 都像强卡片。
- Home 工具卡降低阴影和 active scale，使用更克制 hover。
- AI task chrome 的任务卡、artifact、workflow step 使用统一 surface/border/row 语言。

硬性验收：

- Workbench 不需要长得像 Kanban 内部 boards 侧栏，但视觉权重不能压过工具内容。
- Home 第一屏不再比 Kanban 更“营销卡片化”。
- AI workflow 页保留自身任务结构，但按钮、卡片、状态条与新体系一致。

验证：

- `pnpm --filter @codetool/renderer typecheck`

截图验收：

- Home
- Workbench sidebar with active Kanban
- AI Chat
- AI Image 或 AI Music
- Pi Agent

### Phase 6: Cleanup and Legacy CSS Removal

目标：清理过渡期遗留，确保没有第三套 UI 语言残留。

文件范围：

- `packages/renderer/src/styles/index.css`
- 共享 UI 组件文件
- 所有 renderer 页面

主要改动：

- 删除不再使用的 `.kanban-*` 基础控件样式。
- 删除旧按钮和旧控件残留。
- 检查是否仍有大量 hard-coded Tailwind arbitrary colors 与新 token 冲突。
- 检查是否还有旧棕灰 accent 被误用在新组件路径中。
- 视情况让部分 `--app-*` token 指向 `--ui-*` token，但只在确认不会造成大面积非预期变化后做。

硬性验收：

- `rg "PrimaryButton|SecondaryButton" packages/renderer/src` 无结果。
- `rg "kanban-command|kanban-icon-button|kanban-search|kanban-segmented" packages/renderer/src` 无业务使用；如果 CSS 中仍存在，必须有明确原因。
- 新组件不依赖 Kanban 私有 class。
- 页面截图通过最终 review。

验证：

- `pnpm typecheck`
- `pnpm test`
- 如有本地 dev server，使用浏览器逐页截图验收。

## 7. Screenshot QA Matrix

每个阶段至少覆盖以下页面，阶段特定截图可追加：

| 页面 | 重点检查 |
|---|---|
| Kanban board view | 顶栏、按钮、搜索、segmented、列和卡片未退化 |
| Kanban details drawer | 保存/归档/删除按钮、select/input、focus |
| Settings | 表单按钮、Kanban data、select/input、Panel |
| JSON Tool | 简单工具页是否仍轻量，按钮和 textarea 是否统一 |
| AI Chat 或 Pi Agent | workflow 工具是否没有旧卡片感 |
| Workbench sidebar | 搜索框、nav active、icon container、整体权重 |
| Home | 工具卡阴影、hover、标签、标题权重 |
| Diagnostics | 日志列表是否少卡片化、可扫描 |

每张截图检查：

- 按钮高度和圆角是否统一。
- primary/danger 是否符合 soft tint 规则。
- icon 使用是否一致，不拥挤。
- hover/focus/active 是否有反馈。
- Panel / card 阴影是否克制。
- 是否出现新旧 accent 色混用。
- 文本是否溢出或拥挤。

## 8. Risk and Mitigation

| 风险 | 影响 | 缓解 |
|---|---|---|
| 一次性按钮迁移影响面大 | 多页面 import 和 JSX 改动容易遗漏 | 阶段 1 用 `rg` 做硬验收，删除旧组件迫使编译失败暴露遗漏 |
| 新组件无法承载 Kanban 复杂场景 | 其他页面看似统一，Kanban 仍私有 | Phase 2 强制 Kanban 基础控件回迁 |
| 全局 token 改动造成不可控视觉变化 | 很多页面同时变色 | 先新增 `--ui-*`，不直接改旧 `--app-*` |
| Panel 降阴影后层级变弱 | 页面变平、可读性下降 | Phase 4 单独做，截图检查 surface/border/section 是否足够 |
| 为了统一把轻工具做重 | 工具效率下降 | Non-goals 明确禁止为布局硬加功能 |
| AI workflow 页被简单工具规则误伤 | 复杂任务状态不清晰 | Phase 5 单独处理 AI workflow |

## 9. Implementation Order Summary

1. Phase 1：新增 `--ui-*` token + 新 button system；一次性迁移旧按钮并删除。
2. Phase 2：Kanban 基础控件回迁共享组件；暂不改业务布局。
3. Phase 3：Settings 和简单工具页迁移 compact controls。
4. Phase 4：Panel / ToolLayout / section density 收敛。
5. Phase 5：Workbench / Home / AI workflow 细化。
6. Phase 6：清理 legacy CSS，最终截图验收。

## 10. Definition of Done

- Renderer 中不存在 `PrimaryButton` / `SecondaryButton` 源码使用。
- Kanban 的基础控件使用共享组件，不再靠私有控件 CSS 定义按钮、搜索、segmented。
- Settings、普通工具页、AI workflow 页、Workbench、Home 都通过截图验收。
- 新增共享组件 API 清晰，后续新页面默认使用新 button/control 体系。
- 视觉上不再有“Kanban 一套、其他工具一套”的明显割裂。
- 不引入无意义功能，不强制统一布局结构。
