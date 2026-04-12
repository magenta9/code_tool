---
date: 2026-04-12T18:40:04+08:00
researcher: zhang
git_commit: 7c902e0a9480084628bb19fce60828213c439b72
branch: main
topic: "MiniMax CLI Migration"
tags: [research-spec, requirements, minimax, cli, ai-speech, ai-image, ai-music]
status: complete
confidence: medium
last_updated: 2026-04-12
last_updated_by: zhang
---

# MiniMax CLI Migration Research Spec

## Summary

将当前仍直连 MiniMax HTTP/WebSocket 的能力切换到本地 `mmx` CLI，统一以 CLI 安装与认证状态为准，覆盖当前用户可见的 AI Speech / AI Image / AI Music 与 MiniMax 设置页，并顺手将遗留的 `MiniMaxChatExecutionProvider` 改为走 CLI，但不重新暴露新的 MiniMax Chat UI。

## Background

### 当前行为

仓库里与 MiniMax 相关的活跃路径分成两类：

1. **用户可见路径**
   - `AISpeechView` 直接调用 `MiniMaxAPIClient.shared.textToSpeechStream(...)`
   - `AIImageView` 直接调用 `MiniMaxAPIClient.shared.generateImage(...)`
   - `AIMusicView` 直接调用 `MiniMaxAPIClient.shared.generateMusic(...)`
   - `MiniMaxSettingsView` 通过 `chatCompletion("Hi")` 做 API 连通性测试
2. **遗留但仍存在的基础设施路径**
   - `MiniMaxChatExecutionProvider` 仍通过 `MiniMaxAPIClient.shared.chatCompletionStream(...)` 适配 `.chat` 执行请求

而可见的 **AI Chat** 已经切到 `ClaudeChatView`，并走 `ClaudeCLIClient` 的本地 CLI 子进程模式；当前仓库不存在用户可见的 MiniMax Chat 界面。

### 现状痛点

- MiniMax 集成仍是 API Key + Base URL + 各模型字段的 **HTTP/WebSocket 直连模型**
- 设置页与错误提示仍围绕“MiniMax API”而不是“MiniMax CLI”
- 需要同时维护直连 API 与本地 CLI 两套思路，心智负担高
- README 还没有说明 `mmx` 的安装、认证、以及本 app 对它的依赖
- 部分当前 UI 暴露的高级参数（如 image seed / prompt optimizer、speech volume / pitch、music sample rate / bitrate）在上游 README_CN 中**未被明确展示**

### 已确认的决策

- **切换范围**：覆盖当前活跃的 MiniMax 能力（至少包含 AI Speech / AI Image / AI Music / 设置页检查）
- **失败策略**：`mmx` 不可用时**不回退 HTTP**
- **配置权威**：以 `mmx` CLI 的安装与认证状态为权威，app 不再以 API Key / Base URL 为主路径
- **README 深度**：只补充本 app 所需的安装与使用说明，并链接上游 MiniMax CLI 文档
- **功能对齐策略**：第一版只承诺保留“README_CN 明确或可直接验证”的 CLI 能力；不猜 undocumented flags
- **设置迁移方式**：保留 “MiniMax” 设置入口，但内容改为 “MiniMax CLI” 导向
- **遗留 chat 执行层**：顺手迁到 CLI，但不新增用户可见 MiniMax Chat 路由

## Goals

- 将当前活跃的 MiniMax 请求从直连 API 切换为本地 `mmx` CLI 子进程
- 将 MiniMax 设置页从 API 配置页改为 CLI 配置与状态页
- 统一安装、认证、错误处理与用户引导
- 在 README 中补齐 `mmx` 安装、认证、app 内使用前提与上游文档链接
- 保持历史记录与已有数据可读，不因配置模型变化而破坏旧记录恢复
- 让遗留 `MiniMaxChatExecutionProvider` 也走 CLI，避免仓库继续保留双栈 MiniMax 传输层

