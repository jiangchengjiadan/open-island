# Open Island 对标 Vibe Island Backlog

更新时间：2026-04-27

关联文档：

- [Open Island vs Vibe Island 功能差距与 Roadmap](./vibe-island-gap-analysis.zh-CN.md)
- [Open Island 可借鉴 open-vibe-island 的功能参考](./open-vibe-island-reference.zh-CN.md)

本文把对标分析进一步拆成可执行 backlog，目标是让团队可以直接据此创建 issue、安排 milestone、分配模块 owner。

## 使用方式

建议按以下层级管理：

- `Milestone`：一组可对外表达的阶段结果
- `Epic`：一个完整能力域
- `Issue`：可在 1 到 5 天内完成的具体任务

建议标签：

- `P0`
- `P1`
- `P2`
- `bridge`
- `native`
- `jump`
- `integration`
- `protocol`
- `remote`
- `ux`
- `stability`

## Milestone 规划

### M1：本地能力补强

目标：

- 把 Open Island 从 Claude/Codex 本地预览，推进到多 agent 的稳定本地工作流

完成标准：

- Claude / Codex 默认可用
- Gemini / Cursor 至少能稳定监控
- Ghostty / Warp / IDE terminal jump 有首版支持
- permission / interactive prompt 协议不再只靠临时拼接

### M2：交互协议升级

目标：

- 把产品从“会提示”升级到“可在 notch 中完成更多决策”

完成标准：

- Plan Review 首版上线
- OpenCode 原生接入完成
- interactive prompt 改为协议优先

### M3：产品化补齐

目标：

- 提升留存、可配置性、日常可感知价值

完成标准：

- Settings 首版
- Usage Tracking 首版
- 声音与提醒首版
- 多显示器/外接显示器行为可用

### M4：远程能力上线

目标：

- 支持远端 SSH 场景，让本地与远端 agent 统一进入同一个 island

完成标准：

- remote bridge 可部署
- host 标签与健康状态可见
- 自动重连与 stale cleanup 到位

## M1 Backlog

## Epic 1：Codex 一等支持

### Issue 1.1：默认开启稳定 Codex hook 链路

优先级：`P0`

目标：

- 移除“需要额外环境变量才能得到完整 Codex bridge hook”的现状

涉及模块：

- `scripts/auto-install-hooks.js`
- `native/NotchMonitor/Sources/AppRuntime/scripts/auto-install-hooks.js`
- `bridge/hook.js`

验收标准：

- 新用户安装后无需额外环境变量即可启用 Codex 所需 hook
- 不明显污染 Codex 终端输出
- Codex SessionStart / SessionEnd / PreToolUse / PostToolUse 正常进入 bridge

### Issue 1.2：Codex 主会话与辅助线程去重

优先级：`P0`

目标：

- 减少 process scan 导致的重复 agent、辅助线程误展示

涉及模块：

- `native/NotchMonitor/Sources/Services/SocketService.swift`

验收标准：

- 同一个 Codex 会话不会同时出现多个视觉重复项
- 后台辅助进程不会被误渲染成主 agent
- dedupe 规则有明确注释和测试策略

### Issue 1.3：Codex 审批稳定性回归测试

优先级：`P0`

目标：

- 把 Codex 审批链路从“功能存在”提升为“默认可回归验证”

涉及模块：

- `bridge/server.js`
- `bridge/hook.js`
- `native/NotchMonitor/Sources/Services/SocketService.swift`
- `native/NotchMonitor/Sources/Views/NotchPanel.swift`

验收标准：

- Bash / Edit / Write 类型审批都能闭环
- `Allow Similar` 在 Codex 会话中有效
- 关闭会话后 session grant 能自动失效
- 至少有一份手工 smoke checklist

## Epic 2：新 Agent 接入框架

### Issue 2.1：抽离 integration 层目录结构

优先级：`P0`

目标：

- 为 Claude / Codex / Gemini / Cursor / OpenCode 建立统一接入抽象

涉及模块：

- `bridge/`

建议目录：

```text
bridge/integrations/
  claude/
  codex/
  gemini/
  cursor/
  opencode/
```

验收标准：

