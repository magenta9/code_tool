# Electron + React Migration Plan

## Overview

将 CodeTool 从当前 SwiftUI/macOS 实现并行迁移到 Electron + React。新实现参考 `/Users/zhang/code/ai/tiny-experimental-project/projects/quantdesk` 的基础架构：pnpm workspace、`main`/`preload`/`renderer`/`shared` 分层、类型化 IPC contract、主进程持久化与 renderer 纯 UI。

本迁移不是先做小型 Spike，也不是只迁部分工具。首个 Electron 版本目标是 10 个现有工具全部功能等价：

- JSON Tool
- Image Converter
- JSON Diff
- Timestamp Converter
- JWT Tool
- Word Cloud
- AI Chat
- AI Speech
- AI Image
- AI Music

重要修正：不做 AI 生成资产墙，不把 AI 资产聚合作为首页或产品记忆点。新版只做工具迁移；AI 工具保留各自的输入、生成、预览、历史和诊断能力。

## Resolved Decisions

### 1. Migration Strategy

采用并行重建后切换。

- 保留现有 SwiftPM/SwiftUI app 作为可运行基线。
- 在同一仓库新增 Electron + React 实现。
- Electron 版达到功能等价、测试和 macOS 打包 smoke 后再 cutover。
- 不在首轮直接删除 Swift 实现。

### 2. Repository Layout

在当前仓库根目录引入 quantdesk 风格的 pnpm workspace：

```text
package.json
pnpm-workspace.yaml
tsconfig.base.json
packages/
  main/
  preload/
  renderer/
  shared/
```

现有 Swift 文件保留在 `Sources/`、`Tests/`、`Package.swift` 中，直到 cutover 阶段再决定删除或归档。

### 3. Platform Scope

首版只承诺 macOS。

- 与当前 Swift app 覆盖范围一致。
- Electron 架构保留跨平台可能性，但 Windows/Linux 不进入首版验收。
- macOS 首版需要覆盖打包、用户数据路径、Keychain/keytar、文件保存面板和媒体播放。

### 4. UI Direction

新版是个人高频桌面工具工作台，不是营销页、AI 资产图库或团队 SaaS dashboard。

视觉方向：冷静代码实验室。

- 首页和默认工作流优先服务 DevTools 高效使用。
- AI 工具作为同级工具存在，不额外建立资产墙。
- 保留工具目录、搜索、设置、历史和诊断入口。
- UI 可重设计，不追求 SwiftUI 像素级复刻。
- 使用紧凑布局、编辑器质感、清晰状态反馈和低噪声表面层级。

CSS 策略固定为 Tailwind-only。不要在同一元素上混用 CSS Modules、CSS-in-JS 或动态拼接 Tailwind token。图标优先使用单一图标库，避免混用多套图标风格。

### 5. Data Strategy

不迁移 Swift 版旧数据。

- Electron 版从零开始创建新的历史、设置、日志和媒体资产。
- 不读取 Swift 版 `Application Support/CodeTool` 历史 JSON。
- 不迁移 UserDefaults 中的 MiniMax API Key。
- MiniMax API Key 在 Electron 版中通过主进程和 macOS Keychain/keytar 保存。

新持久化采用 SQLite 元数据 + 文件资产。

- SQLite 存历史、工具记录、设置索引和任务状态。
- 文件系统存图片、语音、音乐等二进制资产。
- renderer 不直接访问数据库、密钥或文件系统；统一通过 IPC 调用 main。

### 6. AI Provider Scope

首版只实现 MiniMax。

- 保留 provider 边界，例如 shared 类型和 IPC 命名中保留 `provider: "minimax"`。
- 不在首版抽象或实现 OpenAI、Claude、Gemini 等未请求 provider。
- 不把 API key 暴露给 renderer。

### 7. AI Task Model

AI 生成使用 taskId + 事件订阅模型。

- renderer 调用 main 创建任务，main 返回 `taskId`。
- renderer 订阅 `ai:task-event` 类型事件。
- 支持流式文本、阶段进度、取消、失败、完成和 reference ID。
- 完成后由 main 写历史记录和文件资产。
- DevTools 这类短操作仍使用普通 invoke。

### 8. Testing Baseline

