# Open Island Code Knowledge Update Log

## 2026-08-10

* **Implementation**: 完成首轮安全与可靠性修复：默认启动只启动 bridge、不再隐式安装；审批连接角色隔离；UUID requestId 与 nonce 严格匹配；断线 fail-closed；socket 完整写与 SIGPIPE 防护；bridge 有界停止与 owner identity；敏感日志、终端读取和终端标题默认关闭；防休眠改为 opt-in。
* **Testing**: 增加 Node 审批协议与 hook 进程级 fail-closed 回归测试，并在 CI 中加入运行时同步漂移检查和 bridge 测试。
* **Initialization**: 创建 OKF 0.1 代码知识 bundle 和渐进披露索引。
* **Creation**: 记录系统架构、审批安全边界、副作用清单和修复测试策略。
* **Creation**: 将 [Open Island 安全与可靠性修复方案](/playbooks/security-reliability-remediation.md) 纳入知识图谱。
* **Review**: 依据安全、运行时和 OKF 子智能体复核，修正 capability 信任模型、fail-closed 范围、bundle 根链接和实施验收标准。
* **Creation**: 增加审批支持矩阵、安装 ownership 与 bridge/socket 生命周期概念。
* **Remediation**: 完成显式 plan/apply/uninstall、精确 ownership、journal v2 crash-safe 条件恢复、运行时 manifest、审批 ACK 与 inherited-FD capability。
* **Review**: 整体测试子智能体多轮复核并推动修复默认 monitor-only 畸形输入误拒绝、manifest 事务缺口及 crash 后用户编辑被覆盖风险。
* **Verification**: Node 22 项测试本地 21 通过/1 项沙箱 socket skip（正常环境由独立智能体验证通过），Swift clean scratch build、语法、whitespace 与 packaged runtime drift 检查通过。
