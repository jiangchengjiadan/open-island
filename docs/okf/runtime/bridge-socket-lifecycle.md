---
type: Runtime State Model
title: Bridge and Socket Lifecycle
description: bridge owner、Process generation、socket 路径、连接和退出的目标状态模型。
tags: [runtime, bridge, socket, lifecycle]
timestamp: 2026-08-10T00:00:00+08:00
---

# Process State

监督器持有 `desiredState`、`state`、`generation`、`processIdentity` 和 `ownerMode`。允许路径为：

```text
stopped → starting → running → stopping → stopped
```

启动失败回到 `stopped + error`；意外退出最多按有限指数退避重启。用户退出先设置 `desiredState=stopped`，取消 timer/reconnect，之后任何旧 generation 回调都不能启动或修改新状态。

# Restart Rule

restart 进入 stopping，向精确 Process identity 发送 SIGTERM，等待有界 grace；必要时再次验证 PID+start-time 后强停。termination 完成前禁止清空 identity 或 spawn 新进程。

# Socket Ownership

- App 和 bridge 分别使用单实例锁；只有 owner 能创建或清理 socket。
- 健康 socket 不接管。只有 connect 失败、lock owner 已死且 nonce manifest 匹配时，才能清理陈旧 socket。
- `RuntimePaths` 统一注入所有组件，私有目录 mode `0700`，路径必须满足 macOS `sockaddr_un` 长度限制。
- read/write 和 DispatchSource 都绑定 FD generation，旧事件不能操作重连后的新 FD。

# Shutdown

停止接收新请求，pending blocking 请求 fail closed，关闭客户端，等待 server close，最后由 owner 清理 nonce 匹配的 socket/lock。退出完成后不得残留进程、socket、锁或 reconnect work item。

# Related Concepts

- [System Overview](/architecture/system-overview.md)
- [Permission Boundary](/security/permission-boundary.md)
- [Remediation Playbook](/playbooks/security-reliability-remediation.md)
