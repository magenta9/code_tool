# AI Image Reference Workbench Implementation Plan

## Overview

将 `AI Image` 从当前的纯 text-to-image 页面升级为支持 **多参考图 + prompt** 的图片生成工作台，同时用 `frontend-design` 的 **Editorial cinematic dark** 方向重做界面，但仍严格复用现有 `ToolWorkbench`、`StyledPanel`、`HistoryDrawer`、`AppTheme` 体系，避免做成脱离应用风格的独立页面。当前目标不是做通用图像编辑器，而是在现有 MiniMax `image_generation` 路线上补齐参考图输入、参数控制、历史恢复和更强的视觉层次。 

## Current State Analysis

当前实现已经具备稳定的工具壳层、输出画廊和历史抽屉，但 AI Image 的输入面和数据模型都还停留在 text-to-image 阶段。

### Key Discoveries

- `Sources/CodeToolFoundation/Tool.swift:68-70`、`Sources/CodeToolCore/Views/ContentView.swift:480-505`  
  `AI Image` 已接入工具注册表和主路由，功能入口稳定，无需改导航结构。
- `Sources/CodeToolCore/Views/AITools/AIImageView.swift:7-18,31-111,131-142,208-243,340-401,450-493`  
  当前页面只有 `promptText`、`aspectRatio`、`imageCount` 和生成结果相关状态；主布局仍是左 prompt / 右 output 两栏，没有参考图输入状态、拖拽区或附件缩略图。
- `Sources/CodeToolCore/Providers/MiniMax/MiniMaxAPIClient.swift:545-623`  
  当前 `generateImage` 只发送 `model`、`prompt`、`aspect_ratio`、`n`、`response_format` 到 `/image_generation`，没有 `subject_reference` 或高级参数模型。
- `Sources/CodeToolCore/Persistence/HistoryStore.swift:41-49,414-422,491-493,550-553,637-640`  
  `ImageHistoryRecord` 只保存 prompt、比例、数量、模型、生成图文件名和 reference ID；历史层目前只持久化输出图，不保存输入参考图。
- `Sources/CodeToolCore/Persistence/HistoryDrawer.swift:58-67,151-266`  
  统一历史抽屉已经能很好承载 AI Image 的 per-generation 恢复流程，应继续沿用“当前工具内右侧抽屉”的方式，而不是单独做页面。
- `Sources/CodeToolCore/Views/DevTools/ImageConverterView.swift:97-151,208-323,395-438,442-503`  
  当前代码库里最成熟的本地图片导入/预览/元信息模式在 `ImageConverterView`：`NSOpenPanel`、大预览区、格式/尺寸信息和图片二进制持久化都可复用。
- `Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift:508-613,641-740,948-964`、`Sources/CodeToolCore/Views/Shared/ClaudeChatComposer.swift:91-149,210-246`  
  当前最成熟的“多图片暂存 + 缩略图 + 删除 + 粘贴图片”模式在 Claude chat，但其中“把图片路径注入 prompt”的协议层是 Claude CLI 特定 workaround，不应搬到 MiniMax AI Image。
- `Sources/CodeToolUI/ToolWorkbench.swift:29-63,65-128`、`Sources/CodeToolUI/Theme.swift:5-57,93-168`  
  现有 shared shell 已经提供合适的 dark 基底、header、status chips 和 panel 语言；本次 redesign 应在这个体系里做“电影分镜台 / light table”风格，而不是改全局主题。
- `/Users/zhang/.copilot/session-state/552b4161-83bc-4f8c-9e33-87630816c870/research/ai-image-prompt.md:10-16,53-57`  
  外部研究已经确认 MiniMax 官方能力支持 reference images + prompt；因此本轮主要是把现有 UI、请求体和历史模型接上上游能力。

## Scope

### In Scope

- 支持 **多参考图** 的 AI Image 生成体验。
- 支持三种参考图输入方式：**拖拽、选择文件、粘贴**。
- 将 AI Image 重新设计为 **Editorial cinematic dark** 的 reference workbench：参考图区、prompt/高级参数区、结果画廊区层次清晰。
- 首版提供高级参数入口，至少包含：
  - 宽高比预设
  - 自定义宽高
  - `seed`
  - `prompt_optimizer`
  - 图片数量
- 历史记录同时持久化：
  - 参考图
  - 生成图
  - prompt
  - 参数快照
