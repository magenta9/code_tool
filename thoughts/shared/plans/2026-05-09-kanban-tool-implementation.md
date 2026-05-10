# Kanban Tool Implementation Plan

> 状态：Draft v0.1
> 日期：2026-05-09
> 输入：`thoughts/shared/prd/2026-05-09-kanban-tool.md` + `thoughts/shared/specs/kanban-prototype.html`

## Goal

在 CodeTool 中新增本地 Kanban 工具：多看板、自定义列、List/Kanban 双视图、富文本详情、归档、标签、JSON 导入导出。首版保持本地 SQLite 持久化，不引入外部服务。

最新 UI 决策以原型为准：默认 **Kaneo light**，提供 **Kaneo dark**，整体低边框、黑白灰主导、少量状态色点缀；Tegon compact / TaskTrove soft 只作为设计探索参考，不作为默认实现目标。

## Non-Goals

- 不做子任务、评论、附件、提醒、自然语言日期解析。
- 不做 GitHub Issues / Linear / 外部 API 同步。
- 不新增 `productivity` category，首版继续挂在 `devTools`。
- 不把 renderer 直接连 SQLite，所有写入留在 main 进程。

## Dependencies

新增依赖建议：

- `packages/renderer`: `@dnd-kit/core`, `@dnd-kit/sortable`, `@dnd-kit/utilities`
- `packages/renderer`: `@tiptap/react`, `@tiptap/starter-kit`

依赖安装后必须更新 `pnpm-lock.yaml`，并跑 `pnpm build` 作为最小验证。

## Phase 0: Align Specs Before Coding

目标：把实现基准固定下来，避免 PRD 与原型分叉。

改动：

- 更新 `thoughts/shared/prd/2026-05-09-kanban-tool.md` 的 UI 风格段落：默认 Kaneo light，支持 Kaneo dark。
- 保留 `thoughts/shared/specs/kanban-prototype.html` 作为视觉参考，不把静态原型直接搬进 production 代码。

验证：

- 人工检查 PRD 与原型描述一致。

## Phase 1: Shared Types and Tool Registration

目标：先建立跨进程契约的类型基础，不碰数据库和 UI。

改动：

- 新增 `packages/shared/src/types/kanban.ts`
  - `KanbanBoard`
  - `KanbanColumn`
  - `KanbanCard`
  - `KanbanLabel`
  - `KanbanPriority`
  - `KanbanRichTextDocument`
  - `KanbanBoardExport`
  - patch/input 类型，如 `CreateKanbanCardInput`, `UpdateKanbanCardPatch`
- 更新 `packages/shared/src/types/tools.ts`
  - `ToolId` 增加 `kanban`
- 更新 `packages/shared/src/tool-catalog.ts`
  - id: `kanban`
  - title: `Kanban`
  - category: `devTools`
  - icon: `KanbanSquare` 或 `Trello`（以 lucide 实际可用为准）
  - routePath: `/tools/kanban`
- 更新 `packages/shared/src/index.ts` 重导出 Kanban 类型。
- 更新 `packages/shared/src/tool-catalog.test.ts`。

验证：

- `pnpm --filter @codetool/shared typecheck`
- `pnpm --filter @codetool/shared test`（如果该 package 有测试命令；否则跑根 `pnpm test` 的 shared 相关用例）

## Phase 2: SQLite Schema and Repository

目标：完成数据层，让业务能力先可测试。

改动：

- 更新 `packages/main/src/db/schema.ts`
  - 新增 `kanban_boards`
  - 新增 `kanban_columns`
  - 新增 `kanban_cards`
  - 新增 `kanban_labels`
  - 新增 `kanban_card_labels`
  - 开启/确认 `PRAGMA foreign_keys = ON`
- 新增 `packages/main/src/db/repositories/kanban-repository.ts`
  - board CRUD
  - default columns 初始化
  - column CRUD + reorder + archive/restore
  - card CRUD + reorder + archive/restore
  - label CRUD + set card labels
  - export/import board
- 新增 fractional indexing helper：
  - `orderBetween(before?: number, after?: number): number`
  - `normalizeColumnOrder(boardId)`
  - `normalizeCardOrder(boardId, columnId)`
- 归档列规则：包含未归档卡片时拒绝归档，返回明确错误。

测试：

- 新增 `packages/main/src/db/repositories/kanban-repository.test.ts`
- 覆盖：
  - 创建 board 自动生成 4 个默认列。
  - 自定义列创建、重命名、重排。
  - card 跨列/列内 reorder。
  - card archive/restore。
  - 删除 board 级联 columns/cards/labels。
  - export/import 后列、卡片、标签、排序、归档状态一致。