最低自动化验收：核心逻辑 + IPC contract + 页面 smoke。

- 每个工具至少覆盖核心逻辑单测。
- shared IPC contract 有类型和绑定测试。
- renderer 对关键页面做 smoke test。
- AI 外部服务通过 mock 覆盖请求构建、事件流、错误和历史写入。
- 最终至少运行 `pnpm build`、`pnpm typecheck`、`pnpm test`。

### 9. Cutover Standard

只有满足以下条件才允许 Electron 版替代 Swift 版：

- 10 个工具功能等价。
- 新历史、设置、日志和文件资产系统可用。
- MiniMax 四类请求具备 mock 测试。
- macOS 打包产物可打开并完成 smoke。
- README、构建命令和开发说明更新。
- Swift 版保留、归档或删除的策略已单独确认。

## Current State Facts

### Existing CodeTool Structure

当前 SwiftPM package 有四个 target：

- `CodeToolApp`: macOS executable entry point。
- `CodeToolCore`: 主要业务视图、provider、persistence、observability。
- `CodeToolFoundation`: 工具目录、共享模型和设置基础设施。
- `CodeToolUI`: 共享主题、shell 和组件。

当前工具目录由 `ToolCatalog` / `ToolRegistry.defaults` 提供，详情页由 `ToolDestinationRegistry` 映射到 SwiftUI view。迁移时应保留这种“工具目录是单一事实源”的边界，但用 TypeScript shared package 重建。

AI 功能当前集中在 MiniMax：

- 设置：`MiniMaxSettingsStore`
- transport：`MiniMaxAPIClient`
- UI：`MiniMaxChatView`、`AISpeechView`、`AIImageView`、`AIMusicView`
- 历史：`HistoryStore` 和各类 `HistoryRecord`
- 诊断：`AppLogger`、`DiagnosticsStore`、reference ID

### Quantdesk Reference Architecture

参考项目使用以下结构：

```text
packages/
  main/      Electron main process, IPC handlers, data/services, secrets
  preload/   contextBridge API exposure
  renderer/  React/Vite UI
  shared/    shared types, IPC channels, IPC contract
```

关键模式：

- `shared` 定义 API 类型、IPC channel 和 contract。
- `preload` 将 contract 绑定到 `window.api`。
- `main` 注册 IPC handlers，集中访问数据库、文件系统、密钥和外部服务。
- `renderer` 只做 React UI 和状态管理。

该模式适合 CodeTool，因为 CodeTool 同样需要强进程边界：API key、文件保存、历史、日志和 MiniMax 网络请求都应放在 main。

## Target Architecture

### Package Boundaries

```text
packages/shared/src/
  tool-catalog.ts
  ipc-channels.ts
  ipc-contract.ts
  types/
    tools.ts
    history.ts
    ai.ts
    settings.ts
    diagnostics.ts

packages/main/src/
  index.ts
  ipc/
    register.ts
    contract-binder.ts
    tools.ts
    ai.ts
    history.ts
    settings.ts
    diagnostics.ts
  db/
    schema.ts
    services.ts
    repositories/
  providers/minimax/
    minimax-client.ts
    minimax-settings.ts
    minimax-task-runner.ts
  storage/
    asset-store.ts
    path-service.ts
  logger/

packages/preload/src/
  index.ts
  api.ts

packages/renderer/src/
  App.tsx
  routes/
  components/
  tools/
    json-tool/
    image-converter/
    json-diff/
    timestamp-converter/
    jwt-tool/
    word-cloud/
    ai-chat/
    ai-speech/
    ai-image/
    ai-music/
  stores/
  styles/
```

### Shared Tool Catalog

`packages/shared/src/tool-catalog.ts` should become Electron 版的 bundled tool source of truth。

It should include:

- stable `ToolId`
- title
- description
- category
- icon key
- route path
- capability flags if needed

The renderer sidebar, route table, tests and README should consume this catalog instead of duplicating tool membership.

### IPC API Shape

Recommended namespaces:

- `system`: app/runtime status and smoke probes
- `tools`: short synchronous DevTools operations
- `history`: list/load/delete tool history
- `settings`: non-secret settings
- `secrets`: MiniMax API key via keytar
- `ai`: provider settings, task creation, task cancellation, task events
- `log`: renderer-to-main log forwarding and open log directory