- 至少 Claude / Codex 两个现有接入迁到统一结构
- 新 integration 的输入输出协议有 README 或注释说明
- 后续新增 agent 不需要继续把逻辑堆进 `hook.js`

### Issue 2.2：Gemini CLI 基础接入

优先级：`P0`

目标：

- 支持 Gemini CLI 基础会话监控

涉及模块：

- `bridge/integrations/gemini/`
- `scripts/auto-install-hooks.js`
- `native/NotchMonitor/Sources/Models/Agent.swift`
- `native/NotchMonitor/Sources/Views/NotchPanel.swift`

验收标准：

- Gemini 会话能注册、更新、结束
- 面板显示 agent 类型和最近任务
- 不依赖纯进程名猜测作为唯一来源

### Issue 2.3：Cursor Agent 基础接入

优先级：`P0`

目标：

- 支持 Cursor Agent 基础监控

涉及模块：

- `bridge/integrations/cursor/`
- `native/NotchMonitor/Sources/Services/SocketService.swift`
- `native/NotchMonitor/Sources/Services/TerminalJumpService.swift`

验收标准：

- Cursor agent 能稳定出现与消失
- 至少能回跳到 Cursor 或其终端上下文
- 不与普通 Cursor 编辑器窗口混淆

### Issue 2.5：Claude-family agent 接入抽象

优先级：`P0`

目标：

- 把 Qoder / Qwen Code / Factory / CodeBuddy 这类 Claude fork 统一到一套接入模型

涉及模块：

- `bridge/integrations/claude-family/`
- `scripts/auto-install-hooks.js`
- `native/NotchMonitor/Sources/Models/Agent.swift`
- `native/NotchMonitor/Sources/Views/NotchPanel.swift`

验收标准：

- 配置路径可按 agent 区分
- hook payload 复用 Claude 事件协议
- 至少 Qoder 与 Qwen Code 完成首版接入
- 面板 branding 与 session 展示不再全部混成 Claude 默认文案

### Issue 2.4：OpenCode 接入预研 Spike

优先级：`P0`

目标：

- 明确 OpenCode 更适合走 SSE/REST 还是 hook/fallback

输出物：

- 一份设计文档
- 端口发现方案
- 鉴权/连接模型说明

验收标准：

- 文档中明确：
  `事件来源`
  `实时流协议`
  `响应回写方式`
  `失败重连策略`

## Epic 3：Jump 能力扩矩阵

### Issue 3.1：Ghostty jump 支持

优先级：`P0`

涉及模块：

- `native/NotchMonitor/Sources/Services/TerminalJumpService.swift`

验收标准：

- 可定位并激活对应 Ghostty 窗口或 tab
- TTY 匹配失败时有安全 fallback

### Issue 3.2：Warp jump 支持

优先级：`P0`

### Issue 3.2A：VS Code / Cursor workspace-jump 策略收敛

优先级：`P0`

目标：

- 明确把 VS Code / Cursor 的首阶段目标定义成 `稳定回到正确 IDE 与 workspace`

涉及模块：

- `native/NotchMonitor/Sources/Services/TerminalJumpService.swift`
- `native/NotchMonitor/Sources/Views/NotchPanel.swift`

验收标准：

- VS Code 会话点击后至少能回到正确 app 和目标 workspace
- Cursor 会话点击后至少能回到正确 app 和目标 workspace
- 文档中不再把这类能力表述成 pane 级精确 terminal jump

### Issue 3.2B：iTerm / tmux session-first jump 重构

优先级：`P0`

目标：

- 将当前 iTerm / tmux jump 从 UI automation 优先，改为 session 标识优先

涉及模块：

- `native/NotchMonitor/Sources/Services/TerminalJumpService.swift`
- `bridge/hook.js`
- `bridge/codex-wrapper.js`

验收标准：

- iTerm 多窗口场景优先按 `ITERM_SESSION_ID` 定位
- tmux 场景优先传播 pane/session 标识，而不是只靠 tty
- UI fallback 只作为最后路径

验收标准：

- Warp 场景可 best-effort 回跳
- 日志可说明命中的是 tty、cwd 还是 app fallback

### Issue 3.3：VS Code / Cursor terminal jump 支持

优先级：`P0`

验收标准：

