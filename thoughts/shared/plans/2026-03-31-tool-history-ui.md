# Tool History UI Implementation Plan

## Overview

为 CodeTool 的每个工具添加历史记录交互界面。当前 `HistoryStore` 已完整实现（save/list/delete/clear/count），4 个 AI 工具已保存历史但无读取 UI，6 个 Dev 工具完全没有历史功能。本计划将：
1. 创建统一的 `HistoryDrawer` 组件（右侧滑出面板）
2. 为 6 个 Dev 工具新增 history record 类型 + 保存逻辑
3. 为所有 10 个工具接入历史浏览 + 回放功能

## Current State Analysis

### Key Discoveries:
- `Sources/CodeToolCore/HistoryStore.swift:81-85` — `HistoryCategory` 目前只有 4 个值：`.chat`, `.speech`, `.image`, `.music`
- `Sources/CodeToolCore/HistoryStore.swift:127-245` — `HistoryStore` 已完整支持 save/list/delete/clear/count，按 category 分目录存储 JSON + 二进制文件
- `Sources/CodeToolCore/AIChatView.swift:343-356`、`AISpeechView.swift:332-349`、`AIImageView.swift:367-381`、`AIMusicView.swift:360-375` — 4 个 AI 工具已在成功调用后保存历史，但没有任何 UI 读取历史
- `Sources/CodeToolCore/JSONToolView.swift:1-235`、`ImageConverterView.swift:1-338`、`JSONDiffView.swift:1-318`、`TimestampConverterView.swift:1-191`、`JWTToolView.swift:1-420`、`WordCloudView.swift:1-382` — 6 个 Dev 工具当前没有历史保存或恢复逻辑
- `Sources/CodeToolCore/ToolWorkbench.swift:13-109` — 所有工具使用 `ToolWorkbench` 外壳，header 右上角有 action 按钮区域（如 "Clear Chat", "Copy Last"）
- 共享组件库：`StyledPanel`, `StyledButton`, `StyledIconButton`, `CopyButton`, `StyledTextEditor`, `ToolMessageBanner`
- 暗色主题设计系统：`AppTheme`（cyan accent, warm orange accent, coral error）
- `Tests/CodeToolTests/CodeToolTests.swift:133-134` — 测试文件包含 `testRegistryContainsTenTools` 断言
- `.github/copilot-instructions.md:5-8` — 当前 CLI 环境以 `swift build` 作为最低验证标准，`swift test` 预计会因缺少 `XCTest` 失败

### Design Decisions:
- **交互形式**：ToolWorkbench header 中添加 History 按钮，点击后从右侧滑出抽屉面板（overlay sheet），不离开当前工具
- **Dev 工具历史**：每次主要操作（format、convert、compare 等）保存一条记录
- **回放行为**：点击历史记录恢复输入参数到工具编辑器；Dev 工具默认不覆盖当前输出，由用户重新执行；AI 工具允许在二进制附件可用时恢复音频/图片预览
- **存储契约**：用于回放的原始输入必须完整持久化；History Drawer 的标题/副标题/详情预览在展示层截断，不依赖截断后的存储字段来回放
- **缺失附件降级**：若历史记录的图片或音频文件缺失，仍恢复文本参数，并显示非阻塞提示；不得因为单条坏记录导致整个历史列表不可用
- **损坏记录处理**：历史列表加载采用“跳过坏文件”的容错策略；坏 JSON 记录不会阻断同类其他记录显示
- **Image Converter 附件约束**：Image Converter 的关联图片文件名必须使用 record id 前缀，或在删除时按 record 中显式记录的文件名精确删除，不能依赖未声明的命名约定
- **历史上限**：无硬上限，HistoryStore 已有 clear/delete 方法供用户手动清理

## Scope

