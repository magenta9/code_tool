---
date: 2026-05-09T23:30:00+08:00
researcher: GitHub Copilot
git_commit: e0a7b39
branch: chore/update_schema
repository: magenta9/code_tool
topic: "React 工具工作台 UI 参考仓库调研"
tags: [research, ui, react, github, references]
status: complete
last_updated: 2026-05-09
last_updated_by: GitHub Copilot
---

# Research: React 工具工作台 UI 参考仓库调研

**Date**: 2026-05-09  
**Git Commit**: e0a7b39  
**Branch**: chore/update_schema

## Research Question

为 CodeTool 当前的 Electron + React 工具工作台界面寻找可参考的 GitHub 开源仓库，重点关注侧栏、主工作区、输入区/结果区、按钮风格、状态反馈和整体布局层级。

## Summary

这轮筛选优先保留了三类项目：

1. 桌面型 AI / developer workbench
2. 工具面板或多功能 utility app
3. 具备成熟 React UI 骨架、可直接借鉴 shell 和 panel layering 的项目

对 CodeTool 最有参考价值的不是“长得像”，而是下面这三个层面：

1. **桌面工作台骨架**：顶部、侧栏、主面板、次级面板如何减弱视觉噪音
2. **工具页内部结构**：输入区、结果区、状态条、动作按钮如何形成统一语言
3. **状态反馈密度**：加载中、执行中、失败、完成、只读、空状态如何不显得廉价

综合相似度和借鉴价值，优先看 **OpenCove、LobeHub、Jan、LibreChat、OxideTerm**。

---

## Selection Criteria

- 前端主实现基于 React 生态
- 产品形态接近工具工作台、AI workbench、developer utility 或 dashboard
- GitHub 仓库或公开说明能直接体现 UI 质量
- 更看重布局层级、信息密度和交互完成度，而非单纯技术栈
- 尽量避开纯组件库、纯 API 项目、只有营销页的仓库

---

## Priority Shortlist

### 1. OpenCove

- GitHub: https://github.com/DeadWaveWave/opencove
- Stack: Electron + React + TypeScript + electron-vite + @xyflow/react + xterm.js
- Why it matters:
  - 与 CodeTool 的桌面工作台形态最接近
  - 同时处理 agent、终端、笔记、任务与多工作区
- Best UI references:
  - 多工作区的整体组织方式
  - 高密度 panel 的层级控制
  - 搜索/控制中心与历史恢复入口
- Risk:
  - 画布化很强，不适合整套照搬

### 2. LobeHub

- GitHub: https://github.com/lobehub/lobehub
- Stack: Next.js + React + TypeScript
- Why it matters:
  - AI workbench 的成品度很高，适合学“精致感”而不是学功能量
- Best UI references:
  - 侧栏与二级导航层级
  - 高密度卡片和标签系统
  - 流式状态与结果反馈
  - 按钮主次与弱强调操作
- Risk:
  - AI 平台气质偏强，容易把 CodeTool 做得过重

### 3. Jan

- GitHub: https://github.com/janhq/jan
- Stack: Tauri + React + TypeScript + Tailwind + Radix UI + Zustand
- Why it matters:
  - 桌面应用感很强，适合参考设置、下载、引导、状态管理相关 UI
- Best UI references:
  - 桌面侧栏开合与分区
  - 设置页和模型管理页的表单节奏
  - 下载/安装中的 inline status
- Risk:
  - 聊天和模型管理占主轴，多工具场景参考面有限

### 4. LibreChat

- GitHub: https://github.com/danny-avila/LibreChat
- Stack: React + TypeScript + React Query + Recoil
- Why it matters:
  - 输入区、工具状态、附件、流式结果这些局部模式很成熟
- Best UI references:
  - Prompt 区附加操作的编排方式
  - Tool call / reasoning / attachment 的层次
  - 侧栏中的会话切换和信息收纳
- Risk:
  - 聊天产品范式较强，整体骨架不一定适合工具箱

### 5. OxideTerm

- GitHub: https://github.com/AnalyseDeCircuit/oxideterm
- Stack: Tauri + React + TypeScript + Vite + Tailwind + Zustand + xterm.js
- Why it matters:
  - 非常接近 developer power tool，适合参考诊断、状态、侧面板和多视图结构
- Best UI references:
  - 主区 + AI 侧栏的双面板结构
  - 状态提示、toast、重连、进度反馈
  - 强工具属性页面的视觉密度控制
- Risk:
  - 偏终端/SSH，不适合直接迁移整体视觉语言

---

## Full Candidate List

### OpenCove

- GitHub: https://github.com/DeadWaveWave/opencove
- Stack: Electron + React + TypeScript
- Why relevant:
  - 与 CodeTool 的“桌面工作台 + AI + 开发工具”方向最接近
  - 更适合借 shell 结构，而不是借某个单独页面
- Borrow:
  - 工作区骨架
  - 搜索和控制中心的入口位置
  - 多面板并置时的分层与留白
- Risk:
  - 过度 canvas 化可能削弱 CodeTool 的工具直达感

### LobeHub

- GitHub: https://github.com/lobehub/lobehub
- Stack: Next.js + React + TypeScript
- Why relevant:
  - 产品化程度高，适合参考 AI 工具工作台的精细感
