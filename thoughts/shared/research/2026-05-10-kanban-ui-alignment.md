# Kanban UI 风格对齐分析

> 日期：2026-05-10  
> 范围：`Kanban` 工具、通用工具页、Settings / Diagnostics、Workbench 侧边栏  
> 结论：当前不一致主要来自两套 UI 语言并存。Kanban 已经形成一套更紧凑、更产品化的局部设计系统；其他页面仍以早期 `ToolLayout + Panel + PrimaryButton / SecondaryButton` 为主，更像表单型工作台页面。后续如果“向 kanban 靠齐”，建议把 Kanban 的设计语言沉淀成新的通用组件，而不是把 `.kanban-*` class 直接扩散到所有页面。

## 1. 参考代码位置

- Kanban 页面：`packages/renderer/src/tools/kanban/kanban.tsx`
- Kanban 样式：`packages/renderer/src/styles/index.css` 中 `.kanban-*`
- 通用布局与按钮：`packages/renderer/src/components/tool-layout.tsx`
- Workbench 侧边栏：`packages/renderer/src/components/workbench.tsx`
- Settings 页面：`packages/renderer/src/routes/settings.tsx`
- Diagnostics 页面：`packages/renderer/src/routes/diagnostics.tsx`
- 典型工具页：`packages/renderer/src/tools/json-tool/json-tool.tsx`、`packages/renderer/src/tools/image-converter/image-converter.tsx`

## 2. 总体差异

| 维度 | Kanban 当前风格 | 其他页面当前风格 | 差异判断 |
|---|---|---|---|
| 页面模型 | 完整应用式界面，内部有二级侧栏、顶栏、画布、抽屉、弹窗 | 文档/表单式工具页，标题 + 描述 + Panel 卡片 | Kanban 更像一个真实产品工具；其他页面更像工具集合里的表单页 |
| 布局密度 | 高密度，12-14px padding、32-34px 控件、信息分层细 | 中密度，Panel `p-4`、按钮 36px、输入框 40px、标题 26px | 其他页面显得更松、更“设置页” |
| 色彩 | 独立暖灰色板，主色已回到暖灰棕 `#756858` | 全局暖米灰 + 棕灰 accent `#756858` | 色相已经收敛，后续重点是统一控件和层级 |
| 边框 | 低对比 `rgba(25,25,22,0.1)`，强边框仅 hover/focus 使用 | 全局 `--app-border` / `--app-border-strong`，Panel 边框更显眼 | Kanban 层次更细，其他页面边界更“卡片化” |
| 圆角 | 大多 6-8px，外层 10px | 大多 8px，Pill 使用 full rounded | 基本接近，但其他页面 pill 更明显 |
| 阴影 | 外层容器和浮层有阴影，卡片本身较克制 | Panel、首页卡片、列表项普遍带阴影 | 其他页面阴影使用更平均，Kanban 只在层级变化时强调 |
| 字体层级 | 控件 12px/650，正文 13px，标题 20-22px | 页面标题 26px，描述 14px，按钮 13px | Kanban 更工具化，其他页面标题感更重 |
| 交互反馈 | hover、focus、active、dragging、over、view enter 动画齐全 | 通用 hover / active 为主，局部状态少 | Kanban 的状态反馈更完整 |

## 3. 按钮风格差异

### 3.1 Kanban 按钮

Kanban 的按钮集中定义在 `.kanban-command`、`.kanban-icon-button`、`.kanban-danger-button`、`.kanban-add-column`、卡片操作、详情侧栏操作等选择器中。核心特征：

- 高度偏小：`min-height: 32px`，列头和卡片内 icon button 是 24px 或 30px。
- 字号偏小：12px，字重 650。
- 圆角克制：7px，icon button 多为 6px。
- 背景很轻：默认 `rgba(25,25,22,0.035)`，hover 到 `rgba(25,25,22,0.06)`。
- 主按钮不是实心色，而是 soft tint：`var(--kanban-primary-soft)` + `var(--kanban-primary)`。
- 危险操作主要改文字/icon 色，不大面积铺红。
- active 统一 `scale(0.98)`。
- icon 使用更充分，很多操作在窄空间下只保留 icon。

这种按钮语言的感觉是：低噪音、紧凑、状态清楚，适合长时间操作的生产力工具。

### 3.2 其他页面按钮

通用 `PrimaryButton` / `SecondaryButton` 的核心特征：

- 高度 36px，比 Kanban 大一档。
- 字号 13px，padding `px-4`，按钮存在感更强。
- 圆角 8px。
- Primary 使用全局 `--app-accent-soft`，文字为 `--app-accent`，色相偏棕灰。
- Secondary 使用白底 panel + hover panel strong。
- 通用按钮没有默认 icon 规范，很多按钮是纯文字。

这种按钮语言更适合表单提交和简单工具操作，但放在 Kanban 旁边会显得更松、更像设置页。

### 3.3 对齐建议

建议新增一组通用 compact action 组件，而不是直接复用现有大按钮：