- 历史恢复时优先恢复 prompt、参数和参考图；若部分文件丢失，使用非阻塞提示降级。
- 保持现有 text-to-image 路径可用：即没有参考图时仍能继续纯 prompt 出图。
- 更新 README 中与 AI Image 能力有关的说明。

### Out of Scope

- 不实现区域蒙版、局部重绘、inpainting/outpainting 等专业编辑能力。
- 不实现独立的全局媒体资源库或跨工具共享附件池。
- 不实现参考图拖拽排序；首版仅支持添加和删除，按加入顺序发送。
- 不把 AI Image 改造成完全独立的主题系统或新导航层。
- 不做 image-only 无 prompt 的首版交互；本轮保持“参考图 + prompt”作为主路径。
- 不引入新的第三方 UI 框架。

## Implementation Approach

### Product / UX Direction

页面采用 **director’s light table** 概念：像在一张电影分镜台上同时摆放参考素材、导演笔记和输出画面。

- **左侧：Reference Board**  
  大面积拖拽区 + 缩略图条 + 添加/粘贴入口，承担“素材池”角色。
- **中间：Prompt & Controls**  
  Prompt 输入、模型显示、生成按钮和高级参数分组，承担“导演控制台”角色。
- **右侧：Output Gallery**  
  保留现有 empty / loading / single / grid 状态机，但强化 hero preview、联系表（contact sheet）和保存动作。

视觉上延续 `AppTheme` 的深色底、冷暖高光和玻璃感 panel 层级，不新增全局 token；差异主要通过布局、对比、信息分组和局部光感实现。

### Technical Strategy

1. 先把 MiniMax 请求和历史记录模型升级成真正支持 reference images 的数据契约。
2. 再补参考图输入链路（拖拽 / picker / paste）和暂存状态。
3. 最后重构 `AIImageView` 页面结构与视觉表现。
4. 测试优先覆盖请求体、历史 roundtrip 和纯 helper，避免把过多逻辑堆在视图里不可测试。

## Phase 1: Data Contract and Persistence

### Overview

先补齐支持参考图与高级参数的请求/存储契约，确保后续 UI 改造有稳定的数据边界。

### Changes Required

#### 1. MiniMax image request model
**File**: `Sources/CodeToolCore/Providers/MiniMax/MiniMaxAPIClient.swift`

将当前 `generateImage(prompt:aspectRatio:n:)` 升级为接收显式请求模型，避免继续追加散乱参数。

建议新增：

```swift
public struct MiniMaxSubjectReference: Sendable {
    public let type: String          // 首版固定 "character"
    public let imageBase64: String?
}

public struct MiniMaxImageGenerationRequest: Sendable {
    public let prompt: String
    public let aspectRatio: String?
    public let width: Int?
    public let height: Int?
    public let imageCount: Int
    public let seed: Int?
    public let promptOptimizer: Bool
    public let subjectReferences: [MiniMaxSubjectReference]
}
```

实现要点：

- 请求体按官方 reference-image 路径追加 `subject_reference`。
- `response_format` 继续固定为 `base64`，与当前解码/持久化链路兼容。
- UI 层不要同时激活“比例预设”和“自定义宽高”两套冲突参数。建议在页面里引入 **Preset Ratio / Custom Size** 二选一模式，避免把“官方 aspect_ratio 优先级更高”这种歧义暴露到用户心智中。
- `prompt_optimizer` 和 `seed` 明确进入 request model，而不是临时字典拼装。

#### 2. AI Image history model
**File**: `Sources/CodeToolCore/Persistence/HistoryStore.swift`

扩展 `ImageHistoryRecord`，让单次生成的完整 replay 信息可恢复：

```swift
public struct ImageReferenceRecord: Codable, Identifiable {
    public let id: UUID
    public let fileName: String
    public let mimeType: String
    public let sizeBytes: Int
}

public struct ImageHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let prompt: String
    public let aspectRatio: String?
    public let width: Int?
    public let height: Int?
    public let imageCount: Int
    public let seed: Int?
    public let promptOptimizer: Bool
    public let model: String
    public let referenceImages: [ImageReferenceRecord]
    public let outputImageFileNames: [String]
    public let referenceID: String
}
```

实现要点：

- 为旧历史 JSON 保持向后兼容：新增字段必须可选或提供兼容解码路径。
- 不截断 replay 所需字段；展示层需要的短标题/副标题仍交给 `HistoryDrawerItem` 计算。
- 参考图和结果图都继续放在 `.image` history 目录，但命名必须显式区分，例如：
  - `"<record-id>-ref-0.png"`
  - `"<record-id>-out-0.png"`