AI event sketch:

```ts
type AiTaskEvent =
  | { type: 'started'; taskId: string; referenceId: string; toolId: ToolId }
  | { type: 'progress'; taskId: string; stage: string; message?: string }
  | { type: 'delta'; taskId: string; text: string }
  | { type: 'artifact'; taskId: string; artifact: GeneratedArtifact }
  | { type: 'completed'; taskId: string; historyId: string; durationMs: number }
  | { type: 'cancelled'; taskId: string }
  | { type: 'failed'; taskId: string; referenceId: string; message: string };
```

## Tool Migration Strategy

### DevTools

DevTools should be migrated as React tools backed by shared pure functions where possible.

- JSON Tool
  - Core: parse, format, minify, validate, stats.
  - Tests: invalid JSON, stable formatting, stats.
- Image Converter
  - Core: base64 encode/decode, image metadata, file save/load through main IPC.
  - Tests: MIME detection, invalid base64, output file asset record.
- JSON Diff
  - Use a mature diff library or a small structured JSON diff adapter.
  - Tests: added/removed/modified counts and nested paths.
- Timestamp Converter
  - Core: seconds/milliseconds detection, ISO/local conversion, timezone display.
  - Tests: ms vs seconds, invalid input, date-to-timestamp.
- JWT Tool
  - Decode safely without trusting payload.
  - Encoding/signing only if current Swift behavior requires it; do not add new auth semantics.
  - Tests: malformed token, exp display, header/payload formatting.
- Word Cloud
  - Use a proven visualization package or canvas/SVG renderer with deterministic tokenization tests.
  - Tests: stop words, frequency sorting, empty input.

### AI Tools

AI tools should share a main-process MiniMax provider layer and renderer-specific UI.

- AI Chat
  - Uses task event stream for assistant deltas.
  - Saves final conversation history through main.
- AI Speech
  - Main calls MiniMax, stores audio asset, renderer plays via object URL or safe file bridge.
- AI Image
  - Supports prompt, size/aspect settings and reference image behavior if current Swift feature requires it.
  - Stores output image files and history metadata.
- AI Music
  - Preserve known long-running request handling and user-facing timeout diagnostics.
  - Prefer URL output and second-step download when MiniMax behavior requires it.

## UI Plan

### App Shell

The app should use a desktop workbench shell:

- left tool rail with categories and search
- main tool workspace
- settings entry
- history/diagnostics entry
- compact execution status region

No landing-page hero. No AI asset wall. No decorative card-heavy marketing layout.

### Visual Thesis

Cold code lab for a local tool workbench: editor-like surfaces, compact typography, precise state feedback, and restrained depth.

### Content Plan

- Orient: tool rail, current tool title, status chips.
- Act: focused input/output panels per tool.
- Review: per-tool history and diagnostics drawers.
- Recover: clear errors with reference ID and retry affordances.

### Interaction Thesis

- Buttons use `active:scale-95` or equivalent `scale(0.96)` only.
- Tool execution shows a compact stage/status strip.
- AI tasks stream progress through the same execution surface instead of modal overlays.
- Motion uses transform/opacity only and honors reduced motion.

## Persistence Plan

### SQLite Tables

Initial tables should cover:

- `history_entries`
- `history_payloads` or per-tool payload tables
- `assets`
- `settings`
- `ai_tasks` if task recovery or diagnostics need it
- `diagnostic_events` if logs need indexed lookup beyond JSONL files

Media files should live under Electron `userData`, for example:

```text
~/Library/Application Support/CodeTool/
  electron/
    codetool.sqlite
    assets/
      image/
      speech/
      music/
    logs/
```

Using an `electron/` subdirectory avoids accidental collision with old Swift data while keeping the product identity path stable.

### Secrets

MiniMax API Key should be stored via keytar/macOS Keychain from main.

Renderer should only know whether a provider is configured, never the raw secret unless explicitly needed for an edit form round trip. Prefer write-only secret forms with clear reset behavior.

## Implementation Phases

### Phase 0: Workspace Foundation

