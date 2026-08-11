---
type: Remediation Playbook
title: Open Island 安全与可靠性修复方案
description: 针对审批安全、全局配置侵入、bridge 生命周期、Swift 并发和隐私问题的分阶段实施方案。
tags: [security, reliability, permissions, side-effects, remediation]
timestamp: 2026-08-10T00:00:00+08:00
status: proposed
owners: [maintainers]
---

# 目标

把 Open Island 从“会自动修改开发工具并代理审批的监控应用”收敛为：默认只读、显式授权、拒绝可靠、可卸载、可审计、单实例运行的本地辅助工具。

本方案不以“编译通过”为完成标准。审批拒绝语义、用户配置完整性、进程所有权和隐私边界都必须有自动化回归测试。

# 原则与硬约束

1. **默认无副作用**：首次启动不得自动修改 `~/.claude`、`~/.cursor`、`~/.gemini`、`~/.qoder`、`~/.codex` 或 `~/.local/bin`。
2. **阻断型审批必须 fail closed**：blocking 事件的超时、解析错误、协议错误和 bridge 断开均不得转换为允许；passive/unsupported 事件不注入审批结果，也不得宣称受保护。
3. **审批端与事件端分权**：hook 只能创建请求，UI 才能响应；普通 socket 客户端不能伪造批准。
4. **写入必须可预览、原子、可回滚**：安装前显示 diff，写入使用临时文件与 rename，保留单份明确备份并提供卸载恢复。
5. **单一事实来源**：`bridge/` 是 JavaScript 运行时源；打包副本必须由构建生成或由 CI 逐文件校验。
6. **最小数据收集**：默认不记录 prompt、命令全文、环境变量和终端内容；诊断日志显式开启、权限 `0600`、有大小上限和生命周期。
7. **每个阶段可独立回退**：安全修复不得依赖后续 UI 重构才能生效。

# 问题域与目标状态

| 问题域 | 当前风险 | 目标状态 |
|---|---|---|
| 审批语义 | Cursor/Gemini 拒绝后仍继续；部分事件绕过审批 | 每个支持的事件有明确 allow/deny 输出；未知事件拒绝或不宣称受保护 |
| 协议安全 | 同 UID 客户端可读快照并伪造批准 | 角色握手、随机能力令牌、请求所有权与 requestId 校验 |
| 配置安装 | 启动即改全局配置并可能形成 20 秒修复循环 | onboarding 中显式选择；dry-run、事务写入、卸载恢复 |
| Codex 集成 | wrapper 劫持 PATH，可能与 hooks 重复注册 | 默认不用 PATH wrapper；只启用一种集成并记录安装状态 |
| bridge 生命周期 | 多实例 unlink socket；重启竞态；Pipe 堵塞 | 单实例锁、所有权校验、可靠 drain、串行状态机 |
| Swift socket | SIGPIPE、短写、状态跨队列竞争 | `SO_NOSIGPIPE`、完整写循环、actor/单队列隔离 |
| 隐私 | 固定 `/tmp` 日志含敏感数据且无轮转 | 默认关闭敏感日志；私有目录、脱敏、轮转和清理 |
| UI | 面板高度重复计算并裁切 | 单一高度模型，审批多行和 tab 切换有 UI 测试 |
| 电源策略 | 默认阻止睡眠 | 默认关闭，用户明确 opt-in，仅 `.running` 可触发 |

# 分阶段实施

## Phase 0：止血与安全声明

目标：先消除“界面说拒绝但实际继续”以及后台反复改配置。