- 删除单条记录时，按 record 明确声明的文件名精确删除，不依赖模糊前缀匹配作为唯一机制。

#### 3. History drawer metadata
**File**: `Sources/CodeToolCore/Persistence/HistoryDrawer.swift`

调整 AI Image 的 drawer 文案，使其能反映参考图与高级参数：

- title：prompt 前 60 字
- subtitle：`<ref-count> refs · <aspect/custom-size> · <n> outputs`

### Success Criteria

#### Automated Verification:
- [x] `make build`
- [ ] 如环境支持 XCTest，执行与 AI Image 相关的定向测试或 `make test`（当前 CLI 环境仍报 `no such module XCTest`）
- [x] 新请求模型能独立编码出包含 `subject_reference`、`seed`、`prompt_optimizer` 的 JSON

#### Manual Verification:
- [ ] 不带参考图时仍能走现有 text-to-image 路径
- [ ] 历史记录恢复后，prompt、高级参数和参考图都能回填
- [ ] 删除单条 AI Image 历史时，不遗留参考图或结果图孤儿文件

> Note: Phase 1 implements the replay contract for reference images and advanced parameters, but end-to-end manual verification of staged reference-image restore depends on the Phase 2 input pipeline UI.

---

## Phase 2: Reference Image Input Pipeline

### Overview

为 AI Image 建立完整的“参考图暂存 → 发送 → 持久化 → 恢复”链路。

### Changes Required

#### 1. Reference image staging model
**File**: `Sources/CodeToolCore/Views/AITools/AIImageView.swift`

新增 view state：

- `referenceImages: [AIImageReferenceItem]`
- `selectedReferenceImageID: UUID?`
- `generationMode: .textOnly | .referenceGuided`
- `parameterMode: .aspectRatio | .customSize`

建议 `AIImageReferenceItem` 至少包含：

- `id`
- `image: NSImage`
- `pngData: Data`
- `fileName`
- `mimeType`
- `sizeBytes`

#### 2. File picker ingestion
**File**: `Sources/CodeToolCore/Views/AITools/AIImageView.swift`

复用 `ImageConverterView.openImageFile()` 的 `NSOpenPanel` 模式，但改为：

- `allowsMultipleSelection = true`
- 限制图片类型为当前仓库已有的 `.png`、`.jpeg`、`.gif`、`.webP`
- 批量读取并 append 到 `referenceImages`

#### 3. Paste ingestion
**Files**:
- `Sources/CodeToolCore/Views/Shared/ClaudeChatComposer.swift`
- `Sources/CodeToolCore/Views/AITools/AIImageView.swift`

不要直接复用 Claude chat 的输入框行为；而是提炼其中的 **图片 pasteboard 解析逻辑**，服务于 AI Image。

推荐做法：

- 抽出通用 helper（例如 `ImagePasteboardReader` 或 `PasteboardImageLoader`）
- AI Image 的 prompt 编辑区或 reference board 接入该 helper
- 普通文本粘贴继续保留原行为；图片粘贴则追加到 `referenceImages`

这样既能保留 `Cmd+V` 图片输入，又避免把 Claude 的 Enter/Shift+Enter 提交语义带入 AI Image。

#### 4. Drag & drop ingestion
**File**: `Sources/CodeToolCore/Views/AITools/AIImageView.swift`

当前仓库没有现成的 drag-and-drop 模式，因此本 phase 需要新增 reference board drop target。

建议实现：

- 拖入 `public.image` 文件 URL
- 拖入图片数据时统一转成 PNG 存储
- 非法类型给出非阻塞 warning banner

#### 5. Reference strip and removal
**File**: `Sources/CodeToolCore/Views/AITools/AIImageView.swift`

借鉴 `ClaudeChatView` 的 staged thumbnail rail：

- 横向滚动缩略图条
- 每张图支持 remove
- 点击后可在左侧 hero preview 中放大查看

首版不做拖拽排序，只按加入顺序发给 API。

### Success Criteria

#### Automated Verification:
- [x] `make build`
- [x] 纯 helper（图片数据归一化、pasteboard 解析、历史恢复映射）已补定向测试（当前 CLI 环境仍无法实际执行 `swift test`，因为缺少 `XCTest`）

#### Manual Verification:
- [ ] 拖拽图片到参考图区后，缩略图立即出现
- [ ] 通过 “Add Images…” 选择多张图片后，缩略图按顺序出现
- [ ] 复制截图或图片文件后按 `Cmd+V`，参考图区能追加图片
- [ ] 删除某一张参考图后，暂存数组和 UI 同步更新
- [ ] 带多张参考图生成后，历史恢复能重新看到这些参考图

