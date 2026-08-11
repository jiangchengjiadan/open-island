---
type: Implementation Log
title: 2026-08-10 Remediation Implementation Log
description: Open Island 安全、安装、协议、运行时和测试修复的执行过程与验证记录。
tags: [implementation, remediation, testing, audit]
timestamp: 2026-08-10T00:00:00+08:00
status: completed
---

# Scope

本轮继续完成修复方案中尚未落地的安装事务、审批提交状态、runtime manifest 与整体测试。所有实现保留用户既有未提交修改，不执行 git stage/commit。

# Baseline

- Node 审批测试：8/8 通过。
- Swift debug build：通过。
- 默认启动已不再自动安装 hooks/wrapper。
- 已有剩余项：installer plan/apply/uninstall、审批 ACK UI、capability 传递强化、runtime manifest、vendor 阻断契约证据。

# Work Log

## 1. Planning

实施顺序固定为 installer → protocol/ACK → runtime manifest → tests → independent test agent → findings remediation。

## 2. Installer

- `auto-install-hooks.js` 默认进入只读 plan，必须显式指定 `--apply --tools ...`。
- 增加 `--status`、`--uninstall`、逐工具选择、稳定 `OPEN_ISLAND_MANAGED=1` ownership marker 和私有 state manifest。
- apply/uninstall 只处理精确 marker，保留第三方 hook；配置写入拒绝 symlink/非普通文件，使用同目录临时文件和 atomic rename。
- plan 写入 digest 和每个目标的 before hash；apply 强制使用 plan 中的工具集合并在 commit 前复核 hash。
- installer 使用私有 `0700` state 目录、进程锁和包含 base64 恢复快照的 prepared journal；journal v2 同时记录每个文件的 base/applied hash。异常会立即 rollback，SIGKILL/断电遗留会在下一次 plan/status/apply/uninstall 前自动恢复；若 crash 后配置又被外部编辑，则保留文件和 journal 并报告冲突，不覆盖新内容。
- manifest v2 按工具保存安装时的完整 command fingerprint。卸载使用历史 fingerprint，不依赖当前环境或仓库路径；带 marker 但已被用户修改的条目会触发 ownership conflict，并保留配置与 manifest。升级会在同一事务内先精确移除旧 fingerprint，再安装并登记新 fingerprint。
- Codex wrapper 支持 status/uninstall，拒绝覆盖或删除非托管 launcher。
- `open-island start` 不再重装；顶层安装脚本要求 `OPEN_ISLAND_TOOLS` 明确列出工具。

## 3. Approval ACK and Capability

- Swift 维护 submitting request ID；点击后显示 `Submitting…` 并禁用重复操作，服务端响应作为 ACK 清理状态。
- UI capability 不再放入子进程环境，改由 App 通过 bridge 标准输入的继承 FD 一次性传递。
- UUID requestId、bridge nonce、role ACL 和 requester/UI disconnect fail-closed 保持启用。

## 4. Runtime Integrity

- canonical source 同步后生成 `runtime-manifest.json`，记录 protocol version 和每个打包 runtime 文件的 SHA-256。
- SwiftPM 将 manifest 作为资源打包；App 启动 bridge 前逐文件验证 hash，失败只报告、不自动修复。
- CI、DMG 与同步脚本共用同一 manifest 生成路径。

## 5. Vendor Boundary

Cursor/Gemini 工具级同步阻断仍缺本机可用的官方 fixture，因此保持 monitor-only。现有测试只验证 adapter 不会吞掉 deny；知识库明确禁止把它描述为已验证审批保护。

Claude `PreToolUse` 同样保持默认 monitor-only。只有安装时显式设置 `NOTCH_MONITOR_ENABLE_BLOCKING_APPROVALS=1` 才写入实验性阻断开关；在完成 vendor 副作用 E2E 前不升级为 verified-blocking。

# Verification Log

- Node：22 项测试中 21 项在当前 sandbox 通过、1 项因 Unix socket `listen EPERM` 明确跳过，0 失败；独立智能体在正常环境确认 socket 测试可通过。覆盖 hook blocking/passive 与 malformed 输入、临时 HOME installer plan/apply/uninstall、跨环境 fingerprint 卸载、blocking→passive 升级、plan 越权、stale plan、manifest failure rollback、SIGKILL 正常恢复、crash 后外部编辑冲突保留、第三方/用户修改 hook 保留、nonce/replay 和 runtime manifest。
- Unix socket capability 集成测试已创建；当前受控 sandbox 返回 `listen EPERM`，测试明确 skip，需在正常 macOS/CI 环境执行。
- Swift clean scratch debug build：通过。
- JS/shell syntax、`git diff --check` 与 canonical/packaged runtime byte drift：通过。

# Review Findings

- 首轮发现 plan 可越权增加工具、partial apply、默认启动文档陈旧；已通过 plan 工具集合绑定、事务 rollback 和 README 更新修复。
- 次轮发现 manifest 写入不在事务内；已纳入同一 journal rollback。
- 终验发现默认 monitor-only 的 malformed Claude 输入仍输出 deny；已把外层 fail-closed 限制到显式 blocking 开关并补黑盒测试。
- 终验发现 SIGKILL 后恢复可能覆盖用户在 crash 后的新编辑；已升级 journal v2 条件恢复并补冲突保留黑盒测试。
- 末轮发现按“当前环境命令”卸载会遗漏实验 blocking/旧路径 hook，随后又发现升级会并存新旧命令；已用 manifest v2 历史 fingerprint、升级前 ownership 校验和事务内精确替换闭环，并补三组环境变化/升级/冲突测试。
- 独立智能体在沙箱外完成最终终验：Node/Unix socket/installer 22/22 通过、0 skip；clean Swift scratch build、runtime drift/manifest、JS/shell syntax 与 `git diff --check` 均通过。SIGKILL 正常恢复、外部编辑冲突保留、blocking→passive 升级、跨环境卸载和 monitor-only/blocking 异常路径均符合预期；未发现剩余 P0/P1。

# Final Status

实现与本地验证完成。实验性 vendor blocking 仍不是发布级能力，默认保持 monitor-only；正式启用前仍需真实 vendor fixture/E2E。
