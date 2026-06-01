# Codex 审批专项回归

更新时间：2026-04-29

适用分支：

- `codex-default-hooks`

目标：

- 把 Codex 审批链路从“功能存在”提升到“每次改 hook / bridge / panel 后都能重复验证”

建议在这些改动后必跑：

- `bridge/hook.js`
- `bridge/server.js`
- `native/NotchMonitor/Sources/Services/SocketService.swift`
- `native/NotchMonitor/Sources/Views/NotchPanel.swift`

## 测试前准备

- Open Island 已启动
- Codex 通过 `~/.local/bin/codex` 启动
- Accessibility 已开启
- 建议同时观察日志：

```bash
tail -n 200 /tmp/notch-monitor-hook.log
tail -n 200 /tmp/notch-monitor-codex-wrapper.log
tail -n 200 /tmp/notch-monitor-jump.log
```

## 用例

### CA-01 Bash 审批闭环

步骤：

1. 启动一个新的 `codex` 会话
2. 让它执行一个会触发 `Bash` 审批的命令
3. 在岛上点击 `Allow`

预期：

- 面板出现审批条
- `Allow` 后审批条消失
- Codex 继续执行
- `hook.log` 中能看到对应的 permission request

### CA-02 Write / Edit 审批闭环

步骤：

1. 启动一个新的 `codex` 会话
2. 让它分别触发 `Write` 或 `Edit` 类型操作
3. 分别测试 `Allow` 与 `Deny`

预期：

- 两类请求都能正常显示
- `Allow` 后继续执行
- `Deny` 后该动作终止，且不会卡住后续会话

### CA-03 Allow Similar 命中

步骤：

1. 在一个新的 `codex` 会话中触发一次可重复的 `Bash` 或 `Write` 请求
2. 点击 `Allow Similar`
3. 在同一会话中再次触发相同请求

预期：

- 第二次请求不再要求人工审批
- agent 直接继续执行
- 日志中可看到自动批准路径

### CA-04 session grant 不跨会话泄漏

步骤：

1. 在会话 A 中对某条请求点 `Allow Similar`
2. 退出会话 A
3. 启动新的会话 B
4. 在会话 B 中触发同样的请求

预期：

- 会话 B 不应继承会话 A 的类似批准
- 新请求应重新弹出审批

### CA-05 多个请求排队不串单

步骤：

1. 在同一个 `codex` 会话里连续触发两个审批请求
2. 不处理第一个时，观察第二个是否覆盖
3. 先响应第一个，再观察第二个

预期：

- 请求按顺序排队
- 不会发生 A 的按钮点击回应到 B
- requestId 不错配

### CA-06 bridge 不可用时 fail-open

步骤：

1. 保持 `codex` 会话运行
2. 暂时停止 bridge 或让 `/tmp/notch-monitor.sock` 不可连接
3. 触发一次 `PreToolUse`

预期：

- 不应因 hook 故障永久卡死 Codex
- `hook.log` 会记录 `ENOENT` 或 `ECONNREFUSED`
- bridge 恢复后，新请求可重新进入正常审批链路

### CA-07 兼容性回归

步骤：

1. 在 `codex` 会话里再次触发 `PreToolUse`
2. 观察 CLI 输出

预期：

- 不再出现以下错误：
  - `unsupported suppressOutput`
  - `unsupported permissionDecision:allow`
- 当前 Codex hook 返回体应只包含最小兼容字段

## 建议记录格式

```text
CA-03
结果：通过 / 失败 / 部分通过
现象：
日志：
复现概率：
备注：
```

## 当前结论

截至 `2026-04-29`，这份文档已经能作为手工回归基线，但还不算自动化回归。

仍待补齐：

- 自动化 smoke harness
- 更明确的日志断言
- 针对 `Allow Similar` 生命周期的可重复脚本化验证