---

## Phase 3: Editorial Cinematic Dark Redesign

### Overview

在不脱离 `ToolWorkbench` 的前提下，把 AI Image 重构成更有辨识度的电影分镜台式工作台。

### Changes Required

#### 1. Page layout refactor
**File**: `Sources/CodeToolCore/Views/AITools/AIImageView.swift`

将当前简单的左右两栏，升级为“左侧 reference board + 中间 prompt/controls + 右侧 output gallery”的工作区。若 `HSplitView` 三栏稳定性不足，可退回为“两栏 + 左栏内上下分区”的结构，但目标是：

- 左：参考图素材池
- 中：prompt 与高级参数
- 右：输出画廊

#### 2. Reference board styling
**File**: `Sources/CodeToolCore/Views/AITools/AIImageView.swift`

视觉方向：

- 深色 light-table 底板
- 虚线高亮拖拽区
- 小幅暖色胶片边框或 contact-sheet 风格缩略图
- 选中缩略图在 hero preview 中放大

仍使用 `StyledPanel` / `AppTheme`，不新增全局主题 token。

#### 3. Prompt and advanced controls
**Files**:
- `Sources/CodeToolCore/Views/AITools/AIImageView.swift`
- 视需要新增小型 helper view（仍建议放在 `Views/AITools/`）

参数区建议分为三个 section：

1. **Prompt**
2. **Composition**
   - aspect ratio preset or custom size
   - image count
3. **Advanced**
   - seed
   - prompt optimizer

复用 `AISpeechView` / `AIMusicView` 的 sectioned control cluster 模式，不做表单大杂烩。

#### 4. Output gallery refinement
**File**: `Sources/CodeToolCore/Views/AITools/AIImageView.swift`

保留当前状态机：

- empty
- generating
- single result
- multi-result grid

但增强：

- hero result 区
- 多图 contact sheet
- 单图/多图保存动作更明确
- status chips 能反映 reference count、mode、generation state

### Success Criteria

#### Automated Verification:
- [x] `make build`
- [x] 页面仍然只通过 `ToolWorkbench` / shared UI shell 渲染，无新顶级壳层

#### Manual Verification:
- [ ] 页面从视觉层次上能明确分辨“参考素材 / 控制 / 结果”
- [ ] 没有参考图时仍能清楚发现 text-to-image 主流程
- [ ] 有参考图时，参考图区、prompt 区和结果图区不会互相争抢视觉焦点
- [ ] 空状态、生成中状态和多图状态都保持统一风格
- [ ] 历史抽屉在 redesign 后仍可无缝使用

---

## Phase 4: Tests, Documentation, and Verification

### Overview

补齐请求体、历史模型、辅助逻辑和用户文档，确保这次 redesign 是可维护的功能升级，不是一次性 UI 改造。

### Changes Required

#### 1. MiniMax request tests
**File**: `Tests/CodeToolTests/CodeToolTests.swift`

新增测试建议：

- `testGenerateImageRequestIncludesSubjectReference`
- `testGenerateImageRequestIncludesAdvancedParameters`
- `testGenerateImageRequestUsesCustomSizeWhenSelected`

这些测试可以直接检查 `MiniMaxAPIClient` 发出的 JSON body。

#### 2. History model and replay tests
**File**: `Tests/CodeToolTests/CodeToolTests.swift`

新增测试建议：

- `testImageHistoryRecordCodableWithReferenceImages`
- `testDeleteImageHistoryRemovesReferenceAndOutputFiles`
- `testAIImageHistoryRestoreKeepsParametersWhenFilesMissing`

优先把文件名生成、history snapshot 构造等逻辑提成纯 helper，降低 UI 测试难度。

#### 3. Paste / normalization helper tests
**File**: `Tests/CodeToolTests/CodeToolTests.swift`

新增测试建议：

- `testImagePasteboardNormalizationPrefersPNGData`
- `testReferenceImageMetadataRoundTrip`

#### 4. README updates
**File**: `README.md`

更新 AI 工具描述，明确：

- AI Image 现在支持参考图 + prompt
- 主要输入方式（拖拽 / 选择文件 / 粘贴）
- 仍使用 MiniMax image model

### Success Criteria

#### Automated Verification:
- [x] `make build`
- [ ] 如环境具备 XCTest，执行 `make test`
- [x] 在当前 CLI 环境若 `make test` 因 `XCTest` 环境问题失败，记录为环境限制，不视为实现缺陷

