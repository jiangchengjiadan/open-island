# OpenCode 接入预研 Spike

更新时间：2026-04-29

目的：

- 明确 OpenCode 更适合走 `plugin + bridge`，而不是只靠进程扫描或泛化 hook
- 定义我们后续实现时需要的协议边界、安装路径和回写格式
- 把 `Issue 2.4 / 7.1 / 7.2` 从“概念想法”收敛成可执行实现

参考实现：

- 本地参考仓库 [`open-vibe-island`](/Users/danielhe/enviroment/server/workspace/open-vibe-island/README.zh-CN.md:1)
- [`OpenCodeHooks.swift`](/Users/danielhe/enviroment/server/workspace/open-vibe-island/Sources/OpenIslandCore/OpenCodeHooks.swift:1)
- [`OpenCodePluginInstallationManager.swift`](/Users/danielhe/enviroment/server/workspace/open-vibe-island/Sources/OpenIslandCore/OpenCodePluginInstallationManager.swift:1)
- [`BridgeServer.swift`](/Users/danielhe/enviroment/server/workspace/open-vibe-island/Sources/OpenIslandCore/BridgeServer.swift:943)
- [`open-island-hooks.py`](/Users/danielhe/enviroment/server/workspace/open-vibe-island/scripts/open-island-hooks.py:211)

## 一句话结论

OpenCode 在我们这里不应该优先走 `SSE + REST`，而应该先做 `JS plugin -> 本地 bridge -> notch UI -> directive 回写`。

原因：

- 现有公开实现已经证明 plugin 入口能拿到完整事件
- 它天然支持权限审批和问答，不需要我们先去反推内部 HTTP 协议
- 和我们现在的本地 bridge 架构更接近，落地成本明显低于直接做 REST adapter

因此建议：

- `Issue 2.4` 结论定为：`P0 首版走 plugin，本地双向 IPC；REST 只作为后续增强`

## 参考实现里已经确认的事实

### 1. 安装位点

OpenCode 插件不是写入某个 `settings.json hooks`，而是：

- 插件文件目录：`~/.config/opencode/plugins/`
- 插件配置文件：`~/.config/opencode/config.json`
- 注册方式：在 `config.json` 的 `plugin` 数组里追加 `file://.../open-island.js`

这意味着我们后续需要一个专门的安装器，而不是继续复用 `auto-install-hooks.js` 当前针对 Claude/Gemini/Cursor 的 JSON hook 逻辑。

### 2. 事件模型

参考实现里的 OpenCode 事件名是：

- `SessionStart`
- `SessionEnd`
- `UserPromptSubmit`
- `PreToolUse`
- `PostToolUse`
- `PermissionRequest`
- `QuestionAsked`
- `Stop`

这组事件比 Cursor/Gemini 更接近 Claude/Codex，但多了一个我们当前 bridge 还没有正式统一支持的能力：

- `QuestionAsked`

这意味着 OpenCode 不是单纯“审批弹窗”问题，而是要求 bridge 能处理：

- allow / deny
- free-form text answer

### 3. Hook / plugin payload 的关键字段

参考实现里的 `OpenCodeHookPayload` 至少包含这些核心字段：

- `hook_event_name`
- `session_id`
- `cwd`
- `tool_name`
- `tool_input`
- `permission_id`
- `permission_title`
- `permission_description`
- `question_id`
- `question_text`
- `prompt`
- `last_assistant_message`
- `model`
- `terminal_app`
- `terminal_session_id`
- `terminal_tty`
- `terminal_title`

这里最重要的不是字段数量，而是它已经自带：

- 稳定的 `session_id`
- workspace 级 `cwd`
- 终端/TTY/会话信息
- 审批和问答的 request 标识

这比我们纯 process scan 更适合做正式 integration。

### 4. stdout directive 回写格式

参考实现里，插件 stdout 支持至少三类 directive：

- `{"type":"allow"}`
- `{"type":"deny","reason":"..."}`
- `{"type":"answer","text":"..."}`

这里的关键信号是：

- OpenCode 不是只接收布尔值
- 问答结果和权限结果共用“回写 directive”模型

这对我们当前代码的直接影响是：