### In Scope
- 新增 `HistoryDrawer` 共享组件（右侧滑出面板，历史列表 + 详情预览 + 删除 + 清空）
- 新增 6 个 Dev 工具的 HistoryRecord 类型
- 扩展 `HistoryCategory` enum 增加 6 个 Dev 工具类别
- 扩展 `HistoryStore` 增加 6 个 Dev 工具的 save/list/delete 方法
- 所有 10 个工具的 View 接入 HistoryDrawer（按钮触发 + 回放回调）
- 4 个 AI 工具：添加历史浏览功能（利用已有保存的数据）
- 6 个 Dev 工具：添加保存 + 浏览功能

### Out of Scope
- 历史搜索/过滤：首版先验证记录写入、浏览、回放闭环，避免在缺少真实使用样本前引入额外状态管理
- 历史导出/导入：本轮仅做本地持久化，不扩展文件交换协议
- 跨工具统一历史页面：继续沿用每个工具自己的上下文，避免打断当前 ToolWorkbench 交互模型
- 云端同步：当前 `HistoryStore` 明确是本地 Application Support 存储，本计划不引入账户体系或同步冲突处理
- 分页加载：列表首版一次加载全部，先复用现有 `HistoryStore` 设计；当历史量级和性能数据明确后再考虑分页

## Implementation Approach

采用分 4 个 Phase 递增实现：
1. Phase 1：数据层 — 新增 record 类型 + 扩展 HistoryStore
2. Phase 2：UI 组件 — 创建通用 HistoryDrawer
3. Phase 3：AI 工具接入 — 先接入已有历史数据的 4 个 AI 工具
4. Phase 4：Dev 工具接入 — 接入 6 个 Dev 工具（保存 + 浏览）

每个 Phase 独立可编译验证。

---

## Phase 1: Data Layer — History Records & Store Extension

### Overview
扩展 HistoryStore 以支持 6 个 Dev 工具的历史记录存储。
本阶段同时修正两个现有约束：
1. 历史数据模型必须区分“用于回放的完整字段”和“用于列表展示的预览信息”
2. `list*` API 需要具备部分容错能力，单个损坏 JSON 文件不能让整个抽屉加载失败

### Changes Required:

#### 1. 扩展 HistoryCategory
**File**: `Sources/CodeToolCore/HistoryStore.swift`
**Changes**: 增加 6 个 Dev 工具的 category 值

```swift
public enum HistoryCategory: String, CaseIterable {
    case chat
    case speech
    case image
    case music
    // Dev tools
    case jsonTool
    case imageConverter
    case jsonDiff
    case timestampConverter
    case jwtTool
    case wordCloud
}
```

#### 2. 新增 6 个 Dev 工具的 HistoryRecord 类型
**File**: `Sources/CodeToolCore/HistoryStore.swift`
**Changes**: 在现有 record 类型后添加

```swift
/// History record for JSON Tool operations.
public struct JSONToolHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let operation: String    // "format" | "minify" | "validate"
    public let inputText: String    // 完整输入，用于回放
    public let outputText: String   // 完整输出，用于详情查看；Drawer 列表展示时自行截断
    public let stats: String
}

/// History record for Image Converter operations.
public struct ImageConverterHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let mode: String         // "imageToBase64" | "base64ToImage"
    public let base64Text: String   // 仅在 Base64→Image 时保存完整输入；Image→Base64 时可为空字符串
    public let base64Preview: String // 预览文本，最多 500 字符
    public let imageInfo: String
    public let imageFileName: String?
}

/// History record for JSON Diff operations.
public struct JSONDiffHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let leftText: String
    public let rightText: String
    public let totalDiffs: Int
    public let addedCount: Int
    public let removedCount: Int
    public let modifiedCount: Int
}

/// History record for Timestamp Converter operations.
public struct TimestampHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let inputValue: String   // timestamp string or formatted date
    public let direction: String    // "timestampToDate" | "dateToTimestamp"
    public let selectedDateISO8601: String? // dateToTimestamp 回放使用的精确时间
    public let resultISO8601: String
    public let resultLocal: String
    public let resultTimestamp: String
}

/// History record for JWT Tool operations.
public struct JWTHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let mode: String         // "decode" | "encode"
    public let jwtInput: String     // raw token (decode) or generated token (encode)
    public let headerJSON: String   // decoded header (decode) or encode editor source (encode)
    public let payloadJSON: String  // decoded payload (decode) or encode editor source (encode)
    public let expirationInfo: String
}

/// History record for Word Cloud operations.
public struct WordCloudHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let inputText: String    // 完整输入，用于回放
    public let inputPreview: String // 展示预览，最多 2000 字符
    public let topWords: String     // 前 20 个词的 "word:count" 格式
    public let minWordLength: Int
    public let maxWords: Int
    public let ignoreStopWords: Bool
}
```

