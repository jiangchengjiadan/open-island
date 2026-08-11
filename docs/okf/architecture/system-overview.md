---
type: System Architecture
title: Open Island System Overview
description: Open Island 的进程、代码区域、数据流和所有权边界。
tags: [architecture, macos, bridge, hooks]
timestamp: 2026-08-10T00:00:00+08:00
---

# Components

| Component | Source | Responsibility |
|---|---|---|
| macOS App | `native/NotchMonitor/Sources/` | 面板 UI、agent 聚合、审批交互、bootstrap、终端跳转和电源策略 |
| Node bridge | `bridge/server.js` | Unix socket 消息路由、agent 状态、审批队列和 session grants |
| Event hook | `bridge/hook.js` | 将各工具事件标准化，注册 agent，阻塞等待审批结果 |
| Integrations | `bridge/integrations/` | 工具特定的 session、事件和 permission output 语义 |
| Codex wrapper | `bridge/codex-wrapper.js` | 包装 Codex 子进程并发送生命周期心跳；属于侵入式可选集成 |
| Installers | `scripts/`、`AppRuntime/scripts/` | 修改用户级工具配置和命令 wrapper |
| Packaged runtime | `native/NotchMonitor/Sources/AppRuntime/` | 随 App 分发的 bridge/scripts 副本，当前存在双份维护风险 |

# Runtime Flow

1. App 启动 `AppBootstrapService`。
2. bootstrap 可能运行安装脚本并启动 Node bridge。
3. 工具 hook 连接 Unix socket，发送 agent 状态或权限请求。
4. `SocketService` 接收快照和事件，并与进程扫描、Codex 扫描结果合并。
5. 用户在面板响应审批，Swift 将 response 发回 bridge。
6. bridge 广播结果，等待中的 hook 输出工具特定 allow/deny 响应。

# Ownership Rules

- bridge 必须有唯一 owner；第二实例不能删除第一实例的活跃 socket。
- `bridge/` 应成为 JavaScript 运行时唯一事实来源，打包资源由构建生成。
- UI 独占审批响应权；hook 和 wrapper 只能发布自身事件。
- 用户配置属于用户，Open Island 只能管理带有明确 ownership metadata 的条目。
- Swift 可变运行时状态必须归属主 actor 或单一专用 actor。

# Known Architectural Debt

- bootstrap 同时承担诊断、安装和进程监督，导致只读检查触发修复副作用。
- socket 协议没有角色认证或版本握手。
- agent 来自 socket、进程扫描和历史扫描，身份模型容易重复。
- AppKit 和 SwiftUI 分别计算窗口高度。

# Related Concepts

- [Permission Boundary](/security/permission-boundary.md)
- [Side Effects](/operations/side-effects.md)
- [Bridge and Socket Lifecycle](/runtime/bridge-socket-lifecycle.md)
- [Remediation Playbook](/playbooks/security-reliability-remediation.md)
