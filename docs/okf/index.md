# Open Island Code Knowledge Bundle

本目录采用 OKF 0.1 组织代码知识，面向维护者和智能体提供渐进式上下文。先阅读索引，再按任务打开对应概念；不要把运行时事实只写在聊天记录中。

# Architecture

* [System Overview](architecture/system-overview.md) - App、bridge、hooks、终端控制和用户配置之间的主要边界。
* [Bridge and Socket Lifecycle](runtime/bridge-socket-lifecycle.md) - bridge 单实例、进程状态、socket ownership 与重连规则。

# Security

* [Permission Boundary](security/permission-boundary.md) - 审批协议的信任边界、失败策略和安全不变量。
* [Approval Support Matrix](integrations/approval-support-matrix.md) - 各工具事件是否具备真实同步阻断能力。

# Operations

* [Side Effects](operations/side-effects.md) - 进程、配置、日志、终端和电源策略的副作用登记表。
* [Installer Ownership](operations/installer-ownership.md) - 配置 plan/apply/uninstall 的 ownership、事务和冲突规则。

# Testing

* [Remediation Test Strategy](testing/remediation-test-strategy.md) - 修复计划对应的自动化验证层级与发布门禁。

# Playbooks

* [Security and Reliability Remediation](playbooks/security-reliability-remediation.md) - 当前代码审查问题的分阶段修复总方案。

# Implementation Logs

* [2026-08-10 Remediation Implementation](logs/2026-08-10-remediation-implementation.md) - 本轮实现、测试、复审与问题闭环记录。

# Maintenance Rules

* 非 `index.md`、`log.md` 的文档必须包含 YAML frontmatter 和非空 `type`。
* 概念应记录稳定事实、边界、不变量和验证方式，不复制容易过期的大段源码。
* 代码改变协议、所有权、副作用或运行方式时，同一提交更新对应概念和 `log.md`。
* 新概念必须加入最近一级 `index.md`，跨概念关系使用标准 Markdown 链接。
* 未验证的推断明确标为假设；已确认事实附仓库文件路径或测试证据。