#### 3. 扩展 HistoryRecord protocol conformance
**File**: `Sources/CodeToolCore/HistoryStore.swift`
**Changes**: 添加 protocol 扩展

```swift
extension JSONToolHistoryRecord: HistoryRecord {}
extension ImageConverterHistoryRecord: HistoryRecord {}
extension JSONDiffHistoryRecord: HistoryRecord {}
extension TimestampHistoryRecord: HistoryRecord {}
extension JWTHistoryRecord: HistoryRecord {}
extension WordCloudHistoryRecord: HistoryRecord {}
```

#### 4. 扩展 HistoryStore 的 save/list/delete 方法
**File**: `Sources/CodeToolCore/HistoryStore.swift`
**Changes**: 添加 Dev 工具的存储方法

```swift
// MARK: - Dev Tool Save

public func save(_ record: JSONToolHistoryRecord) throws {
    let dir = try categoryURL(.jsonTool)
    let data = try encoder.encode(record)
    try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
}

public func save(_ record: ImageConverterHistoryRecord, imageData: Data?) throws {
    let dir = try categoryURL(.imageConverter)
    let data = try encoder.encode(record)
    try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
    if let imageData, let imageFileName = record.imageFileName {
        try imageData.write(to: dir.appendingPathComponent(imageFileName))
    }
}

public func save(_ record: JSONDiffHistoryRecord) throws {
    let dir = try categoryURL(.jsonDiff)
    let data = try encoder.encode(record)
    try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
}

public func save(_ record: TimestampHistoryRecord) throws {
    let dir = try categoryURL(.timestampConverter)
    let data = try encoder.encode(record)
    try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
}

public func save(_ record: JWTHistoryRecord) throws {
    let dir = try categoryURL(.jwtTool)
    let data = try encoder.encode(record)
    try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
}

public func save(_ record: WordCloudHistoryRecord) throws {
    let dir = try categoryURL(.wordCloud)
    let data = try encoder.encode(record)
    try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
}

// MARK: - Dev Tool List

public func listJSONTool() throws -> [JSONToolHistoryRecord] {
    try loadRecords(category: .jsonTool)
}

public func listImageConverter() throws -> [ImageConverterHistoryRecord] {
    try loadRecords(category: .imageConverter)
}

public func listJSONDiff() throws -> [JSONDiffHistoryRecord] {
    try loadRecords(category: .jsonDiff)
}

public func listTimestamp() throws -> [TimestampHistoryRecord] {
    try loadRecords(category: .timestampConverter)
}

public func listJWT() throws -> [JWTHistoryRecord] {
    try loadRecords(category: .jwtTool)
}

public func listWordCloud() throws -> [WordCloudHistoryRecord] {
    try loadRecords(category: .wordCloud)
}

// MARK: - Corruption Tolerance

// `loadRecords(category:)` 需要改为容错模式：
// - 单个 JSON 文件 decode 失败时跳过该记录
// - 保留其余记录并继续按 createdAt 倒序返回
// - 如需要，可后续通过 AppLogger 记录坏文件路径

// MARK: - Dev Tool Delete

public func deleteJSONTool(id: UUID) throws {
    let dir = try categoryURL(.jsonTool)
    try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id.uuidString).json"))
}

public func deleteImageConverter(id: UUID) throws {
    let dir = try categoryURL(.imageConverter)
    let jsonURL = dir.appendingPathComponent("\(id.uuidString).json")
    if let data = try? Data(contentsOf: jsonURL),
       let record = try? decoder.decode(ImageConverterHistoryRecord.self, from: data),
       let imageFileName = record.imageFileName {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(imageFileName))
    }
    try? FileManager.default.removeItem(at: jsonURL)
}

public func deleteJSONDiff(id: UUID) throws {
    let dir = try categoryURL(.jsonDiff)
    try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id.uuidString).json"))
}

public func deleteTimestamp(id: UUID) throws {
    let dir = try categoryURL(.timestampConverter)
    try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id.uuidString).json"))
}

public func deleteJWT(id: UUID) throws {
    let dir = try categoryURL(.jwtTool)
    try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id.uuidString).json"))
}

public func deleteWordCloud(id: UUID) throws {
    let dir = try categoryURL(.wordCloud)
    try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id.uuidString).json"))
}
```