## Non-goals

- 不把 AI Chat 从 Claude CLI 改回 MiniMax，也不新增新的 MiniMax Chat UI
- 不保留自动或隐式的 MiniMax HTTP 回退链路
- 不保证保留所有当前 UI 中的高级参数；对于上游文档未明确或实现中未验证的参数，允许降级或隐藏
- 不在本次需求中支持 README_CN 未明确覆盖的新 MiniMax 能力（如视频、vision、search UI）
- 不要求 app 自动安装 `mmx-cli`

## Requirements

### Functional Requirements

#### FR1: 新增 MiniMax CLI 传输层

新增 MiniMax CLI 客户端与设置存储，形态参考当前 `ClaudeCLIClient` / `ClaudeCLISettingsStore`：

- 通过 `Process` 启动本地 `mmx` 二进制
- 负责 CLI 路径发现、参数拼装、stdout/stderr 读取、退出码判断、取消/中断
- 统一返回结构化结果，供 Speech / Image / Music / 遗留 Chat 执行层调用

建议新增或重构的核心类型：

- `MiniMaxCLISettingsStore`
- `MiniMaxCLIClient`
- 面向具体能力的请求/结果模型（text/image/speech/music）

#### FR2: MiniMax 设置页改造成 CLI 设置页

保留设置入口标题 **MiniMax**，但界面语义改成 **MiniMax CLI**：

- 显示 `mmx` 路径发现结果
- 提供可选的显式 CLI 路径覆盖
- 提供认证状态检查
- 明确提示安装方式：`npm install -g mmx-cli`
- 明确提示认证方式：`mmx auth login --api-key ...` 或 OAuth 登录
- 使用 `mmx auth status` 作为认证状态权威检查方式

以下旧设置不再作为活跃链路配置项：

- API Key
- Base URL
- 以 app 内 UserDefaults 为主的 per-tool 模型字段

如果需要保留旧值，只能作为迁移兼容数据存在，**不能继续驱动运行时请求**。

#### FR3: CLI 可执行文件发现与可用性检查

MiniMax CLI 发现逻辑应与 Claude CLI 一致地具备“自动发现 + 手动覆盖”两层：

搜索顺序建议为：

1. 用户手动指定路径
2. `/opt/homebrew/bin/mmx`
3. `/usr/local/bin/mmx`
4. `~/.local/bin/mmx`
5. 通过 `/usr/bin/which mmx` 查找

当 CLI 不存在时：

- 设置页显示清晰安装引导
- AI Speech / AI Image / AI Music 入口给出明确错误提示
- 不回退到 `MiniMaxAPIClient`

#### FR4: 认证与连通性检查改为 CLI 语义

原来的 “Test Connection” 不再发送 MiniMax Chat API 请求，而改为 CLI 语义的检查：

- `mmx auth status` 用于认证状态检查
- 需要明确区分三类失败：
  - CLI 未安装
  - CLI 已安装但未认证/认证失效
  - CLI 已安装且已认证，但命令执行失败

设置页文案与状态标识需围绕以上三种状态设计。

#### FR5: AI Speech 切换到 mmx CLI

`AISpeechView` 不再调用 `MiniMaxAPIClient.textToSpeechStream`，改为调用 CLI 层。

第一版只承诺保留 README_CN 明确示例或容易验证的能力：

- 输入文本
- voice
- speed
- `--stream` 或等价的 CLI 流式能力（若可稳定接入）
- 生成后的播放与历史保存

当前 UI 中的以下能力若没有可靠 CLI 对应参数，可在第一版降级或隐藏：

- volume
- pitch
- 自定义 output format（若 CLI 仅稳定支持特定输出）

如果 CLI 的稳定实现更适合“完整文件完成后再播放”，允许在规范中接受该降级，但前提是仍然走 CLI 且 UX 文案明确。

#### FR6: AI Image 切换到 mmx CLI

