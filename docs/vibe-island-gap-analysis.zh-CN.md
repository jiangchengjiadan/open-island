# Open Island vs Vibe Island 功能差距与 Roadmap

更新时间：2026-04-27

本文基于以下两部分信息整理：

- Open Island 当前仓库实现与 README
- Vibe Island 官网、功能页与更新日志公开信息
- open-vibe-island 开源仓库公开 README 与 roadmap

目标不是复述营销文案，而是回答两个问题：

1. 我们现在相对 Vibe Island 还缺什么
2. 接下来应该先补什么，分别落到哪些模块

补充参考：

- [Open Island 可借鉴 open-vibe-island 的功能参考](./open-vibe-island-reference.zh-CN.md)

## 一句话结论

Open Island 已经具备一个可用的本地最小闭环：

- 原生 Swift 面板
- 本地 Unix socket bridge
- Claude / Codex 基础会话监控
- 权限审批
- 跳回终端
- 基础 onboarding / hook 安装

但和 Vibe Island 相比，当前差距主要不在“有没有 notch 面板”，而在：

- 多 Agent 集成广度
- 远程 SSH 能力
- 终端跳转覆盖面与精度
- 更深一层的交互能力（Plan Review、协议化问答）
- 产品化能力（设置、声音、用量、自动修复、显示器行为）

## 当前能力基线

### 已有能力

- 本地 bridge + 原生 Swift 架构已成型
- Claude Code hook 安装与事件转发
- Codex 基础监控与部分桥接
- 会话级相似权限自动批准
- Terminal / iTerm / JetBrains 基础跳转
- 基于 Terminal 内容解析的交互式选项回答
- 启动时自动 bootstrap、诊断与 onboarding

### 当前公开定位

从仓库 README 看，当前第一优先支持仍然是：

- Claude Code
- Codex

README 也明确说明：

- 远程 agent 还不支持
- JetBrains 精确跳转仍有明显边界

这说明项目现在更接近“本地开发者预览版”，而不是“大范围 agent / terminal / remote 场景都成熟”的产品状态。

## 差距总表

### P0：核心竞争力缺口

#### 1. 多 Agent 一等支持不完整

Vibe Island 当前公开支持：

- Claude Code
- Codex
- Gemini CLI
- Cursor Agent
- OpenCode
- Droid
- Qoder
- Copilot
- CodeBuddy
- Kiro
- Kimi Code

Open Island 当前实际成熟支持仍以 Claude / Codex 为主。代码虽能识别 `cursor`、`gemini`、`opencode` 相关进程，但缺少对应的完整接入链路：

- 自动安装 / 自动配置
- 事件协议适配
- 审批/问答交互
- 文案与状态细节打磨
- 可验证的稳定性

影响：

- 官网叙事弱
- 实际使用场景窄
- 很难建立“一个 notch 管所有 agent”的心智

建议优先级：最高

#### 2. SSH Remote 完全缺失

Vibe Island 已将 SSH Remote 做成独立能力：

- 远端部署
- 多服务器展示
- 自动重连
- 睡眠/网络切换恢复
- Linux / macOS / FreeBSD 远端支持
- 本地与远端会话统一展示

Open Island README 当前明确写明不支持 remote agents。

影响：

- 无法覆盖远程开发 / 云主机 / 容器开发场景
- 与竞品的能力层级差距最大

建议优先级：最高

#### 3. 终端与 IDE 跳转覆盖面不足

Vibe Island 主打 13+ terminals，并强调：

- split pane
- tmux
- IDE terminal
- Warp / Ghostty / Kitty / Alacritty 等

Open Island 当前跳转逻辑核心仍集中在：

- Terminal.app
- iTerm2
- JetBrains

其中 JetBrains 仍存在 same-project multi-window 不够精确的问题。

影响：

- 核心卖点“jump back”不够稳定
- 一旦支持更多 agent，却跳不准，体验会明显掉档

建议优先级：最高

补充判断：

- 可参考 open-vibe-island 的策略，区分：
  - `terminal session/pane jump`
  - `IDE workspace activate`
- 对 VS Code / Cursor 这类 IDE，短期更应该先保证 workspace 级成功，而不是继续把 pane 级精确跳转当作默认承诺

#### 4. Codex 集成还未达到默认可用

当前 Open Island 的 Codex 集成存在两个明显信号：

- 通过进程扫描补足会话感知
- bridge hook 默认并未完全开启，需要环境变量控制

这说明 Codex 监控还没到“零配置、默认稳定、低侵入”的阶段。

而 Vibe Island 最近几个版本持续在强化：

- Codex shell approval from notch
- Codex Desktop precise jump
- 辅助线程隐藏
- idle CPU 降低

影响：

- Codex 用户无法获得稳定的一等体验
- 监控与审批链路容易出现“看得见但不可控”

建议优先级：最高

### P1：体验层能力缺口