Image Converter 若选择继续复用 `removeFiles(in:prefix:)`，则必须明确规定 `imageFileName == "\(id.uuidString)-..."`。本计划推荐按 record 中显式记录的文件名精确删除，避免隐式约定。

### Success Criteria:

#### Automated Verification:
- [x] `swift build` 编译通过
- [ ] 如当前环境缺少 `XCTest`，记录 `swift test --filter CodeToolTests` 因环境限制跳过；若在完整 Xcode 环境执行，则测试通过

#### Manual Verification:
- [ ] HistoryCategory 新增的 6 个 case 都有 rawValue（用于目录名）
- [ ] Image Converter 删除单条记录不会遗留关联图片文件
- [ ] 单个损坏历史 JSON 文件不会导致整个分类列表读取失败

---

## Phase 2: UI Component — HistoryDrawer

### Overview
创建通用的 `HistoryDrawer` 组件，作为右侧滑出抽屉面板，复用于所有 10 个工具。

### Design Direction (Frontend Design Skill)

**美学风格**: 延续现有 dark theme — 但 History Drawer 采用略微不同的表面层级来暗示"时间线"概念。使用垂直时间线元素连接历史卡片，卡片左侧有微小的时间节点圆点（cyan accent）。整体以 editorial/magazine 为灵感，简洁但有层次。

**Typography**: 继续使用 `.rounded` design font，时间戳使用 `.monospaced` 小字号。

**Motion**: 抽屉从右侧弹性滑入（`spring` animation），卡片列表使用交错动画（staggered reveal）。hover 状态有微妙的亮度提升。

**Layout**: 固定宽度 380pt 右侧抽屉，overlay 在工具内容之上。顶部：标题 + 关闭按钮 + 清空按钮。中部：可滚动历史卡片列表。底部：统计信息。

### Changes Required:

#### 1. 新建 HistoryDrawer 组件
**File**: `Sources/CodeToolCore/HistoryDrawer.swift` (新文件)
**Changes**: 通用抽屉面板 + 历史卡片

```swift
// HistoryDrawer.swift — 通用历史抽屉面板
//
// 使用方式:
//   HistoryDrawer(
//       isPresented: $showHistory,
//       title: "Chat History",
//       items: chatHistoryItems,
//       onSelect: { item in /* 恢复到工具 */ },
//       onDelete: { item in /* 删除单条 */ },
//       onClearAll: { /* 清空全部 */ }
//   )
```

组件结构：

```
HistoryDrawer<Item: HistoryDrawerItem>
├── Header (title + item count badge + close button)
├── Action bar (Clear All button)
├── ScrollView
│   └── LazyVStack (时间线样式)
│       └── HistoryCard (per item)
│           ├── 时间节点圆点 (left)
│           ├── 时间戳 (relative, e.g. "2 min ago")
│           ├── 标题 (primary line, e.g. prompt 首 60 字符)
│           ├── 副标题 (secondary info, e.g. "1:1 · 2 images")
│           ├── 操作按钮 (Load + Delete)
│           └── 时间线连接竖线
└── Footer (total count + storage hint)
```

#### 2. HistoryDrawerItem Protocol
**File**: `Sources/CodeToolCore/HistoryDrawer.swift` (同文件)