`AIImageView` 不再调用 `MiniMaxAPIClient.generateImage`，改为调用 CLI 层。

第一版优先保留以下明确能力：

- prompt
- image count（若 CLI 参数可验证）
- aspect ratio（若 CLI 参数可验证）
- 输出图像保存与历史恢复

当前 UI 中的以下能力需要“文档明确或实现验证”后才可保留，否则应隐藏/降级：

- reference-guided / subject reference images
- seed
- prompt optimizer
- 自定义 width / height（如果 CLI 只稳定支持 aspect ratio）

若参考图能力在 CLI 中没有明确入口，则 v1 允许只保留文本生图主路径。

#### FR7: AI Music 切换到 mmx CLI

`AIMusicView` 不再调用 `MiniMaxAPIClient.generateMusic` / `downloadAudio`，改为调用 CLI 层。

第一版优先保留以下明确能力：

- prompt
- lyrics
- `lyrics-optimizer`
- instrumental
- 音频输出文件落盘 / 导入播放器 / 历史保存

以下当前参数若 CLI 未明确支持，可在第一版隐藏或降级：

- output format 自定义
- sample rate
- bitrate

如果 CLI 生成行为天然是文件导向，app 应围绕临时输出文件或受控缓存目录设计，而不是继续假设 HTTP 下载 URL。

#### FR8: 遗留 MiniMax Chat 执行层迁到 CLI

`MiniMaxChatExecutionProvider` 需从 HTTP API 流式调用切换为 `mmx text chat` 或等价 CLI 命令：

- 保持 `.chat` 执行接口不变
- 继续支持系统提示词、消息拼装和结果 metadata
- 不新增新的 UI 入口
- 测试和实现应明确：它是**基础设施迁移**，不是产品层重新启用 MiniMax Chat

如果 CLI 无法提供当前 HTTP 路径同级别的 token 统计，则允许保留估算值或最小可用 metadata，但需要在实现说明中明确差异。

#### FR9: 历史记录与兼容性

当前历史模型包括：

- `SpeechHistoryRecord`
- `ImageHistoryRecord`
- `MusicHistoryRecord`
- `ChatHistoryRecord`

迁移后需满足：

- 新纪录仍能保存并恢复
- 旧纪录仍可读取
- 即使某些参数在新 UI 中被隐藏，历史展示也不能崩
- 若模型来源从 app 配置切换为 CLI 默认值，历史记录可以继续按“当时执行时的 resolved model / command metadata”保存

#### FR10: README 更新

README 需要新增面向 app 用户的 MiniMax CLI 使用说明，至少包括：

1. 安装 `mmx-cli` 的前提（Node.js 18+）
2. 安装命令
3. 认证命令
4. `mmx auth status` 检查方式
5. 本 app 中哪些功能依赖 `mmx`
6. 出现 “CLI 未安装 / 未认证” 时的处理方向
7. 上游 MiniMax CLI README_CN 链接

README 不需要搬运完整命令参考，只需覆盖 app 相关前置条件与常见使用路径。

### Non-functional Requirements

- **性能**：CLI 冷启动可接受，但不应引入 UI 卡死；所有命令执行必须异步处理
- **可靠性**：退出码、stderr、stdout 缺失、路径错误都要有明确错误语义
- **安全**：不在日志中输出用户敏感文本、认证凭据；避免继续把 API Key 当主配置保存在 app 内
- **兼容性**：保持现有历史记录兼容；不破坏 Claude CLI 现有路径
- **可维护性**：MiniMax 不再同时维持“活跃 HTTP 链路 + CLI 链路”；HTTP client 可保留过渡期测试价值，但不应继续作为活跃实现源

### Constraints

- 只能基于本地已安装的 `mmx` CLI 工作
- 第一版以上游 README_CN 明确可见的 CLI 用法为准，不猜测 undocumented flags
- 当前仓库的 AI Speech / AI Image / AI Music 直接在 view 层调用 MiniMax API，因此迁移需要跨 view / settings / tests / docs / persistence 多处联动
- AI Chat 的可见路由仍是 Claude CLI，本次不能破坏该现状