- 不能只用 `permissionOutput(source, eventName, allowed)` 这种布尔接口
- 后续需要引入更泛化的 `interaction directive` 输出模型

## 对 Open Island 的实现建议

## Phase 1：Plugin First

第一阶段不做 REST，不做 SSE，先做本地 plugin integration。

建议链路：

1. `scripts/install-opencode-plugin.js`
2. 在 `~/.config/opencode/plugins/` 写入 `open-island.js`
3. 在 `~/.config/opencode/config.json` 注册插件引用
4. OpenCode 插件把事件 payload 发给本地 `bridge/server.js`
5. bridge 更新 session、弹审批、弹问题
6. UI 决策后，bridge 给插件返回 directive
7. 插件把 directive 以 stdout 或 plugin 回调格式回写给 OpenCode

这样能最大化复用我们已有的：

- 本地 Unix socket bridge
- island session 渲染
- permission queueing
- stale cleanup

## Phase 2：Bridge 需要补的能力

### A. 新增 source

bridge 层要新增 `opencode` source，并支持：

- `sessionId`
  - 直接用 `payload.session_id`
- `sessionName`
  - 优先 `cwd` 的 workspace 名
- `cwd`
  - 直接用 `payload.cwd`

### B. 新增 interaction 类型

当前 bridge 基本以 `permission_request` 为核心。OpenCode 至少要求两类 interaction：

- `permission`
- `question`

建议在 bridge 里抽象：

- `pendingInteractions[sessionId]`
- `kind = permission | question`
- `response = allow | deny(reason?) | answer(text)`

这样未来也能反过来服务更泛化的 Claude/Cursor 交互。

### C. 新增 directive encoder

当前 `hook.js` 的 stdout 兼容逻辑是按 source 写死的。OpenCode 需要单独 encoder：

- `allow -> {"type":"allow"}`
- `deny -> {"type":"deny","reason":...}`
- `answer -> {"type":"answer","text":...}`

这一步和 Codex/Claude 的差异很大，建议不要硬塞进现有 `permissionOutput()`。

## Phase 3：UI 需要补的能力

OpenCode 的 `QuestionAsked` 不能只用当前二选一审批条承接。

至少需要：

- 一个文本输入式 question response UI
- 超时/取消的默认行为
- session 结束后自动清理 pending question

这部分和 M2 里的 `interactive prompt 统一协议` 是同一批能力，应该合并设计，不要单独做一套只服务 OpenCode 的 UI。

## 为什么现在不建议先做 REST/SSE

虽然对标文档里提到 `OpenCode SSE + REST`，但按我们当前项目状态，直接做这条线风险更高：

- 我们还没有掌握稳定的本地服务发现和鉴权模型
- 当前 bridge 是 Unix socket 模式，不是 HTTP service
- OpenCode 的最核心用户价值其实是“权限/问答/状态进入岛里”，plugin 已经能覆盖

因此更合理的顺序是：

1. 先做 plugin 双向闭环
2. 再评估是否需要旁路 HTTP / SSE 做 richer metadata 或 remote/watch 能力

## 建议的仓库落点

建议后续实现拆成这些文件：

```text
bridge/
  integrations/
    opencode.js
  opencode/
    plugin-template.js
    install-plugin.js
```

以及：

- `scripts/install-hooks.sh`
  - 增加 OpenCode plugin 安装步骤
- `native/NotchMonitor/Sources/Views/`
  - 承接 question response UI
- `native/NotchMonitor/Sources/Models/Agent.swift`
  - 如需新增 interaction / metadata 字段，同步扩展

## 当前结论

`Issue 2.4` 的结论已经可以定稿：

- 接入模型：`Plugin First`
- 首版协议：`local bridge + directive response`
- 回写格式：`allow / deny / answer`
- 当前 blocker：
  - 我们还没拿到本机 OpenCode 真实 payload 做回归
  - UI 还没有 question response 正式协议层

这意味着下一步真正开做时，最合理的顺序是：

1. `Issue 7.1` OpenCode plugin installer + payload ingest
2. `Issue 6.1` interactive prompt 统一协议
3. `Issue 7.2` OpenCode directive response adapter
