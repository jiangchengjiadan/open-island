---
type: Security Model
title: Permission Boundary
description: Open Island 权限审批链的参与者、信任关系和必须保持的不变量。
tags: [security, permissions, protocol, fail-closed]
timestamp: 2026-08-10T00:00:00+08:00
---

# Actors

| Actor | Allowed capabilities | Forbidden capabilities |
|---|---|---|
| UI client | 查看已授权展示的数据；回答当前审批 | 创建伪造 agent；回答非当前请求 |
| Hook client | 注册自身 session；创建权限请求；接收自身结果 | 批准请求；读取其他 session 快照 |
| Wrapper client | 注册和更新自身子进程生命周期 | 参与权限审批；读取其他 session |
| Bridge | 验证、排队和路由消息 | 自行扩大授权范围；把协议错误当作允许 |

# Security Invariants

1. Deny、超时、断连、未知事件和解析失败均不得产生 allow。
2. response 必须绑定已认证 UI 连接、agent instance、requestId 和随机 nonce。
3. `allow_similar` 最多持续到当前进程实例结束，不能被相同字符串 ID 的新进程继承。
4. 一个请求最多完成一次；迟到或重复响应不能改变当前队列。
5. 普通本地同 UID 进程不能仅通过连接 socket 获得快照或批准能力。
6. 集成不支持真实阻断时，UI 不得宣称其审批可保护操作。

# Implemented Safeguards

- Cursor/Gemini adapter 不再把 deny 转成 continue；未验证的 Cursor/Gemini 工具事件保持 monitor-only。
- blocking hook 在 bridge 不可达、协议异常和 malformed input 时保守输出 deny。
- UI 响应需要临时 capability、UI role、当前 requestId 和单次 nonce；hook/wrapper 不能提交响应。
- hook requestId 使用 UUID；响应定向到请求连接；UI/requester 断线会拒绝 pending 请求。
- frame 和单 agent pending queue 已有硬上限，陈旧/错 nonce 响应被忽略。

# Remaining Gaps

- UI capability 通过 bridge 标准输入的继承 FD 一次性传递，不进入子进程环境；威胁模型仍不声称抵御同 UID 主动调试进程内存。
- hook/wrapper role 仍缺独立凭据，agent instance/grant 尚未完整绑定进程 start identity。
- 仍需全局 client/pending/backpressure 限制以及 vendor 级真实副作用 E2E。
- Cursor/Gemini 同步阻断能力仍未验证，因此不能宣称审批保护。

# Verification

协议测试必须覆盖伪造客户端、重放、迟到响应、错 agent、错 nonce、断连、超时、进程重启和 flood。完整策略见 [Remediation Test Strategy](/testing/remediation-test-strategy.md)。集成能否阻断以 [Approval Support Matrix](/integrations/approval-support-matrix.md) 为准。