### Assumptions

- `mmx-cli` 在目标环境可通过 `npm install -g mmx-cli` 获得
- `mmx auth status` 可稳定作为认证状态检查的权威命令
- `mmx` 对 text/image/speech/music 的基本命令在本地 CLI 环境中可直接执行
- CLI 输出模式足以支撑 app 的最小可用结果提取；对于不能稳定映射的高级参数，允许第一版缩减

## Current Behavior Summary

### MiniMax 当前数据流

#### Speech

`AISpeechView.generateSpeech()`：

- 从 UI 收集 text / voice / speed / volume / pitch / format
- 调用 `MiniMaxAPIClient.textToSpeechStream(...)`
- 流式接收音频 chunk
- 完成后保存 `SpeechHistoryRecord`

#### Image

`AIImageView.generateImages()`：

- 构建 `MiniMaxImageGenerationRequest`
- 支持 prompt、aspect ratio / custom size、imageCount、seed、promptOptimizer、reference images
- 调用 `MiniMaxAPIClient.generateImage(request:)`
- 将返回的 base64 image data 持久化为 `ImageHistoryRecord`

#### Music

`AIMusicView.generateMusic()`：

- 收集 prompt / lyrics / instrumental / format / sampleRate / bitrate
- 调用 `MiniMaxAPIClient.generateMusic(...)`
- 如果返回 URL，再继续 `downloadAudio(...)`
- 保存 `MusicHistoryRecord`

#### Settings

`MiniMaxSettingsView`：

- 围绕 API Key / Base URL / per-tool model 配置
- 用 chat API 请求 “Hi” 做连接测试

#### Legacy Chat Execution

`MiniMaxChatExecutionProvider`：

- 将 `.chat` payload 转成 MiniMax HTTP chat messages
- 调用 `chatCompletionStream(...)`
- 产出执行层 metadata

## Proposed Design

### Architecture

建议形成以下新结构：

```text
Views/
  AITools/
    AISpeechView.swift       -> 调 MiniMaxCLI layer
    AIImageView.swift        -> 调 MiniMaxCLI layer
    AIMusicView.swift        -> 调 MiniMaxCLI layer
Providers/
  MiniMax/
    MiniMaxCLIClient.swift
    MiniMaxCLISettingsStore.swift
    MiniMaxCLISettingsView.swift   (或改造现有 MiniMaxSettingsView)
Execution/
  MiniMaxChatExecutionProvider.swift -> 改调 CLI
Persistence/
  HistoryStore.swift         -> 保持兼容，必要时扩展 metadata
Docs/
  README.md
Tests/
  CodeToolTests+MiniMax.swift
  AIExecutionSessionTests.swift
  可能新增 MiniMax CLI 参数/事件解析测试
```

### Command Strategy

不同能力通过各自 `mmx` 子命令执行：

- Text: `mmx text chat ...`
- Image: `mmx image ...`
- Speech: `mmx speech synthesize ...`
- Music: `mmx music generate ...`

统一约束：

- `MiniMaxCLIClient` 负责 cwd、env、stdout/stderr、退出码、临时文件管理
- 每次请求一个独立子进程
- 所有调用都带 reference ID 进入日志上下文
- 不再拼接 HTTP URL、不再手动构造 Authorization header、不再在 app 内认定 Base URL

### Settings Strategy

设置页只保留与 CLI 直接相关的内容：

- `mmx` binary path（可选覆盖）
- CLI detected / missing 状态
- auth status
- 简洁的安装与认证提示

对于“模型”：

- 只有在 CLI 文档或实现验证后，才保留对应模型选择项
- 若 CLI 主要依赖全局 config，则 app 应显示“follow CLI config”而不是维护旧的 per-tool 模型输入框

### Feature-Subset Strategy

