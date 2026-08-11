---
type: Test Strategy
title: Remediation Test Strategy
description: 安全与可靠性修复所需的自动化测试层级、隔离要求和发布门禁。
tags: [testing, security, ci, release]
timestamp: 2026-08-10T00:00:00+08:00
---

# Isolation Rules

- 安装器测试必须使用临时 HOME，不得读写开发者真实配置。
- socket 测试使用随机临时目录和路径，不依赖共享 `/tmp/notch-monitor.sock`。
- 每个测试启动的进程必须由测试持有并在 teardown 精确终止，禁止宽泛 `pkill`。
- 日志测试只能写临时私有目录，并验证 mode、内容脱敏和轮转。

# Required Suites

| Suite | Required assertions |
|---|---|
| Integration adapters | 每个事件的 allow/deny 精确输出；未知事件 fail closed |
| Permission protocol | 角色、capability、nonce、requestId、一次性完成和 session grant 生命周期 |
| Installer | plan/apply/uninstall、幂等、第三方条目保留、原子失败、特殊路径 quoting |
| Bridge lifecycle | 第二实例、旧 socket、crash、restart、输出 backpressure、owner cleanup |
| Swift socket | SIGPIPE 防护、partial write、EINTR、重连和失败 UI |
| Swift concurrency | Thread Sanitizer 下 agent merge、prompt cache 和进程状态 |
| UI/layout | 多审批行、Usage tab、onboarding opt-in 和 power assertion 状态 |
| Packaging | canonical bridge 生成打包资源，构建后无 drift |

# Release Gates

1. Node 和 Swift 构建通过。
2. P1 回归测试全部通过，禁止 quarantine 或 skip。
3. 临时 HOME 对比证明默认启动和 dry-run 不产生全局配置变化。
4. 安装、重复安装、升级、卸载后文件 hash 符合预期。
5. 安全测试证明非 UI 客户端无法批准或读取跨 session 数据。
6. 打包路径包含空格的端到端 hook 测试通过。

# Traceability

每个修复 PR 应在描述中链接 [Remediation Playbook](/playbooks/security-reliability-remediation.md) 的 phase，并列出新增或更新的测试。若实现改变架构或副作用，应同步更新对应 OKF concept 和根 `log.md`。