- Borrow:
  - 标签、胶囊、按钮、切换器的层级
  - 面板头部动作区的排布
  - 列表和详情并存时的节奏控制
- Risk:
  - 设计语言偏完整平台，迁移时要做减法

### Jan

- GitHub: https://github.com/janhq/jan
- Stack: Tauri + React + TypeScript
- Why relevant:
  - 桌面应用语境下的高级感与稳重感很强
- Borrow:
  - Settings/Logs/Downloads 等系统页面
  - 首屏欢迎与空状态
  - 窗口应用的边框、表面层和按钮轻重关系
- Risk:
  - 偏模型应用，不是多工具箱

### LibreChat

- GitHub: https://github.com/danny-avila/LibreChat
- Stack: React + TypeScript
- Why relevant:
  - 输入和结果这两块做得成熟
- Borrow:
  - Prompt 区动作条
  - Response 区层级与内容分块
  - 运行中和异常状态的视觉处理
- Risk:
  - 容易把结果区做成聊天 transcript 风格

### OxideTerm

- GitHub: https://github.com/AnalyseDeCircuit/oxideterm
- Stack: React + TypeScript + Vite + Tailwind
- Why relevant:
  - 很适合做 developer-oriented utility 的壳层参考
- Borrow:
  - 多工具 panel 的切换方式
  - 日志、终端、状态反馈的组合方式
  - 更偏专业工具而非营销化的表面语言
- Risk:
  - 偏重型工具，不适合全部照搬到轻量 utility 页

### Langflow

- GitHub: https://github.com/langflow-ai/langflow
- Stack: React + TypeScript + Vite + @xyflow/react
- Why relevant:
  - 如果 CodeTool 后续要强化 agent/flow，可借它的三段式工作区
- Borrow:
  - 左栏组件库 + 主区 + 右配置面的经典工作台结构
  - 流程调试的状态反馈
  - 模板入口和空态设计
- Risk:
  - 图编辑器属性太强，当前 CodeTool 并不需要这么重

### Flowise

- GitHub: https://github.com/FlowiseAI/Flowise
- Stack: React 前端 + Node 后端
- Why relevant:
  - 适合参考 builder 与 run/test 之间的过渡状态
- Borrow:
  - 配置态/运行态切换
  - 多级导航和复杂工具的组织方式
- Risk:
  - 低代码 builder 味道重，不是当前 CodeTool 的核心方向

### Supabase Studio

- GitHub: https://github.com/supabase/supabase
- Focus path: apps/studio
- Stack: Next.js + React + Tailwind
- Why relevant:
  - 控制台类 UI 很成熟，适合参考后台式工作区的层级和稳定感
- Borrow:
  - 列表、详情、抽屉、设置页的一致性
  - 弱边框、轻表面、强结构的控制台语言
  - 空态、错误态、权限态的处理
- Risk:
  - 太偏管理后台，桌面 utility 味道不足

### ToolJet

- GitHub: https://github.com/ToolJet/ToolJet
- Stack: React + JavaScript/TypeScript
- Why relevant:
  - 适合参考“左导航 + 中央构建区 + 右属性面板”的工作台组织方式
- Borrow:
  - inspector 面板结构
  - 多级操作按钮和查询区的关系
  - 复杂工具视图下的信息归组
- Risk:
  - 低代码语义明显，视觉语言略旧

---

## CodeTool UI Recommendations

基于这批参考仓库，CodeTool 更适合走下面这条线，而不是继续当前的“单纯黑底 + 硬边框 + 生硬双栏”。

### 1. Shell 方向

- 参考 OpenCove / Jan
- 建议做法：
  - 顶部只保留低存在感窗口 chrome
  - 侧栏强调结构，不强调装饰
  - 主区用面板层级区分，而不是粗边框区分

### 2. Tool Page 方向

- 参考 LobeHub / LibreChat
- 建议做法：
  - 页面头部只保留标题、说明、主动作
  - 输入区和结果区头部动作并入 panel header
  - 用状态条、只读标签、空态替代额外的框中框

### 3. Developer Utility 方向

- 参考 OxideTerm / Supabase Studio
- 建议做法：
  - 诊断、日志、转换结果统一采用稳定的 code block / status strip 语言
  - 控件保持一致圆角和一致高度
  - 页面之间共享输入框、下拉框、结果块，而不是各写各的

### 4. 明确不建议的方向

- 不建议把 CodeTool 做成完整聊天平台的翻版
- 不建议直接走低代码 builder 风格
- 不建议继续加强高对比粗边框和显眼标题栏

---

## Suggested Next Step

如果下一步继续做 UI 收敛，建议按下面顺序：

1. 先从 OpenCove 和 Jan 提取 shell 层参考
2. 再从 LobeHub 和 LibreChat 提取 panel header / input / result 的局部模式
3. 最后参考 OxideTerm 补开发者工具感和状态反馈密度

如果需要进一步落地，可以继续做一份横向矩阵，把这些仓库按下面维度拆开：

- 侧栏
- 顶部 chrome
- panel 层级
- 输入区
- 结果区
- 状态反馈
- 按钮体系
- 空状态