验证：

- `pnpm --filter @codetool/main typecheck`
- `pnpm test -- packages/main/src/db/repositories/kanban-repository.test.ts`（如 Vitest 支持路径过滤）

## Phase 3: IPC Contract and Preload API

目标：把数据层安全暴露给 renderer，保持 main 进程边界。

改动：

- 更新 `packages/shared/src/ipc-channels.ts`
  - 增加 `kanban.*` channels。
- 更新 `packages/shared/src/ipc-contract.ts`
  - 增加 `kanban` contract。
- 新增 `packages/main/src/ipc/kanban.ts`
  - 使用 `KanbanRepository` 实现 handler。
  - 统一输入校验和错误消息。
- 更新 `packages/main/src/ipc/register.ts`
  - 注册 Kanban handlers。
- 更新 `packages/preload/src/api.ts`
  - 暴露 `window.codetool.kanban.*`。
- 更新 renderer API 类型声明：
  - `packages/renderer/src/global.d.ts`
  - `packages/renderer/src/api.ts`（如需要）

测试：

- 更新 `packages/shared/src/ipc-contract.test.ts`，确保 channels 与 contract 对齐。
- 给 `kanban.ts` handler 加轻量单测（可 mock repository）。

验证：

- `pnpm typecheck`
- `pnpm test`

## Phase 4: Renderer Skeleton

目标：让新工具可进入、可加载真实 board/card 数据，但先不做复杂交互。

改动：

- 新增目录 `packages/renderer/src/tools/kanban/`
  - `kanban.tsx`
  - `use-kanban-store.ts`
  - `kanban-types.ts`（renderer-only view model，如需要）
  - `kanban-theme.ts` 或 CSS class tokens（如需要）
- 更新 `packages/renderer/src/App.tsx`
  - 路由 `/tools/kanban`
- 更新 `packages/renderer/src/components/workbench.tsx`
  - lucide icon 映射增加 Kanban 图标。
- 初始 UI：
  - board sidebar
  - topbar
  - view toggle
  - empty state
  - create board

实现原则：

- 先复用现有 `ToolLayout`, `Panel`, `PrimaryButton`, `SecondaryButton` 等组件。
- 如果现有组件过于深色或边框感太强，只在 Kanban 工具内加局部 class，不要全局改主题。

测试：

- 更新 `packages/renderer/src/App.test.tsx`
  - 能渲染 Kanban 页面。
  - 无 board 时显示 create board empty state。

验证：

- `pnpm --filter @codetool/renderer typecheck`
- `pnpm test -- packages/renderer/src/App.test.tsx`

## Phase 5: Board and Column Management

目标：实现多看板与自定义列能力。

改动：

- board switcher：list/create/rename/delete。
- column header menu：rename/archive。
- add column action。
- column reorder：先用按钮或简单 move 操作，Phase 9 再接 dnd-kit 拖拽。
- archived column 展示策略：默认隐藏，可在管理菜单里查看/恢复。

测试：

- hook/store 单测：board/column optimistic update 与失败回滚。
- renderer 组件测试：新建列、重命名列、归档空列。

验证：

- `pnpm typecheck`
- `pnpm test`

## Phase 6: Card CRUD, Details Sidebar, and Archive

目标：实现卡片核心生命周期，不做拖拽和富文本高级体验。

改动：

- 创建卡片：默认进入当前列或第一列。
- 卡片详情右侧栏：
  - 默认关闭。
  - 点击卡片打开。
  - column/priority/dueDate/labels/title 编辑。
  - archive/restore/delete 操作。
- archived cards view：列表 + restore + permanent delete。
- 搜索：基于 title + `description_text` 的前端过滤；后续再做 repository 查询优化。

测试：

- 创建卡片后刷新数据仍存在。
- 归档卡片默认列表不可见，归档入口可见。
- 恢复后回到原列。

验证：

- `pnpm typecheck`
- `pnpm test`

## Phase 7: Rich Text Editor

目标：引入 tiptap，但把存储和搜索边界做清楚。

改动：

- 安装 `@tiptap/react`, `@tiptap/starter-kit`。
- 新增 `CardRichTextEditor`。
- 保存：
  - `description_json`: tiptap JSON string。
  - `description_text`: 从 editor state 生成纯文本。
- 加基础工具条：Bold / Italic / Heading / Bullet / Code。
- import/export 中保留 `description_json` 和 `description_text`。

测试：

- 富文本编辑后关闭再打开格式保留。
- 搜索能命中纯文本。
- 空文档和非法 JSON 有安全 fallback。