- `ActionButton`：默认 32px 高、12px、650 字重、7px 圆角。
- `ActionButton variant="primary"`：soft tint，不做实心色。
- `ActionButton variant="danger"`：红色文字/icon + 轻边框，不做红底。
- `IconButton`：24/30/32 三档尺寸，默认透明背景，hover 才显边框和背景。
- `SegmentedControl`：复用 Kanban 的 thumb 动画和 30px 高按钮。

`PrimaryButton` / `SecondaryButton` 可以保留给真正的表单主操作，但工具页顶部、Panel actions、Settings 中的重复操作应逐步切到 `ActionButton`。

## 4. 页面结构差异

### 4.1 Kanban 是“工具内应用”

Kanban 自己包含：

- 左侧 boards 二级导航。
- 顶部 per-board toolbar。
- 搜索框。
- segmented view switch。
- 横向滚动画布。
- 列、卡片、列表、归档视图。
- 右侧详情抽屉。
- 局部 modal dialog。

它的 UI 不依赖 `ToolLayout` 的大标题和描述，因此第一屏更像真实工作空间。

### 4.2 其他页面是“表单卡片集合”

Settings、Diagnostics、JSON Tool、Image Converter 等页面主要遵循：

- 外层 `ToolLayout`，最大宽度 1180px。
- 顶部大标题 + 描述。
- 内容用 `Panel` 分块。
- Panel 标题使用大写小字 + accent dot。
- 操作按钮挂在 Panel header 或 ToolLayout actions 上。

这个结构清晰，但和 Kanban 的紧凑产品感不一致。尤其是 Settings 里的 “Kanban data” 使用通用 Panel，看起来不像 Kanban 生态的一部分。

### 4.3 对齐建议

建议把页面分为两类：

| 页面类型 | 建议结构 |
|---|---|
| 工作流型工具，如 Kanban、未来 agent 工作台、复杂 AI 任务页 | 使用 app-shell：局部侧栏 / 顶栏 / 主画布 / 详情侧栏 |
| 单输入单输出型工具，如 JSON、JWT、Timestamp | 使用 compact tool-shell：保留 Panel，但弱化大标题、降低按钮高度、减少阴影 |
| 设置与诊断 | 使用 settings-shell：保留表单语义，但按钮、输入框、section header 向 Kanban 的紧凑风格靠齐 |

不要强行让所有页面都有 Kanban 的二级侧栏，但要统一控件语言和层级语法。

## 5. 侧边栏差异

### 5.1 Workbench 侧边栏

Workbench 侧边栏当前特点：

- 宽度 276px，比 Kanban 内部 boards 侧栏 238px 宽。
- nav item 高度 48/56px，带 icon 方块和两行文字。
- active 状态是左边 2px accent border + soft background。
- 搜索框高度 40px，圆角 8px。
- 页面顶部还有 `Workspace` 胶囊标签。

它是“应用总导航”，信息更完整，但视觉权重也更高。

### 5.2 Kanban 内部侧栏

Kanban boards 侧栏特点：

- 宽度 238px。
- 背景 `kanban-surface-soft`。
- board item 是 8px/9px padding 的紧凑行。
- active/hover 用整块轻背景和边框，不使用左侧 accent 线。
- 顶部 brand 简洁，`New board` 使用 compact action。

它是“当前工具内导航”，比 Workbench 更安静。

### 5.3 对齐建议

Workbench 不应该完全变成 Kanban 内部侧栏，因为二者层级不同。但可以对齐以下细节：

- 搜索框高度从 40px 降到 34-36px。
- nav item 的 icon 方块弱化，active 状态减少棕色 accent 面积。
- hover 背景使用更接近 Kanban 的 `rgba(25,25,22,0.05)`。
- sidebar 背景从 `--app-sidebar` 向 `--kanban-surface-soft` 靠近，统一暖灰感。
- 页面顶部 `Workspace` 胶囊可弱化或移除，避免和工具内 toolbar 争抢层级。

## 6. 输入框、选择器和搜索差异

Kanban 输入控件：

- 搜索高度 34px，icon + input 内联。
- 卡片 composer input 高 32px。
- 详情选择器是自定义 select trigger，高 38px，有 dropdown menu。
- focus ring 使用主色 soft tint：`0 0 0 3px var(--kanban-primary-soft)`。

通用输入控件：

- `TextInput` / `SelectField` 高 40px。
- `TextArea` 默认很大，适合文本工具。
- focus ring 是黑灰 `rgba(36,36,36,0.06)`，缺少品牌色反馈。
- 原生 select 与 Kanban 自定义 select 视觉差异明显。

对齐建议：

- 新增 `CompactInput` / `CompactSelect`，用于 Settings 和工具页参数区。
- 通用 focus ring 改成 soft accent tint，和 Kanban 的 primary-soft 统一。
- 搜索控件抽成 `SearchField`，Workbench 和 Kanban 共用。
- Settings 的 Kanban import/export select 优先使用 compact select，减少和 Kanban 本体割裂。

## 7. Panel、卡片和信息层级差异

Kanban 的卡片层级更像真实业务对象：