#### Manual Verification:
- [ ] 纯 text-to-image、单参考图、多参考图三条主路径都可成功操作
- [ ] 高级参数能正确回填和再次提交
- [ ] README 与实际页面能力一致
- [ ] 历史恢复后重新生成不会丢失参考图上下文

## Implementation Status

- Phase 1-4 source changes are implemented.
- `swift build` is green after the AI Image workbench rewrite, shared image-import helper extraction, persistence updates, README updates, and new request/history/helper tests.
- `swift test` remains blocked in this CLI environment because `XCTest` is unavailable, so the newly added tests are source-validated but not executed here.
- Remaining unchecked items above are interactive manual verification steps that require running the macOS app UI.

## Testing Strategy

### Unit Tests

- MiniMax image request body 编码测试
- `ImageHistoryRecord` / `ImageReferenceRecord` Codable roundtrip
- 文件删除清理测试
- 缺失文件降级恢复测试
- 图片导入 helper（picker / paste normalization）测试

### Manual Testing Steps

1. 进入 AI Image，确认页面为 reference workbench 布局。
2. 不添加参考图，仅输入 prompt，确认纯 text-to-image 仍可用。
3. 通过文件选择添加多张参考图并生成，确认输出正常。
4. 复制截图后按 `Cmd+V`，确认参考图区追加图片。
5. 将图片从 Finder 拖入参考图区，确认接受合法图片并拒绝非法类型。
6. 修改 `seed`、`prompt_optimizer`、宽高/比例参数，确认 UI 与请求同步。
7. 从历史抽屉恢复一条包含参考图的记录，确认参考图、prompt、参数和输出图尽可能恢复。
8. 删除该历史记录，确认其参考图和结果图文件一并清理。

## Performance Considerations

- 参考图导入后统一归一化为 PNG 数据，减少不同输入来源带来的持久化分叉。
- 视图层尽量展示 `NSImage`，存储层只持久化一次二进制文件，避免在历史里重复存 Base64。
- 多图缩略图条使用 `ScrollView` / `LazyHStack`，结果区继续用 `LazyVGrid`。
- 输出图仍保持 base64 → `Data` → `NSImage` 解码路径；若后续多图场景出现卡顿，再考虑引入缩略图缓存，但不在本轮提前复杂化。

## Migration Notes

- 旧的 `ImageHistoryRecord` 不含参考图和高级参数字段，新字段必须向后兼容解码。
- 旧记录恢复时，如无参考图字段，应自动降级为当前 text-to-image 恢复逻辑。
- README 的 AI Image 说明需要与新 UI 同步，避免用户看到旧能力描述。

## References

- Current AI Image view: `Sources/CodeToolCore/Views/AITools/AIImageView.swift:7-18,31-111,131-142,208-243,340-401,450-493`
- Current MiniMax image client: `Sources/CodeToolCore/Providers/MiniMax/MiniMaxAPIClient.swift:545-623`
- MiniMax settings/model config: `Sources/CodeToolCore/Providers/MiniMax/MiniMaxProvider.swift:18-25,46-121`
- Shared shell: `Sources/CodeToolUI/ToolWorkbench.swift:29-63,65-128`
- Theme tokens: `Sources/CodeToolUI/Theme.swift:5-57,93-168`
- Image file import pattern: `Sources/CodeToolCore/Views/DevTools/ImageConverterView.swift:97-151,208-323,395-438,442-503`
- Paste / staged image pattern: `Sources/CodeToolCore/Views/Shared/ClaudeChatComposer.swift:91-149,210-246`
- Staged thumbnail / persisted attachment pattern: `Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift:508-613,641-740,948-964`
- Image history store: `Sources/CodeToolCore/Persistence/HistoryStore.swift:41-49,414-422,491-493,550-553,637-640`
- Shared history drawer: `Sources/CodeToolCore/Persistence/HistoryDrawer.swift:58-67,151-266`
- Prior history plan: `thoughts/shared/plans/2026-03-31-tool-history-ui.md`
- Prior upload UX plans to borrow from selectively: `thoughts/shared/plans/2026-03-31-claude-cli-optimization.md`, `thoughts/shared/plans/2026-04-03-claude-cli-chat-ux-optimization.md`
- External capability research: `/Users/zhang/.copilot/session-state/552b4161-83bc-4f8c-9e33-87630816c870/research/ai-image-prompt.md`