```swift
/// Protocol for items displayed in the HistoryDrawer.
public protocol HistoryDrawerItem: Identifiable {
    var id: UUID { get }
    var drawerTitle: String { get }        // 主标题（如 prompt 前 60 字符）
    var drawerSubtitle: String { get }     // 副信息（如 "1:1 · 2 images" 或 "format · 1.2KB"）
    var drawerTimestamp: Date { get }       // 创建时间
    var drawerIcon: String { get }          // SF Symbol name
}
```

#### 3. 为所有 10 个 HistoryRecord 类型添加 HistoryDrawerItem conformance
**File**: `Sources/CodeToolCore/HistoryStore.swift` 底部或单独 extension 文件

每个 record 类型实现 `HistoryDrawerItem`：

| Record Type | drawerTitle | drawerSubtitle | drawerIcon |
|---|---|---|---|
| ChatHistoryRecord | 最后一条 user message 前 60 字 | "\(messages.count) messages · ~\(totalTokens) tokens" | "bubble.left.and.bubble.right" |
| SpeechHistoryRecord | inputText 前 60 字 | "\(voice) · \(outputFormat) · \(durationMs/1000)s" | "waveform" |
| ImageHistoryRecord | prompt 前 60 字 | "\(aspectRatio) · \(imageCount) image(s)" | "photo.artframe" |
| MusicHistoryRecord | prompt 前 60 字 | "\(isInstrumental ? "Instrumental" : "Vocal") · \(outputFormat)" | "music.note" |
| JSONToolHistoryRecord | inputText 前 60 字 | "\(operation) · \(stats)" | "curlybraces" |
| ImageConverterHistoryRecord | imageInfo 前 60 字（或 "Base64 conversion"） | mode 的中文/英文描述 | "photo" |
| JSONDiffHistoryRecord | "Diff: \(totalDiffs) differences" | "+\(added) −\(removed) ≠\(modified)" | "arrow.left.arrow.right" |
| TimestampHistoryRecord | inputValue | "\(direction) → \(resultISO8601)" | "clock" |
| JWTHistoryRecord | payloadJSON 前 60 字 | "\(mode) · \(expirationInfo)" | "key" |
| WordCloudHistoryRecord | inputPreview 前 60 字 | "\(topWords 中的第一个词) · \(maxWords) words max" | "cloud" |

Drawer 卡片只负责展示预览，不承担“存储截断”的职责。所有标题/副标题截断逻辑在 `HistoryDrawerItem` 计算属性中完成。

### Success Criteria:

#### Automated Verification:
- [x] `swift build` 编译通过
- [ ] HistoryDrawer 可以在任意 View 中嵌入而不崩溃
- [ ] 如当前环境具备 XCTest，则补充针对空状态和基本 item 渲染的单元测试；否则记录为环境受限未执行

#### Manual Verification:
- [ ] 抽屉从右侧滑入时有弹性动画
- [ ] 历史卡片有时间线样式（左侧圆点 + 竖线）
- [ ] 空状态显示友好提示（"No history yet"）
- [ ] 关闭按钮和清空按钮可正常交互
- [ ] 部分历史记录损坏时，抽屉仍能显示可读记录，并给出非阻塞提示

---

## Phase 3: AI Tools — Wire Up History Drawer

### Overview
为 4 个 AI 工具接入 HistoryDrawer，利用已有的历史数据。

### Changes Required:

#### 1. AIChatView — 接入历史
**File**: `Sources/CodeToolCore/AIChatView.swift`
**Changes**:

新增 state:
```swift
@State private var showHistory = false
@State private var chatHistory: [ChatHistoryRecord] = []
```

在 ToolWorkbench 的 actions 区域添加 History 按钮：
```swift
StyledButton("History", systemImage: "clock.arrow.circlepath", variant: .secondary) {
    loadHistory()
    showHistory = true
}
```

添加 HistoryDrawer overlay：
```swift
.overlay(alignment: .trailing) {
    if showHistory {
        HistoryDrawer(
            isPresented: $showHistory,
            title: "Chat History",
            items: chatHistory,
            onSelect: { record in restoreChat(record) },
            onDelete: { record in deleteChat(record) },
            onClearAll: { clearChatHistory() }
        )
    }
}
```

