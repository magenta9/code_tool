# Kanban 工具 PRD

> 状态：Draft v0.2
> 日期：2026-05-09
> 关联工作台：CodeTool（Electron + React + SQLite）

## 1. 背景与目标

CodeTool 当前以"开发者效率 + 多模态 AI"为主，缺少一个轻量、本地、可自管的"任务/想法看板"工具。用户在调试、写作、研究 AI 任务时，需要一个能：

- 快速记录任务和想法；
- 跨多个项目独立管理；
- 同一份数据能在 List（Linear 风）和 Kanban（看板）两种视图之间切换；
- 完全本地持久化、无外部服务依赖、随 CodeTool 一起启动。

参考：[Tegon](https://github.com/RedPlanetHQ/tegon)（List + Kanban 双视图、Linear 风布局）+ [TaskTrove](https://github.com/dohsimpson/TaskTrove)（柔和卡片）+ [Kaneo](https://github.com/usekaneo/kaneo)（dnd-kit 实践）。

## 2. 范围

### 2.1 In Scope（首版 MVP）

- 多看板（项目）管理：新建 / 重命名 / 删除 / 切换。
- 同一看板下两种视图：**List 视图**（Linear 风）与 **Kanban 视图**（看板列）。
- 列（Column）：首版支持自定义列名、列排序、列归档；新看板默认创建 `Backlog / Todo / In Progress / Done`。
- 卡片字段：`title`、`description (Rich Text JSON)`、`columnId`、`priority (none/low/medium/high/urgent)`、`labels[]`、`dueDate`、`createdAt`、`updatedAt`、`order`、`archivedAt`。
- 拖拽：Kanban 视图下跨列与列内重排（`@dnd-kit`）；List 视图下跨 column 分组拖拽与重排。
- 卡片详情：右侧抽屉打开（不离开看板上下文）。
- 卡片描述：首版使用富文本编辑器（建议 `tiptap`），存储结构化 JSON；导出时同时可生成纯文本摘要。
- 卡片归档：支持归档/取消归档；默认视图隐藏已归档卡片，提供归档列表入口。
- 持久化：复用 `packages/main/src/db`（SQLite，better-sqlite3）。
- 全局快捷键：`N` 新建卡片、`/` 搜索、`Esc` 关闭抽屉。
- 数据导出/导入：JSON（per-board），便于备份。

### 2.2 Out of Scope（首版不做）

- 子任务 / 检查项。
- 评论与协作。
- 附件上传（与 `asset-store` 解耦，下个版本再评估）。
- 自定义字段。
- 第三方同步（GitHub Issues、Linear 等）。
- 自然语言日期解析。
- 提醒/通知。

## 3. UI 风格规范

最终视觉方向以 `thoughts/shared/specs/kanban-prototype.html` 的 Kaneo 风格为准：默认 **Kaneo light**，同时提供 **Kaneo dark**。Tegon/Linear 的信息密度和 TaskTrove/Notion 的卡片柔和感只作为辅助参考，不作为默认主题。

- **整体**：浅色模式使用温暖的 off-white 背景、黑白灰主导、低边框、低阴影；暗色模式使用温暖黑灰表面，避免高饱和深蓝/紫色。状态色只用于 priority、label、column dot 等功能信号。
- **List 视图**：单行密集排布（一行 = 一个 issue），左侧 column 状态点，中间 title，右侧 priority/labels/dueDate。同一 column 折叠为分组 section，可折叠/展开。
- **Kanban 视图**：水平滚动的列；列头显示列名 + 计数 + 列菜单；列本身可排序，列内卡片纵向排列、可拖拽。空列显示低干扰占位提示。
- **顶栏（per-board）**：左侧看板名 + 切换器，右侧 view toggle（List / Kanban）+ 搜索框 + "+ New"。
- **侧栏（工具内部）**：看板列表（不污染 workbench 全局侧栏；放在 `tool-layout` 内的二级导航位置）。
- **卡片详情侧栏**：贴右侧展开，宽度 `~520px`，不是浮动 modal；上半 title + column/priority 选择器，下半富文本描述编辑器。
- **归档入口**：顶栏更多菜单或看板侧栏底部提供 `Archived cards`，进入后以列表形式展示、恢复或永久删除已归档卡片。

## 4. 信息架构与数据模型

### 4.1 表结构（SQLite）

```sql
-- 看板
CREATE TABLE kanban_boards (
  id TEXT PRIMARY KEY,           -- ulid
  name TEXT NOT NULL,
  description TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  archived_at INTEGER            -- nullable, soft delete
);

-- 列
CREATE TABLE kanban_columns (
  id TEXT PRIMARY KEY,
  board_id TEXT NOT NULL REFERENCES kanban_boards(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  color TEXT,                    -- nullable, optional accent
  sort_order REAL NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  archived_at INTEGER            -- nullable, hidden from active board when set
);

CREATE INDEX idx_kanban_columns_board_order ON kanban_columns(board_id, archived_at, sort_order);

-- 卡片
CREATE TABLE kanban_cards (
  id TEXT PRIMARY KEY,           -- ulid
  board_id TEXT NOT NULL REFERENCES kanban_boards(id) ON DELETE CASCADE,
  column_id TEXT NOT NULL REFERENCES kanban_columns(id) ON DELETE RESTRICT,
  title TEXT NOT NULL,
  description_json TEXT,         -- rich text JSON, serialized
  description_text TEXT,         -- searchable plain text snapshot
  priority TEXT NOT NULL DEFAULT 'none', -- 'none' | 'low' | 'medium' | 'high' | 'urgent'
  due_date INTEGER,              -- epoch ms, nullable
  sort_order REAL NOT NULL,      -- 列内排序，使用浮点便于插入（fractional indexing）
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  archived_at INTEGER            -- nullable, archived cards are hidden by default
);

CREATE INDEX idx_kanban_cards_board_column ON kanban_cards(board_id, column_id, archived_at, sort_order);

-- 标签（多对多）
CREATE TABLE kanban_labels (
  id TEXT PRIMARY KEY,
  board_id TEXT NOT NULL REFERENCES kanban_boards(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  color TEXT NOT NULL            -- hex 或预设枚举名
);

CREATE TABLE kanban_card_labels (
  card_id TEXT NOT NULL REFERENCES kanban_cards(id) ON DELETE CASCADE,
  label_id TEXT NOT NULL REFERENCES kanban_labels(id) ON DELETE CASCADE,
  PRIMARY KEY (card_id, label_id)
);
```

`sort_order` 同时用于列排序和列内卡片排序，采用 fractional indexing：插入新卡片/新列到 A、B 之间时取 `(A.order + B.order) / 2`，避免大规模重排。定期（或同一分组数量超阈值）做一次 normalize。

归档列时不自动归档卡片；首版策略是禁止归档仍包含未归档卡片的列，提示用户先移动或归档卡片，避免隐藏数据。

### 4.2 共享类型（packages/shared）

新增 `packages/shared/src/types/kanban.ts`，导出 `KanbanBoard`、`KanbanColumn`、`KanbanCard`、`KanbanLabel`、`KanbanPriority`、`KanbanRichTextDocument`。在 `packages/shared/src/index.ts` 重导出。

## 5. 架构与模块拆分

遵循 `.github/copilot-instructions.md` 的边界：

| 层 | 改动 |
|---|---|
| `packages/shared` | `types/kanban.ts`；`tool-catalog.ts` 注册 `kanban` 工具；`ipc-channels.ts` + `ipc-contract.ts` 增加 kanban 通道。 |
| `packages/main/src/db` | 新增 `repositories/kanban-repository.ts`（boards/columns/cards/labels CRUD + reorder + archive）；schema migration。 |
| `packages/main/src/ipc` | 新增 `kanban.ts`，挂载到 `register.ts`。 |
| `packages/preload/src/api.ts` | 暴露 `window.codetool.kanban.*`。 |
| `packages/renderer/src/tools/kanban/` | 工具页：board switcher、view toggle、List 视图、Kanban 视图、card drawer、stores。 |
| `packages/renderer/src/App.tsx` | 加路由 `/tools/kanban`。 |
| `packages/renderer/src/components/workbench.tsx` | 加导航项（如有显式工具列表）。 |

### 5.1 IPC Contract（草案）

```ts
type KanbanApi = {
  listBoards(): Promise<KanbanBoard[]>;
  createBoard(input: { name: string; description?: string }): Promise<KanbanBoard>;
  renameBoard(input: { id: string; name: string }): Promise<KanbanBoard>;
  deleteBoard(input: { id: string }): Promise<void>;

  listColumns(input: { boardId: string; includeArchived?: boolean }): Promise<KanbanColumn[]>;
  createColumn(input: { boardId: string; name: string; color?: string }): Promise<KanbanColumn>;
  updateColumn(input: { id: string; patch: Partial<KanbanColumnPatch> }): Promise<KanbanColumn>;
  reorderColumn(input: { id: string; beforeId?: string; afterId?: string }): Promise<KanbanColumn>;
  archiveColumn(input: { id: string }): Promise<KanbanColumn>;
  restoreColumn(input: { id: string }): Promise<KanbanColumn>;

  listCards(input: { boardId: string; includeArchived?: boolean }): Promise<KanbanCard[]>;
  createCard(input: { boardId: string; columnId: string; title: string }): Promise<KanbanCard>;
  updateCard(input: { id: string; patch: Partial<KanbanCardPatch> }): Promise<KanbanCard>;
  deleteCard(input: { id: string }): Promise<void>;
  archiveCard(input: { id: string }): Promise<KanbanCard>;
  restoreCard(input: { id: string }): Promise<KanbanCard>;
  reorderCard(input: { id: string; toColumnId: string; beforeId?: string; afterId?: string }): Promise<KanbanCard>;

  listLabels(input: { boardId: string }): Promise<KanbanLabel[]>;
  createLabel(input: { boardId: string; name: string; color: string }): Promise<KanbanLabel>;
  deleteLabel(input: { id: string }): Promise<void>;
  setCardLabels(input: { cardId: string; labelIds: string[] }): Promise<void>;

  exportBoard(input: { boardId: string }): Promise<KanbanBoardExport>;   // 纯 JSON
  importBoard(input: { payload: KanbanBoardExport }): Promise<KanbanBoard>;
};
```

所有 IPC 走现有 `contract-binder` 模式，类型由 `packages/shared/src/ipc-contract.ts` 统一。

### 5.2 拖拽

- 使用 `@dnd-kit/core` + `@dnd-kit/sortable`。
- 新增 dependencies 仅放在 `packages/renderer`。
- 卡片拖拽完成后调 `reorderCard`，列拖拽完成后调 `reorderColumn`。
- 渲染层先做 optimistic update，IPC 失败再回滚。

### 5.3 富文本

- 首版建议使用 `@tiptap/react` + `@tiptap/starter-kit`，依赖仅放在 `packages/renderer`。
- renderer 保存 `description_json`，同时生成 `description_text` 传给 main，便于搜索与导出。
- 若后续不想引入 tiptap，可替换为 ProseMirror 轻量配置，但首版 PRD 以 tiptap 为验收目标。

## 6. 工具注册

在 `packages/shared/src/tool-catalog.ts` 增加：

```ts
{
  id: "kanban",
  title: "Kanban",
  description: "Plan tasks in List or Kanban view, with multi-board local storage.",
  category: "devTools",                // 暂归 devTools；如未来工具变多再考虑新建 'productivity'
  icon: "Trello",                       // lucide icon
  routePath: "/tools/kanban",
  capabilities: ["history"]            // 沿用现有 capability tag，不新增 'productivity'
}
```

> 决策：首版不新增 `productivity` category，也不新增 capability tag，避免连带改 workbench 分组逻辑；后续工具变多再切。

## 7. 验收标准

MVP 完成需满足以下用例全部通过：

1. 新建看板 → 默认创建 4 个列 → 添加 5 张卡片 → 关闭重启应用 → 数据完整保留。
2. 新建自定义列并重命名/重排 → 刷新后列名与列顺序保持正确。
3. 在 Kanban 视图下把"Todo"列卡片拖到"In Progress"列，刷新后 column_id 与 sort_order 正确。
4. 在 List 视图下拖动卡片改变 column，再切回 Kanban 视图，结果一致。
5. 归档卡片 → 默认视图不可见 → 归档列表可见 → 恢复后回到原列与排序位置附近。
6. 在卡片详情里编辑富文本描述 → 关闭再打开后格式保留，搜索可命中纯文本内容。
7. 删除看板 → 该看板下所有列、卡片与标签级联删除（外键 ON DELETE CASCADE 验证）。
8. 导出当前看板为 JSON，删除原看板，再导入 → 列、卡片、标签、排序、归档状态完全恢复。
9. `pnpm build` / `pnpm typecheck` / `pnpm test` 全部通过；新增 vitest 覆盖：repository CRUD、column/card reorder 算法、archive/restore、IPC 契约。

## 8. 非功能需求

- **性能**：单看板 ≤ 1000 张卡片时，初次渲染 < 200ms，拖拽帧率 ≥ 50fps。
- **数据安全**：所有写入仍在 main 进程；renderer 不直连 SQLite。
- **可观测**：复用 `app-logger`，记录 IPC error 与 reorder 异常。

## 9. 里程碑（不含时间预估）

1. **M1 数据层**：schema + repository + 单测。
2. **M2 IPC + preload**：通道、contract、preload 暴露、契约测试。
3. **M3 渲染层骨架**：路由、tool-catalog 注册、空白页面 + board switcher。
4. **M4 列管理**：列新建/重命名/重排/归档，默认列初始化。
5. **M5 List 视图**：基本展示 + 增删改 + 拖拽排序。
6. **M6 Kanban 视图**：列布局 + dnd-kit 列/卡片拖拽 + 卡片详情抽屉。
7. **M7 富文本 + 归档**：tiptap 描述编辑、description_text 生成、卡片归档/恢复。
8. **M8 标签 + 导入导出**：labels CRUD、JSON export/import。
9. **M9 收尾**：README 更新、capability/icon 调整、E2E 用例。

## 10. 待决问题（Open Questions）

- (Q1) 列是否首版就允许"自定义列名/排序"？决策：**支持**。
- (Q2) 是否新增 `productivity` category？决策：**不新增**，挂在 `devTools`。
- (Q3) 卡片详情编辑器是否首版就上富文本？决策：**支持**，建议 tiptap。
- (Q4) 是否需要"归档卡片"功能？决策：**需要**。
