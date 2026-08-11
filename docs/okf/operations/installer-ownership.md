---
type: Configuration Ownership Model
title: Installer Ownership
description: Open Island 修改用户配置时的 plan、事务、ownership、冲突和卸载模型。
tags: [installer, configuration, rollback, ownership]
timestamp: 2026-08-10T00:00:00+08:00
---

# Invariants

1. 默认启动和诊断不得调用 apply。
2. plan 绑定目标路径、原 hash、所选工具和 plan digest；apply 重新校验。
3. manifest 按工具保存安装时的完整 command fingerprint；安装升级/卸载只精确移除该历史 fingerprint，禁止 substring ownership。
4. 单文件使用同目录原子 replace；多文件使用可恢复 journal。
5. journal 恢复比较 current/applied hash；不覆盖 crash 后的用户编辑。
6. symlink、非普通文件、owner/mode 异常和 schema 冲突均停止并请求用户处理。

# Manifest

当前 manifest v2 记录版本、已安装工具、稳定 marker、每个工具安装时的 command fingerprint 和更新时间。事务 journal v2 单独记录目标路径、base 快照、base hash 与 applied hash。state 目录为 `0700`；不得存储 secret，恢复快照仅在未完成事务期间存在。

# Apply State

`planned → prepared → applied → committed`。任意 crash 后下一次运行先恢复未完成 journal，再允许新 plan。跨文件不存在真正原子 rename，因此每个 failpoint 都必须可回滚或安全继续。

当前实现将 `prepared` journal 与 installer PID lock 写入私有 state 目录；journal 保存所有目标及 manifest 的恢复快照，并在每个已应用步骤后刷新 applied hash。正常异常立即条件回滚，SIGKILL/断电场景由下一次命令在持锁后先恢复。若 current hash 不等于 journal 中的 applied hash，恢复停止、保留当前文件和 journal并报告冲突。plan digest、工具集合和 before hash 在 apply 时再次验证。

# Uninstall Conflict Policy

- 当前条目仍与 manifest 的安装时 fingerprint 完全相等：精确删除 owned 部分，即使当前环境、可执行文件或仓库路径已经变化。
- 用户修改了 owned 命令或出现未登记的 marker 命令：报告 ownership conflict，保留配置与 manifest 工具状态。
- 升级到新命令：先确认现有 marker 命令仅匹配旧 fingerprint，再在 journal 事务内删除旧命令、安装新命令并提交新 fingerprint。
- 安装前文件不存在：仅当当前文件为空且无第三方变化时删除文件。

# Related Concepts

- [Side Effects](/operations/side-effects.md)
- [Remediation Playbook](/playbooks/security-reliability-remediation.md)
