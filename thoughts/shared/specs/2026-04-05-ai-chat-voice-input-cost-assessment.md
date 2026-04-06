---
date: 2026-04-05T23:23:11+08:00
researcher: zhang
git_commit: a310c816b38bc3c4a9bf8b9baf188f9205492816
branch: main
topic: "AI Chat Voice Input Cost Assessment"
tags: [research-spec, requirements, ai-chat, voice-input, speech-to-text]
status: complete
confidence: medium
last_updated: 2026-04-05
last_updated_by: zhang
---

# AI Chat Voice Input Cost Assessment

## Summary

为 AI Chat 增加语音输入，最小可行版本是“按按钮录音，停止后转写成文本并回填到输入框”。在当前代码库里，这不是局部 UI 改动，而是新增一条完整的输入链路：麦克风采集、权限、录音状态、转写 provider、错误处理、以及跨聊天入口的共享抽象。

## Background

### 现状

当前 AI Chat 的输入是纯文本 composer：
- 主路由把 `.aiChat` 指向 [ClaudeChatView](../../Sources/CodeToolCore/Views/ContentView.swift#L15)
- 输入区域在 [ClaudeChatView](../../Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift#L669)
- 文本编辑和快捷键处理在 [ClaudeChatComposer](../../Sources/CodeToolCore/Views/Shared/ClaudeChatComposer.swift#L1)

仓库里没有找到麦克风采集、录音、系统 Speech 识别、或者语音输入权限的现成实现；现有音频能力主要是 AI Speech / AI Music 的播放与 TTS，不是输入侧能力。

### 这次需求的边界

用户指定的目标是：
- 按按钮录音转写，不做连续监听或语音唤醒
- 支持配置项切换
- 云端转写先接 ElevenLabs Scribe V2 Realtime
- 目标是全局通用能力，不只挂在单一聊天页面

## Cost Estimate

### 结论

如果按你给的范围实现，成本属于中等偏高，不是低风险的小改动。

### 粗略工期

- 仅做“当前聊天页 + 单一云端转写 provider”的 MVP：约 2-4 个工作日
- 你现在指定的范围（全局通用、配置可切换、云端 + 本地两种方案、权限和测试）：约 1-2 周
- 如果再要求把转写结果、录音失败、取消、重试、以及多入口复用都做得比较完整：约 2-3 周

### 成本驱动因素

- 新增麦克风权限和录音生命周期管理
- 处理实时录音、停止录制、上传/流式转写的状态机
- 为 ElevenLabs Scribe V2 Realtime 单独做 provider 适配层
- 若保留本地 Speech 方案，还要再做一层系统框架适配和降级逻辑
- 你要求“全局通用能力”，这意味着不能只改一个 composer，而是要抽共享输入层
- 需要补测试：转写完成、失败、取消、权限拒绝、空结果、网络超时

### 哪些地方可以省成本

- 先只做“按住说话/点一下开始，点一下停止，然后回填文本”
- 先只实现云端转写，等体验确认后再补本地 Speech fallback
- 先把语音按钮做成当前聊天页可用，再抽共享能力到其他输入入口

## Goals

- 提供一个可点击的语音输入入口，把语音转成文本回填到聊天输入框
- 支持配置不同转写 provider
- 先接 ElevenLabs Scribe V2 Realtime 作为云端转写实现
- 让语音输入能力可以复用到多个聊天入口，而不是只绑定单个视图

## Non-goals

- 不做持续监听或唤醒词
- 不做语音指令控制 UI
- 不做端到端的实时同声字幕级体验，除非后续明确要求
- 不改现有聊天回复模型或消息历史结构

## Requirements

### Functional Requirements

- 用户可以从聊天输入区启动录音
- 用户可以停止录音并触发转写
- 转写结果会回填到当前输入框，并允许用户继续编辑后发送
- 支持在设置中选择转写 provider
- 支持云端转写 provider，首个实现为 ElevenLabs Scribe V2 Realtime
- 支持错误提示，包括权限拒绝、网络失败、转写失败、空结果
- 语音输入状态应在发起中、录音中、转写中、失败、完成等阶段可见

### Non-functional Requirements

- **性能**: 录音开始/停止反馈应接近即时；转写完成时间取决于音频长度和网络
- **安全**: 麦克风权限必须显式申请；API key / token 不应落日志
- **兼容性**: 不破坏现有文本输入、Enter 提交、图片粘贴等行为
- **可用性**: 失败后应保留录音前文本草稿，不丢失用户正在输入的内容

### Constraints

- 当前仓库没有现成的麦克风采集或 Speech 识别模块
- 当前 AI Chat 入口和 composer 是单一文本输入链路，语音功能需要额外抽象层
- 需要同时支持配置选择和全局复用，会增加 UI 与状态管理复杂度

### Assumptions

- 语音输入采用“录音结束后再转写”的模式，不做连续流式字幕
- ElevenLabs Scribe V2 Realtime 作为首个云端 provider
- 本地 Speech 方案若实现，主要作为可选 fallback，而不是默认唯一方案

## Edge Cases

| 场景 | 预期行为 |
| --- | --- |
| 用户拒绝麦克风权限 | 显示明确错误，并引导去系统设置授权 |
| 用户录到空音频 | 不发送请求，提示未捕获到有效语音 |
| 网络中断或 provider 超时 | 保留录音前输入内容，允许重试 |
| 转写返回空文本 | 不自动清空输入框，提示结果为空 |
| 用户在录音中切换聊天入口 | 录音状态必须被统一管理，避免悬挂 session |

## Dependencies

- AVFoundation / 麦克风权限
- 转写 provider API：ElevenLabs Scribe V2 Realtime
- 如果要做本地 fallback，还需要系统 Speech / ASR 相关框架
- 现有聊天输入视图抽象，尤其是 [ClaudeChatView](../../Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift#L669) 和 [ClaudeChatComposer](../../Sources/CodeToolCore/Views/Shared/ClaudeChatComposer.swift#L1)

## Acceptance Criteria

- [ ] 可以从聊天输入区开始和停止录音
- [ ] 录音完成后，文本成功回填到输入框
- [ ] 至少支持一个云端转写 provider，并可配置切换
- [ ] 权限拒绝、网络失败、转写失败都有明确反馈
- [ ] 现有文本输入和发送流程不被破坏
- [ ] 语音输入逻辑可被多个聊天入口复用，而不是只写死在单个视图里

## Success Metrics

- 录音开始到 UI 响应的时间低于 200ms 体感
- 常见正常场景下，转写成功率和用户手动输入相比没有明显摩擦
- 语音输入失败时，草稿不丢失率为 100%

## Open Questions

- [ ] 本地 Speech 方案是否必须和云端方案同一版本交付，还是可以分阶段上线
- [ ] 配置项是“每个 provider 单独配置”还是“全局只选一个默认 provider”
- [ ] 是否要求转写过程中显示逐字回填，还是只在结束后一次性回填
- [ ] ElevenLabs 的认证方式和错误码是否已经确定
