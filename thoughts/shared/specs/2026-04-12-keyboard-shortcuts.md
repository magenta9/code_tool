---
date: 2026-04-12T19:24:00+08:00
researcher: zhang
git_commit: b9265c5850aafc0044e4bb949c84c4a86f18508e
branch: main
topic: "Keyboard Shortcuts"
tags: [research-spec, requirements, keyboard-shortcuts, navigation, macOS]
status: complete
confidence: high
last_updated: 2026-04-12
last_updated_by: zhang
---

# 键盘快捷键 Research Spec

## Summary

为 CodeTool 添加完整的键盘快捷键体系，覆盖工具切换（⌘1~⌘9 + ⌘⇧0）、设置打开（⌘,）、搜索聚焦（⌘K），提升高级用户的操作效率。

## Background

当前 CodeTool 仅有 4 个快捷键：`⌘0`（回到 Landing）、`⌘\`（切换侧边栏）、`⌘⇧O`/`⌘L`（Claude Chat 专用）。作为一款桌面开发工具集，缺少工具间快速切换和常用操作的快捷键，影响高频用户的使用效率。

## Goals

- 支持通过键盘快捷键直接切换到任意一个工具（10 个工具全覆盖）
- 支持 `⌘,` 打开设置面板（符合 macOS 惯例）
- 支持 `⌘K` 聚焦侧边栏搜索框（侧边栏隐藏时自动展开）
- 所有快捷键在菜单栏 Workspace 菜单中可见、可发现

## Non-goals

- 不做侧边栏宽度调整/缩放功能（保留现有 ⌘\ 显示/隐藏切换即可）
- 不做自定义快捷键映射（用户不能自行修改快捷键绑定）
- 不做 ⌘[ / ⌘] 历史前后切换（本次不实现）
- 不修改现有 Claude Chat 专用快捷键（⌘⇧O、⌘L）

## Requirements

### Functional Requirements

#### FR-1: 工具切换快捷键

按 `ToolCatalog.bundled` 顺序分配快捷键：

| 快捷键 | ToolID | 工具名 | 分类 |
|--------|--------|--------|------|
| `⌘1` | `.jsonTool` | JSON Tool | Dev Tools |
| `⌘2` | `.imageConverter` | Image Converter | Dev Tools |
| `⌘3` | `.jsonDiff` | JSON Diff | Dev Tools |
| `⌘4` | `.timestampConverter` | Timestamp Converter | Dev Tools |
| `⌘5` | `.jwtTool` | JWT Tool | Dev Tools |
| `⌘6` | `.wordCloud` | Word Cloud | Dev Tools |
| `⌘7` | `.aiChat` | AI Chat | AI Tools |
| `⌘8` | `.aiSpeech` | AI Speech | AI Tools |
| `⌘9` | `.aiImage` | AI Image | AI Tools |
| `⌘⇧0` | `.aiMusic` | AI Music | AI Tools |

- 按快捷键后，`selectedToolID` 应切换到对应工具
- 如果已在该工具页，按快捷键无额外效果（幂等）
- 快捷键在任何工具页面都应生效（全局作用域，通过 Commands 注册）

#### FR-2: 打开设置 (`⌘,`)

- 按 `⌘,` 打开现有的设置面板（触发 `showSettings = true`）
- 符合 macOS 标准 `⌘,` = Preferences 惯例
- 使用 SwiftUI `CommandGroup(replacing: .appSettings)` 注册，确保出现在标准位置（App 菜单下）

#### FR-3: 聚焦搜索框 (`⌘K`)

- 按 `⌘K` 将焦点移动到侧边栏搜索框
- 如果侧边栏当前隐藏，先自动展开侧边栏（带动画），然后聚焦搜索框
- 需要引入 `@FocusState` 来管理搜索框焦点

#### FR-4: 菜单栏集成

所有新快捷键在现有 **Workspace** 菜单中展示，结构如下：

```
Workspace
├── Show Landing          ⌘0
├── Toggle Sidebar        ⌘\
├── Focus Search          ⌘K
├── ─────────────────────
├── Dev Tools
│   ├── JSON Tool         ⌘1
│   ├── Image Converter   ⌘2
│   ├── JSON Diff         ⌘3
│   ├── Timestamp Conv.   ⌘4
│   ├── JWT Tool          ⌘5
│   └── Word Cloud        ⌘6
├── AI Tools
│   ├── AI Chat           ⌘7
│   ├── AI Speech         ⌘8
│   ├── AI Image          ⌘9
│   └── AI Music          ⌘⇧0
```

`⌘,` 打开设置不放在 Workspace 菜单，而是通过 `CommandGroup(replacing: .appSettings)` 放在标准的 App 菜单（"CodeTool" 菜单 → Settings...）位置。

### Non-functional Requirements

- **性能**: 快捷键响应应即时（< 16ms），不引入额外延迟
- **兼容性**: 不与 macOS 系统快捷键冲突（⌘1~⌘9 在非浏览器 app 中无系统占用）
- **可发现性**: 所有快捷键在菜单栏中可见，用户可通过菜单了解可用快捷键

### Constraints

- 必须通过 SwiftUI `Commands` API 注册快捷键，与现有 `WorkspaceCommands` 架构一致
- 使用现有的 `FocusedValue` 机制传递 actions 到 `ContentView`
- `⌘,` 必须使用 `CommandGroup(replacing: .appSettings)` 而非自定义菜单项

### Assumptions

- `ToolCatalog.bundled` 的顺序在可预见的未来不会频繁变动
- 10 个工具是当前全量，若未来新增工具超过 10 个，需重新设计快捷键方案
- 设置面板已存在并可通过 `showSettings` 状态触发

## Edge Cases

| 场景 | 预期行为 |
|------|----------|
| 按 ⌘7 已在 AI Chat 页 | 无变化（幂等），不重新创建视图 |
| 按 ⌘K 侧边栏已展开 | 直接聚焦搜索框，不触发侧边栏动画 |
| 按 ⌘K 侧边栏已隐藏 | 先展开侧边栏（带动画），然后聚焦搜索框 |
| 按 ⌘, 设置面板已打开 | 无变化（幂等），不重复打开 |
| 搜索框有焦点时按 ⌘1 | 切换到 JSON Tool，搜索框失去焦点 |
| 多窗口场景 | 快捷键只作用于当前 focused window（FocusedValue 机制保证） |

## Dependencies

- SwiftUI `Commands` API（已在使用）
- `FocusedValue` / `focusedSceneValue`（已在使用）
- `@FocusState`（需新增，用于搜索框焦点管理）

## Acceptance Criteria

- [ ] ⌘1~⌘9 可切换到对应的前 9 个工具
- [ ] ⌘⇧0 可切换到 AI Music（第 10 个工具）
- [ ] ⌘0 仍然回到 Landing 页（现有功能不受影响）
- [ ] ⌘\ 仍然切换侧边栏（现有功能不受影响）
- [ ] ⌘, 打开设置面板
- [ ] ⌘K 聚焦侧边栏搜索框
- [ ] ⌘K 在侧边栏隐藏时自动展开侧边栏再聚焦
- [ ] 所有工具切换快捷键在 Workspace 菜单中可见
- [ ] ⌘, 在标准 App 菜单 Settings 位置可见
- [ ] 所有快捷键不与现有快捷键冲突
- [ ] `swift build` 编译通过
- [ ] `make test` 测试通过

## Success Metrics

- 所有 12 个新快捷键均可从菜单栏发现并触发
- 现有 4 个快捷键功能不受影响

## Open Questions

- [x] 工具切换方案 → 方案 A: ⌘1~⌘9 顺序 + ⌘⇧0
- [x] 侧边栏缩放 → 仅保留现有显示/隐藏切换
- [x] 额外快捷键 → ⌘, 设置 + ⌘K 搜索聚焦
- [x] 菜单组织 → 放在现有 Workspace 菜单中
- [x] ⌘K 侧边栏隐藏时行为 → 自动展开并聚焦
- [x] 工具映射顺序 → ToolCatalog.bundled 顺序确认

## Implementation Notes

### 涉及的文件

| 文件 | 变更内容 |
|------|----------|
| `Sources/CodeToolApp/CodeToolApp.swift` | 扩展 `WorkspaceCommands` 添加工具切换和搜索菜单项；新增 `CommandGroup(replacing: .appSettings)` |
| `Sources/CodeToolCore/Views/Shared/WorkspaceCommands.swift` | 扩展 `WorkspaceCommandActions` 添加 `selectTool(_:)`、`focusSearch()`、`showSettings()` 闭包 |
| `Sources/CodeToolCore/Views/ContentView.swift` | 添加 `@FocusState` 管理搜索框焦点；扩展 `focusedSceneValue` 发布新 actions |
| `Tests/CodeToolTests/CodeToolTests.swift` | 验证快捷键相关的测试（如 ToolID 数量一致性） |

### 架构约束

- 通过 `WorkspaceCommandActions` 结构体传递所有 action 闭包，保持 Commands 与 View 解耦
- `⌘,` 设置使用独立的 `CommandGroup(replacing: .appSettings)`，不经过 `WorkspaceCommandActions`
- 搜索框焦点通过 `@FocusState` + `FocusedValue` 链路管理