本需求明确接受“先收敛到 CLI 明确支持的能力子集”：

- Speech：优先保 text / voice / speed
- Image：优先保 text-to-image 主路径；reference / seed / optimizer 视 CLI 能力决定
- Music：优先保 prompt / lyrics / instrumental
- Legacy Chat execution：迁到 CLI，但不作为产品功能扩张

## Edge Cases

| 场景 | 预期行为 |
| --- | --- |
| 本机未安装 `mmx` | 设置页和工具页都显示安装指引；不回退 HTTP |
| `mmx` 已安装但未认证 | `mmx auth status` 失败后提示登录指引 |
| CLI 路径配置错误 | 明确提示路径无效，并引导恢复自动发现 |
| CLI stderr 有内容且退出非 0 | 将 stderr 摘要展示给用户，并保留 reference ID |
| CLI stdout 为空但退出 0 | 视为无效响应，给出结构化错误 |
| Speech 的流式模式无法稳定映射到 app 播放器 | 允许降级为“生成完成后播放”，但仍必须走 CLI |
| Image 的 reference-guided 在 CLI 中找不到明确入口 | 第一版隐藏该模式，保留文本生图主路径 |
| Music 的 sampleRate / bitrate 无明确 CLI 参数 | 第一版隐藏这些字段，使用 CLI 默认值 |
| 旧历史记录包含已下线参数 | 仍可读取与展示，不要求在新 UI 中继续编辑 |
| `MiniMaxChatExecutionProvider` 迁移后无可见 UI 覆盖 | 通过执行层测试验证，不新增产品入口 |

## Dependencies

- 本地 `mmx` 可执行文件
- Node.js 18+
- MiniMax CLI 认证状态
- 现有的 `HistoryStore` / `AppLogger` / `Diagnostics`
- 现有的 SwiftUI 工具页与 `ToolWorkbench` 共享组件
- 现有的 Claude CLI 集成模式（作为实现参考）

## Acceptance Criteria

- [ ] AI Speech / AI Image / AI Music 的活跃请求链路不再调用 `MiniMaxAPIClient.shared`
- [ ] MiniMax 设置页不再围绕 API Key / Base URL，而是围绕 `mmx` CLI 安装与认证状态
- [ ] `mmx auth status` 成为认证状态权威检查方式
- [ ] `mmx` 缺失或未认证时，app 给出明确安装/登录引导，且不回退 HTTP
- [ ] 遗留 `MiniMaxChatExecutionProvider` 改为通过 CLI 执行，但 AI Chat 的可见路由仍保持 Claude CLI
- [ ] 对 README_CN 未明确或未验证的高级参数，第一版可以安全隐藏/降级
- [ ] README 补充安装、认证、使用前提与上游文档链接
- [ ] 旧历史记录可继续读取；新历史记录可继续保存
- [ ] MiniMax 相关测试从“HTTP 请求体/响应解析”转向“CLI 命令拼装/输出解析/错误处理”
- [ ] `swift build` 与现有测试体系保持可通过

## Success Metrics

- MiniMax 在仓库中的活跃接入方式统一为本地 CLI，而不是继续双栈维护
- 用户能仅通过安装并认证 `mmx` 使用 Speech / Image / Music
- README 足以让新用户完成安装、登录和使用
- 迁移后错误场景更可解释：用户知道是“未安装”“未登录”还是“命令执行失败”

## Open Questions

- [ ] 需要在实现阶段确认 `mmx` 对 image reference / custom size / seed / prompt optimizer 的实际支持面；若无可靠参数，则按本 spec 隐藏这些能力
- [ ] 需要在实现阶段确认 `mmx speech synthesize --stream` 的 stdout 形式是否适合现有播放器；若不适合，则采用完成后播放的 CLI 方案
- [ ] 需要在实现阶段确认 `mmx` 是否暴露稳定的 per-feature model override；若无，则设置页仅展示“follow CLI config”