- 能区分 IDE app 激活与 terminal 精确回跳
- 至少可回到正确 app 与大致会话上下文

### Issue 3.4：Jump 策略层重构

优先级：`P1`

目标：

- 避免继续把不同 terminal 的 AppleScript 模板堆在一个枚举里

涉及模块：

- `native/NotchMonitor/Sources/Services/TerminalJumpService.swift`

验收标准：

- 按 terminal strategy 拆分逻辑
- 新增 terminal 不需要改动大段共享脚本
- 失败日志统一格式

## Epic 4：稳定性工程

### Issue 4.1：stale session cleanup

优先级：`P0`

目标：

- 避免 bridge 重启、hook 异常、终端关闭后留下僵尸会话

涉及模块：

- `bridge/server.js`
- `native/NotchMonitor/Sources/Services/SocketService.swift`

验收标准：

- 异常结束的 agent 能在合理时间内被清理
- 不会影响活跃会话

### Issue 4.2：permission request 排队与并发保护

优先级：`P0`

目标：

- 避免多个请求同时进来时状态互相覆盖

涉及模块：

- `bridge/server.js`
- `native/NotchMonitor/Sources/Models/Agent.swift`
- `native/NotchMonitor/Sources/Views/NotchPanel.swift`

验收标准：

- 同一 agent 多个连续审批请求有确定行为
- UI 不会出现 requestId 丢失或错配

### Issue 4.3：bootstrap 自愈检查

优先级：`P1`

目标：

- 把安装和诊断做得更接近产品，而不是纯文档依赖

涉及模块：

- `native/NotchMonitor/Sources/Services/AppBootstrapService.swift`
- `scripts/auto-install-hooks.js`

验收标准：

- hook 丢失时可自动修复
- bridge 掉起失败时 UI 能明确提示原因
- Codex / Claude 安装状态分别可见

## M2 Backlog

## Epic 5：Plan Review

### Issue 5.1：定义 Plan Review 协议

优先级：`P1`

目标：

- 为 agent 计划审阅建立专用事件模型

建议消息：

- `plan_review_requested`
- `plan_review_responded`

涉及模块：

- `bridge/server.js`
- `bridge/hook.js`
- `native/NotchMonitor/Sources/Models/Agent.swift`

验收标准：

- 协议包含标题、摘要、markdown 内容、来源 agent、requestId
- 响应至少支持 `approve`、`revise`、`open_terminal`

### Issue 5.2：Plan Review UI 首版

优先级：`P1`

涉及模块：

- `native/NotchMonitor/Sources/Views/NotchPanel.swift`

验收标准：

- 能在面板中展示 plan 标题与摘要
- 能展开 markdown 或打开专门窗口
- 用户可一键回到 terminal

### Issue 5.3：Claude / Codex plan 事件适配 Spike

优先级：`P1`

目标：

- 确认不同 agent 是否能稳定输出可用于 plan review 的结构化事件

输出物：

- 对比文档
- 每个 agent 的适配可行性结论

## Epic 6：Interactive Prompt 协议升级

### Issue 6.1：定义统一 interactive prompt 协议

优先级：`P1`

目标：

- 让 prompt 不再主要依赖 terminal 文本解析

建议消息：

- `interactive_prompt_requested`
- `interactive_prompt_responded`

验收标准：

- 统一支持 title / message / options / metadata
- response 有 requestId 与 selected option

### Issue 6.2：Terminal 文本解析降级为 fallback

优先级：`P1`

涉及模块：

- `native/NotchMonitor/Sources/Services/TerminalPromptService.swift`
- `native/NotchMonitor/Sources/Services/SocketService.swift`

验收标准：

- 协议事件优先
- 没有协议事件时仍可走旧解析逻辑
- UI 不需要知道 prompt 来自协议还是 fallback

## Epic 7：OpenCode 原生集成

### Issue 7.1：OpenCode SSE client

优先级：`P1`

涉及模块：

- `bridge/integrations/opencode/`

验收标准：

- 可订阅实时事件流
- 支持自动重连
- 连接状态可上报给 bridge

### Issue 7.2：OpenCode REST response adapter

优先级：`P1`

验收标准：

- 可向 OpenCode 回写审批/问答结果
- 错误时 bridge 有明确日志与重试策略

