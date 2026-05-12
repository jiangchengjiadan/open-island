# 本次会话类似权限审批方案

## 目标

Open Island 当前的权限审批只有两个选择：批准一次和拒绝一次。Claude Code 和 Codex 还支持一种会话级选项：本次会话中类似命令或权限自动批准。本方案为 Open Island 增加同类能力。

## 当前链路

1. `bridge/hook.js` 收到 `PreToolUse` 事件。
2. hook 向 `bridge/server.js` 发送 `permission_request`。
3. server 广播 `permission_requested` 给 macOS app。
4. `NotchPanel.swift` 展示 `Deny` 和 `Allow`。
5. `SocketService.swift` 发送只包含 `allowed: Bool` 的 `permission_response`。
6. server 广播 `permission_responded`。
7. hook 向 agent runtime 返回 `allow` 或 `deny`。

现有协议不能表达审批范围；同时 hook 进程是短生命周期进程，也不能自己记住跨工具调用的审批结果。

## 协议设计

`permission_response` 增加 `scope` 字段：

```json
{
  "type": "permission_response",
  "data": {
    "agentId": "claude:session-id",
    "requestId": "claude:session-id:timestamp",
    "allowed": true,
    "scope": "session_similar"
  }
}
```

支持两种范围：

- `once`：只对当前请求生效。
- `session_similar`：批准当前请求，并在当前 agent 会话中自动批准后续类似请求。

hook 每次发起审批时，需要带上稳定的 `permissionKey`：

```json
{
  "id": "claude:session-id:timestamp",
  "type": "Bash",
  "message": "Bash npm test",
  "filePath": null,
  "command": "npm test",
  "permissionKey": "Bash:command:npm test",
  "timestamp": 1776660000000
}
```

## 类似规则

第一版采用保守匹配，避免一次宽泛批准放大风险：

- `Edit`、`Write`、`MultiEdit`、`NotebookEdit`：同工具、同文件路径才算类似。
- `Bash`：同工具、同规范化后的完整命令字符串才算类似。
- `Task`：同工具、同规范化后的序列化输入才算类似。
- 其他可变更工具：同工具、同规范化后的序列化输入才算类似。

后续如果要更接近原生体验，可以再引入命令族白名单，例如把 `npm test`、`npm run build` 这类低风险命令做更宽松的归类。

## 状态归属

会话级授权缓存放在 `bridge/server.js`：

```js
Map<agentId, Set<permissionKey>>
```

原因：

- hook 进程短生命周期，不能跨请求保留内存。
- macOS app 可能重连，UI 层不适合作为授权缓存的唯一来源。
- bridge server 的生命周期正好对应 Open Island 当前运行期。
- agent 注销或 bridge 停止后，缓存自然失效。

## 实现步骤

1. 在 `bridge/hook.js` 中生成 `permissionKey`，并把 `command`、`filePath`、`permissionKey` 放进请求。
2. 在 `bridge/server.js` 中增加 `sessionPermissionGrants`。
3. 扩展 `permission_response`，增加 `scope` 和 `permissionKey`。
4. server 收到 `permission_request` 时先查 `agentId + permissionKey`，命中后直接自动返回批准。
5. 在 `NotchPanel.swift` 增加 `Allow Similar` 按钮。
6. 在 `SocketService.swift` 和 `PermissionRequest` 中支持新字段。
7. 同步修改 `native/NotchMonitor/Sources/AppRuntime/bridge/` 下的打包运行时副本。
8. 使用 Node 语法检查和 `swift build` 验证。

## 行为定义

- `Deny`：只拒绝当前请求。
- `Allow`：只批准当前请求。
- `Allow Similar`：批准当前请求，并把当前请求的 `permissionKey` 写入当前 `agentId` 的会话缓存。
- 后续来自同一 `agentId` 且 `permissionKey` 相同的请求，会自动收到 `permission_responded { allowed: true, autoApproved: true }`。
- agent 注销时删除对应会话缓存。