回放逻辑 `restoreChat(_:)`:
- 清空当前 messages
- 恢复 systemPrompt
- 恢复 messages 数组
- 恢复 token 计数
- 关闭抽屉

#### 2. AISpeechView — 接入历史
**File**: `Sources/CodeToolCore/AISpeechView.swift`
**Changes**: 同模式

回放逻辑 `restoreSpeech(_:)`:
- 恢复 inputText
- 恢复 selectedVoice, speed, volume, pitch, outputFormat
- 尝试加载 audioData（通过 `HistoryStore.shared.loadData(category: .speech, fileName:)`）
- 若音频文件缺失，仅恢复文本和参数，并显示 warning banner

#### 3. AIImageView — 接入历史
**File**: `Sources/CodeToolCore/AIImageView.swift`
**Changes**: 同模式

回放逻辑 `restoreImage(_:)`:
- 恢复 promptText, aspectRatio, imageCount
- 尝试加载图片（通过 HistoryStore.loadData 加载每个 imageFileName）
- 若任一图片缺失，仍恢复 prompt 与参数，并显示 warning banner

#### 4. AIMusicView — 接入历史
**File**: `Sources/CodeToolCore/AIMusicView.swift`
**Changes**: 同模式

回放逻辑 `restoreMusic(_:)`:
- 恢复 promptText, lyricsText, isInstrumental, outputFormat, sampleRate, bitrate
- 尝试加载 audioData
- 若音频文件缺失，仅恢复文本和参数，并显示 warning banner

### Success Criteria:

#### Automated Verification:
- [x] `swift build` 编译通过
- [x] 不破坏现有 AI 工具的保存行为
- [ ] 如当前环境具备 XCTest，则运行 `swift test --filter CodeToolTests`；否则记录为环境受限未执行

#### Manual Verification:
- [ ] 每个 AI 工具 header 出现 "History" 按钮
- [ ] 点击 History 按钮后右侧抽屉滑出
- [ ] 历史列表按时间倒序显示
- [ ] 点击历史记录可恢复输入参数
- [ ] AI Chat 恢复后可看到之前的对话
- [ ] AI Speech/Image/Music 恢复后可加载之前的媒体文件
- [ ] 附件缺失时不会崩溃，且会保留可恢复的文本参数
- [ ] 删除单条记录后列表刷新
- [ ] 清空全部后列表为空

---

## Phase 4: Dev Tools — Add Save Logic & Wire Up History Drawer

### Overview
为 6 个 Dev 工具添加历史保存逻辑并接入 HistoryDrawer。

### Changes Required:

#### 1. JSONToolView — 添加历史
**File**: `Sources/CodeToolCore/JSONToolView.swift`
**Changes**:

保存时机：每次 `formatJSON()`, `minifyJSON()`, `validateJSON()` 成功执行后保存。

```swift
private func saveToHistory(operation: String) {
    let record = JSONToolHistoryRecord(
        id: UUID(),
        createdAt: Date(),
        operation: operation,
        inputText: inputText,
        outputText: outputText,
        stats: stats
    )
    Task { try? await HistoryStore.shared.save(record) }
}
```

回放逻辑：恢复 `inputText` → 用户可手动重新执行操作。

#### 2. ImageConverterView — 添加历史
**File**: `Sources/CodeToolCore/ImageConverterView.swift`
**Changes**:

保存时机：成功转换后（Image→Base64 或 Base64→Image）。
Image 数据通过 `imageData` 参数保存到 HistoryStore。

记录策略：
- `imageToBase64`：保存关联图片二进制文件；`base64Text` 可留空，`base64Preview` 保存前 500 字符用于详情预览
- `base64ToImage`：保存完整 `base64Text` 以保证可回放；若成功解码图片，则同时保存关联图片文件用于预览
- `imageFileName` 使用 `"\(id.uuidString)-image.png"` 一类的稳定命名，或删除时按 record 中显式文件名精确移除

回放逻辑：恢复 mode + base64Text（如果有），尝试加载关联图片。

#### 3. JSONDiffView — 添加历史
**File**: `Sources/CodeToolCore/JSONDiffView.swift`
**Changes**:

