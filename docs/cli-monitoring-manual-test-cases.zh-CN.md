# CLI 监控手工测试用例

更新时间：2026-05-12

适用范围：

- `Claude`
- `Codex`
- `Qoder`
- `Gemini`

当前不包含：

- Cursor
- OpenCode
- SSH Remote

## 测试前准备

1. 执行：

```bash
./scripts/install-hooks.sh
```

2. 确认输出中每个 event 的 `managed hooks` 数量都是 `1`

3. 启动 Open Island：

```bash
open-island restart
```

## Claude

### TC-CLAUDE-01 会话出现

步骤：

- 启动一个新的 Claude CLI 会话
- 发一条 prompt

预期：

- 岛内出现 Claude 会话
- 名称和任务文案正常更新

### TC-CLAUDE-02 完成态保活

步骤：

- 让 Claude 完成一轮回复后观察

预期：

- 会话不会立即消失
- 至少会短暂保留完成态

### TC-CLAUDE-03 审批

步骤：

- 触发一次需要 Bash / Edit / Write 审批的动作

预期：

- 岛内弹出审批
- `Allow / Deny` 可用

### TC-CLAUDE-04 Allow Similar

步骤：

- 连续触发两次相同审批
- 第一次选择 `Allow Similar`

预期：

- 第二次自动通过
- 不再重复弹相同审批

## Codex

### TC-CODEX-01 hooks 去重

步骤：

- 运行一次需要 `PreToolUse` 的操作

预期：

- 不再出现 `Running 3 PreToolUse hooks`

### TC-CODEX-02 会话出现

步骤：

- 打开一个 Codex 会话
- 发一条 prompt

预期：

- 岛内出现 Codex 会话
- 不会出现重复主会话项

### TC-CODEX-03 完成态保活

步骤：

- 让 Codex 完成一轮任务后观察

预期：

- 会话短暂保留 completed
- 不会刚完成就丢失

### TC-CODEX-04 审批排队

步骤：

- 连续触发多个审批请求

预期：

- 审批按顺序显示
- 不串单、不覆盖

## Qoder

### TC-QODER-01 会话出现

步骤：

- 启动 `qodercli`
- 发起一轮任务

预期：

- 岛内出现 Qoder 会话

### TC-QODER-02 权限事件

步骤：

- 触发一次 shell/tool 权限动作

预期：

- 岛内能看到审批
- 不会出现“部分权限不监控”

### TC-QODER-03 完成态

步骤：

- 让一轮任务完成

预期：

- 会话不会异常提前消失

## Gemini

### TC-GEMINI-01 会话出现

步骤：

- 启动 Gemini CLI
- 发起一轮任务

预期：

- 岛内出现 Gemini 会话

### TC-GEMINI-02 事件状态

步骤：

- 观察一次完整流程：
  - `BeforeAgent`
  - `AfterAgent`
  - `Notification`

预期：

- 状态变化合理
- 不会一直停在 running

### TC-GEMINI-03 完成态

步骤：

- 等一轮任务结束

预期：

- 会话能正常结束或短暂保留完成态

## 通用稳定性

### TC-CLI-01 stale cleanup

步骤：

- 关闭 CLI 会话或异常中断
- 等待 cleanup

预期：

- 僵尸会话会被清理
- 活跃会话不被误删

### TC-CLI-02 重复安装幂等

步骤：

- 连续两次执行：

```bash
./scripts/install-hooks.sh
```

预期：

- 第二次输出的 `managed hooks` 计数不增长
- 各 event 仍是 `1`
