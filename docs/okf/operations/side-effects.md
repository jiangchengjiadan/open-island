---
type: Operational Inventory
title: Side Effects Inventory
description: Open Island 当前和目标副作用的范围、风险、默认值与撤销要求。
tags: [operations, side-effects, configuration, privacy]
timestamp: 2026-08-10T00:00:00+08:00
---

# Inventory

| Side effect | Current trigger | Risk | Target policy |
|---|---|---|---|
| 修改 Claude/Cursor/Gemini/Qoder/Codex 配置 | App bootstrap 和 auto repair | 删除第三方条目、配置损坏、反复备份 | 显式逐工具 opt-in，原子写入，可预览/卸载 |
| 覆盖 `~/.local/bin/codex` | App bootstrap | 全局 PATH 劫持、原 wrapper 丢失 | 默认禁用；不用 PATH wrapper 或用户显式选择 |
| 启动 Node bridge | App 启动 | 多实例、固定 socket 争用 | 单实例 owner 和可靠状态机 |
| 写 `/tmp` 日志 | hook/wrapper 错误和生命周期 | prompt、命令、环境泄露及 symlink 风险 | 默认脱敏，私有目录，`0600`，轮转和清理 |
| 读取 Terminal 内容 | prompt 检测 | 终端隐私暴露 | 单独 opt-in，最小读取，用户可见状态 |
| AppleScript 激活终端并发送按键 | 用户在岛上提交选项 | 焦点切换、误输入 | 精确 session 路由和提交前确认 |
| 修改终端标题 | session start/prompt submit | 干扰用户标题和工具行为 | opt-in 或可恢复原标题 |
| 阻止系统睡眠 | agent 被判定活跃 | 电量和睡眠策略改变 | 默认关闭，仅明确 `.running` 状态触发 |
| 周期进程/历史扫描 | App 运行 | CPU、磁盘与隐私成本 | 降频、按需、可关闭、避免读取正文 |
| 宽泛 `pkill -f /NotchMonitor` | CLI stop | 误杀命令行或路径匹配的其他进程 | 使用 owner manifest 中的精确 PID+start-time，验证后终止 |

# Change Control

新增副作用前必须说明：触发条件、影响范围、默认值、授权 UI、失败行为、日志内容、撤销方式和测试。没有卸载或恢复路径的全局写入不得进入默认启动流程。

# Related Concepts

- [System Overview](/architecture/system-overview.md)
- [Installer Ownership](/operations/installer-ownership.md)
- [Remediation Playbook](/playbooks/security-reliability-remediation.md)