保存时机：`compare()` 成功执行后。

回放逻辑：恢复 leftText + rightText → 用户可重新执行 compare。

#### 4. TimestampConverterView — 添加历史
**File**: `Sources/CodeToolCore/TimestampConverterView.swift`
**Changes**:

保存时机：
- `timestampToDate`：用户在输入框完成一次有效输入，或主动点击 `Capture Now` / `Now` 按钮后保存
- `dateToTimestamp`：用户修改 `DatePicker` 后，经 debounce 且与最近一次保存值不同再保存
- 定时器驱动的 `currentTimestamp` 自动刷新不保存

回放逻辑：
- `timestampToDate`：恢复 `timestampInput`
- `dateToTimestamp`：通过 `selectedDateISO8601` 恢复 `selectedDate`

#### 5. JWTToolView — 添加历史
**File**: `Sources/CodeToolCore/JWTToolView.swift`
**Changes**:

保存时机：`decodeJWT()` 或 `encodeJWT()` 成功后。

回放逻辑：decode 模式恢复 jwtInput，encode 模式恢复 encodeHeader + encodePayload。

#### 6. WordCloudView — 添加历史
**File**: `Sources/CodeToolCore/WordCloudView.swift`
**Changes**:

保存时机：`generateWordCloud()` 成功后。

回放逻辑：恢复 inputText + minWordLength + maxWords + ignoreStopWords。

记录策略：`inputText` 保存完整值用于回放，`inputPreview` 保存前 2000 字符用于列表和详情预览。

### Success Criteria:

#### Automated Verification:
- [x] `swift build` 编译通过
- [x] 不破坏现有功能
- [ ] 如当前环境具备 XCTest，则运行 `swift test --filter CodeToolTests`；否则记录为环境受限未执行

#### Manual Verification:
- [ ] 每个 Dev 工具 header 出现 "History" 按钮
- [ ] 执行操作后新增一条历史记录
- [ ] 历史列表正确显示操作信息
- [ ] 点击历史记录可恢复输入参数
- [ ] JSON Tool 恢复后显示操作类型 badge
- [ ] Image Converter 恢复后加载关联图片
- [ ] JSON Diff 恢复后可重新对比
- [ ] Timestamp 恢复后显示正确时间
- [ ] JWT 恢复后根据 mode 恢复到正确视图
- [ ] Word Cloud 恢复后显示参数设置
- [ ] Image Converter 删除记录后不会遗留孤儿图片文件
- [ ] 大输入文本仍可完整回放，而不是只恢复预览截断内容

---

## Testing Strategy

### Unit Tests
新增测试用例到 `Tests/CodeToolTests/CodeToolTests.swift`:

1. **HistoryCategory 测试**: 验证新增的 6 个 category rawValue 正确
2. **Dev Tool Record 编码/解码测试**: 每个新 record 类型的 JSON round-trip
3. **HistoryStore save/list/delete 测试**: 针对新 category 的 CRUD（使用 `setBaseURLForTesting`）
4. **HistoryDrawerItem conformance 测试**: 验证每个 record 类型的 drawerTitle/drawerSubtitle 非空
5. **坏记录容错测试**: 在某个 category 目录放入损坏 JSON，验证其余记录仍可被列出
6. **Image Converter 附件清理测试**: 删除记录后，JSON 和关联图片文件都被移除

### CLI Verification
- 必做：`swift build`
- 条件执行：`swift test --filter CodeToolTests` 仅在当前机器具备完整 Xcode / XCTest 环境时执行
- 若测试因 `no such module XCTest` 失败，应在验证记录中明确标注为环境限制，而不是实现缺陷

### Manual Testing Steps:
1. 打开每个工具，执行一次操作，确认 History 按钮出现
2. 点击 History 按钮，确认抽屉打开
3. 操作后确认新记录出现在列表中
4. 点击记录确认回放正确
5. 删除单条记录后确认已移除
6. 清空全部后确认列表为空
7. 人工删除一条关联音频或图片文件，再点击回放，确认工具不会崩溃且能显示 warning
8. 在 history 目录手工放入一个损坏 JSON 文件，确认同类其他记录仍能显示
9. 退出并重启应用，确认历史数据持久化

