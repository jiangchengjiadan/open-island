---
type: Integration Capability Matrix
title: Approval Support Matrix
description: 记录各开发工具事件是否能被 Open Island 同步阻断以及所需验证证据。
tags: [integrations, permissions, compatibility]
timestamp: 2026-08-10T00:00:00+08:00
---

# Status Values

- `verified-blocking`：有版本化 fixture 或实机测试证明 deny 后目标操作未发生。
- `monitor-only`：只能观察事件，UI 不显示审批保护。
- `unverified`：存在候选 hook，但输出语义尚未验证，发布时按 monitor-only 处理。

# Matrix

| Tool | Event | Current status | Release policy |
|---|---|---|---|
| Claude family | `PreToolUse` | unverified | 默认 monitor-only；仅设置 `NOTCH_MONITOR_ENABLE_BLOCKING_APPROVALS=1` 时启用实验性阻断，完成 vendor deny E2E 后才标 verified-blocking |
| Cursor | `beforeShellExecution` | unverified | adapter 已保留 deny，但事件仍按 monitor-only；完成 vendor E2E 后才能接入审批 |
| Cursor | `beforeMCPExecution` | unverified | adapter 已保留 deny，但事件仍按 monitor-only；完成 vendor E2E 后才能接入审批 |
| Gemini | 当前已安装事件 | monitor-only | 未发现工具级前置阻断事件，不展示审批 UI |
| Codex | wrapper lifecycle | monitor-only | wrapper 只报告生命周期，不代理审批 |

# Change Rule

任何状态提升到 `verified-blocking` 必须记录工具版本、输入 fixture、预期 output schema 和“目标副作用未发生”的自动化证据。adapter JSON 单测不能单独作为升级依据。

# Evidence

- `bridge/hook.js`：当前仅严格匹配 `PreToolUse` 进入审批。
- `scripts/auto-install-hooks.js`：当前 Gemini 安装事件不包含工具级同步前置事件。
- `bridge/integrations/`：各工具 output adapter 的实现位置。
