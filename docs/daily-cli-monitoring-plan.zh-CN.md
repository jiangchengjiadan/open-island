# 每日 10 个任务计划：CLI 监控优先

更新时间：2026-05-12

当前策略调整：

- 暂停 `Cursor` 相关开发和修复
- 暂停 `OpenCode` 实现推进
- 当前只优先做四类本地 CLI 监控：
  - `Claude`
  - `Codex`
  - `Qoder`
  - `Gemini`

目标：

- 先把本地 CLI 监控、审批、去重、会话保活、基础跳转做稳
- 再回头做 IDE agent 和更重的协议扩展

## 任务切分规则

每天固定拆成 10 个小任务，分布建议：

- `4 个` 稳定性 / bug 修复
- `3 个` integration / hook / bridge
- `2 个` 测试 / 日志 / 回归
- `1 个` 文档 / 提交 / 收口

避免：

- 一天只做 1 到 2 个超大任务
- 同时并行推进 `Cursor / OpenCode / SSH Remote`

## Day 1

### 1. Codex hooks 重复执行排查

状态：`Done`

目标：

- 收敛 `Running 3 PreToolUse hooks`

验收：

- `~/.codex/hooks.json` 中同一事件只保留一条 managed hook

### 2. Codex hooks 安装器幂等自检

状态：`Done`

目标：

- 安装后直接输出每个 event 的 managed hook 数量

验收：

- 重复执行安装脚本时数量不继续增长

### 3. Claude 会话保活检查

状态：`Partial`

目标：

- 确认 `SessionStart / UserPromptSubmit / Stop / SessionEnd` 显示稳定

验收：

- 完成一轮后会话不会异常提前消失

### 4. Qoder 权限事件覆盖检查

状态：`Partial`

目标：

- 补齐未触发审批的 `tool_name / tool_input` 字段路径

验收：

- 常见 shell/tool 权限都能进入岛内

### 5. Gemini 真实事件回归

状态：`Partial`

目标：

- 验证 `BeforeAgent / AfterAgent / Notification` 的状态映射是否合理

验收：

- 不再只停留在“脚本已安装”

### 6. CLI 会话去重策略收口

状态：`In Progress`

目标：

- 收敛 `Claude / Qoder / Gemini / Codex` 的重复项和幽灵项

验收：

- 同一 CLI 会话不出现两个视觉重复项

### 7. stale cleanup 对 CLI 的影响复查

状态：`Partial`

目标：

- 确认 cleanup 不会误删仍在运行的 CLI 会话

验收：

- 活跃会话不被 TTL 误清

### 8. permission queue 回归测试补强

状态：`Pending`

目标：

- 重点验证 `Claude / Codex / Qoder`

验收：

- 同一 agent 连续审批不覆盖、不串单

### 9. 生成 CLI 手工测试清单

状态：`Done`

目标：

- 单独整理一份只针对 `Claude / Codex / Qoder / Gemini` 的测试用例

验收：

- 至少覆盖出现、更新、完成、审批、Allow Similar、异常清理

### 10. 提交与日志整理

状态：`Pending`

目标：

- 把当天完成的 CLI 改动及时提交，避免继续堆在脏工作区

验收：

- 有清晰 commit
- 有对应验证记录

## 当前不做

- Cursor 监控修复
- Cursor jump 精调
- OpenCode 实现
- Plan Review UI
- SSH Remote

## 进入下一轮的条件

只有在下面 4 条都基本稳定后，再恢复非 CLI 优先级：

- Claude 稳定
- Codex 稳定
- Qoder 稳定
- Gemini 稳定