- 建立版本化的 blocking/passive/unsupported [审批支持矩阵](/integrations/approval-support-matrix.md)。只有经 vendor fixture 或实机验证能同步阻断的事件才能进入审批。
- 修正已验证集成的 `permissionOutput(eventName, allowed)`；拒绝必须产生上游认可的 deny/abort 结果。Gemini 在证明存在工具级同步阻断 API 前仅作为只读监控集成。
- 对 blocking 事件统一处理 parse、connect、timeout 和协议异常，保证每条异常路径都有 vendor 可识别的 deny/abort；passive 事件保持旁路。
- 为 Cursor 的 `beforeShellExecution`、`beforeMCPExecution` 建立显式映射；不支持审批拦截的集成不得显示为“受 Open Island 保护”。
- 从 `startIfNeeded → runBootstrap` 和自动修复路径移除 `installToolingIfPossible()`；诊断、首次启动、retry 和 onboarding dismiss 都不能修改用户系统。安装仅能来自用户明确操作。
- 临时停止启动时安装 Codex wrapper；保留手动安装入口并在 UI 中标为实验性。
- 将防休眠默认值改为关闭；明确区分新安装默认值与既有用户迁移，若执行一次性强制迁移必须提示用户。

验收：每个宣称支持的 vendor 都验证目标操作未发生，而不只断言 adapter JSON；parse/connect/timeout/断连均阻断。使用临时 HOME、隔离 UserDefaults/Support 目录记录完整目录树，首次启动、周期诊断、retry 和 onboarding 路径运行 2 分钟后，文件集合、symlink、mode、hash、inode、mtime 均不变化。

## Phase 1：重建审批协议边界

目标：让批准只能来自当前 App UI，并且只能回答当前请求。

- 协议状态固定为 `connected → hello(version, role) → challenge/auth → ready`；认证前不发送 snapshot，只接受握手帧，超时、额外消息或版本不匹配立即断开并 fail closed。
- 角色不能只信任客户端声明。UI approval secret 仅驻内存，由 App 启动 bridge 时通过继承 FD/匿名 pipe 建立信任，绝不落盘或共享给 hook。hook/wrapper 使用彼此独立的降权凭据；威胁模型明确不声称抵御同 UID 对进程内存的主动调试读取。
- `permission_response` 只接受已认证的 UI 连接。
- 所有消息都有 role ACL、schema 和 connection ownership 校验。hook 只能操作自己连接创建的 agent/request；wrapper 无审批权限；结果只定向返回 requester，禁止全局 broadcast。
- bridge 接收合法请求后生成随机 instanceId 和单次 nonce；nonce 只发送给 UI。Swift 响应 API 必须携带不可变的 `instanceId + requestId + nonce + decision`，避免旧按钮回答新请求。
- requester 断开、UI 断开或 bridge 重启时，pending 请求原子 deny/cancel；内部 auto-approve 走独立状态转换，不能伪装成 UI response。
- `allow_similar` 绑定 bridge 随机 instanceId 与 permissionKey；重注册、PID/start-time 变化、断开、SessionEnd 或 bridge restart 清除授权。
- 量化限制 pre-auth buffer、frame bytes、JSON 深度/字段长度、client 数、per-client outbound bytes、per-agent/global pending 和处理速率；超限动作固定为拒绝或断开。

验收：认证前快照泄露、角色越权、伪造/迟到/重复/错 agent/错 nonce 响应、requester/UI 断开、bridge 重启、慢读客户端、随机 agentId flood 和授权继承测试通过。

## Phase 2：将安装改为显式事务

目标：用户知道改了什么，也能完整撤销。

- onboarding 提供按工具独立 opt-in，默认全部不选。
- 安装器支持 `plan`、`apply`、`uninstall`、`status`；plan 包含目标路径、原文件 hash、所选工具与 plan digest。apply 持有逐目标锁后重新核验 hash/digest，不一致则拒绝并要求重新 plan。
- 托管条目使用明确稳定的 `open-island` metadata/ID，不再用 `includes('bridge/hook.js')` 删除模糊匹配项。
- 禁止无条件删除 `beforeStart` 或第三方 hook。
- 单文件写入：拒绝 symlink/非普通文件，解析验证 → 同目录 `O_CREAT|O_EXCL` 临时文件 → 保留 owner/mode → fsync → 原子 rename → fsync parent。多文件 apply 使用 `prepared → applied → committed` journal，并为每个 failpoint 提供恢复/回滚。
- 私有 manifest/journal 目录权限 `0700`、文件 `0600`。卸载采用 base/install/current 三方合并，只删除仍匹配 owned fingerprint 的条目；冲突只报告，不用旧备份覆盖用户后续编辑。
- hook 命令必须使用平台安全的参数编码。优先写入 argv 数组；若上游只接受 shell 字符串，使用经过测试的 POSIX shell quoting。
- Codex 只选择 hooks 或 wrapper 一种方式。wrapper 不再默认占用 `~/.local/bin/codex`。