- column 是 soft surface。
- card 是 white surface。
- card hover 只增强 border，不默认大阴影。
- footer 用细边框分隔 metadata。
- label / priority 是小 chip，20px 左右。

其他页面的 Panel 更像容器：

- 每个 Panel 都有边框、白底、padding、阴影。
- Panel header 有 accent dot + 大写标题。
- 首页工具卡、Diagnostics event 也使用类似阴影卡片。

对齐建议：

- 降低通用 `Panel` 阴影，改为默认无阴影或极轻阴影。
- Panel header 的 accent dot 可仅用于状态型 section，普通 section 改为 Kanban 式小标题。
- 工具页的结果区、日志区可以借鉴 Kanban list row：用 border-top 行分隔，减少卡片套卡片。
- 首页工具卡的 hover 可以改为 Kanban card hover：只变 border/background，不明显 scale。

## 8. 色板对齐

现在有两套核心色板：

- 全局：`--app-accent: #756858`，偏棕灰。
- Kanban：`--kanban-primary: #756858`，偏暖灰棕。

如果产品方向以 Kanban 为准，建议将全局 token 向 Kanban 收敛：

| Token | 建议 |
|---|---|
| `--app-bg` | 可保留 `#fafaf8`，与 Kanban 背景接近 |
| `--app-bg-muted` / `--app-sidebar` | 向 `#f1f1ee` 靠近 |
| `--app-accent` | 保持或映射到暖灰棕 `#756858` |
| `--app-accent-soft` | 保持或映射到 `rgba(117,104,88,0.12)` |
| `--app-border` | 与 Kanban `rgba(25,25,22,0.1)` 合并 |
| `--app-text-muted` | 向 `#686861` 靠近 |

不建议继续扩大棕灰 accent 的使用，否则其他页面会持续和 Kanban 分叉。

## 9. 迁移优先级

### P0：先统一 token 和基础控件

目标：最小改动让视觉不再明显割裂。

- 抽出全局 compact action button。
- 抽出 icon button。
- 抽出 segmented control。
- 抽出 search field。
- 将全局 primary soft 色调整到 Kanban primary 体系。
- Settings 的按钮和 select/input 先迁移，因为它直接包含 Kanban data。

### P1：收敛通用工具页

目标：JSON、JWT、Image、Timestamp 等页面看起来像同一个工具系统。

- ToolLayout 标题从 26px 降低到 22-24px，描述减少首屏权重。
- Panel 阴影降级。
- Panel actions 改用 compact action。
- 表单区和结果区使用更细的 border、较小控件高度。

### P2：调整 Workbench 侧边栏

目标：总导航保持清晰，但不压过工具内容。

- 搜索框降高。
- nav active 状态减少棕色左线的存在感。
- icon container 从固定强视觉方块改为更轻的 hover/active 背景。
- 顶部 `Workspace` 胶囊弱化。

### P3：抽象“应用式工具壳”

目标：后续复杂工具可以复用 Kanban 的结构能力。

- `ToolAppShell`：支持 internal sidebar、topbar、canvas、right drawer。
- `ToolToolbar`：标题、搜索、segmented、actions。
- `ToolDrawer`：右侧详情栏。
- `ToolDialog`：替代 Kanban 私有 dialog 样式。

## 10. 具体落地清单

1. 在 `components/tool-layout.tsx` 或新文件 `components/ui.tsx` 增加：
   - `ActionButton`
   - `IconButton`
   - `SegmentedControl`
   - `SearchField`
   - `CompactInput`
   - `CompactSelect`
2. 把 Kanban 里的按钮尺寸、hover、active、focus 规则提炼为通用 token，不直接引用 `.kanban-*`。
3. Settings 页面先迁移：
   - `Save key`、`Clear`、`Export selected board`、`Import board` 改用 compact action。
   - `SelectField` 改 compact。
   - `Kanban data` section 的标题和按钮语气靠近 Kanban。
4. JSON / Image / JWT 等工具页迁移 Panel actions。
5. Diagnostics event 从独立卡片改成 list rows。
6. Workbench 搜索与 nav active 状态调整。
7. 最后再考虑是否把 Kanban 私有 CSS 中可复用部分删除或替换成通用组件。

## 11. 风格判定标准

后续改 UI 时可以用这组标准判断是否已经向 Kanban 靠齐：

- 常规操作按钮高度是否在 32-34px，而不是默认 36-40px。
- 主操作是否使用 soft tint，而不是高饱和实心色。
- 危险操作是否以文字/icon 色为主，而不是红底。
- hover 是否只增强 border/background，不制造过多阴影。
- 页面是否减少“卡片套卡片”，更多使用 toolbar、row、section 分隔。
- 搜索、segmented、icon button 是否有统一组件。
- Settings 和工具页的控件看起来是否能自然放进 Kanban 顶栏或详情侧栏。

## 12. 一句话结论

Kanban 的方向更适合作为 CodeTool 下一版 UI 基准：低噪音、紧凑、状态完整、工具感强。其他页面要向它靠齐，核心不是复制看板布局，而是统一按钮、输入框、色板、边框、hover/focus 和信息密度。