## Performance Considerations

- `loadRecords` 使用 `loadRecords<T>` 泛型方法，一次读取所有 JSON 文件。对于大量历史记录（>1000 条），可能需要后续优化为分页加载
- Drawer 的标题和副标题在展示层动态截断；为保证可回放，Dev 工具的核心输入字段不做持久化截断
- Image Converter 在 `imageToBase64` 模式下避免同时保存完整 Base64 和完整图片二进制，优先保存图片文件和短预览；只有 `base64ToImage` 才保存完整 Base64 输入
- HistoryDrawer 使用 `LazyVStack` 延迟渲染，大列表滚动性能好
- 历史读取采用“跳过坏文件”策略，避免单个损坏记录放大成整类历史不可用的问题

## File Change Summary

| File | Action | Description |
|------|--------|-------------|
| `Sources/CodeToolCore/HistoryStore.swift` | MODIFY | 扩展 HistoryCategory + 6 个新 record 类型 + save/list/delete 方法 |
| `Sources/CodeToolCore/HistoryDrawer.swift` | NEW | 通用历史抽屉组件 + HistoryDrawerItem protocol |
| `Sources/CodeToolCore/AIChatView.swift` | MODIFY | 添加 History 按钮 + HistoryDrawer + restoreChat |
| `Sources/CodeToolCore/AISpeechView.swift` | MODIFY | 添加 History 按钮 + HistoryDrawer + restoreSpeech |
| `Sources/CodeToolCore/AIImageView.swift` | MODIFY | 添加 History 按钮 + HistoryDrawer + restoreImage |
| `Sources/CodeToolCore/AIMusicView.swift` | MODIFY | 添加 History 按钮 + HistoryDrawer + restoreMusic |
| `Sources/CodeToolCore/JSONToolView.swift` | MODIFY | 添加保存逻辑 + History 按钮 + HistoryDrawer |
| `Sources/CodeToolCore/ImageConverterView.swift` | MODIFY | 添加保存逻辑 + History 按钮 + HistoryDrawer |
| `Sources/CodeToolCore/JSONDiffView.swift` | MODIFY | 添加保存逻辑 + History 按钮 + HistoryDrawer |
| `Sources/CodeToolCore/TimestampConverterView.swift` | MODIFY | 添加保存逻辑 + History 按钮 + HistoryDrawer |
| `Sources/CodeToolCore/JWTToolView.swift` | MODIFY | 添加保存逻辑 + History 按钮 + HistoryDrawer |
| `Sources/CodeToolCore/WordCloudView.swift` | MODIFY | 添加保存逻辑 + History 按钮 + HistoryDrawer |
| `Tests/CodeToolTests/CodeToolTests.swift` | MODIFY | 新增 Dev record round-trip 测试 + HistoryStore CRUD 测试 |

## References

- Tool Registry: `Sources/CodeToolCore/Tool.swift:30-64` (ToolRegistry.defaults — 10 tools)
- History Store: `Sources/CodeToolCore/HistoryStore.swift:81-245` (actor, JSON file persistence + current category/delete behavior)
- UI Shell: `Sources/CodeToolCore/ToolWorkbench.swift:13-109` (header + actions + content)
- Shared Components: `Sources/CodeToolCore/StyledComponents.swift`
- Theme: `Sources/CodeToolCore/Theme.swift` (AppTheme tokens)
- AI history save points: `AIChatView.swift:343-356`, `AISpeechView.swift:332-349`, `AIImageView.swift:367-381`, `AIMusicView.swift:360-375`
- Dev tool current state: `JSONToolView.swift:1-235`, `ImageConverterView.swift:1-338`, `JSONDiffView.swift:1-318`, `TimestampConverterView.swift:1-191`, `JWTToolView.swift:1-420`, `WordCloudView.swift:1-382`
- Copilot Instructions: `.github/copilot-instructions.md:5-8` (CLI verification constraints)