验收：路径含空格、单引号、换行、`$`、反引号和分号并经 `/bin/sh -c` 验证参数原样到达；另覆盖 stale plan、并发 apply、逐 failpoint crash、symlink、权限保留、第三方 hooks、安装后用户编辑、manifest 损坏、重复安装与卸载冲突。

## Phase 3：bridge 与 Swift 运行时可靠性

目标：单实例、可重启、不阻塞、不因断连杀掉 App。

- bridge 启动先 connect-probe；已有健康实例则复用或退出，不能直接 unlink。
- socket 放入用户私有 runtime/support 目录；锁文件和 socket 都记录 instance nonce，并只由 owner 清理。
- 将 `AppBootstrapService` 改为 runtime actor/串行状态机，记录 desired state、generation/identity 和 owner mode：`stopped → starting → running → stopping → stopped`。旧 generation 回调不能改变新状态；用户退出先设置 desired=stopped 并取消 timer/reconnect，永不自启。
- restart 必须等待精确旧 Process identity 有界退出后再 spawn；异常退出仅允许有限指数退避。第二 App 采用单实例锁，健康 bridge 不接管；只有锁 owner 能清理 nonce 匹配且确认陈旧的 socket。
- 统一 `RuntimePaths` 注入 Swift/Node/hook/wrapper；私有短路径目录 mode `0700`，并测试超长 HOME 与 macOS Unix socket 路径上限。
- stdout/stderr 使用持续 drain 的 readability handler，或在非调试模式重定向到 `/dev/null`；短任务也必须并发 drain 后再 wait。
- Swift socket 设置 `SO_NOSIGPIPE`，实现 EINTR/partial-write 循环，写失败转入断线状态并保留待处理 UI 反馈。
- 拆分 `SocketTransport` actor/串行执行器与 `@MainActor AgentStore`；后台扫描只返回带 generation 的不可变结果，主域丢弃旧 generation，禁止跨域读写 `promptCache`。
- read 处理 EINTR/EAGAIN/EOF 和 frame 上限；write 除 `SO_NOSIGPIPE`、EINTR/partial loop 外还校验 FD generation，避免重连后旧操作写入新 FD。
- 审批 response 增加 responseId/ack。ack 前 UI 显示提交中，失败不本地清除；断线后不得自动重放 allow，用户可在 nonce 仍有效时明确重试。
- 退出时先禁用诊断和自动行为，再关闭 socket/bridge；不得在 termination handler 中重新启动。

验收：连续重启、第二实例、bridge crash、断连时点击审批、大消息、长时间 stderr 输出和 Thread Sanitizer 场景通过。

## Phase 4：隐私、UI 与可观测性

目标：减少数据面并补齐用户可见控制。

- 建立统一 Logger facade 和 privacy 分类，覆盖 Node 文件日志与 Swift `print`/TerminalJump/Prompt 日志。默认只记录事件类型、随机 request ID 和结果，不记录 prompt、命令、cwd、完整环境或终端内容。
- 调试日志写入用户私有目录，以安全 open flags 创建，权限 `0600`，限制总大小并支持一键清除。
- Terminal 内容读取和 AppleScript 按键提交分别 opt-in；关闭或撤权时立即停止扫描、取消任务并清理 prompt cache。最近动作只保留时间、目标类型和结果。
- 面板高度由纯值 layout model 计算，输入 tab、各类 row 高度、诊断行与屏幕约束；tab 状态提升为共享 panel state，AppKit window 与 SwiftUI 使用同一结果。
- Usage tab 的窗口高度随 tab 状态更新。
- 防休眠采用 `disabled/eligible/asserted/paused` 幂等状态模型，默认关闭；仅用户选择的 `.running` agent 可触发，agent 消失、关闭设置、系统睡眠和 App 退出均 release。