验证：

- `pnpm build`
- `pnpm test`

## Phase 8: List View

目标：实现 Kaneo/Linear 风的密集列表视图。

改动：

- 按 column 分组。
- 行展示：column dot、title、priority、labels、dueDate、row menu。
- 分组折叠/展开。
- 行点击打开详情侧栏。
- List 视图下移动 column：首版可通过 row menu 的 `Move to...` 完成；dnd 作为增强项放 Phase 9。

测试：

- 切换 List/Kanban 后选中 board、搜索条件、详情侧栏状态合理保留。
- 分组折叠状态在当前页面生命周期内保留。

验证：

- `pnpm typecheck`
- `pnpm test`

## Phase 9: Kanban View and Drag-and-Drop

目标：接入 dnd-kit，实现卡片与列拖拽。

改动：

- 安装 `@dnd-kit/core`, `@dnd-kit/sortable`, `@dnd-kit/utilities`。
- Kanban columns：横向滚动、列头、列菜单、空列提示。
- Card sortable：列内重排。
- Cross-column drop：更新 `columnId` + `sortOrder`。
- Column sortable：列重排。
- optimistic update + IPC 失败回滚。
- 键盘可访问拖拽作为后续增强；首版至少保证按钮/菜单可完成同等移动操作。

测试：

- reorder helper 单测已在 Phase 2 覆盖。
- renderer 测试覆盖 optimistic reorder 成功/失败。
- 手工验收：跨列拖拽、列内拖拽、列拖拽。

验证：

- `pnpm typecheck`
- `pnpm test`
- 手动运行 dev UI 检查交互。

## Phase 10: Import/Export and Labels

目标：完成可备份、可恢复的首版闭环。

改动：

- label create/delete/set card labels。
- board export：生成 JSON 文件或文本 blob。
- board import：校验 payload，生成新 id，恢复 columns/cards/labels/card-labels。
- 冲突策略：import 总是创建新 board，不覆盖现有 board。

测试：

- export/import roundtrip。
- import 非法 JSON 返回清晰错误。
- label 删除后 card-label join 表清理。

验证：

- `pnpm typecheck`
- `pnpm test`

## Phase 11: Visual Polish and Theme Modes

目标：把静态原型的视觉落进 production UI。

改动：

- 默认 Kaneo light。
- 支持 Kaneo dark（建议先跟随 app/theme 或页面内 toggle；不要强塞全局设置）。
- 低边框、少阴影、黑白灰主导，状态色只用于标签、优先级和 column dot。
- 详情侧栏是贴右侧的 TaskTrove/Kaneo 式 side panel，不做浮动 modal 卡片。
- 移动端：工具栏换行，Kanban 横向滚动，详情侧栏占满屏宽。

验证：

- Playwright 或手工检查：desktop 1440x900、mobile 390x844。
- 无文本溢出。
- 无控制台错误。

## Phase 12: Documentation and Final Verification

目标：确保新工具作为正式内置工具收尾完整。

改动：

- 更新 `README.md` Features。
- 如 tool catalog 测试有固定数量，更新期望值。
- 检查 `packages/shared/src/tool-catalog.ts`, `packages/renderer/src/App.tsx`, `packages/renderer/src/components/workbench.tsx` 对齐。

最终验证：

- `pnpm build`（项目要求的最低 CLI 验证）
- `pnpm typecheck`
- `pnpm test`

报告规则：

- 只有 `pnpm test` 成功后才能说测试通过。
- 如果某一步失败，保留失败输出并说明剩余风险。

## Suggested Commit Slices

1. `feat(kanban): add shared types and tool catalog entry`
2. `feat(kanban): add sqlite repository and ordering tests`
3. `feat(kanban): expose ipc and preload api`
4. `feat(kanban): add renderer shell and board management`
5. `feat(kanban): add card details and archive flow`
6. `feat(kanban): add rich text descriptions`
7. `feat(kanban): add list view`
8. `feat(kanban): add dnd kanban board`
9. `feat(kanban): add labels and import export`
10. `test(kanban): cover integration flows and docs`

## Open Risks

- `tiptap` 和 `dnd-kit` 会增加 renderer bundle；实现后需要看构建产物是否明显膨胀。
- 当前 PRD 的 UI 段落仍带有早期 Tegon/TaskTrove 文案，Phase 0 必须先更新。
- List 视图拖拽与 Kanban 视图拖拽共享排序模型，若一次性实现会复杂；建议先用菜单移动，再接 dnd。
- 自定义列归档策略必须严格，避免用户以为数据丢失。