- Add root `package.json`, `pnpm-workspace.yaml`, `tsconfig.base.json`.
- Add `packages/shared`, `packages/main`, `packages/preload`, `packages/renderer`.
- Configure Vite, React, Electron, tsup, Vitest, ESLint and electron-builder.
- Keep SwiftPM build untouched.

Verification:

- `pnpm build`
- `pnpm typecheck`
- `pnpm test`
- existing Swift `swift build` still succeeds if run separately.

### Phase 1: Shell, Catalog and IPC Contract

- Port `ToolID` and `ToolCatalog` into shared TypeScript.
- Build renderer shell with left rail, search, route mapping and empty tool placeholders.
- Implement preload `window.api` from shared IPC contract.
- Register main IPC contract binder.

Verification:

- Catalog tests ensure every tool has a route.
- Renderer smoke test renders all routes.
- IPC contract test ensures every declared handler is bound.

### Phase 2: DevTools Functional Migration

- Migrate JSON Tool, Image Converter, JSON Diff, Timestamp Converter, JWT Tool and Word Cloud.
- Add shared pure logic tests.
- Add per-tool history writes where current Swift behavior has history.

Verification:

- Unit tests for each tool's core logic.
- Renderer smoke test for each tool page.
- Manual smoke for file open/save where applicable.

### Phase 3: Persistence, History and Diagnostics

- Add SQLite schema and repository layer in main.
- Add file asset store for image/audio outputs.
- Add history drawer/list/load/delete APIs.
- Add JSONL logging or indexed diagnostics, preserving reference ID semantics.

Verification:

- Repository tests use temporary userData path.
- History list/load/delete tests cover payload and asset cleanup.
- Diagnostics tests cover reference ID lookup.

### Phase 4: MiniMax Provider and AI Task Runtime

- Port MiniMax settings into main + shared types.
- Store API key via keytar.
- Implement MiniMax client in main.
- Implement task runner with taskId, cancellation and event subscription.
- Migrate AI Chat, AI Speech, AI Image and AI Music renderer tools.

Verification:

- Mocked MiniMax request tests for each AI tool.
- Streaming chat event tests.
- Speech/image/music artifact persistence tests.
- Timeout and upstream failure diagnostics tests for music.

### Phase 5: Packaging, Documentation and Cutover Prep

- Add macOS electron-builder config.
- Add package smoke path.
- Update README with new dev/build/test commands.
- Document Swift legacy status and cutover criteria.
- Decide separately whether to delete, archive or keep Swift implementation after Electron passes acceptance.

Verification:

- packaged macOS app opens.
- app can run all 10 tool smoke checks.
- `pnpm build`, `pnpm typecheck`, `pnpm test` pass.
- README commands are accurate.

## Out of Scope

- Windows/Linux support in the first Electron release.
- Migrating Swift historical data or UserDefaults.
- AI asset wall or cross-tool media gallery.
- Multi-provider AI abstraction beyond a MiniMax provider boundary.
- Reusing Swift UI code directly.
- Pixel-perfect SwiftUI visual replication.
- Direct renderer access to file system, SQLite or secrets.

## Cutover Checklist

- [ ] Electron workspace builds from a clean checkout.
- [ ] All 10 tools are present in shared catalog and renderer routes.
- [ ] All 10 tools have functional parity smoke coverage.
- [ ] DevTools core logic has unit tests.
- [ ] AI tools have mocked provider tests.
- [ ] IPC contract coverage confirms declared handlers exist.
- [ ] SQLite persistence tests pass with temporary userData.
- [ ] Keytar-backed MiniMax secret storage works on macOS.
- [ ] macOS package opens and runs basic smoke checks.
- [ ] README documents Electron commands and legacy Swift status.
- [ ] User explicitly approves Swift removal or archival.

## Open Implementation Details

These should be decided during implementation, not before the plan starts:

- Exact npm libraries for JSON diff, JWT, editor surfaces and word cloud.
- Exact Tailwind token values and font choice for the cold code lab direction.
- Whether diagnostics remain JSONL-only or add SQLite indexing in V1.
- Whether history payloads use a single envelope table or per-tool payload tables.
- Whether packaged app keeps product name `CodeTool` or uses a temporary migration name during parallel development.