验收：隐私快照检查、日志权限/轮转测试、3 个以上审批行、tab 切换和电源 assertion 生命周期测试通过。

## Phase 5：消除双份运行时与建立发布门禁

- `bridge/` 作为唯一源目录，由明确 allowlist 的生成脚本产生带 GENERATED 标识的 AppRuntime；禁止 wildcard 带入 node_modules、日志和测试。生成在 `swift build` 和 DMG 打包前执行，CI 重新生成并要求无 diff。
- 引入 runtime manifest（相对路径、SHA256、protocol/runtime version），App 启动只校验并报错，不自动修复。RuntimeLocator 明确处理 `Bundle.module`、安装包 Resources 和测试路径，不能依赖源码 fallback 掩盖缺包。
- 先建立测试骨架：Node 使用 `node:test`；Swift 抽出可测 core target 与 testTarget，并注入 syscall、Process launcher、clock、filesystem 和 IOKit adapter。
- 对安装器使用临时 HOME 做黑盒测试，禁止 CI 触碰真实用户目录。
- 发布门禁包含：安全用例、升级/卸载、双实例、路径 quoting、日志隐私和打包资源一致性。

# 测试矩阵

| 层级 | 必测内容 |
|---|---|
| Node 单元测试 | 各集成 allow/deny 输出、事件映射、permission key、配置 merge/uninstall、shell quoting |
| 协议集成测试 | 角色认证、nonce、requestId 匹配、队列、超时、重放、错误 frame、大小限制 |
| 安装黑盒测试 | 临时 HOME、第三方配置保留、重复 apply、崩溃恢复、卸载、特殊路径 |
| Swift 单元测试 | bridge 状态机、完整写循环、agent 去重、layout model、电源策略 |
| Swift 并发测试 | Thread Sanitizer 下 prompt 刷新、socket 重连、进程扫描并发 |
| 端到端测试 | Claude/Cursor/Gemini/Codex 的 allow、deny、断连、重启与多会话 |

# 实施顺序和提交边界

建议每个提交只覆盖一个可回滚主题：

1. `bridge: enforce deny semantics for supported integrations`
2. `native: stop automatic tooling mutation`
3. `bridge: authenticate permission responders`
4. `installer: add transactional plan apply uninstall workflow`
5. `native: serialize bridge process lifecycle`
6. `native: harden unix socket writes and state isolation`
7. `runtime: generate packaged bridge from canonical sources`
8. `privacy: minimize and rotate diagnostic logs`
9. `ui: unify panel sizing and make power assertion opt-in`

禁止把 Phase 0 与大规模 UI 重构合并；安全止血应先独立发布。

# 回滚策略

- Phase 0 可通过关闭集成审批功能回滚，但不能恢复为“拒绝仍继续”。
- 协议升级期间采用明确版本握手；版本不匹配时 fail closed，不做静默兼容。
- 安装器应用前生成 manifest；回滚使用 manifest 精确恢复，而不是覆盖整个配置目录。
- bridge 新状态机保留旧实现的 feature flag 仅用于开发诊断，发布构建不允许自动降级到不认证协议。

# 完成定义

- 所有 P1 审批和配置侵入问题有自动化回归测试。
- 默认启动不会修改用户工具配置、PATH wrapper、电源策略或读取终端内容。
- blocking 事件的 Deny、解析失败、超时、断线、协议错误均 fail closed；passive/unsupported 事件不伪装成审批。
- 安装和卸载可在临时 HOME 中重复执行且结果幂等。
- 同一会话只显示一个 agent；同一用户只能有一个活跃 bridge owner。
- 日志不包含 prompt/命令全文，权限和轮转符合设计。
- `bridge/` 与打包资源不存在人工双写。

# 相关知识

- [系统架构](/architecture/system-overview.md)
- [审批安全模型](/security/permission-boundary.md)
- [审批支持矩阵](/integrations/approval-support-matrix.md)
- [副作用清单](/operations/side-effects.md)
- [安装所有权](/operations/installer-ownership.md)
- [Bridge 生命周期](/runtime/bridge-socket-lifecycle.md)
- [测试策略](/testing/remediation-test-strategy.md)