## M3 Backlog

## Epic 8：Settings

### Issue 8.1：Settings Window 骨架

优先级：`P2`

建议 tabs：

- General
- Integrations
- Shortcuts
- Diagnostics

涉及模块：

- `native/NotchMonitor/Sources/`

验收标准：

- 可从菜单栏打开
- 配置项可持久化

### Issue 8.2：Integrations 状态面板

优先级：`P2`

验收标准：

- Claude / Codex / Gemini / Cursor / OpenCode 各自状态可见
- 可触发 recheck / reinstall

## Epic 9：Usage Tracking

### Issue 9.1：Claude usage 采集

优先级：`P2`

输出物：

- provider 数据来源说明
- 刷新策略
- stale 策略

### Issue 9.2：Codex usage 采集

优先级：`P2`

### Issue 9.3：面板首版 usage UI

优先级：`P2`

验收标准：

- 用户能快速看到 remaining / used / last updated

## Epic 10：声音与通知

### Issue 10.1：完成事件通知

优先级：`P2`

### Issue 10.2：审批事件通知

优先级：`P2`

### Issue 10.3：mute / quiet hours

优先级：`P2`

## Epic 11：显示策略

### Issue 11.1：无刘海 / 外接显示器顶部模式

优先级：`P2`

### Issue 11.2：follow focus

优先级：`P2`

### Issue 11.3：auto-hide

优先级：`P2`

## M4 Backlog

## Epic 12：SSH Remote

### Issue 12.1：remote bridge 架构设计

优先级：`P0`

目标：

- 明确 remote bridge 是常驻守护进程、临时脚本还是 agent-side helper

输出物：

- 架构设计文档
- 安全模型
- 部署模型

### Issue 12.2：remote bridge prototype

优先级：`P0`

验收标准：

- 能从一台远端主机采集至少一个 agent 会话
- 本地 app 能看到 host 标签
- 会话断开后可自动清理

### Issue 12.3：SSH deploy helper

优先级：`P1`

验收标准：

- 用户能一条命令完成远端部署
- 可检测远端 Node 依赖或替代运行时

### Issue 12.4：remote health / reconnect

优先级：`P1`

验收标准：

- 网络抖动或睡眠恢复后状态可回归
- host offline / reconnecting / healthy 状态明确

## 推荐 Issue 创建顺序

如果现在就开始开 issue，建议顺序如下：

1. `Issue 1.1` 默认开启稳定 Codex hook 链路
2. `Issue 1.2` Codex 主会话与辅助线程去重
3. `Issue 3.1` Ghostty jump 支持
4. `Issue 3.2` Warp jump 支持
5. `Issue 2.1` 抽离 integration 层目录结构
6. `Issue 2.2` Gemini CLI 基础接入
7. `Issue 2.3` Cursor Agent 基础接入
8. `Issue 4.1` stale session cleanup
9. `Issue 4.2` permission request 排队与并发保护
10. `Issue 12.1` remote bridge 架构设计

## Owner 建议

如果团队人数有限，建议不要按 agent 分工，而按技术层分工：

- `Bridge Owner`
  负责协议、server、integrations、remote
- `Native Owner`
  负责 models、SocketService、panel UI、settings
- `Jump Owner`
  负责 terminal / IDE 跳转矩阵与自动化稳定性
- `Product Owner`
  负责 onboarding、文案、使用量、提醒、诊断体验

## Definition of Done

每个 backlog issue 完成时，至少应满足：

- 有明确手工验证步骤
- README 或 docs 在必要时更新
- 若涉及 bridge 行为变更，同步更新 runtime 副本
- 若涉及面板新增内容，同步检查 panel height 与 hover/scroll 行为
- 日志字段可用于排查线上问题

## 最后建议

不要同时并行推进：

- 多 agent 接入
- SSH Remote
- Settings 大重构

这三件事会争抢同一批协议与状态模型。

建议真实执行顺序：

1. 先稳 Codex 与 jump
2. 再抽 integration 层并接 Gemini / Cursor
3. 然后做 OpenCode + Plan Review
4. 最后进入 remote 和大产品化阶段

这样风险最低，也最容易每个 milestone 都对外可展示。