#### 5. OpenCode 原生接入缺失

Vibe Island 对 OpenCode 不是简单进程识别，而是：

- SSE 实时事件流
- REST API 双向交互
- 自动端口发现
- 自动重连

Open Island 当前没有这条集成链路。

影响：

- 错失一个很适合“notch 控制台”定位的 agent
- 现有“prompt 检测”方案难泛化到类似 OpenCode 的协议式交互

建议优先级：高

#### 6. Plan Review / Markdown 审阅缺失

Vibe Island 已将“在 notch 中预览计划并给反馈”作为显式能力。

Open Island 当前只有：

- 权限审批
- 选项式问答

没有：

- Markdown 渲染
- plan diff / plan summary 展示
- 在面板中直接给审阅反馈

影响：

- 交互层级还停留在“准入确认”
- 无法承接更高价值的人机协作

建议优先级：高

#### 7. 协议化问答能力不足

当前 Open Island 的交互式问题回答主要依赖：

- 读取 Terminal 内容
- 解析序号选项
- 回填键盘输入

这条路径短期可用，但可扩展性和稳定性有限。

限制：

- 强依赖终端 UI 文本格式
- 对非 Terminal 生态不通用
- 难以支持 richer prompt 类型

建议方向：

- 优先走 agent 原生 hook / API 协议
- 终端文本解析作为 fallback

建议优先级：高

### P2：产品化与可售卖能力缺口

#### 8. Usage / Quota Tracking 缺失

Vibe Island 已支持 Claude / Codex / Kimi 用量展示，并有 provider 选择、老化数据保留、刷新策略等细节。

Open Island 当前没有使用量面板，也没有对应 provider 采集链路。

影响：

- 缺少高频“抬头即看”的第二价值点
- 用户只在 agent 需要审批时才感知产品

建议优先级：中

#### 9. 声音与提醒系统缺失

Vibe Island 公开能力包括：

- 8-bit sound
- 自定义 sound file / sound pack
- Quiet Hours
- 快速静音
- 完成提醒

Open Island 当前没有完整事件提醒系统。

建议优先级：中

#### 10. 设置面板缺失

Vibe Island 的 Settings 已经承载：

- Integrations
- Usage
- Labs
- Shortcuts
- 卸载 / 清理
- 远程部署入口

Open Island 当前更像“运行时自举 + 简单诊断”，不具备完整的可配置产品面。

影响：

- 很多高级能力无处承载
- 无法把实验特性渐进式放给用户

建议优先级：中

#### 11. 多显示器 / Follow Focus / Auto-hide 行为缺失

Vibe Island 已公开支持：

- 外接显示器 / 无刘海顶部浮条
- Follow Focus
- Auto-hide
- fullscreen / hover 行为修复

Open Island 当前没有同等级的显示策略能力。

建议优先级：中

#### 12. 发布形态与商业化能力缺失

Vibe Island 公开具备：

- 下载页
- 试用
- 定价
- 自动更新叙事
- Homebrew 安装
- License 管理入口

Open Island 当前更接近开源预览项目。

这不是技术核心，但会影响：

- 分发效率
- 用户信任
- 反馈闭环

建议优先级：低到中

## 建议 Roadmap

## P0：把核心闭环做成“真的能打”

目标：

- 让 Open Island 从“Claude/Codex 本地 demo”变成“多 agent、本地强闭环”的产品原型

### P0-1. 做实 Gemini / Cursor / OpenCode 接入框架

先不要一口气补 10+ agent，优先补这 3 个：

- Gemini CLI
- Cursor Agent
- OpenCode

原因：

- 代码里已经有类型枚举与识别痕迹
- 这三类能覆盖 hook、IDE、SSE/API 三种不同接入模型
- 做完后可自然抽象出统一 integration framework

交付标准：

- 可自动安装或自动发现
- 会话可稳定出现在 panel
- 至少支持监控
- 至少 1 个支持审批
- 至少 1 个支持问答

### P0-2. 把 Codex 升级为默认一等支持

重点：

- 默认启用稳定链路，而不是依赖环境变量
- 区分真实主线程与辅助/子线程
- 明确 approvals 的来源与状态
- 降低 process polling 对稳定性的依赖

交付标准：

- 新用户无额外环境变量也能使用
- Codex CLI 会话稳定注册、更新、清理
- Codex 审批能可靠闭环

### P0-3. 扩展 terminal jump 矩阵

优先终端：

- Ghostty
- Warp
- VS Code terminal
- Cursor terminal

第二梯队：

- Kitty
- Alacritty
- WezTerm

交付标准：

- 至少补到 6 个常用 terminal / IDE terminal
- split pane 有清晰策略
- tmux 至少做到 best-effort 定位

### P0-4. 稳定化 jump 和 approval

在扩支持面之前，把当前两个最关键动作打稳：

- jump
- approval

要补的不是功能，而是稳定性工程：

- stale session cleanup
- reconnect
- race condition 处理
- 多请求排队
- hook 自愈

## P1：把“监控工具”升级成“协作控制台”

目标：

- 提高人在 notch 里完成决策的比例

### P1-1. 上 Plan Review

建议先支持只读能力：

- 展示 plan title
- 渲染 markdown
- 提供 approve / ask to revise / open terminal

然后再迭代：

- inline feedback
- plan diff
- collapsible sections

### P1-2. 把交互 prompt 升级成协议优先

策略：

- 原生 hook / API 优先
- 终端内容解析兜底

输出统一协议，例如：

- `interactive_prompt`
- `interactive_prompt_response`
- `plan_review_request`

### P1-3. OpenCode 原生集成

单独做一个 integration：

- SSE client
- port discovery
- reconnect
- REST response adapter

这会是后续更多“非 hook agent”接入的模板。

## P2：补产品化护城河

目标：

- 提升日常留存与付费感知

### P2-1. Usage Tracking

建议顺序：

1. Claude
2. Codex
3. 其他 provider

先做：

- remaining / used
- stale indicator
- last refresh

再做：

- provider switch
- refresh policy
- errors / fallback UX

### P2-2. 声音与提醒

最小可行版：

- task completed
- permission requested
- question asked

第二阶段：

- event-specific sound
- mute
- quiet hours

### P2-3. Settings 面板

建议最早只做 4 个 tab：

- General
- Integrations
- Shortcuts
- Diagnostics

把现在散落在 bootstrap / 文档 / 环境变量里的控制项搬进去。

### P2-4. 多显示器行为

建议能力：

- notch mode / top-center mode
- active display follow focus
- external display fallback
- auto-hide

## 模块落点建议

### 1. 集成层抽象

建议新增统一 integration 层，而不是继续把逻辑散在 hook、process scan、prompt parse 里。

建议目录：

```text
bridge/integrations/
  claude/
  codex/
  gemini/
  cursor/
  opencode/
```

每个 integration 统一输出：

- session register / update / unregister
- permission request
- interactive prompt
- plan review request

### 2. Bridge 协议扩展

重点文件：

- `bridge/server.js`
- `bridge/hook.js`

建议补充消息类型：

- `interactive_prompt_requested`
- `interactive_prompt_responded`
- `plan_review_requested`
- `plan_review_responded`
- `integration_health_updated`

### 3. Native 状态层

重点文件：

- `native/NotchMonitor/Sources/Services/SocketService.swift`
- `native/NotchMonitor/Sources/Models/Agent.swift`

建议模型增加：

- server / host 标签
- integration source
- grouped subagent metadata
- notification state
- usage state
- plan review payload

### 4. Native UI 层

重点文件：

- `native/NotchMonitor/Sources/Views/NotchPanel.swift`

建议拆分子组件：

- `AgentRow`
- `ApprovalBar`
- `PromptBar`
- `PlanReviewCard`
- `UsageHeader`
- `HostBadge`

现在面板逻辑已经开始变复杂，继续堆在单文件里后面会很难扩。

### 5. Jump 层

重点文件：

- `native/NotchMonitor/Sources/Services/TerminalJumpService.swift`

建议把终端支持做成策略注册，而不是继续把 AppleScript 模板都堆在一个枚举里。

例如：

```text
TerminalJumpStrategies/
  TerminalApp
  iTerm
  Ghostty
  Warp
  VSCodeTerminal
  CursorTerminal
  JetBrainsTerminal
```

### 6. 设置与诊断层

建议新增：

- `SettingsWindow`
- `SettingsViewModel`
- `DiagnosticsService`

把现有 `AppBootstrapService` 中偏安装/诊断的逻辑，和偏用户设置的逻辑拆开。

## 推荐排期

### 版本 A：本地能力补强

- Claude / Codex 稳定化
- Gemini / Cursor 基础接入
- Ghostty / Warp / IDE terminal jump
- approval / prompt 协议整理

### 版本 B：协议升级

- OpenCode SSE + REST 集成
- Plan Review
- 统一交互协议
- 子线程 / 子 agent 收敛显示

### 版本 C：产品化

- Settings
- Usage Tracking
- Sound / Notifications
- Display behavior

### 版本 D：远程

- SSH Remote deploy
- remote bridge
- host tagging
- reconnect / health model

## 最后判断

如果目标是“尽快把产品做到能和 Vibe Island 正面对比”，最值得投入的不是立刻做声音、皮肤、官网，而是这四件事：

1. 多 Agent 一等支持
2. Codex 默认稳定可用
3. 跳转矩阵扩展
4. SSH Remote

如果这四件事没补齐，Open Island 依然更像一个很不错的本地原型。

如果这四件事补齐，即便还没有 Usage、Sound、完整 Settings，也已经会进入“产品级竞争”区间。
